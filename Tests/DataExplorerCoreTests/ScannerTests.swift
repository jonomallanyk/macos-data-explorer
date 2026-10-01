import XCTest
@testable import DataExplorerCore

/// Builds a throwaway folder tree for scanning.
final class Sandbox {
    let root: String

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        root = base + "/DataExplorerTests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit {
        // Restore permissions changed by tests so the folder can be removed.
        if let enumerator = FileManager.default.enumerator(atPath: root) {
            for case let relative as String in enumerator {
                chmod(root + "/" + relative, 0o755)
            }
        }
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    func file(_ relative: String, bytes: Int) throws -> String {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // Non-zero bytes so the file system can't store it sparsely.
        let data = Data(repeating: 0x5A, count: bytes)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func folder(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: root + "/" + relative, withIntermediateDirectories: true)
    }
}

final class ScannerTests: XCTestCase {
    func testScanMeasuresSizesAndKeepsLargeFiles() throws {
        let box = try Sandbox()
        try box.file("big.bin", bytes: 2_000_000)
        try box.file("small.txt", bytes: 10)
        try box.file("nested/deeper/medium.bin", bytes: 1_200_000)
        try box.file("nested/tiny.txt", bytes: 100)

        let output = try DiskScanner.scan(ScanOptions(rootPath: box.root, displayName: "Sandbox", individualFileThreshold: 1_000_000))
        let tree = output.tree
        let root = tree.root

        XCTAssertEqual(root.name, "Sandbox")
        XCTAssertEqual(root.fileCount, 4)
        XCTAssertGreaterThanOrEqual(root.size, 3_200_000)

        let big = try XCTUnwrap(root.child(named: "big.bin"))
        XCTAssertEqual(big.kind, .file)
        XCTAssertGreaterThanOrEqual(big.size, 2_000_000)
        XCTAssertNil(root.child(named: "small.txt"), "Small files are summarised, not listed")
        XCTAssertEqual(root.looseFileCount, 1)

        let nested = try XCTUnwrap(root.child(named: "nested"))
        XCTAssertEqual(nested.fileCount, 2)
        XCTAssertNotNil(nested.child(named: "deeper")?.child(named: "medium.bin"))

        // Largest first.
        XCTAssertEqual(root.children.first?.name, "big.bin")
        XCTAssertEqual(tree.path(of: big), box.root + "/big.bin")
        XCTAssertTrue(tree.node(atPath: box.root + "/nested/deeper") === nested.child(named: "deeper"))
        XCTAssertTrue(tree.node(atPath: box.root) === root)
    }

    func testHardLinksCountedOnce() throws {
        let box = try Sandbox()
        let original = try box.file("a/original.bin", bytes: 1_500_000)
        try box.folder("b")
        try FileManager.default.linkItem(atPath: original, toPath: box.root + "/b/link.bin")

        let tree = try DiskScanner.scan(.folder(box.root)).tree
        XCTAssertLessThan(tree.root.size, 2_500_000, "The second link shouldn't add to the total")
        XCTAssertEqual(tree.root.fileCount, 2)
    }

    func testMarkersAreRecorded() throws {
        let box = try Sandbox()
        try box.file("project/package.json", bytes: 20)
        try box.file("project/node_modules/lib/index.js", bytes: 20)
        let tree = try DiskScanner.scan(.folder(box.root)).tree
        let project = try XCTUnwrap(tree.root.child(named: "project"))
        XCTAssertTrue(project.markers.contains(.packageJSON))
    }

    func testUnreadableFolder() throws {
        guard getuid() != 0 else { throw XCTSkip("Root can read everything") }
        let box = try Sandbox()
        try box.file("locked/secret.bin", bytes: 1_500_000)
        try box.file("open/file.bin", bytes: 1_500_000)
        chmod(box.root + "/locked", 0o000)

        let output = try DiskScanner.scan(.folder(box.root))
        XCTAssertGreaterThanOrEqual(output.unreadableCount, 1)
        let locked = try XCTUnwrap(output.tree.root.child(named: "locked"))
        XCTAssertTrue(locked.isUnreadable)
        XCTAssertNotNil(output.tree.root.child(named: "open"), "Scanning continues past unreadable folders")
    }

    func testMissingFolderThrows() {
        XCTAssertThrowsError(try DiskScanner.scan(.folder("/definitely/not/here/\(UUID().uuidString)")))
    }

    func testCancellation() throws {
        let box = try Sandbox()
        for index in 0..<2_000 {
            try box.file("many/\(index % 20)/f\(index).txt", bytes: 1)
        }
        XCTAssertThrowsError(try DiskScanner.scan(.folder(box.root), isCancelled: { true })) { error in
            guard case ScanError.cancelled = error else {
                return XCTFail("Expected cancellation, got \(error)")
            }
        }
    }

    func testTreeRemovalUpdatesParents() throws {
        let box = try Sandbox()
        try box.file("a/one.bin", bytes: 1_500_000)
        try box.file("a/two.bin", bytes: 1_500_000)
        try box.file("b/three.bin", bytes: 1_500_000)
        let tree = try DiskScanner.scan(.folder(box.root)).tree
        let before = tree.root.size
        let a = try XCTUnwrap(tree.root.child(named: "a"))
        let one = try XCTUnwrap(a.child(named: "one.bin"))
        let oneSize = one.size

        tree.remove(one)
        XCTAssertNil(a.child(named: "one.bin"))
        XCTAssertEqual(tree.root.size, before - oneSize)

        tree.removeContents(of: a)
        XCTAssertTrue(a.children.isEmpty)
        XCTAssertEqual(a.fileCount, 0)
        XCTAssertEqual(tree.root.fileCount, 1)
    }

    /// Builds a deep tree so the parallel scanner has folders to hand to other threads.
    private func makeDeepTree() throws -> Sandbox {
        let box = try Sandbox()
        for branch in 0..<4 {
            for leaf in 0..<3 {
                let base = "b\(branch)/l1/l2/leaf\(leaf)"
                try box.file("\(base)/big.bin", bytes: 1_100_000 + branch * 10_000 + leaf * 1_000)
                try box.file("\(base)/small.txt", bytes: 300)
                try box.file("\(base)/deeper/still/more/file.bin", bytes: 1_050_000)
                try box.file("\(base)/deeper/note.txt", bytes: 20)
            }
            try box.file("b\(branch)/l1/top.bin", bytes: 1_300_000)
            try box.file("b\(branch)/package.json", bytes: 10)
        }
        try box.file("root-file.bin", bytes: 1_400_000)
        return box
    }

    private func assertSameTree(_ a: FileNode, _ b: FileNode, path: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.size, b.size, "size of \(path)", file: file, line: line)
        XCTAssertEqual(a.fileCount, b.fileCount, "fileCount of \(path)", file: file, line: line)
        XCTAssertEqual(a.looseFileCount, b.looseFileCount, "loose files of \(path)", file: file, line: line)
        XCTAssertEqual(a.looseFileSize, b.looseFileSize, "loose size of \(path)", file: file, line: line)
        XCTAssertEqual(a.markers, b.markers, "markers of \(path)", file: file, line: line)
        XCTAssertEqual(a.children.map(\.size), a.children.map(\.size).sorted(by: >), "order of \(path)", file: file, line: line)
        XCTAssertEqual(Set(a.children.map(\.name)), Set(b.children.map(\.name)), "children of \(path)", file: file, line: line)
        for child in a.children {
            guard let other = b.child(named: child.name) else { continue }
            XCTAssertTrue(child.parent === a, "parent of \(path)/\(child.name)", file: file, line: line)
            assertSameTree(child, other, path: path + "/" + child.name, file: file, line: line)
        }
    }

    func testParallelScanMatchesSequentialScan() throws {
        let box = try makeDeepTree()
        var sequential = ScanOptions.folder(box.root)
        sequential.parallel = false
        var parallel = ScanOptions.folder(box.root)
        parallel.parallel = true
        var deep = ScanOptions.folder(box.root)
        deep.deepSplitPrefix = box.root + "/b1"

        let expected = try DiskScanner.scan(sequential).tree.root
        XCTAssertEqual(expected.fileCount, 4 * (3 * 4 + 2) + 1)
        assertSameTree(try DiskScanner.scan(parallel).tree.root, expected)
        assertSameTree(try DiskScanner.scan(deep).tree.root, expected)
    }

    func testParallelScanReportsProgressAndCancels() throws {
        let box = try makeDeepTree()
        let counter = ProgressCounter()
        _ = try DiskScanner.scan(.folder(box.root), progress: { _ in counter.increment() })
        XCTAssertThrowsError(try DiskScanner.scan(.folder(box.root), isCancelled: { true }))
    }

    func testDataVolumePaths() {
        let root = FileNode(name: "Macintosh HD", kind: .directory, parent: nil)
        let users = FileNode(name: "Users", kind: .directory, parent: root)
        root.children = [users]
        let spotlight = FileNode(name: ".Spotlight-V100", kind: .directory, parent: root)
        root.children.append(spotlight)
        let tree = FileTree(root: root, rootPath: FileTree.dataVolumePath, style: .dataVolume, displayName: "Macintosh HD")

        XCTAssertEqual(tree.path(of: users), "/Users")
        XCTAssertEqual(tree.path(of: spotlight), "/System/Volumes/Data/.Spotlight-V100")
        XCTAssertEqual(tree.path(of: root), "/")
        XCTAssertTrue(tree.node(atPath: "/Users") === users)
        XCTAssertTrue(tree.node(atPath: "/System/Volumes/Data/Users") === users)
        XCTAssertTrue(tree.node(atPath: "/System/Volumes/Data/.Spotlight-V100") === spotlight)
        XCTAssertNil(tree.node(atPath: "/.Spotlight-V100"))
    }
}

final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
