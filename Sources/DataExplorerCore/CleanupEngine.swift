import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum CleanupMode: String, CaseIterable, Sendable {
    /// Move to the Trash, so it can be put back. Space is only freed once the Trash is emptied.
    case moveToTrash
    /// Delete straight away.
    case deleteImmediately

    public var title: String {
        switch self {
        case .moveToTrash: return "Move to Trash"
        case .deleteImmediately: return "Delete immediately"
        }
    }
}

public protocol FileRemoving: Sendable {
    func moveToTrash(_ path: String) throws
    func deletePermanently(_ path: String) throws
    func contentsOfDirectory(_ path: String) throws -> [String]
}

public struct FileManagerRemover: FileRemoving {
    public init() {}

    public func moveToTrash(_ path: String) throws {
        #if os(macOS)
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    public func deletePermanently(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    public func contentsOfDirectory(_ path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
}

public struct CleanupOutcome: Sendable {
    public struct Failure: Identifiable, Sendable {
        public let path: String
        public let reason: String
        public var id: String { path }
    }

    public var mode: CleanupMode
    /// Targets that were fully removed.
    public var completed: [CleanupTarget] = []
    /// Folder-contents targets where only some items could be removed.
    public var partial: [CleanupTarget] = []
    public var failures: [Failure] = []
    /// Every file or folder that was removed.
    public var removedPaths: [String] = []
    /// Folders whose contents were removed completely.
    public var clearedFolders: [String] = []
    /// Estimated bytes removed (or moved to the Trash).
    public var bytesHandled: Int64 = 0

    public init(mode: CleanupMode) {
        self.mode = mode
    }
}

/// Deletes the user's chosen targets, re-checking each against the safety policy first.
public struct CleanupEngine: Sendable {
    public let policy: SafetyPolicy
    public let remover: FileRemoving
    public let trashFolder: String

    public init(policy: SafetyPolicy, remover: FileRemoving = FileManagerRemover(), trashFolder: String? = nil) {
        self.policy = policy
        self.remover = remover
        self.trashFolder = trashFolder ?? policy.knowledge.home + "/.Trash"
    }

    public func run(
        _ targets: [CleanupTarget],
        mode: CleanupMode,
        progress: ((_ done: Int, _ total: Int, _ current: String) -> Void)? = nil
    ) -> CleanupOutcome {
        var outcome = CleanupOutcome(mode: mode)

        for (offset, target) in targets.enumerated() {
            progress?(offset, targets.count, target.title)

            if case .blocked(let reason) = policy.check(target.path, kind: target.kind) {
                outcome.failures.append(.init(path: target.path, reason: reason))
                continue
            }

            switch target.kind {
            case .item:
                do {
                    try remove(target.path, mode: mode)
                    outcome.completed.append(target)
                    outcome.removedPaths.append(target.path)
                    outcome.bytesHandled += target.size
                } catch {
                    outcome.failures.append(.init(path: target.path, reason: Self.describe(error)))
                }

            case .contents:
                let names: [String]
                do {
                    names = try remover.contentsOfDirectory(target.path)
                } catch {
                    outcome.failures.append(.init(path: target.path, reason: Self.describe(error)))
                    continue
                }
                var failed = 0
                for name in names {
                    let child = target.path + "/" + name
                    if case .blocked(let reason) = policy.check(child, kind: .item, partOfClearing: true) {
                        failed += 1
                        outcome.failures.append(.init(path: child, reason: reason))
                        continue
                    }
                    do {
                        try remove(child, mode: mode)
                        outcome.removedPaths.append(child)
                    } catch {
                        failed += 1
                        if outcome.failures.count < 1_000 {
                            outcome.failures.append(.init(path: child, reason: Self.describe(error)))
                        }
                    }
                }
                if failed == 0 {
                    outcome.completed.append(target)
                    outcome.clearedFolders.append(target.path)
                    outcome.bytesHandled += target.size
                } else if failed < names.count {
                    outcome.partial.append(target)
                    let share = Double(names.count - failed) / Double(names.count)
                    outcome.bytesHandled += Int64(Double(target.size) * share)
                }
            }
        }

        progress?(targets.count, targets.count, "")
        return outcome
    }

    private func remove(_ path: String, mode: CleanupMode) throws {
        let alreadyInTrash = path.hasPrefix(trashFolder + "/")
        do {
            if mode == .deleteImmediately || alreadyInTrash {
                try remover.deletePermanently(path)
            } else {
                try remover.moveToTrash(path)
            }
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone, which is what we wanted.
        }
    }

    static func describe(_ error: Error) -> String {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileWriteNoPermission, .fileReadNoPermission:
                return "Permission denied. This item belongs to macOS or another user; deleting it needs an administrator password (try it in Finder)."
            case .fileWriteVolumeReadOnly:
                return "The disk is read-only."
            case .fileLocking:
                return "The item is locked. Unlock it in Finder (Get Info) first."
            default:
                break
            }
            if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.domain == NSPOSIXErrorDomain,
               underlying.code == Int(EPERM) || underlying.code == Int(EACCES) {
                return "Permission denied. Data Explorer may need Full Disk Access, or the item needs an administrator password to delete (try it in Finder)."
            }
        }
        return error.localizedDescription
    }
}
