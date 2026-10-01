import Foundation

/// Capacity figures for a disk, as macOS reports them.
public struct VolumeCapacity: Sendable {
    public let name: String
    public let total: Int64
    /// Truly free space.
    public let available: Int64
    /// Free space plus "purgeable" space macOS can reclaim on demand (snapshots, cached iCloud files…).
    public let availableIncludingPurgeable: Int64

    public init(name: String, total: Int64, available: Int64, availableIncludingPurgeable: Int64) {
        self.name = name
        self.total = total
        self.available = available
        self.availableIncludingPurgeable = max(available, availableIncludingPurgeable)
    }

    public var purgeable: Int64 { availableIncludingPurgeable - available }
    public var used: Int64 { max(0, total - available) }

    public static func current(for path: String = "/") -> VolumeCapacity? {
        let url = URL(fileURLWithPath: path)
        #if os(macOS)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        return VolumeCapacity(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            total: Int64(total),
            available: Int64(available),
            availableIncludingPurgeable: important
        )
        #else
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let total = (attributes[.systemSize] as? NSNumber)?.int64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else { return nil }
        return VolumeCapacity(name: "Disk", total: total, available: free, availableIncludingPurgeable: free)
        #endif
    }
}

/// Runs a command-line tool and captures its output.
public enum CommandRunner {
    public struct Result: Sendable {
        public let status: Int32
        public let output: Data
        public let errorOutput: String

        public var text: String { String(decoding: output, as: UTF8.self) }
    }

    public static func run(_ executable: String, _ arguments: [String]) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: output, errorOutput: String(decoding: errorData, as: UTF8.self))
    }
}

// MARK: - APFS volumes

/// A volume inside the APFS container that holds the startup disk.
public struct APFSVolume: Identifiable, Sendable {
    public let name: String
    public let device: String
    public let roles: [String]
    public let used: Int64

    public var id: String { device }

    public var role: String { roles.first ?? "" }

    public var title: String {
        switch role {
        case "System": return "macOS (sealed system)"
        case "Data": return "Data (\(name))"
        case "VM": return "Virtual memory (swap)"
        case "Preboot": return "Preboot"
        case "Recovery": return "Recovery"
        case "Update": return "macOS update staging"
        default: return name
        }
    }

    public var explanation: String {
        switch role {
        case "System":
            return "macOS itself, on a sealed read-only volume. System Settings shows this as \"macOS\". It can't be changed or shrunk."
        case "Data":
            return "Everything else: your files, apps, caches and most of what System Settings calls \"System Data\". This is what Data Explorer scans."
        case "VM":
            return "Swap space macOS uses when apps need more memory than your Mac has. It grows under memory pressure and shrinks after a restart. Counted in System Data."
        case "Preboot":
            return "Files needed to start up your Mac and unlock FileVault, for each installed macOS version. Counted in System Data."
        case "Recovery":
            return "macOS Recovery, used to repair or reinstall macOS."
        case "Update":
            return "A staging area for macOS updates. Usually empty or small once updates are installed."
        default:
            return "An additional volume in your startup disk's container."
        }
    }
}

public struct APFSContainer: Sendable {
    public let reference: String
    public let capacity: Int64
    public let free: Int64
    public let volumes: [APFSVolume]

    public var dataVolume: APFSVolume? { volumes.first { $0.roles.contains("Data") } }
}

public enum APFSInfo {
    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let int = value as? Int { return Int64(int) }
        if let int = value as? Int64 { return int }
        return nil
    }

    private static func dictionary(from data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    /// Parses `diskutil apfs list -plist`.
    public static func parseContainers(_ data: Data) -> [APFSContainer] {
        guard let root = dictionary(from: data),
              let containers = root["Containers"] as? [[String: Any]] else { return [] }
        return containers.compactMap { container -> APFSContainer? in
            guard let reference = container["ContainerReference"] as? String else { return nil }
            let volumes = (container["Volumes"] as? [[String: Any]] ?? []).compactMap { volume -> APFSVolume? in
                guard let device = volume["DeviceIdentifier"] as? String else { return nil }
                return APFSVolume(
                    name: volume["Name"] as? String ?? device,
                    device: device,
                    roles: volume["Roles"] as? [String] ?? [],
                    used: int64(volume["CapacityInUse"]) ?? 0
                )
            }
            return APFSContainer(
                reference: reference,
                capacity: int64(container["CapacityCeiling"]) ?? 0,
                free: int64(container["CapacityFree"]) ?? 0,
                volumes: volumes
            )
        }
    }

    /// Parses `diskutil info -plist /` to find which container holds the startup disk.
    public static func containerReference(fromDiskInfo data: Data) -> String? {
        guard let info = dictionary(from: data) else { return nil }
        return info["APFSContainerReference"] as? String ?? info["ParentWholeDisk"] as? String
    }

    /// The container holding the startup disk, using diskutil.
    public static func startupContainer() -> APFSContainer? {
        guard let info = CommandRunner.run("/usr/sbin/diskutil", ["info", "-plist", "/"]), info.status == 0,
              let reference = containerReference(fromDiskInfo: info.output),
              let list = CommandRunner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"]), list.status == 0 else {
            return nil
        }
        return parseContainers(list.output).first { $0.reference == reference }
    }
}

// MARK: - Time Machine local snapshots

public struct LocalSnapshot: Identifiable, Hashable, Sendable {
    public let name: String
    /// The snapshot's timestamp, formatted as tmutil expects (YYYY-MM-DD-HHMMSS).
    public let stamp: String?

    public var id: String { name }

    public var date: Date? {
        guard let stamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: stamp)
    }
}

public enum LocalSnapshots {
    /// Parses `tmutil listlocalsnapshots /`.
    public static func parse(_ output: String) -> [LocalSnapshot] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine -> LocalSnapshot? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("com.apple.") else { return nil }
            let stamp = line.split(separator: ".").map(String.init).first(where: isStamp)
            return LocalSnapshot(name: line, stamp: stamp)
        }
    }

    /// True for "2024-05-01-123456".
    static func isStamp(_ text: String) -> Bool {
        let characters = Array(text)
        guard characters.count == 17 else { return false }
        for (index, character) in characters.enumerated() {
            if [4, 7, 10].contains(index) {
                if character != "-" { return false }
            } else if !character.isASCII || !character.isNumber {
                return false
            }
        }
        return true
    }

    public static func list(volume: String = "/") -> [LocalSnapshot] {
        guard let result = CommandRunner.run("/usr/bin/tmutil", ["listlocalsnapshots", volume]), result.status == 0 else {
            return []
        }
        return parse(result.text)
    }

    /// A shell command that deletes the given snapshots, or nil if none have a valid timestamp.
    /// Only validated timestamps are included, so the command is safe to run with admin rights.
    public static func deletionCommand(for snapshots: [LocalSnapshot]) -> String? {
        let commands = snapshots.compactMap(\.stamp).filter(isStamp).map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }
        return commands.isEmpty ? nil : commands.joined(separator: "; ")
    }
}
