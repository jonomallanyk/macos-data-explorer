import AppKit
import DataExplorerCore

/// macOS-specific helpers: permissions, Finder, and app names.
enum MacSystem {
    static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Full Disk Access can't be queried directly, so check whether a few locations that only
    /// Full Disk Access unlocks can be read. These are silently denied otherwise, so the check
    /// never triggers a permission prompt. (Folders like Documents or other apps' containers
    /// would prompt, so they're deliberately not used.)
    static func hasFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let probes = [
            home + "/Library/Safari",
            home + "/Library/Mail",
            home + "/Library/Messages",
            "/Library/Application Support/com.apple.TCC",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
                return true
            }
        }
        let tccDatabase = "/Library/Application Support/com.apple.TCC/TCC.db"
        if let handle = FileHandle(forReadingAtPath: tccDatabase) {
            try? handle.close()
            return true
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(fullDiskAccessSettingsURL)
    }

    static func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// Runs a shell command after macOS asks the user for an administrator password.
    static func runWithAdministratorPrivileges(_ command: String) -> (success: Bool, message: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        guard let result = CommandRunner.run("/usr/bin/osascript", ["-e", script]) else {
            return (false, "Couldn't run the command.")
        }
        if result.status == 0 { return (true, result.text) }
        let message = result.errorOutput.contains("-128") ? "Cancelled." : result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, message)
    }

    /// Asks Finder to empty the Trash, as a fallback when Data Explorer can't read it itself.
    static func emptyTrashWithFinder() -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        script?.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Finder couldn't empty the Trash."
        }
        return nil
    }
}

/// Moves items to the Trash, falling back to Finder's way of doing it (which can ask for an
/// administrator password) when the item belongs to another user or the system.
struct MacFileRemover: FileRemoving {
    func moveToTrash(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
            try recycle(url, originalError: error)
        }
    }

    func deletePermanently(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func contentsOfDirectory(_ path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    private final class ResultBox: @unchecked Sendable {
        var failed = false
    }

    private func recycle(_ url: URL, originalError: Error) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()
        DispatchQueue.main.async {
            NSWorkspace.shared.recycle([url]) { _, error in
                result.failed = error != nil
                semaphore.signal()
            }
        }
        if semaphore.wait(timeout: .now() + 300) == .timedOut || result.failed {
            throw originalError
        }
    }
}

/// Friendly names for folders named after app bundle IDs, like "com.spotify.client".
@MainActor
enum AppNames {
    private static var cache: [String: String] = [:]
    private static var misses: Set<String> = []

    static func looksLikeBundleID(_ name: String) -> Bool {
        name.split(separator: ".").count >= 3 && !name.contains(" ") && !name.hasSuffix(".app")
    }

    static func name(forBundleID identifier: String) -> String? {
        if let cached = cache[identifier] { return cached }
        if misses.contains(identifier) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            misses.insert(identifier)
            return nil
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        cache[identifier] = name
        return name
    }

    /// "Spotify" for "com.spotify.client"; otherwise the name unchanged.
    static func friendly(_ name: String) -> String {
        guard looksLikeBundleID(name) else { return name }
        return self.name(forBundleID: name) ?? name
    }
}

/// App icons for .app bundles, cached.
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        if cache.count > 500 { cache.removeAll() }
        cache[path] = image
        return image
    }
}
