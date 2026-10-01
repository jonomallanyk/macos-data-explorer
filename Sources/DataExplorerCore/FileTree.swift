import Foundation

/// One folder or (large enough) file found during a scan.
///
/// Files smaller than the scan's threshold aren't kept as separate nodes. Their sizes are
/// added to `looseFileSize` on the folder that contains them, which keeps memory use
/// reasonable when a disk holds millions of files.
public final class FileNode: Identifiable, @unchecked Sendable {
    public enum Kind: UInt8, Sendable {
        case directory
        case file
        case symlink
        case other
    }

    /// Well-known files spotted inside a folder, used to recognise project folders.
    public struct Markers: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let packageJSON = Markers(rawValue: 1 << 0)
        public static let cargoToml = Markers(rawValue: 1 << 1)
        public static let pyvenvCfg = Markers(rawValue: 1 << 2)
        public static let podfile = Markers(rawValue: 1 << 3)
        public static let packageSwift = Markers(rawValue: 1 << 4)
        public static let gradleBuild = Markers(rawValue: 1 << 5)
        public static let composerJSON = Markers(rawValue: 1 << 6)

        static func forFileName(_ name: String) -> Markers? {
            switch name {
            case "package.json": return .packageJSON
            case "Cargo.toml": return .cargoToml
            case "pyvenv.cfg": return .pyvenvCfg
            case "Podfile": return .podfile
            case "Package.swift": return .packageSwift
            case "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts": return .gradleBuild
            case "composer.json": return .composerJSON
            default: return nil
            }
        }
    }

    public let name: String
    public let kind: Kind
    public internal(set) weak var parent: FileNode?
    /// Sub-folders and large files, sorted largest first once the scan finishes.
    public internal(set) var children: [FileNode] = []
    /// Bytes allocated on disk by this item and everything inside it.
    public internal(set) var size: Int64 = 0
    /// Number of files inside (recursively). 1 for a file.
    public internal(set) var fileCount: Int = 0
    /// Files directly inside this folder that were too small to list individually.
    public internal(set) var looseFileCount: Int = 0
    public internal(set) var looseFileSize: Int64 = 0
    /// Last modification time, in seconds since 1970.
    public internal(set) var modified: Int64 = 0
    public internal(set) var markers: Markers = []
    /// True when the folder couldn't be read (usually missing permission).
    public internal(set) var isUnreadable = false
    /// True when this is, or contains, a Photos, Music or similar library.
    public internal(set) var containsMediaLibrary = false

    /// Folders whose children are named after bundle IDs (which can look like file extensions).
    static let containerFolderNames: Set<String> = ["Containers", "Group Containers", "Application Scripts"]

    init(name: String, kind: Kind, parent: FileNode?) {
        self.name = name
        self.kind = kind
        self.parent = parent
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public var isDirectory: Bool { kind == .directory }
    public var modificationDate: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }

    public var pathExtension: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    /// Folders that Finder shows as a single item, such as apps and photo libraries.
    public var isPackage: Bool {
        guard isDirectory, FileTypeHints.packageExtensions.contains(pathExtension) else { return false }
        if let parentName = parent?.name, Self.containerFolderNames.contains(parentName) { return false }
        return true
    }

    /// Bytes in this node that aren't accounted for by its listed children.
    public var ownSize: Int64 {
        guard isDirectory else { return size }
        return size - children.reduce(0) { $0 + $1.size }
    }

    public func child(named name: String) -> FileNode? {
        children.first { $0.name == name }
    }
}

/// The result of scanning a folder or a whole disk.
public final class FileTree: @unchecked Sendable {
    public enum Style: Sendable {
        /// The tree's root is the scanned folder and paths are relative to it.
        case plain
        /// The tree's root is the macOS Data volume (/System/Volumes/Data). Folders that macOS
        /// "firmlinks" into the root of the disk (Users, Applications, Library, private…)
        /// are reported with their familiar paths, e.g. /Users/you instead of
        /// /System/Volumes/Data/Users/you.
        case dataVolume
    }

    public static let dataVolumePath = "/System/Volumes/Data"

    /// Top-level folders of the Data volume that appear at the root of the disk.
    /// Mirrors /usr/share/firmlinks on macOS 10.15 and later.
    public static let firmlinkedTopLevelNames: Set<String> = [
        "AppleInternal", "Applications", "Library", "System", "Users", "Volumes",
        "cores", "opt", "private", "usr",
    ]

    public let root: FileNode
    public let rootPath: String
    public let style: Style
    public let displayName: String

    public init(root: FileNode, rootPath: String, style: Style, displayName: String) {
        self.root = root
        self.rootPath = rootPath
        self.style = style
        self.displayName = displayName
    }

    /// Path components that come before the given top-level child's name in its canonical path.
    func basePathComponents(forTopLevelChild name: String) -> [String] {
        switch style {
        case .plain:
            return KnowledgeBase.components(of: rootPath)
        case .dataVolume:
            return Self.firmlinkedTopLevelNames.contains(name) ? [] : ["System", "Volumes", "Data"]
        }
    }

    /// Path components for the root node itself.
    var rootPathComponents: [String] {
        switch style {
        case .plain: return KnowledgeBase.components(of: rootPath)
        case .dataVolume: return []
        }
    }

    /// The real, usable path of a node.
    public func path(of node: FileNode) -> String {
        var names: [String] = []
        var current: FileNode? = node
        while let n = current, n !== root {
            names.append(n.name)
            current = n.parent
        }
        names.reverse()
        guard let first = names.first else {
            return style == .dataVolume ? "/" : rootPath
        }
        let base = basePathComponents(forTopLevelChild: first)
        return "/" + (base + names).joined(separator: "/")
    }

    /// Finds the node for a path, if it was part of this scan.
    public func node(atPath path: String) -> FileNode? {
        let comps = KnowledgeBase.components(of: path)
        let relative: ArraySlice<String>
        switch style {
        case .plain:
            let rootComps = KnowledgeBase.components(of: rootPath)
            guard comps.starts(with: rootComps) else { return nil }
            relative = comps.dropFirst(rootComps.count)
        case .dataVolume:
            if comps.starts(with: ["System", "Volumes", "Data"]) {
                relative = comps.dropFirst(3)
            } else if let first = comps.first {
                guard Self.firmlinkedTopLevelNames.contains(first) else { return nil }
                relative = comps[...]
            } else {
                return root
            }
        }
        var node = root
        for name in relative {
            guard let next = node.child(named: name) else { return nil }
            node = next
        }
        return node
    }

    /// The chain of folders from the root down to (and including) the node.
    public func ancestors(of node: FileNode) -> [FileNode] {
        var chain: [FileNode] = []
        var current: FileNode? = node
        while let n = current {
            chain.append(n)
            if n === root { break }
            current = n.parent
        }
        return chain.reversed()
    }

    /// Removes a node after it was deleted from disk, updating the sizes of its parents.
    public func remove(_ node: FileNode) {
        guard node !== root, let parent = node.parent else { return }
        parent.children.removeAll { $0 === node }
        adjustAncestors(startingAt: parent, size: -node.size, files: -node.fileCount)
        node.parent = nil
    }

    /// Empties a folder after its contents were deleted from disk.
    public func removeContents(of node: FileNode) {
        let removedSize = node.children.reduce(node.looseFileSize) { $0 + $1.size }
        let removedFiles = node.fileCount
        for child in node.children { child.parent = nil }
        node.children = []
        node.looseFileCount = 0
        node.looseFileSize = 0
        adjustAncestors(startingAt: node, size: -removedSize, files: -removedFiles)
    }

    private func adjustAncestors(startingAt start: FileNode, size: Int64, files: Int) {
        var current: FileNode? = start
        while let n = current {
            n.size = max(0, n.size + size)
            n.fileCount = max(0, n.fileCount + files)
            if n === root { break }
            current = n.parent
            // Keep siblings ordered largest first now that this node shrank.
            current?.children.sort { $0.size > $1.size }
        }
    }
}
