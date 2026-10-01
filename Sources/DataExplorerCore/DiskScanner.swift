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

    public init(
        rootPath: String,
        style: FileTree.Style = .plain,
        displayName: String? = nil,
        stayOnVolume: Bool = true,
        individualFileThreshold: Int64 = 1_000_000
    ) {
        self.rootPath = rootPath
        self.style = style
        self.displayName = displayName ?? (rootPath as NSString).lastPathComponent
        self.stayOnVolume = stayOnVolume
        self.individualFileThreshold = individualFileThreshold
    }

    /// Scans the whole startup disk. On macOS that means the Data volume, which holds
    /// everything except the sealed, read-only system.
    public static func entireDisk(displayName: String) -> ScanOptions {
        if FileManager.default.fileExists(atPath: FileTree.dataVolumePath) {
            return ScanOptions(rootPath: FileTree.dataVolumePath, style: .dataVolume, displayName: displayName)
        }
        return ScanOptions(rootPath: "/", style: .plain, displayName: displayName)
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
public enum DiskScanner {
    private struct HardLinkKey: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    public static func scan(
        _ options: ScanOptions,
        isCancelled: () -> Bool = { false },
        progress: ((ScanProgress) -> Void)? = nil
    ) throws -> ScanOutput {
        let start = Date()

        guard let rootCString = strdup(options.rootPath) else {
            throw ScanError.cannotOpen(options.rootPath, ENOMEM)
        }
        defer { free(rootCString) }
        var argv: [UnsafeMutablePointer<CChar>?] = [rootCString, nil]

        var flags = FTS_PHYSICAL | FTS_NOCHDIR
        if options.stayOnVolume { flags |= FTS_XDEV }

        guard let fts = fts_open(&argv, flags, nil) else {
            throw ScanError.cannotOpen(options.rootPath, errno)
        }
        defer { fts_close(fts) }

        var root: FileNode?
        var stack: [(node: FileNode, level: Int)] = []
        var hardLinks = Set<HardLinkKey>()
        var unreadableCount = 0
        var unreadablePaths: [String] = []
        var files = 0
        var folders = 0
        var bytes: Int64 = 0
        var entriesSinceCheck = 0
        var lastReport = DispatchTime.now().uptimeNanoseconds
        let threshold = options.individualFileThreshold

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

        func noteUnreadable(_ path: String) {
            unreadableCount += 1
            if unreadablePaths.count < 200 { unreadablePaths.append(path) }
        }

        while let entryPointer = fts_read(fts) {
            entriesSinceCheck += 1
            if entriesSinceCheck >= 512 {
                entriesSinceCheck = 0
                if isCancelled() { throw ScanError.cancelled }
                if let progress {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now - lastReport > 150_000_000 {
                        lastReport = now
                        progress(ScanProgress(
                            filesScanned: files,
                            foldersScanned: folders,
                            bytesScanned: bytes,
                            currentPath: String(cString: entryPointer.pointee.fts_path)
                        ))
                    }
                }
            }

            let entry = entryPointer.pointee
            let level = Int(entry.fts_level)
            let info = Int32(entry.fts_info)

            switch info {
            case Int32(FTS_DP):
                popToLevel(level)

            case Int32(FTS_D):
                popToLevel(level)
                let parent = stack.last?.node
                let node = FileNode(
                    name: parent == nil ? options.displayName : name(of: entry),
                    kind: .directory,
                    parent: parent
                )
                let st = entry.fts_statp.pointee
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

            case Int32(FTS_DNR), Int32(FTS_ERR):
                let entryName = name(of: entry)
                noteUnreadable(String(cString: entry.fts_path))
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
                    throw ScanError.cannotOpen(options.rootPath, entry.fts_errno)
                }

            case Int32(FTS_DC):
                // A folder that links back to one of its parents. Skip it.
                continue

            case Int32(FTS_NS):
                noteUnreadable(String(cString: entry.fts_path))
                if level == 0 && root == nil {
                    throw ScanError.cannotOpen(options.rootPath, entry.fts_errno)
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
                    if !hardLinks.insert(key).inserted {
                        // Another link to a file we've already counted.
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

        if isCancelled() { throw ScanError.cancelled }
        while !stack.isEmpty { finishTop() }

        guard let root else {
            throw ScanError.cannotOpen(options.rootPath, errno == 0 ? ENOENT : errno)
        }

        let tree = FileTree(root: root, rootPath: options.rootPath, style: options.style, displayName: options.displayName)
        return ScanOutput(
            tree: tree,
            unreadableCount: unreadableCount,
            unreadablePaths: unreadablePaths,
            duration: Date().timeIntervalSince(start),
            finishedAt: Date()
        )
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
