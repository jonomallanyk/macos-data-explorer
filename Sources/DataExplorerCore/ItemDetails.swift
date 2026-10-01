import Foundation

/// Reads small metadata files to describe items more helpfully, e.g. which iPhone a backup
/// belongs to.
enum ItemDetails {
    struct Detail {
        var name: String?
        var detail: String?
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func readPlist(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    static func describe(locationID: String, path: String, name: String) -> Detail? {
        switch locationID {
        case "ios-backups": return iosBackup(path)
        case "simulator-devices": return simulatorDevice(path)
        case "derived-data": return derivedData(path, name: name)
        default: return nil
        }
    }

    static func iosBackup(_ path: String) -> Detail? {
        guard let info = readPlist(path + "/Info.plist") else { return nil }
        let deviceName = info["Device Name"] as? String ?? info["Display Name"] as? String
        let model = info["Product Name"] as? String ?? info["Product Type"] as? String
        var parts: [String] = []
        if let model { parts.append(model) }
        if let version = info["Product Version"] as? String { parts.append("iOS \(version)") }
        if let date = info["Last Backup Date"] as? Date {
            parts.append("backed up \(dateFormatter.string(from: date))")
        }
        return Detail(name: deviceName.map { "Backup of \($0)" }, detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    static func simulatorDevice(_ path: String) -> Detail? {
        guard let info = readPlist(path + "/device.plist") else { return nil }
        let name = info["name"] as? String
        var detail: String?
        if let runtime = info["runtime"] as? String {
            detail = runtimeName(runtime)
        }
        return Detail(name: name, detail: detail)
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-2" → "iOS 17.2"
    static func runtimeName(_ identifier: String) -> String {
        guard let marker = identifier.range(of: "SimRuntime.") else { return identifier }
        let raw = identifier[marker.upperBound...]
        let parts = raw.split(separator: "-").map(String.init)
        guard let platform = parts.first else { return String(raw) }
        let version = parts.dropFirst().joined(separator: ".")
        let displayPlatform = platform == "xrOS" ? "visionOS" : platform
        return version.isEmpty ? displayPlatform : "\(displayPlatform) \(version)"
    }

    /// DerivedData folders are named "<Project>-<28 random letters>".
    static func derivedData(_ path: String, name: String) -> Detail? {
        var projectName = name
        if let dash = name.lastIndex(of: "-"), name.distance(from: dash, to: name.endIndex) == 29 {
            projectName = String(name[..<dash])
        }
        guard let info = readPlist(path + "/info.plist"), let workspace = info["WorkspacePath"] as? String else {
            return Detail(name: projectName, detail: nil)
        }
        let exists = FileManager.default.fileExists(atPath: workspace)
        let shown = (workspace as NSString).abbreviatingWithTildeInPath
        return Detail(
            name: projectName,
            detail: exists ? "Project: \(shown)" : "Project no longer exists at \(shown)"
        )
    }

    /// Turns "com.example.MyApp" into something friendlier when there's no better name.
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && !name.contains(" ")
    }
}

/// Finds the bundle identifiers of installed apps, to spot data left behind by deleted apps.
public enum InstalledApps {
    public static var defaultSearchFolders: [String] {
        [
            "/Applications", NSHomeDirectory() + "/Applications", "/System/Applications",
            "/System/Library/CoreServices", "/Library/Application Support",
        ]
    }

    /// Lower-cased bundle IDs of every app (and app extension or helper) found.
    public static func bundleIdentifiers(searching folders: [String] = defaultSearchFolders) -> Set<String> {
        var identifiers = Set<String>()
        let fileManager = FileManager.default

        func readBundle(_ bundlePath: String, depth: Int) {
            if let info = ItemDetails.readPlist(bundlePath + "/Contents/Info.plist"),
               let identifier = info["CFBundleIdentifier"] as? String {
                identifiers.insert(identifier.lowercased())
            }
            guard depth < 2 else { return }
            for sub in ["Contents/Library/LoginItems", "Contents/PlugIns", "Contents/Helpers", "Contents/Applications", "Contents/Library/Helpers"] {
                let folder = bundlePath + "/" + sub
                guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { continue }
                for name in names where name.hasSuffix(".app") || name.hasSuffix(".appex") {
                    readBundle(folder + "/" + name, depth: depth + 1)
                }
            }
        }

        func walk(_ folder: String, depth: Int) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { return }
            for name in names {
                let path = folder + "/" + name
                if name.hasSuffix(".app") {
                    readBundle(path, depth: 0)
                } else if depth < 2, !name.hasPrefix(".") {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                        walk(path, depth: depth + 1)
                    }
                }
            }
        }

        for folder in folders { walk(folder, depth: 0) }
        return identifiers
    }

    /// True when an installed app's ID equals the given ID or is a prefix of it
    /// (extensions and helpers use IDs like "com.example.app.widget").
    public static func isInstalled(_ identifier: String, in installed: Set<String>) -> Bool {
        let id = identifier.lowercased()
        if installed.contains(id) { return true }
        var parts = id.split(separator: ".")
        while parts.count > 2 {
            parts.removeLast()
            if installed.contains(parts.joined(separator: ".")) { return true }
        }
        return false
    }
}
