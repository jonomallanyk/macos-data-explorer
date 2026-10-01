import XCTest
@testable import DataExplorerCore

final class AnalyzerTests: XCTestCase {
    /// The sandbox lives under /private/var/folders on macOS, which the default policy protects,
    /// so tests use a policy that only protects the usual system folders.
    func makePolicy(_ knowledge: KnowledgeBase) -> SafetyPolicy {
        SafetyPolicy(knowledge: knowledge, protectedPrefixes: ["/System", "/usr", knowledge.home + "/Library/Keychains"])
    }

    func makeHome() throws -> Sandbox {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example.app/cache.db", bytes: 2_000_000)
        try box.file("Library/Caches/com.other.tool/blob", bytes: 1_100_000)
        try box.file("Library/Caches/loose.txt", bytes: 50)
        try box.file("Library/Developer/Xcode/DerivedData/MyApp-abcdefghijklmnopqrstuvwxyzab/Build/out.o", bytes: 3_000_000)
        try box.file("Library/Containers/com.gone.app/Data/Library/data.bin", bytes: 11_000_000)
        try box.file("Library/Containers/com.present.app/Data/Library/Caches/c.bin", bytes: 1_500_000)
        try box.file("Library/Messages/chat.db", bytes: 1_500_000)
        try box.file("Code/web/package.json", bytes: 30)
        try box.file("Code/web/node_modules/react/index.js", bytes: 6_000_000)
        try box.file("Code/rusty/Cargo.toml", bytes: 30)
        try box.file("Code/rusty/target/debug/app", bytes: 5_500_000)
        try box.file("Code/notrust/target/thing.bin", bytes: 5_500_000)
        try box.file("Downloads/Tool.dmg", bytes: 2_500_000)
        try box.file("Downloads/Notes.txt", bytes: 1_200_000)
        try box.file("Documents/movie.mov", bytes: 4_000_000)
        try box.file(".Trash/old.zip", bytes: 1_300_000)
        return box
    }

    func testAnalysisFindsSuggestions() throws {
        let box = try makeHome()
        let knowledge = KnowledgeBase.standard(home: box.root)
        var analyzer = ScanAnalyzer(knowledge: knowledge, policy: makePolicy(knowledge), installedAppIDs: ["com.present.app"])
        analyzer.largeFileThreshold = 3_500_000

        let output = try DiskScanner.scan(.folder(box.root))
        let report = analyzer.analyze(output)
        let byID = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.id, $0) })

        // App caches: listed per app, and the whole folder can be emptied.
        let caches = try XCTUnwrap(byID["caches"])
        XCTAssertEqual(caches.safety, .safe)
        XCTAssertEqual(caches.wholeTargets.map(\.kind), [.contents])
        XCTAssertEqual(caches.items.first?.name, "com.example.app")
        XCTAssertNotNil(caches.items.first?.target)
        XCTAssertTrue(caches.items.contains { $0.isSummary }, "Loose files are summarised")

        let derived = try XCTUnwrap(byID["derived-data"])
        XCTAssertEqual(derived.items.first?.name, "MyApp")

        // Sandboxed app caches are found through the wildcard rule.
        let containerCaches = try XCTUnwrap(byID["container-caches"])
        XCTAssertEqual(containerCaches.items.first?.name, "com.present.app")

        // Messages can't be deleted from here.
        let messages = try XCTUnwrap(byID["messages"])
        XCTAssertTrue(messages.wholeTargets.isEmpty)
        XCTAssertNotNil(messages.manualSteps)
        XCTAssertFalse(messages.isActionable)

        // Project folders: node_modules and a real Rust target, but not a random "target" folder.
        let artifacts = try XCTUnwrap(byID["project-artifacts"])
        let artifactPaths = Set(artifacts.items.map(\.path))
        XCTAssertTrue(artifactPaths.contains(box.root + "/Code/web/node_modules"))
        XCTAssertTrue(artifactPaths.contains(box.root + "/Code/rusty/target"))
        XCTAssertFalse(artifactPaths.contains(box.root + "/Code/notrust/target"))

        let installers = try XCTUnwrap(byID["downloaded-installers"])
        XCTAssertEqual(installers.items.map(\.name), ["Tool.dmg"])

        let leftovers = try XCTUnwrap(byID["leftover-app-data"])
        XCTAssertEqual(leftovers.items.map(\.name), ["com.gone.app"])

        let trash = try XCTUnwrap(byID["trash"])
        XCTAssertEqual(trash.items.first?.name, "old.zip")

        // Categories add up to everything scanned.
        let categorised = report.categoryTotals.values.reduce(0, +)
        XCTAssertEqual(categorised, report.totalBytes)
        XCTAssertGreaterThan(report.categoryTotals[.caches] ?? 0, 3_000_000)
        XCTAssertGreaterThan(report.categoryTotals[.developer] ?? 0, 3_000_000)
        XCTAssertGreaterThan(report.safeBytes, 0)

        XCTAssertEqual(Set(report.largeFiles.map(\.name)), ["data.bin", "index.js", "app", "thing.bin", "movie.mov"])
        XCTAssertEqual(report.largeFiles.first?.name, "data.bin", "Largest first")
    }

    func testCleanupEngineDeletesAndRespectsPolicy() throws {
        let box = try makeHome()
        let knowledge = KnowledgeBase.standard(home: box.root)
        let policy = makePolicy(knowledge)
        let engine = CleanupEngine(policy: policy)

        let cachesTarget = CleanupTarget(path: box.root + "/Library/Caches", kind: .contents, title: "Caches", size: 3_000_000, safety: .safe)
        let messagesTarget = CleanupTarget(path: box.root + "/Library/Messages/chat.db", kind: .item, title: "Messages", size: 1, safety: .protected)
        let movieTarget = CleanupTarget(path: box.root + "/Documents/movie.mov", kind: .item, title: "Movie", size: 4_000_000, safety: .review)
        let missingTarget = CleanupTarget(path: box.root + "/Documents/already-gone.txt", kind: .item, title: "Gone", size: 1, safety: .review)

        let outcome = engine.run([cachesTarget, messagesTarget, movieTarget, missingTarget], mode: .deleteImmediately)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: box.root + "/Library/Caches"), "The folder itself stays")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: box.root + "/Library/Caches"), [])
        XCTAssertFalse(fm.fileExists(atPath: box.root + "/Documents/movie.mov"))
        XCTAssertTrue(fm.fileExists(atPath: box.root + "/Library/Messages/chat.db"), "Protected items are never deleted")

        XCTAssertEqual(outcome.failures.map(\.path), [messagesTarget.path])
        XCTAssertEqual(Set(outcome.completed.map(\.id)), Set([cachesTarget.id, movieTarget.id, missingTarget.id]))
        XCTAssertEqual(outcome.clearedFolders, [cachesTarget.path])
        XCTAssertEqual(outcome.bytesHandled, 3_000_000 + 4_000_000 + 1)
    }

    func testFoldersContainingPhotoLibrariesAreProtected() throws {
        let box = try Sandbox()
        try box.file("Desktop/Old Mac/Photos Library.photoslibrary/database/Photos.sqlite", bytes: 1_200_000)
        try box.file("Desktop/Old Mac/notes.txt", bytes: 10)
        try box.file("Desktop/Other/file.bin", bytes: 1_200_000)
        let knowledge = KnowledgeBase.standard(home: box.root)
        let policy = makePolicy(knowledge)
        let tree = try DiskScanner.scan(.folder(box.root)).tree

        let oldMac = try XCTUnwrap(tree.node(atPath: box.root + "/Desktop/Old Mac"))
        XCTAssertTrue(oldMac.containsMediaLibrary)
        XCTAssertFalse(policy.check(oldMac, in: tree).isAllowed)
        let other = try XCTUnwrap(tree.node(atPath: box.root + "/Desktop/Other"))
        XCTAssertTrue(policy.check(other, in: tree).isAllowed)

        // The cleanup engine looks on disk too, even with only a path to go on.
        let engine = CleanupEngine(policy: policy)
        let target = CleanupTarget(path: box.root + "/Desktop/Old Mac", kind: .item, title: "Old Mac", size: 1, safety: .review)
        let outcome = engine.run([target], mode: .deleteImmediately)
        XCTAssertEqual(outcome.failures.map(\.path), [target.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testSymlinkedPathsAreRefused() throws {
        let box = try Sandbox()
        try box.file("real/folder/file.bin", bytes: 100)
        try FileManager.default.createSymbolicLink(atPath: box.root + "/shortcut", withDestinationPath: box.root + "/real")
        let knowledge = KnowledgeBase.standard(home: box.root)
        let engine = CleanupEngine(policy: makePolicy(knowledge))
        let viaLink = CleanupTarget(path: box.root + "/shortcut/folder", kind: .item, title: "folder", size: 1, safety: .review)
        let outcome = engine.run([viaLink], mode: .deleteImmediately)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: box.root + "/real/folder/file.bin"))
    }

    func testNestedSuggestionsAreNotCountedTwice() throws {
        let box = try Sandbox()
        try box.file(".cache/lm-studio/models/model.gguf", bytes: 3_000_000)
        try box.file(".cache/other/blob", bytes: 1_500_000)
        let knowledge = KnowledgeBase.standard(home: box.root)
        let analyzer = ScanAnalyzer(knowledge: knowledge, policy: makePolicy(knowledge))
        let report = analyzer.analyze(try DiskScanner.scan(.folder(box.root)))
        let byID = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.id, $0) })
        let models = try XCTUnwrap(byID["lm-studio"])
        let cache = try XCTUnwrap(byID["dot-cache"])
        XCTAssertGreaterThanOrEqual(models.totalSize, 3_000_000)
        XCTAssertLessThan(cache.totalSize, 3_000_000, "The models are listed separately")
        // Emptying the whole cache folder still removes everything in it.
        XCTAssertGreaterThan(cache.wholeTargets.first?.size ?? 0, 4_000_000)
    }

    func testExecutablesAreTreatedAsPartsOfPrograms() throws {
        let box = try Sandbox()
        let tool = try box.file("tools/bin/mytool", bytes: 10)
        let notes = try box.file("tools/notes", bytes: 10)
        chmod(tool, 0o755)
        chmod(notes, 0o644)
        let knowledge = KnowledgeBase.standard(home: box.root)
        let policy = makePolicy(knowledge)
        XCTAssertFalse(policy.check(tool, kind: .item).isAllowed)
        XCTAssertTrue(policy.check(notes, kind: .item).isAllowed)
        XCTAssertTrue(policy.check(box.root + "/tools", kind: .item).isAllowed, "The whole tool can still go")
    }

    func testTrashModeUsesRemover() throws {
        final class RecordingRemover: FileRemoving, @unchecked Sendable {
            var trashed: [String] = []
            var deleted: [String] = []
            func moveToTrash(_ path: String) throws { trashed.append(path) }
            func deletePermanently(_ path: String) throws { deleted.append(path) }
            func contentsOfDirectory(_ path: String) throws -> [String] { ["a", "b"] }
        }

        let knowledge = KnowledgeBase.standard(home: "/Users/tester")
        let remover = RecordingRemover()
        let engine = CleanupEngine(policy: SafetyPolicy(knowledge: knowledge), remover: remover)
        let outcome = engine.run([
            CleanupTarget(path: "/Users/tester/Downloads/x.dmg", kind: .item, title: "x", size: 5, safety: .review),
            CleanupTarget(path: "/Users/tester/.Trash", kind: .contents, title: "Trash", size: 7, safety: .safe),
        ], mode: .moveToTrash)

        XCTAssertEqual(remover.trashed, ["/Users/tester/Downloads/x.dmg"])
        XCTAssertEqual(remover.deleted, ["/Users/tester/.Trash/a", "/Users/tester/.Trash/b"], "Items already in the Trash are deleted, not re-trashed")
        XCTAssertEqual(outcome.bytesHandled, 12)
    }
}

final class SystemInfoTests: XCTestCase {
    func testParseAPFSList() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Containers</key>
            <array>
                <dict>
                    <key>CapacityCeiling</key><integer>494384795648</integer>
                    <key>CapacityFree</key><integer>100000000000</integer>
                    <key>ContainerReference</key><string>disk3</string>
                    <key>Volumes</key>
                    <array>
                        <dict>
                            <key>CapacityInUse</key><integer>11000000000</integer>
                            <key>DeviceIdentifier</key><string>disk3s1</string>
                            <key>Name</key><string>Macintosh HD</string>
                            <key>Roles</key><array><string>System</string></array>
                        </dict>
                        <dict>
                            <key>CapacityInUse</key><integer>350000000000</integer>
                            <key>DeviceIdentifier</key><string>disk3s5</string>
                            <key>Name</key><string>Macintosh HD - Data</string>
                            <key>Roles</key><array><string>Data</string></array>
                        </dict>
                        <dict>
                            <key>CapacityInUse</key><integer>4000000000</integer>
                            <key>DeviceIdentifier</key><string>disk3s6</string>
                            <key>Name</key><string>VM</string>
                            <key>Roles</key><array><string>VM</string></array>
                        </dict>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let containers = APFSInfo.parseContainers(Data(plist.utf8))
        let container = try XCTUnwrap(containers.first)
        XCTAssertEqual(container.reference, "disk3")
        XCTAssertEqual(container.capacity, 494_384_795_648)
        XCTAssertEqual(container.volumes.count, 3)
        XCTAssertEqual(container.dataVolume?.used, 350_000_000_000)
        XCTAssertEqual(container.volumes.last?.title, "Virtual memory (swap)")
    }

    func testParseSnapshots() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-09-30-101530.local
        com.apple.TimeMachine.2026-09-30-111702.local
        """
        let snapshots = LocalSnapshots.parse(output)
        XCTAssertEqual(snapshots.map(\.stamp), ["2026-09-30-101530", "2026-09-30-111702"])
        XCTAssertNotNil(snapshots.first?.date)
        XCTAssertEqual(
            LocalSnapshots.deletionCommand(for: snapshots),
            "/usr/bin/tmutil deletelocalsnapshots 2026-09-30-101530; /usr/bin/tmutil deletelocalsnapshots 2026-09-30-111702"
        )
        XCTAssertNil(LocalSnapshots.deletionCommand(for: [LocalSnapshot(name: "evil", stamp: "1; rm -rf /")]))
    }

    #if os(macOS)
    func testLiveSystemQueries() throws {
        // These run against the real Mac; they should never crash, whatever they return.
        let capacity = try XCTUnwrap(VolumeCapacity.current())
        XCTAssertGreaterThan(capacity.total, 0)
        XCTAssertGreaterThanOrEqual(capacity.purgeable, 0)
        if let container = APFSInfo.startupContainer() {
            XCTAssertFalse(container.volumes.isEmpty)
        }
        _ = LocalSnapshots.list()
    }

    func testScanRealLibraryFolder() throws {
        // A quick end-to-end pass over a real folder with the default policy.
        let home = NSHomeDirectory()
        let knowledge = KnowledgeBase.standard(home: home)
        let analyzer = ScanAnalyzer(knowledge: knowledge, policy: SafetyPolicy(knowledge: knowledge), installedAppIDs: InstalledApps.bundleIdentifiers())
        let output = try DiskScanner.scan(.folder(home + "/Library/Caches"))
        let report = analyzer.analyze(output)
        XCTAssertEqual(report.categoryTotals.values.reduce(0, +), report.totalBytes)
    }
    #endif
}
