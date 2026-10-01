import AppKit
import SwiftUI

@main
struct DataExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Data Explorer", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan Entire Mac") { model.startScan(scope: .entireMac) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.isScanning)
                Button("Scan Home Folder") { model.startScan(scope: .home) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isScanning)
                Button("Scan a Folder…") { model.chooseFolderAndScan() }
                    .keyboardShortcut("o", modifiers: [.command])
                    .disabled(model.isScanning)
                Divider()
                Button("Stop Scan") { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!model.isScanning)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Makes the app behave normally (Dock icon, menu bar) when launched with `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
