import Foundation

/// How risky it is to delete something.
public enum SafetyLevel: Int, Comparable, CaseIterable, Sendable, Codable {
    /// Rebuilt or re-downloaded automatically. Nothing you made is lost.
    case safe = 0
    /// Your own files or downloads. Fine to delete if you don't need them.
    case review
    /// Data an app relies on. Deleting it can reset the app or lose data kept inside it.
    case caution
    /// Needed by macOS or managed by another app. Data Explorer never deletes it.
    case protected

    public static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .safe: return "Safe to delete"
        case .review: return "Review first"
        case .caution: return "Use caution"
        case .protected: return "Don't delete"
        }
    }

    public var explanation: String {
        switch self {
        case .safe:
            return "Rebuilt or re-downloaded automatically when it's needed again. Deleting it won't lose anything you made."
        case .review:
            return "Your files, downloads or backups. Fine to delete if you no longer need them, but take a look first."
        case .caution:
            return "Data an app relies on. Deleting it may sign you out, reset settings, or lose data stored in that app."
        case .protected:
            return "Needed by macOS or managed by another app. Data Explorer won't delete it. Check the notes for the right way to shrink it."
        }
    }

    public var symbolName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .review: return "eye.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .protected: return "lock.fill"
        }
    }

    public var isDeletable: Bool { self != .protected }
}

/// Broad buckets used to explain where the space went.
public enum StorageCategory: String, CaseIterable, Sendable, Codable, Identifiable {
    case apps
    case personalFiles
    case mediaLibraries
    case cloudFiles
    case mailAndMessages
    case deviceBackups
    case developer
    case virtualMachines
    case caches
    case logs
    case appData
    case systemManaged
    case trash
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apps: return "Apps"
        case .personalFiles: return "Your files"
        case .mediaLibraries: return "Photos, music & video libraries"
        case .cloudFiles: return "iCloud Drive & cloud folders"
        case .mailAndMessages: return "Mail & Messages"
        case .deviceBackups: return "iPhone & iPad backups"
        case .developer: return "Developer tools & caches"
        case .virtualMachines: return "Virtual machines & Docker"
        case .caches: return "Caches"
        case .logs: return "Logs & crash reports"
        case .appData: return "App data"
        case .systemManaged: return "Managed by macOS"
        case .trash: return "Trash"
        case .other: return "Other"
        }
    }

    public var summary: String {
        switch self {
        case .apps:
            return "Applications you've installed."
        case .personalFiles:
            return "Documents, Desktop, Downloads and other files in your home folder."
        case .mediaLibraries:
            return "The Photos, Music, TV and Podcasts libraries, and media projects."
        case .cloudFiles:
            return "Local copies of files from iCloud Drive, Dropbox, Google Drive, OneDrive and similar."
        case .mailAndMessages:
            return "Downloaded email, attachments and message history."
        case .deviceBackups:
            return "Backups and software updates for iPhone and iPad made through Finder."
        case .developer:
            return "Xcode, simulators, package-manager caches and project build folders."
        case .virtualMachines:
            return "Disk images for Docker, Parallels, UTM, VMware and other virtual machines."
        case .caches:
            return "Temporary copies apps keep to load faster. Apps rebuild them when needed."
        case .logs:
            return "Diagnostic logs and crash reports."
        case .appData:
            return "Settings, databases and downloaded content that apps keep in your Library."
        case .systemManaged:
            return "Indexes, temporary files, virtual memory and system assets that macOS manages itself."
        case .trash:
            return "Files you've deleted but not yet emptied from the Trash."
        case .other:
            return "Files Data Explorer doesn't have a specific explanation for."
        }
    }

    /// Where System Settings › General › Storage usually puts this.
    public var settingsLabel: String {
        switch self {
        case .apps: return "Applications"
        case .personalFiles: return "Documents"
        case .mediaLibraries: return "Photos, Music, TV or Podcasts"
        case .cloudFiles: return "iCloud Drive or Documents"
        case .mailAndMessages: return "Mail or Messages"
        case .deviceBackups: return "iOS Files"
        case .developer: return "Developer, or System Data"
        case .virtualMachines: return "System Data"
        case .caches: return "System Data"
        case .logs: return "System Data"
        case .appData: return "System Data"
        case .systemManaged: return "System Data or macOS"
        case .trash: return "Trash"
        case .other: return "System Data or Documents"
        }
    }

    /// Whether System Settings typically lumps this into "System Data".
    public var isUsuallySystemData: Bool {
        switch self {
        case .virtualMachines, .caches, .logs, .appData, .systemManaged, .other: return true
        default: return false
        }
    }
}

/// Formats byte counts with decimal units, matching Finder and System Settings.
public enum ByteFormatter {
    private static let units = ["KB", "MB", "GB", "TB", "PB"]

    public static func string(_ bytes: Int64) -> String {
        if bytes == 1 { return "1 byte" }
        if bytes.magnitude < 1000 { return "\(bytes) bytes" }
        var value = Double(bytes) / 1000
        var index = 0
        while abs(value) >= 999.95, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let text = abs(value) >= 99.95 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(text) \(units[index])"
    }
}

/// Something the user can choose to delete.
public struct CleanupTarget: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// Delete the file or folder itself.
        case item
        /// Keep the folder, delete everything inside it.
        case contents
    }

    public let path: String
    public let kind: Kind
    public let title: String
    public let size: Int64
    public let safety: SafetyLevel

    public init(path: String, kind: Kind, title: String, size: Int64, safety: SafetyLevel) {
        self.path = path
        self.kind = kind
        self.title = title
        self.size = size
        self.safety = safety
    }

    public var id: String { kind.rawValue + ":" + path }

    /// True when cleaning this target would also take care of `other`.
    public func covers(_ other: CleanupTarget) -> Bool {
        if other.path == path {
            return kind == .item || other.kind == .contents
        }
        return other.path.hasPrefix(path == "/" ? "/" : path + "/")
    }
}

/// The list of things the user has picked for deletion.
public struct CleanupBasket: Sendable {
    public private(set) var targets: [CleanupTarget] = []

    public init() {}

    public var isEmpty: Bool { targets.isEmpty }
    public var count: Int { targets.count }
    public var totalSize: Int64 { targets.reduce(0) { $0 + $1.size } }

    public func contains(_ target: CleanupTarget) -> Bool {
        targets.contains { $0.id == target.id }
    }

    /// True when the target, or something containing it, is already in the basket.
    public func isCovered(_ target: CleanupTarget) -> Bool {
        targets.contains { $0.covers(target) }
    }

    /// Adds a target, dropping anything it makes redundant. Returns false if it was already covered.
    @discardableResult
    public mutating func add(_ target: CleanupTarget) -> Bool {
        if isCovered(target) { return false }
        targets.removeAll { target.covers($0) }
        targets.append(target)
        return true
    }

    public mutating func remove(_ target: CleanupTarget) {
        targets.removeAll { $0.id == target.id }
    }

    /// Removes the target and anything inside it.
    public mutating func removeCovered(by target: CleanupTarget) {
        targets.removeAll { target.covers($0) || $0.id == target.id }
    }

    public mutating func removeAll() {
        targets.removeAll()
    }

    /// Drops targets whose paths were deleted.
    public mutating func removeTargets(atPaths paths: Set<String>) {
        targets.removeAll { paths.contains($0.path) }
    }
}
