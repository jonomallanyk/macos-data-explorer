import AppKit
import Combine
import SwiftUI
import DataExplorerCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessBanner()
                }
                if model.isScanning {
                    ScanProgressBanner()
                }
                if case .failed(let message) = model.phase {
                    ErrorBanner(message: message)
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isScanning {
                    Button {
                        model.cancelScan()
                    } label: {
                        Label("Stop Scan", systemImage: "stop.circle")
                    }
                    .help("Stop scanning")
                } else {
                    Menu {
                        Button("Scan Entire Mac") { model.startScan(scope: .entireMac) }
                        Button("Scan Home Folder") { model.startScan(scope: .home) }
                        Divider()
                        Button("Scan a Folder…") { model.chooseFolderAndScan() }
                    } label: {
                        Label(model.report == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                    } primaryAction: {
                        model.startScan()
                    }
                    .help("Scan \(model.scope.title)")
                }
            }
        }
        .sheet(isPresented: $model.showAccessPrompt) {
            FullDiskAccessSheet()
        }
        .alert(item: $model.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
        .task {
            await ScreenshotMode.run(model: model)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .overview {
        case .overview:
            OverviewView()
        case .suggestions:
            SuggestionsView(fixedCategory: nil)
        case .explore:
            ExploreView()
        case .largeFiles:
            LargeFilesView()
        case .developer:
            SuggestionsView(fixedCategory: .developer)
        case .cleanup:
            CleanupView()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Your Mac") {
                Label("Overview", systemImage: "internaldrive")
                    .tag(SidebarItem.overview)
                Label("Suggestions", systemImage: "sparkles")
                    .badge(model.report.map { formatBytes($0.safeBytes + $0.reviewBytes) })
                    .tag(SidebarItem.suggestions)
                Label("Explore", systemImage: "folder")
                    .tag(SidebarItem.explore)
                Label("Large Files", systemImage: "doc.badge.ellipsis")
                    .tag(SidebarItem.largeFiles)
                Label("Developer", systemImage: "hammer")
                    .tag(SidebarItem.developer)
            }
            Section("Clean Up") {
                Label("Review & Delete", systemImage: "trash")
                    .badge(model.basket.count)
                    .tag(SidebarItem.cleanup)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarDiskSummary()
                .padding(12)
        }
    }
}

/// A compact used/free meter at the bottom of the sidebar.
struct SidebarDiskSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let volume = model.volume {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "internaldrive")
                    Text(volume.name).font(.callout.weight(.medium))
                }
                SizeBar(fraction: Double(volume.used) / Double(max(1, volume.total)), color: .accentColor)
                Text("\(formatBytes(volume.available)) free of \(formatBytes(volume.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .sizeStyle()
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Full Disk Access for a complete picture")
                    .font(.callout.weight(.semibold))
                Text("macOS hides Mail, Messages, Safari, other apps' data and parts of your Library from apps without it, so those would show up as \"couldn't read\". Turn on Data Explorer in System Settings › Privacy & Security › Full Disk Access, then reopen the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Settings") { MacSystem.openFullDiskAccessSettings() }
            Button("Check Again") { model.refreshAccess() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct FullDiskAccessSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                Text("Allow Full Disk Access first?")
                    .font(.title2.weight(.semibold))
            }
            Text("macOS keeps some folders private: Mail, Messages, Safari, other apps' data and parts of your Library. Without Full Disk Access, Data Explorer can't measure them, and macOS will interrupt the scan to ask about several folders one at a time.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Click Open System Settings.")
                Text("2. Turn on Data Explorer in the Full Disk Access list. If it's missing, click + and choose it from Applications.")
                Text("3. When macOS asks, choose Quit & Reopen, then scan again.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", role: .cancel) { model.showAccessPrompt = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Scan Without It") { model.scanWithoutFullDiskAccess() }
                Button("Open System Settings") {
                    MacSystem.openFullDiskAccessSettings()
                    model.showAccessPrompt = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct ScanProgressBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.phase == .analyzing ? "Making sense of what was found…" : "Scanning \(model.scope.title)…")
                    .font(.callout.weight(.semibold))
                Spacer()
                if let progress = model.progress {
                    Text("\(progress.filesScanned.formatted()) files · \(formatBytes(progress.bytesScanned))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .sizeStyle()
                }
            }
            if let fraction = expectedFraction, model.phase == .scanning {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(model.progress.map { MacSystem.abbreviate($0.currentPath) } ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// For a whole-disk scan we know roughly how much data there is, so show real progress.
    private var expectedFraction: Double? {
        guard model.scope == .entireMac, let progress = model.progress else { return nil }
        let expected = model.container?.dataVolume?.used ?? model.volume?.used ?? 0
        guard expected > 0 else { return nil }
        return min(0.99, Double(progress.bytesScanned) / Double(expected))
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}
