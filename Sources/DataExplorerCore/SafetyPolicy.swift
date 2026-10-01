import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Decides whether Data Explorer is allowed to delete something.
///
/// Every cleanup goes through this check twice: when the item is offered in the interface, and
/// again right before it's deleted.
public struct SafetyPolicy: Sendable {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(String)

        public var isAllowed: Bool { self == .allowed }

        public var reason: String? {
            if case .blocked(let reason) = self { return reason }
            return nil
        }
    }

    public let knowledge: KnowledgeBase
    /// Paths that are never deleted, nor anything inside them.
    public let protectedPrefixes: [String]
    /// Paths inside `protectedPrefixes` that are allowed after all.
    public let exceptions: [String]
    /// Cloud-synced folders where deleting removes files everywhere.
    public let cloudPrefixes: [String]
    /// Essential folders that must survive when a folder containing them is deleted or emptied.
    private let guardedFolders: [String]

    public init(knowledge: KnowledgeBase, protectedPrefixes: [String]? = nil, exceptions: [String]? = nil) {
        let home = knowledge.home
        self.knowledge = knowledge
        self.protectedPrefixes = (protectedPrefixes ?? Self.defaultProtectedPrefixes(home: home)).map { $0.lowercased() }
        self.exceptions = (exceptions ?? ["/usr/local"]).map { $0.lowercased() }
        self.cloudPrefixes = [home + "/Library/Mobile Documents", home + "/Library/CloudStorage"].map { $0.lowercased() }
        var guards = [home.lowercased()]
        for location in knowledge.locations where location.isEssential {
            guards += location.paths
                .map { KnowledgeBase.expand($0, home: home) }
                .filter { !$0.contains("*") }
                .map { $0.lowercased() }
        }
        self.guardedFolders = guards
    }

    public static func defaultProtectedPrefixes(home: String) -> [String] {
        [
            "/System", "/bin", "/sbin", "/usr", "/private", "/etc", "/var", "/tmp", "/dev", "/Volumes",
            "/Library/Keychains", "/Library/Apple", "/Library/Extensions", "/Library/SystemExtensions",
            "/Library/Security", "/Library/LaunchDaemons", "/Library/LaunchAgents", "/Library/PrivilegedHelperTools",
            "/Library/Preferences", "/Library/Frameworks", "/Library/Filesystems",
            "/Library/OpenDirectory", "/Library/DirectoryServices", "/Library/Managed Preferences",
            "/Library/DriverExtensions", "/Library/StagedExtensions", "/Library/KernelCollections",
            "/Library/Receipts", "/Library/SystemMigration", "/Library/Application Support/com.apple.TCC",
            home + "/Library/Keychains", home + "/.ssh", home + "/.gnupg",
        ]
    }

    private static func isPath(_ path: String, inside prefix: String) -> Bool {
        path == prefix || path.hasPrefix(prefix == "/" ? "/" : prefix + "/")
    }

    /// - Parameter partOfClearing: true when the path is a direct child of a folder whose
    ///   contents are being cleared, which has already passed its own check.
    public func check(_ path: String, kind: CleanupTarget.Kind, partOfClearing: Bool = false) -> Verdict {
        guard path.hasPrefix("/"), path.count > 1 else {
            return .blocked("This is the top of your disk.")
        }
        let names = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        if names.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            return .blocked("This path looks unusual, so Data Explorer won't touch it.")
        }

        let lowered = path.lowercased()
        let isException = exceptions.contains { Self.isPath(lowered, inside: $0) }
        if !isException, protectedPrefixes.contains(where: { Self.isPath(lowered, inside: $0) }) {
            let detail = knowledge.explain(path: path, isDirectory: kind == .contents)
            if let steps = detail.manualSteps {
                return .blocked("This belongs to macOS, so Data Explorer won't delete it. \(steps)")
            }
            return .blocked("This belongs to macOS. Deleting it could stop your Mac or its apps from working properly.")
        }
        if cloudPrefixes.contains(where: { Self.isPath(lowered, inside: $0) }) {
            return .blocked("This is cloud storage: deleting it here deletes it from the cloud and from your other devices. To free space without deleting, right-click it in Finder and choose Remove Download.")
        }

        for (index, name) in names.dropLast().enumerated() {
            // App containers are named after bundle IDs like "com.utmapp.UTM"; they aren't packages.
            if index >= 2, names[index - 2] == "Library", FileNode.containerFolderNames.contains(names[index - 1]) {
                continue
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if FileTypeHints.packageExtensions.contains(ext) {
                return .blocked("This is part of \"\(name)\". Pieces of it can't be deleted on their own; delete the whole item instead, or manage it from its app.")
            }
        }
        if let last = names.last, FileTypeHints.mediaLibraryExtensions.contains((last as NSString).pathExtension.lowercased()) {
            return .blocked("This is a media library holding photos, music or video. Open it in its app to remove what you don't need, and only delete the whole library in Finder once you're sure it's backed up or no longer needed.")
        }

        if !partOfClearing {
            let ancestorGuard = lowered + "/"
            if let guarded = guardedFolders.first(where: { $0.hasPrefix(ancestorGuard) }) {
                let inner = (guarded as NSString).lastPathComponent
                return .blocked("This folder contains folders that apps or macOS rely on (such as \"\(inner)\"). Delete specific items inside it instead.")
            }
        }

        guard let match = knowledge.match(path: path) else {
            return kind == .item ? .allowed : .blocked("Choose individual items inside this folder instead.")
        }
        let location = match.location
        if let ancestor = match.restrictingAncestor {
            return .blocked(blockedReason(for: ancestor))
        }

        if match.isExact {
            if location.safety == .protected {
                return .blocked(blockedReason(for: location))
            }
            switch (kind, location.cleanup) {
            case (.item, .trashItem), (.contents, .trashContents):
                return .allowed
            case (_, .manual(let steps)):
                return .blocked(steps)
            case (.item, _) where partOfClearing:
                return .allowed
            case (.item, _):
                return .blocked("This is a standard folder that macOS or apps expect to exist. You can delete what's inside it, but not the folder itself.")
            case (.contents, _):
                return .blocked("Emptying this whole folder isn't supported. Choose individual items inside it instead.")
            }
        }

        if kind == .contents {
            return .blocked("Emptying this whole folder isn't supported. Choose individual items inside it instead.")
        }
        if location.cleanup == .individually || location.cleanup == .trashItem, Self.isProgramFile(path) {
            return .blocked("This is part of an installed program or tool. Deleting it on its own would break that program. Remove the whole program (or use its uninstaller) instead.")
        }
        if (location.insideSafety ?? location.safety) == .protected {
            return .blocked(blockedReason(for: location))
        }
        if let steps = location.manualSteps {
            return .blocked("This is part of \(location.title), which shouldn't be edited directly. \(steps)")
        }
        return .allowed
    }

    static let containsLibraryReason = "This folder contains a photo, music or video library. Open the library in its app to remove what you don't need, or move the library somewhere else first."

    /// Checks a scanned item, which also knows whether a folder holds a media library somewhere inside.
    public func check(_ node: FileNode, in tree: FileTree) -> Verdict {
        check(node, at: tree.path(of: node))
    }

    public func check(_ node: FileNode, at path: String) -> Verdict {
        if node.isDirectory, node.containsMediaLibrary,
           !FileTypeHints.mediaLibraryExtensions.contains(node.pathExtension) {
            return .blocked(Self.containsLibraryReason)
        }
        return check(path, kind: .item)
    }

    /// Whether deleting this folder needs a look inside it first (for media libraries). Folders
    /// meant to be emptied, like caches, don't.
    func shouldLookInside(_ path: String) -> Bool {
        guard let match = knowledge.match(path: path) else { return true }
        return match.location.cleanup != .trashContents
    }

    /// Looks for Photos, Music, TV or similar libraries anywhere inside a folder on disk.
    static func containsMediaLibrary(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if FileTypeHints.mediaLibraryExtensions.contains(url.pathExtension.lowercased()) { return true }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) else { return false }
        for case let item as URL in enumerator where FileTypeHints.mediaLibraryExtensions.contains(item.pathExtension.lowercased()) {
            return true
        }
        return false
    }

    /// Libraries and other pieces of installed software: removing one breaks the whole program.
    static let programExtensions: Set<String> = ["dylib", "so", "a", "o", "jar", "node", "dll", "exe", "pyd", "wasm"]

    /// True for code libraries and for executable files without an extension.
    static func isProgramFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if programExtensions.contains(ext) { return true }
        guard ext.isEmpty else { return false }
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        let mode = UInt32(info.st_mode)
        let isRegularFile = mode & 0o170000 == 0o100000
        return isRegularFile && mode & 0o111 != 0
    }

    private func blockedReason(for location: KnownLocation) -> String {
        if let steps = location.manualSteps {
            return "\(location.title) shouldn't be deleted directly. \(steps)"
        }
        return "\(location.title): \(location.ifDeleted) Data Explorer won't delete it."
    }
}
