import AppKit
import SwiftUI
import DataExplorerCore

/// Drives the app through each screen and saves screenshots, for the README and for checking
/// the interface in CI. Only active when the DATA_EXPLORER_SCREENSHOTS environment variable
/// names an output folder; set DATA_EXPLORER_SCREENSHOT_SCOPE=home to scan just the home folder.
@MainActor
enum ScreenshotMode {
    private static let environment = ProcessInfo.processInfo.environment

    static var outputFolder: String? { environment["DATA_EXPLORER_SCREENSHOTS"] }

    static func run(model: AppModel) async {
        guard let folder = outputFolder else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        await pause(1)
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first else {
            print("Screenshot mode: no window")
            NSApp.terminate(nil)
            return
        }
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        await pause(1.5)
        capture(window, "01-welcome", in: folder)

        let scope: ScanScope = environment["DATA_EXPLORER_SCREENSHOT_SCOPE"] == "home" ? .home : .entireMac
        model.startScan(scope: scope, skipAccessCheck: true)
        await pause(4)
        capture(window, "02-scanning", in: folder)
        while model.isScanning { await pause(0.5) }

        guard let report = model.report else {
            print("Screenshot mode: scan failed: \(model.phase)")
            NSApp.terminate(nil)
            return
        }
        printSummary(report, model: model)

        model.selection = .overview
        await pause(2)
        capture(window, "03-overview", in: folder)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(1.5)
        capture(window, "04-overview-dark", in: folder)
        NSApp.appearance = nil

        model.selection = .suggestions
        model.focusedFindingID = report.findings.first(where: { $0.isActionable })?.id
        await pause(2.5)
        capture(window, "05-suggestions", in: folder)

        if let library = report.tree.node(atPath: model.home + "/Library") {
            model.exploreFolder = library
            model.exploreSelection = library.children.first?.id
        }
        model.selection = .explore
        await pause(2)
        capture(window, "06-explore", in: folder)

        model.selection = .largeFiles
        await pause(2)
        capture(window, "07-large-files", in: folder)

        model.selection = .developer
        await pause(2)
        capture(window, "08-developer", in: folder)

        // Fill the cleanup list (nothing is deleted).
        for finding in report.findings where finding.safety == .safe && finding.isActionable {
            if model.checkState(for: finding) == .unchecked { model.toggle(finding) }
            if model.basket.count >= 6 { break }
        }
        model.selection = .cleanup
        await pause(2)
        capture(window, "09-review-and-delete", in: folder)

        NSApp.terminate(nil)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private static func capture(_ window: NSWindow, _ name: String, in folder: String) {
        window.displayIfNeeded()
        // The frame view includes the title bar and toolbar; fall back to the content.
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        let bounds = view.bounds
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
        do {
            try data.write(to: url)
            print("Saved \(url.lastPathComponent)")
        } catch {
            print("Couldn't save \(name): \(error)")
        }
    }

    private static func printSummary(_ report: ScanReport, model: AppModel) {
        print("Scanned \(report.tree.displayName): \(report.tree.root.fileCount) files, \(ByteFormatter.string(report.totalBytes)) in \(String(format: "%.1f", report.duration)) s")
        print("Unreadable: \(report.unreadableCount); Full Disk Access: \(model.hasFullDiskAccess)")
        print("Safe: \(ByteFormatter.string(report.safeBytes)); review: \(ByteFormatter.string(report.reviewBytes)); System Data: \(ByteFormatter.string(report.systemDataBytes))")
        for entry in report.sortedCategories {
            print("  \(entry.category.title): \(ByteFormatter.string(entry.bytes))")
        }
        print("Findings:")
        for finding in report.findings.prefix(40) {
            print("  [\(finding.safety.title)] \(finding.title): \(ByteFormatter.string(finding.totalSize)) (\(finding.items.count) items)")
        }
    }
}
