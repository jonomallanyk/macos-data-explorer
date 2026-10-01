import XCTest
@testable import DataExplorerCore

final class KnowledgeBaseTests: XCTestCase {
    let home = "/Users/tester"
    lazy var knowledge = KnowledgeBase.standard(home: home)

    func testCatalogIDsAreUnique() {
        let ids = Catalog.locations.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate IDs: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    func testCatalogEntriesHaveText() {
        for location in Catalog.locations {
            XCTAssertFalse(location.title.isEmpty, location.id)
            XCTAssertFalse(location.whatItIs.isEmpty, location.id)
            XCTAssertFalse(location.ifDeleted.isEmpty, location.id)
            XCTAssertFalse(location.paths.isEmpty, location.id)
        }
    }

    func testWildcard() {
        XCTAssertTrue(Wildcard.matches("*", "anything"))
        XCTAssertTrue(Wildcard.matches("Install macOS*.app", "Install macOS Sonoma.app"))
        XCTAssertFalse(Wildcard.matches("Install macOS*.app", "Install macOS Sonoma.zip"))
        XCTAssertTrue(Wildcard.matches("*.photoslibrary", "Photos Library.photoslibrary"))
        XCTAssertFalse(Wildcard.matches("*.photoslibrary", "Photos"))
        XCTAssertTrue(Wildcard.matches("a*b*c", "aXXbYYc"))
        XCTAssertFalse(Wildcard.matches("a*b*c", "aXXbYY"))
    }

    func testExactAndInsideMatches() {
        let caches = knowledge.explain(path: home + "/Library/Caches", isDirectory: true)
        XCTAssertTrue(caches.isExact)
        XCTAssertEqual(caches.location.id, "caches")
        XCTAssertEqual(caches.safety, .safe)
        XCTAssertEqual(caches.category, .caches)

        let appCache = knowledge.explain(path: home + "/Library/Caches/com.spotify.client", isDirectory: true)
        XCTAssertFalse(appCache.isExact)
        XCTAssertEqual(appCache.location.id, "caches")
        XCTAssertEqual(appCache.safety, .safe)
    }

    func testLiteralBeatsWildcard() {
        XCTAssertEqual(knowledge.match(path: home)?.location.id, "home")
        XCTAssertEqual(knowledge.match(path: "/Users/someone")?.location.id, "other-user")
        XCTAssertEqual(knowledge.match(path: "/Users/Shared/file.txt")?.location.id, "users-shared")
        XCTAssertEqual(knowledge.match(path: home + "/Documents/notes.txt")?.location.id, "documents")
    }

    func testWildcardCaptures() {
        let match = knowledge.match(path: home + "/Library/Containers/com.example.app/Data/Library/Caches")
        XCTAssertEqual(match?.location.id, "container-caches")
        XCTAssertEqual(match?.captures, ["com.example.app"])
        XCTAssertEqual(match?.isExact, true)

        let prefs = knowledge.match(path: home + "/Library/Containers/com.example.app/Data/Library/Preferences")
        XCTAssertEqual(prefs?.location.id, "containers")
        XCTAssertEqual(prefs?.isExact, false)

        let slack = knowledge.match(path: home + "/Library/Application Support/Slack/Service Worker/CacheStorage")
        XCTAssertEqual(slack?.location.id, "web-app-caches")
        XCTAssertEqual(slack?.captures, ["Slack"])
    }

    func testSystemLocations() {
        XCTAssertEqual(knowledge.match(path: "/System/Volumes/Data/.Spotlight-V100")?.location.id, "spotlight-index")
        XCTAssertEqual(knowledge.match(path: "/private/var/vm/swapfile0")?.location.id, "virtual-memory")
        XCTAssertEqual(knowledge.match(path: "/private/var/folders/ab/xyz/T")?.location.id, "var-folders")
        XCTAssertEqual(knowledge.match(path: "/Applications/Install macOS Sonoma.app")?.location.id, "macos-installer")
        XCTAssertEqual(knowledge.match(path: "/Applications/Safari.app")?.location.id, "applications")
        XCTAssertEqual(knowledge.match(path: "/opt/something")?.location.id, "opt")
        XCTAssertEqual(knowledge.match(path: "/some-unknown-folder")?.location.id, "disk-root")
    }

    func testFileTypeHintsInsideAreas() {
        let dmg = knowledge.explain(path: home + "/Downloads/Tool.dmg", isDirectory: false)
        XCTAssertEqual(dmg.headline, "Disk image")
        XCTAssertEqual(dmg.safety, .review)

        let library = knowledge.explain(path: home + "/Pictures/Photos Library.photoslibrary", isDirectory: true)
        XCTAssertEqual(library.location.id, "photos-library")
        XCTAssertEqual(library.safety, .protected)

        let otherLibrary = knowledge.explain(path: home + "/Desktop/Old Photos.photoslibrary", isDirectory: true)
        XCTAssertEqual(otherLibrary.safety, .protected)

        // A file's type doesn't override a specific location like the caches folder.
        let cachedImage = knowledge.explain(path: home + "/Library/Caches/thing.png", isDirectory: false)
        XCTAssertEqual(cachedImage.safety, .safe)
    }

    func testFriendlyRuntimeAssetNames() {
        XCTAssertEqual(ItemDetails.friendlyName(locationID: "simulator-runtime-assets", name: "com_apple_MobileAsset_xrOSSimulatorRuntime"), "visionOS simulator runtimes")
        XCTAssertEqual(ItemDetails.friendlyName(locationID: "simulator-runtime-assets", name: "com_apple_MobileAsset_iOSSimulatorRuntime"), "iOS simulator runtimes")
        XCTAssertNil(ItemDetails.friendlyName(locationID: "caches", name: "anything"))
    }

    func testRuntimeNames() {
        XCTAssertEqual(ItemDetails.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-2"), "iOS 17.2")
        XCTAssertEqual(ItemDetails.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-1-0"), "visionOS 1.0")
    }

    func testInstalledAppMatching() {
        let installed: Set<String> = ["com.microsoft.teams2", "com.spotify.client"]
        XCTAssertTrue(InstalledApps.isInstalled("com.microsoft.teams2.notificationcenter", in: installed))
        XCTAssertTrue(InstalledApps.isInstalled("com.Spotify.Client", in: installed))
        XCTAssertFalse(InstalledApps.isInstalled("com.example.gone", in: installed))
        XCTAssertFalse(InstalledApps.isInstalled("com.microsoft.word", in: installed))
        XCTAssertTrue(InstalledApps.isInstalled("UBF8T346G9.com.spotify.client.helper", in: installed))
    }
}

final class FormattingTests: XCTestCase {
    func testByteFormatting() {
        XCTAssertEqual(ByteFormatter.string(0), "0 bytes")
        XCTAssertEqual(ByteFormatter.string(1), "1 byte")
        XCTAssertEqual(ByteFormatter.string(999), "999 bytes")
        XCTAssertEqual(ByteFormatter.string(1_500), "1.5 KB")
        XCTAssertEqual(ByteFormatter.string(1_500_000), "1.5 MB")
        XCTAssertEqual(ByteFormatter.string(999_960), "1.0 MB")
        XCTAssertEqual(ByteFormatter.string(12_345_678_900), "12.3 GB")
        XCTAssertEqual(ByteFormatter.string(123_456_789_000), "123 GB")
        XCTAssertEqual(ByteFormatter.string(2_000_000_000_000), "2.0 TB")
    }

    func testRelativeAge() {
        let now = Date()
        XCTAssertEqual(ScanAnalyzer.relativeAge(now, now: now), "today")
        XCTAssertEqual(ScanAnalyzer.relativeAge(now.addingTimeInterval(-86_400 * 10), now: now), "10 days ago")
        XCTAssertEqual(ScanAnalyzer.relativeAge(now.addingTimeInterval(-86_400 * 95), now: now), "3 months ago")
        XCTAssertEqual(ScanAnalyzer.relativeAge(now.addingTimeInterval(-86_400 * 800), now: now), "2 years ago")
    }
}

final class BasketTests: XCTestCase {
    func target(_ path: String, _ kind: CleanupTarget.Kind = .item, size: Int64 = 10) -> CleanupTarget {
        CleanupTarget(path: path, kind: kind, title: path, size: size, safety: .safe)
    }

    func testCovering() {
        XCTAssertTrue(target("/a").covers(target("/a")))
        XCTAssertTrue(target("/a").covers(target("/a", .contents)))
        XCTAssertTrue(target("/a").covers(target("/a/b")))
        XCTAssertFalse(target("/a").covers(target("/ab")))
        XCTAssertTrue(target("/a", .contents).covers(target("/a/b")))
        XCTAssertFalse(target("/a", .contents).covers(target("/a")))
    }

    func testAddingParentReplacesChildren() {
        var basket = CleanupBasket()
        basket.add(target("/x/1", size: 5))
        basket.add(target("/x/2", size: 5))
        XCTAssertEqual(basket.count, 2)
        basket.add(target("/x", .contents, size: 30))
        XCTAssertEqual(basket.count, 1)
        XCTAssertEqual(basket.totalSize, 30)
        XCTAssertFalse(basket.add(target("/x/3")), "Already covered by the folder")
        XCTAssertTrue(basket.isCovered(target("/x/3")))
        basket.removeCovered(by: target("/x", .contents))
        XCTAssertTrue(basket.isEmpty)
    }
}
