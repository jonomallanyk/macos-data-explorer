import XCTest
@testable import DataExplorerCore

final class SafetyPolicyTests: XCTestCase {
    let home = "/Users/tester"
    lazy var policy = SafetyPolicy(knowledge: KnowledgeBase.standard(home: home))

    func assertBlocked(_ path: String, _ kind: CleanupTarget.Kind = .item, file: StaticString = #filePath, line: UInt = #line) {
        let verdict = policy.check(path, kind: kind)
        XCTAssertFalse(verdict.isAllowed, "Expected \(kind) \(path) to be blocked", file: file, line: line)
    }

    func assertAllowed(_ path: String, _ kind: CleanupTarget.Kind = .item, file: StaticString = #filePath, line: UInt = #line) {
        let verdict = policy.check(path, kind: kind)
        XCTAssertTrue(verdict.isAllowed, "Expected \(kind) \(path) to be allowed, got: \(verdict.reason ?? "")", file: file, line: line)
    }

    func testEssentialFoldersCannotBeDeleted() {
        assertBlocked("/")
        assertBlocked("/Users")
        assertBlocked(home)
        assertBlocked(home + "/Library")
        assertBlocked(home + "/Documents")
        assertBlocked("/Applications")
        assertBlocked(home + "/Library/Developer/Xcode")
        assertBlocked(home + "/Library/Caches")
    }

    func testSystemAndProtectedData() {
        assertBlocked("/System/Library/CoreServices/Finder.app")
        assertBlocked("/System/Volumes/Data/.Spotlight-V100")
        assertBlocked("/private/var/vm/swapfile0")
        assertBlocked("/private/var/folders/ab/cd/T/thing")
        assertBlocked("/usr/bin/ls")
        assertBlocked("/Library/LaunchDaemons/com.example.helper.plist")
        assertBlocked(home + "/Library/Keychains/login.keychain-db")
        assertBlocked(home + "/Library/Messages/Attachments/ab/photo.heic")
        assertBlocked(home + "/Library/Mail/V10/account")
        assertBlocked("/Users/someone/Documents/file.txt")
    }

    func testCloudAndLibrariesAreProtected() {
        assertBlocked(home + "/Library/Mobile Documents/com~apple~CloudDocs/Report.pages")
        assertBlocked(home + "/Library/CloudStorage/Dropbox/file.zip")
        assertBlocked(home + "/Pictures/Photos Library.photoslibrary")
        assertBlocked(home + "/Pictures/Photos Library.photoslibrary/originals/0/IMG.heic")
        assertBlocked(home + "/Desktop/Old.photoslibrary")
    }

    func testInsidePackagesIsBlocked() {
        assertBlocked("/Applications/Foo.app/Contents/MacOS/Foo")
        assertAllowed("/Applications/Foo.app")
    }

    func testManualCleanupLocations() {
        assertBlocked(home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        assertBlocked("/opt/homebrew/bin/node")
        assertBlocked(home + "/.ollama/models/blobs/sha256-abc")
    }

    func testUnusualPathsAreBlocked() {
        assertBlocked(home + "/Documents/../Library")
        assertBlocked(home + "/Documents/./x")
        assertBlocked(home + "//Documents")
    }

    func testCachesAndContents() {
        assertAllowed(home + "/Library/Caches", .contents)
        assertAllowed(home + "/Library/Caches/com.spotify.client")
        assertAllowed(home + "/Library/Caches/Homebrew")
        assertAllowed(home + "/.cache", .contents)
        assertAllowed(home + "/Library/Developer/Xcode/DerivedData", .contents)
        assertAllowed(home + "/Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab")
        assertAllowed(home + "/.Trash", .contents)
        assertAllowed(home + "/.Trash/old.zip")
        assertAllowed(home + "/Library/Application Support/MobileSync/Backup/00008030-ABC")
        assertAllowed("/Library/Caches/com.example")
        assertBlocked(home + "/Documents", .contents)
        assertBlocked(home + "/Library/Caches/com.spotify.client", .contents)
    }

    func testChildrenOfClearedFolders() {
        // A folder that contains an essential one can't be deleted by itself...
        assertBlocked(home + "/Library/Containers/com.docker.docker")
        // ...but clearing a cache folder may remove anything directly inside it.
        XCTAssertTrue(policy.check(home + "/.cache/lm-studio", kind: .item, partOfClearing: true).isAllowed)
        // Protected things stay protected even then.
        XCTAssertFalse(policy.check("/private/var/vm/swapfile0", kind: .item, partOfClearing: true).isAllowed)
    }

    func testDeveloperToolFoldersCanBeRemovedWhole() {
        assertAllowed(home + "/Library/Android")
        assertAllowed(home + "/Library/Android/sdk")
        assertAllowed(home + "/Library/Android/sdk/ndk/27.3.13750724")
        assertAllowed(home + "/.cache/lm-studio")
        assertAllowed(home + "/.gradle")
        // Xcode's folder holds your settings, so it stays.
        assertBlocked(home + "/Library/Developer/Xcode/UserData")
    }

    func testPiecesOfProgramsAreBlocked() {
        assertBlocked(home + "/Library/Android/sdk/ndk/27/toolchains/llvm/lib/libclang.dylib")
        assertBlocked("/usr/local/lib/libssl.dylib")
        assertBlocked(home + "/tools/runtime/lib/core.jar")
        // Anything goes inside folders that are meant to be emptied.
        assertAllowed(home + "/Library/Caches/com.example/plugin.dylib")
        assertAllowed(home + "/Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab/Build/x.o")
    }

    func testOrdinaryFiles() {
        assertAllowed(home + "/Documents/report.pdf")
        assertAllowed(home + "/Downloads/Installer.dmg")
        assertAllowed(home + "/Library/Containers/com.example.gone")
        assertAllowed("/usr/local/bin/tool")
        assertAllowed("/Applications/Install macOS Sonoma.app")
    }

    func testCaseInsensitiveProtection() {
        assertBlocked("/system/Library/Kernels/kernel")
        assertBlocked("/PRIVATE/var/vm/sleepimage")
        // The Mac's file system ignores case, so the catalogue must too.
        assertBlocked(home + "/Library/messages/chat.db")
        assertBlocked(home + "/library/Safari/History.db")
        assertBlocked("/users/someone/Documents/file.txt")
    }

    func testPersonalDataIsProtected() {
        assertBlocked(home + "/Library/Group Containers/group.com.apple.notes")
        assertBlocked(home + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
        assertBlocked(home + "/Library/Containers/com.apple.BKAgentService")
        assertBlocked(home + "/.ssh/id_ed25519")
        assertBlocked("/Library/OpenDirectory/configurations")
    }

    func testGenericCachePatternsDontReachIntoProtectedFolders() {
        assertBlocked(home + "/Library/Application Support/AddressBook/Cache", .contents)
        assertBlocked(home + "/Library/Application Support/FileProvider/Cache/x")
        assertBlocked(home + "/Library/Group Containers/group.com.apple.notes/Library/Caches", .contents)
        // Ordinary apps' caches are still fine.
        assertAllowed(home + "/Library/Application Support/Slack/Cache", .contents)
    }

    func testPiecesOfRepositoriesAndRuntimesAreBlocked() {
        assertBlocked("/usr/local/share/vcpkg/.git/objects/pack/pack-1234.pack")
        assertBlocked(home + "/Projects/app/.git/objects/pack/pack-1234.pack")
        assertAllowed(home + "/Projects/app/.git")
        assertBlocked(home + "/tools/Java_Temurin/25/arm64/Contents/Home/lib/modules")
        assertAllowed(home + "/tools/Java_Temurin/25")
    }

    func testBundleIDFoldersAreNotPackages() {
        assertAllowed(home + "/Library/Containers/com.utmapp.UTM/Data/Documents", .contents)
        assertAllowed(home + "/Library/Containers/com.apple.iWork.Pages/Data/Library/Caches", .contents)
    }
}
