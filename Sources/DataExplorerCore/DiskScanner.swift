import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ScanProgress: Sendable {
    public var filesScanned: Int
    public var foldersScanned: Int
    public var bytesScanned: Int64
    public var currentPath: String
}

public struct ScanOptions: Sendable {
    public var rootPath: String
    public var style: FileTree.Style
    public var displayName: String
    /// Don't descend into other disks mounted inside the scanned folder.
    public var stayOnVolume: Bool
    /// Files at least this large are kept as separate entries; smaller ones are summed per folder.
    public var individualFileThreshold: Int64
    /// Scan sub-folders on several threads at once.
    public var parallel: Bool
    /// Folders inside this path are split up one level deeper for parallel scanning. Set it to
    /// the home folder, which usually holds most of the files.
    public var deepSplitPrefix: String?

    public init(
        rootPath: String,
        style: FileTree.Style = .plain,
        displayName: String? = nil,
        stayOnVolume: Bool = true,
        individualFileThreshold: Int64 = 1_000_000,
        parallel: Bool = true,
        deepSplitPrefix: String? = nil
    ) {
        self.rootPath = rootPath
        self.style = style
        self.displayName = displayName ?? (rootPath as NSString).lastPathComponent
        self.stayOnVolume = stayOnVolume
        self.individualFileThreshold = individualFileThreshold
        self.parallel = parallel
        self.deepSplitPrefix = deepSplitPrefix
    }

    /// Scans the whole startup disk. On macOS that means the Data volume, which holds
    /// everything except the sealed, read-only system.
    public static func entireDisk(displayName: String) -> ScanOptions {
        if FileManager.default.fileExists(atPath: FileTree.dataVolumePath) {
            return ScanOptions(
                rootPath: FileTree.dataVolumePath,
                style: .dataVolume,
                displayName: displayName,
                deepSplitPrefix: FileTree.dataVolumePath + NSHomeDirectory()
            )
        }
        return ScanOptions(rootPath: "/", style: .plain, displayName: displayName, deepSplitPrefix: NSHomeDirectory())
    }

    /// Folders at this depth are handed to separate threads.
    var splitLevel: Int? {
        guard parallel else { return nil }
        return style == .dataVolume ? 4 : 3
    }

    public static func folder(_ path: String) -> ScanOptions {
        ScanOptions(rootPath: path, style: .plain, displayName: (path as NSString).lastPathComponent)
    }
}

public struct ScanOutput: Sendable {
    public let tree: FileTree
    public let unreadableCount: Int
    /// A sample of folders that couldn't be read.
    public let unreadablePaths: [String]
    public let duration: TimeInterval
    public let finishedAt: Date

    public init(tree: FileTree, unreadableCount: Int, unreadablePaths: [String], duration: TimeInterval, finishedAt: Date) {
        self.tree = tree
        self.unreadableCount = unreadableCount
        self.unreadablePaths = unreadablePaths
        self.duration = duration
        self.finishedAt = finishedAt
    }
}

public enum ScanError: Error, LocalizedError {
    case cannotOpen(String, Int32)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let path, let code):
            return "Couldn't read \(path): \(String(cString: strerror(code)))"
        case .cancelled:
            return "The scan was cancelled."
        }
    }
}

/// Walks a folder tree with fts(3), measuring the space each item actually takes on disk.
///
/// The top few levels are walked first. Folders below that are then scanned in parallel, each
/// with its own fts walk, and their totals are added to the folders above them at the end.
public enum DiskScanner {
    struct HardLinkKey: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    /// State shared by every thread taking part in one scan.
    final class SharedState: @unchecked Sendable {
        private let lock = NSLock()
        private var hardLinks = Set<HardLinkKey>()
        private var files = 0
        private var folders = 0
        private var bytes: Int64 = 0
        private var lastReport: UInt64 = 0
        private var cancelled = false
        private(set) var unreadableCount = 0
        private(set) var unreadablePaths: [String] = []
        let progress: ((ScanProgress) -> Void)?

        init(progress: ((ScanProgress) -> Void)?) {
            self.progress = progress
        }

        /// False when another hard link to the same file was already counted.
        func isFirstLink(_ key: HardLinkKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return hardLinks.insert(key).inserted
        }

        func noteUnreadable(_ path: String) {
            lock.lock()
            defer { lock.unlock() }
            unreadableCount += 1
            if unreadablePaths.count < 200 { unreadablePaths.append(path) }
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        /// Adds one thread's counts, reporting progress at most every 150 ms.
        func add(files newFiles: Int, folders newFolders: Int, bytes newBytes: Int64, currentPath: () -> String) {
            lock.lock()
            files += newFiles
            folders += newFolders
            bytes += newBytes
            var snapshot: ScanProgress?
            let now = DispatchTime.now().uptimeNanoseconds
            if progress != nil, now - lastReport > 150_000_000 {
                lastReport = now
                snapshot = ScanProgress(filesScanned: files, foldersScanned: folders, bytesScanned: bytes, currentPath: "")
            }
            lock.unlock()
            if var snapshot, let progress {
                snapshot.currentPath = currentPath()
                progress(snapshot)
            }
        }
    }

    private struct WalkResult {
        let root: FileNode
        /// Folders left for other threads to scan, with their paths.
        let deferred: [(node: FileNode, path: String)]
    }

    public static func scan(
        _ options: ScanOptions,
        isCancelled: () -> Bool = { false },
        progress: ((ScanProgress) -> Void)? = nil
    ) throws -> ScanOutput {
        let start = Date()
        let shared = SharedState(progress: progress)

        let first = try walk(
            path: options.rootPath,
            existingRoot: nil,
            splitLevel: options.splitLevel,
            options: options,
            shared: shared,
            isCancelled: isCancelled
        )
        let root = first.root
        let deferred = first.deferred

        if !deferred.isEmpty {
            let sizesBefore = deferred.map { $0.node.size }
            DispatchQueue.concurrentPerform(iterations: deferred.count) { index in
                if shared.isCancelled { return }
                let item = deferred[index]
                do {
                    _ = try walk(
                        path: item.path,
                        existingRoot: item.node,
                        splitLevel: nil,
                        options: options,
                        shared: shared,
                        isCancelled: isCancelled
                    )
                } catch ScanError.cancelled {
                    shared.cancel()
                } catch {
                    item.node.isUnreadable = true
                    shared.noteUnreadable(item.path)
                }
            }
            if shared.isCancelled { throw ScanError.cancelled }

            // Add what each thread found to the folders above it, then re-sort those folders.
            var deferredIDs = Set<ObjectIdentifier>()
            for (index, item) in deferred.enumerated() {
                deferredIDs.insert(ObjectIdentifier(item.node))
                let addedSize = item.node.size - sizesBefore[index]
                let addedFiles = item.node.fileCount
                var ancestor = item.node.parent
                while let node = ancestor {
                    node.size += addedSize
                    node.fileCount += addedFiles
                    ancestor = node.parent
                }
            }
            resort(root, skipping: deferredIDs)
        }

        if isCancelled() { throw ScanError.cancelled }

        let tree = FileTree(root: root, rootPath: options.rootPath, style: options.style, displayName: options.displayName)
        return ScanOutput(
            tree: tree,
            unreadableCount: shared.unreadableCount,
            unreadablePaths: shared.unreadablePaths,
            duration: Date().timeIntervalSince(start),
            finishedAt: Date()
        )
    }

    private static func resort(_ node: FileNode, skipping finished: Set<ObjectIdentifier>) {
        node.children.sort { $0.size > $1.size }
        for child in node.children where child.isDirectory && !finished.contains(ObjectIdentifier(child)) {
            resort(child, skipping: finished)
        }
    }

    /// Walks one folder tree.
    ///
    /// - Parameters:
    ///   - existingRoot: When set, the folder's node was already created by the first pass and
    ///     this walk fills in its contents.
    ///   - splitLevel: Folders at this depth (one deeper inside `deepSplitPrefix`) are skipped
    ///     and returned so they can be scanned in parallel.
    private static func walk(
        path rootPath: String,
        existingRoot: FileNode?,
        splitLevel: Int?,
        options: ScanOptions,
        shared: SharedState,
        isCancelled: () -> Bool
    ) throws -> WalkResult {
        guard let rootCString = strdup(rootPath) else {
            throw ScanError.cannotOpen(rootPath, ENOMEM)
        }
        defer { free(rootCString) }
        var argv: [UnsafeMutablePointer<CChar>?] = [rootCString, nil]

        var flags = FTS_PHYSICAL | FTS_NOCHDIR
        if options.stayOnVolume { flags |= FTS_XDEV }

        guard let fts = fts_open(&argv, flags, nil) else {
            throw ScanError.cannotOpen(rootPath, errno)
        }
        defer { fts_close(fts) }

        var root: FileNode?
        var deferred: [(node: FileNode, path: String)] = []
        var stack: [(node: FileNode, level: Int)] = []
        var rootDevice: UInt64 = 0
        var files = 0
        var folders = 0
        var bytes: Int64 = 0
        var entriesSinceCheck = 0
        let threshold = options.individualFileThreshold
        let deepPrefix = options.deepSplitPrefix.map { $0 + "/" }

        func finishTop() {
            let finished = stack.removeLast().node
            finished.children.sort { $0.size > $1.size }
            if let parent = stack.last?.node {
                parent.size += finished.size
                parent.fileCount += finished.fileCount
            }
        }

        func popToLevel(_ level: Int) {
            while let top = stack.last, top.level >= level {
                finishTop()
            }
        }

        func flushCounts(_ entry: UnsafeMutablePointer<FTSENT>?) {
            shared.add(files: files, folders: folders, bytes: bytes) {
                guard let entry, let path = entry.pointee.fts_path else { return rootPath }
                return String(cString: path)
            }
            files = 0
            folders = 0
            bytes = 0
        }

        while let entryPointer = fts_read(fts) {
            entriesSinceCheck += 1
            if entriesSinceCheck >= 512 {
                entriesSinceCheck = 0
                if isCancelled() || shared.isCancelled { throw ScanError.cancelled }
                flushCounts(entryPointer)
            }

            let entry = entryPointer.pointee
            let level = Int(entry.fts_level)
            let info = Int32(entry.fts_info)

            switch info {
            case Int32(FTS_DP):
                popToLevel(level)

            case Int32(FTS_D):
                popToLevel(level)
                let st = entry.fts_statp.pointee
                let device = UInt64(truncatingIfNeeded: st.st_dev)
                if level == 0 {
                    rootDevice = device
                    if let existingRoot {
                        // Counted and sized by the first pass already.
                        root = existingRoot
                        stack.append((existingRoot, 0))
                        continue
                    }
                }
                let parent = stack.last?.node
                let node = FileNode(
                    name: parent == nil ? options.displayName : name(of: entry),
                    kind: .directory,
                    parent: parent
                )
                node.size = Int64(st.st_blocks) * 512
                node.modified = modificationTime(st)
                if let parent {
                    parent.children.append(node)
                } else {
                    root = node
                }
                stack.append((node, level))
                folders += 1
                bytes += node.size

                // Hand deeper folders to other threads. Mount points are left alone: fts won't
                // descend into them, and neither should anyone else.
                if let splitLevel, level >= splitLevel, device == rootDevice {
                    let path = String(cString: entry.fts_path)
                    let deep = deepPrefix.map { path.hasPrefix($0) } ?? false
                    if level == splitLevel + (deep ? 1 : 0) {
                        deferred.append((node, path))
                        _ = fts_set(fts, entryPointer, Int32(FTS_SKIP))
                    }
                }

            case Int32(FTS_DNR), Int32(FTS_ERR):
                let entryName = name(of: entry)
                shared.noteUnreadable(String(cString: entry.fts_path))
                if info == Int32(FTS_DNR), let top = stack.last, top.level == level,
                   top.node.name == entryName || level == 0 {
                    // The folder was already added when fts reported it; it just couldn't be listed.
                    top.node.isUnreadable = true
                } else if level > 0 {
                    popToLevel(level)
                    if let parent = stack.last?.node {
                        let node = FileNode(name: entryName, kind: .directory, parent: parent)
                        node.isUnreadable = true
                        parent.children.append(node)
                    }
                } else if root == nil {
                    throw ScanError.cannotOpen(rootPath, entry.fts_errno)
                }

            case Int32(FTS_DC):
                // A folder that links back to one of its parents. Skip it.
                continue

            case Int32(FTS_NS):
                shared.noteUnreadable(String(cString: entry.fts_path))
                if level == 0 && root == nil {
                    throw ScanError.cannotOpen(rootPath, entry.fts_errno)
                }

            default:
                // Regular files, symlinks and anything else that isn't a folder.
                popToLevel(level)
                let st = entry.fts_statp.pointee
                var allocated = Int64(st.st_blocks) * 512
                if UInt64(truncatingIfNeeded: st.st_nlink) > 1 {
                    let key = HardLinkKey(
                        device: UInt64(truncatingIfNeeded: st.st_dev),
                        inode: UInt64(truncatingIfNeeded: st.st_ino)
                    )
                    if !shared.isFirstLink(key) {
                        // Another link to a file that's already been counted.
                        allocated = 0
                    }
                }
                files += 1
                bytes += allocated

                let kind: FileNode.Kind
                switch info {
                case Int32(FTS_F): kind = .file
                case Int32(FTS_SL), Int32(FTS_SLNONE): kind = .symlink
                default: kind = .other
                }

                guard let parent = stack.last?.node else {
                    // The scan root is a single file.
                    let node = FileNode(name: options.displayName, kind: kind, parent: nil)
                    node.size = allocated
                    node.fileCount = 1
                    node.modified = modificationTime(st)
                    root = node
                    continue
                }

                let entryName = name(of: entry)
                parent.size += allocated
                parent.fileCount += 1
                if let marker = FileNode.Markers.forFileName(entryName) {
                    parent.markers.insert(marker)
                }
                if kind == .file && allocated >= threshold {
                    let node = FileNode(name: entryName, kind: kind, parent: parent)
                    node.size = allocated
                    node.fileCount = 1
                    node.modified = modificationTime(st)
                    parent.children.append(node)
                } else {
                    parent.looseFileCount += 1
                    parent.looseFileSize += allocated
                }
            }
        }

        if isCancelled() || shared.isCancelled { throw ScanError.cancelled }
        while !stack.isEmpty { finishTop() }
        flushCounts(nil)

        guard let root else {
            throw ScanError.cannotOpen(rootPath, errno == 0 ? ENOENT : errno)
        }
        return WalkResult(root: root, deferred: deferred)
    }

    /// The entry's file name. fts stores it at the end of `fts_path`.
    private static func name(of entry: FTSENT) -> String {
        let pathLength = Int(entry.fts_pathlen)
        let nameLength = Int(entry.fts_namelen)
        guard let path: UnsafeMutablePointer<CChar> = entry.fts_path else { return "" }
        return String(cString: path + (pathLength - nameLength))
    }

    private static func modificationTime(_ st: stat) -> Int64 {
        #if canImport(Darwin)
        return Int64(st.st_mtimespec.tv_sec)
        #else
        return Int64(st.st_mtim.tv_sec)
        #endif
    }
}
