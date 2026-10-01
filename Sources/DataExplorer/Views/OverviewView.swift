import SwiftUI
import DataExplorerCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DiskCard()
                if let report = model.report {
                    if report.tree.style == .dataVolume {
                        SystemDataCard(report: report)
                    }
                    CategoriesCard(report: report)
                } else if !model.isScanning {
                    WelcomeCard()
                }
                ManagedSpaceCard()
                if let report = model.report {
                    ScanDetailsCard(report: report)
                }
            }
            .padding(20)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }
}

// MARK: - Disk

private struct DiskCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            if let volume = model.volume {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(volume.name).font(.title2.weight(.semibold))
                            Text(summary(volume))
                                .foregroundStyle(.secondary)
                                .sizeStyle()
                        }
                        Spacer()
                        if let report = model.report, report.safeBytes + report.reviewBytes > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatBytes(report.safeBytes))
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .sizeStyle()
                                Text("safe to remove")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("See Suggestions") { model.selection = .suggestions }
                                .padding(.leading, 8)
                        }
                    }
                    let segments = self.segments(volume)
                    CapacityBar(segments: segments, total: volume.total)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(segments) { segment in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(segment.color)
                                    .frame(width: 10, height: 10)
                                Text(segment.title).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(formatBytes(segment.bytes))
                                    .foregroundStyle(.secondary)
                                    .sizeStyle()
                            }
                            .font(.callout)
                            .help(segment.detail)
                        }
                    }
                }
            } else {
                Text("Couldn't read your disk's capacity.").foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ volume: VolumeCapacity) -> String {
        var text = "\(formatBytes(volume.used)) used of \(formatBytes(volume.total)) · \(formatBytes(volume.available)) free"
        if volume.purgeable > 0 {
            text += " (+\(formatBytes(volume.purgeable)) purgeable)"
        }
        return text
    }

    private func segments(_ volume: VolumeCapacity) -> [CapacitySegment] {
        guard let report = model.report, report.tree.style == .dataVolume else {
            var segments = [
                CapacitySegment(
                    id: "used",
                    title: "Used",
                    bytes: max(0, volume.used - volume.purgeable),
                    color: .accentColor,
                    detail: "Space in use."
                ),
            ]
            if volume.purgeable > 0 {
                segments.append(CapacitySegment(
                    id: "purgeable",
                    title: "Purgeable",
                    bytes: volume.purgeable,
                    color: .accentColor.opacity(0.35),
                    detail: "Space macOS can free on its own when it needs to."
                ))
            }
            return segments
        }

        var segments = report.sortedCategories.map { entry in
            CapacitySegment(
                id: entry.category.rawValue,
                title: entry.category.title,
                bytes: entry.bytes,
                color: entry.category.color,
                detail: entry.category.summary
            )
        }
        let systemVolumes = model.container?.volumes.filter { !$0.roles.contains("Data") }.reduce(Int64(0)) { $0 + $1.used } ?? 0
        if systemVolumes > 0 {
            segments.append(CapacitySegment(
                id: "system-volumes",
                title: "macOS & system volumes",
                bytes: systemVolumes,
                color: Color(white: 0.45),
                detail: "The sealed macOS volume, virtual memory, Preboot, Recovery and update volumes."
            ))
        }
        let unmeasured = unmeasuredBytes(report: report, volume: volume, systemVolumes: systemVolumes)
        if unmeasured > 0 {
            segments.append(CapacitySegment(
                id: "unmeasured",
                title: "Not measured",
                bytes: unmeasured,
                color: Color(white: 0.8),
                detail: "Space the scan couldn't see: Time Machine snapshots, folders macOS wouldn't let Data Explorer read, and file-system overhead."
            ))
        }
        return segments
    }
}

/// Used space that the scan didn't account for.
func unmeasuredBytes(report: ScanReport, volume: VolumeCapacity, systemVolumes: Int64) -> Int64 {
    max(0, volume.used - systemVolumes - report.totalBytes)
}

// MARK: - Welcome

private struct WelcomeCard: View {
    var body: some View {
        Card(
            title: "See what's really using your disk",
            subtitle: "Data Explorer measures every folder, explains what it is in plain language, and points out what's safe to delete. Scanning only reads sizes. Nothing is changed or uploaded, and nothing is deleted unless you choose it."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledText(label: "Entire Mac", text: "covers everything, including the hidden folders behind \"System Data\". Takes a few minutes.", systemImage: "internaldrive")
                LabeledText(label: "Home Folder", text: "is quicker and covers your files, your Library, caches and app data.", systemImage: "house")
                ScanButtons()
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - System Data

private struct SystemDataRow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64
    let safety: SafetyLevel?
    let symbol: String
    let action: Action?

    enum Action {
        case finding(String)
        case path(String)
    }
}

private struct SystemDataCard: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport

    var body: some View {
        let categories = report.sortedCategories.filter { $0.category.isUsuallySystemData }
        let total = categories.reduce(Int64(0)) { $0 + $1.bytes }
        Card(
            title: "What's in \"System Data\"?",
            subtitle: "System Settings lumps caches, logs, app data, virtual machines, snapshots and macOS's own working files into one grey bar. Here's what's actually in yours, biggest first."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                CapacityBar(
                    segments: categories.map {
                        CapacitySegment(id: $0.category.rawValue, title: $0.category.title, bytes: $0.bytes, color: $0.category.color)
                    },
                    total: max(1, total)
                )
                .frame(height: 14)

                HStack(spacing: 14) {
                    ForEach(categories) { entry in
                        HStack(spacing: 4) {
                            Circle().fill(entry.category.color).frame(width: 8, height: 8)
                            Text("\(entry.category.title) \(formatBytes(entry.bytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .sizeStyle()
                        }
                    }
                }

                Divider()

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        SystemDataRowView(row: row)
                        if row.id != rows.last?.id { Divider().padding(.leading, 34) }
                    }
                }
            }
        }
    }

    private var rows: [SystemDataRow] {
        var rows: [SystemDataRow] = []
        var coveredPaths: [String] = []

        for finding in report.findings where finding.countsAsSystemData {
            rows.append(SystemDataRow(
                id: "finding:" + finding.id,
                title: finding.title,
                detail: finding.whatItIs,
                bytes: finding.totalSize,
                safety: finding.safety,
                symbol: finding.category.symbolName,
                action: .finding(finding.id)
            ))
            coveredPaths += finding.paths
        }

        // The biggest individual app-data folders, which often explain the rest.
        let appDataFolders = [
            model.home + "/Library/Application Support",
            model.home + "/Library/Containers",
            model.home + "/Library/Group Containers",
            "/Library/Application Support",
        ]
        var candidates: [(node: FileNode, path: String)] = []
        for folder in appDataFolders {
            guard let node = report.tree.node(atPath: folder) else { continue }
            for child in node.children.prefix(15) where child.isDirectory {
                let path = folder + "/" + child.name
                let overlaps = coveredPaths.contains { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }
                if !overlaps { candidates.append((child, path)) }
            }
        }
        candidates.sort { $0.node.size > $1.node.size }
        for candidate in candidates.prefix(6) where candidate.node.size >= 200_000_000 {
            let explanation = model.explanation(forPath: candidate.path, isDirectory: true)
            let name = AppNames.friendly(candidate.node.name)
            rows.append(SystemDataRow(
                id: "folder:" + candidate.path,
                title: "\(name) app data",
                detail: "\(explanation.whatItIs) (\(MacSystem.abbreviate(candidate.path)))",
                bytes: candidate.node.size,
                safety: explanation.safety,
                symbol: "square.stack.3d.up",
                action: .path(candidate.path)
            ))
        }

        if let volume = model.volume {
            let systemVolumes = model.container?.volumes.filter { !$0.roles.contains("Data") }.reduce(Int64(0)) { $0 + $1.used } ?? 0
            let unmeasured = unmeasuredBytes(report: report, volume: volume, systemVolumes: systemVolumes)
            if unmeasured > 500_000_000 {
                var detail = "Space the scan couldn't see."
                if !model.snapshots.isEmpty {
                    detail += " You have \(model.snapshots.count) Time Machine snapshot\(model.snapshots.count == 1 ? "" : "s"), which macOS can't size but often account for most of this."
                }
                if report.unreadableCount > 0 {
                    detail += " \(report.unreadableCount.formatted()) folder\(report.unreadableCount == 1 ? "" : "s") couldn't be read\(model.hasFullDiskAccess ? "" : "; Full Disk Access would reveal most of them")."
                }
                rows.append(SystemDataRow(
                    id: "unmeasured",
                    title: "Hidden or unreadable",
                    detail: detail,
                    bytes: unmeasured,
                    safety: nil,
                    symbol: "eye.slash",
                    action: nil
                ))
            }
        }

        return rows.sorted { $0.bytes > $1.bytes }.prefix(14).map { $0 }
    }
}

private struct SystemDataRowView: View {
    @Environment(AppModel.self) private var model
    let row: SystemDataRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.title).font(.body.weight(.medium))
                    if let safety = row.safety { SafetyBadge(level: safety) }
                }
                Text(row.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(formatBytes(row.bytes))
                .font(.body.weight(.semibold))
                .sizeStyle()
            if let action = row.action {
                Button {
                    switch action {
                    case .finding(let id): model.showFinding(id)
                    case .path(let path): model.showInExplore(path)
                    }
                } label: {
                    Image(systemName: "chevron.right.circle")
                }
                .buttonStyle(.borderless)
                .help("Show details")
            } else {
                Image(systemName: "chevron.right.circle").hidden()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Categories

private struct CategoriesCard: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport

    var body: some View {
        let entries = report.sortedCategories
        let largest = entries.first?.bytes ?? 1
        Card(
            title: "Where your space goes",
            subtitle: "Everything Data Explorer measured in \(report.tree.displayName), grouped by what it's for."
        ) {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    let findings = report.findings.filter { $0.category == entry.category }
                    Button {
                        model.showSuggestions(for: entry.category)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: entry.category.symbolName)
                                .foregroundStyle(entry.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.category.title).font(.body.weight(.medium))
                                    Spacer()
                                    Text(formatBytes(entry.bytes))
                                        .font(.body.weight(.semibold))
                                        .sizeStyle()
                                }
                                SizeBar(fraction: Double(entry.bytes) / Double(max(1, largest)), color: entry.category.color)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.category.summary)
                                    Spacer()
                                    Text("Settings calls this: \(entry.category.settingsLabel)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .opacity(findings.isEmpty ? 0 : 1)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(findings.isEmpty)
                    if entry.category != entries.last?.category { Divider().padding(.leading, 36) }
                }
            }
        }
    }
}

// MARK: - Space macOS manages

private struct ManagedSpaceCard: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSnapshots = false

    var body: some View {
        Card(
            title: "Space macOS manages itself",
            subtitle: "These don't show up as files, so other tools miss them. Most of this is counted as \"System Data\" or \"macOS\" in System Settings."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if let volumes = model.container?.volumes.filter({ !$0.roles.contains("Data") }), !volumes.isEmpty {
                    ForEach(volumes.sorted { $0.used > $1.used }) { volume in
                        ManagedRow(symbol: "externaldrive", title: volume.title, detail: volume.explanation, bytes: volume.used)
                        Divider().padding(.leading, 34)
                    }
                }
                if let volume = model.volume {
                    ManagedRow(
                        symbol: "arrow.3.trianglepath",
                        title: "Purgeable space",
                        detail: "Space macOS can free by itself when it runs low: Time Machine snapshots, iCloud files that can be downloaded again, and some caches. It counts as used, but macOS reclaims it before you run out.",
                        bytes: volume.purgeable
                    )
                    Divider().padding(.leading, 34)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Time Machine local snapshots").font(.body.weight(.medium))
                        Text(snapshotText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Text("\(model.snapshots.count)")
                        .font(.body.weight(.semibold))
                        .sizeStyle()
                    if model.isDeletingSnapshots {
                        ProgressView().controlSize(.small)
                    } else if !model.snapshots.isEmpty {
                        Button("Delete…") { confirmSnapshots = true }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .confirmationDialog(
            "Delete \(model.snapshots.count) local snapshot\(model.snapshots.count == 1 ? "" : "s")?",
            isPresented: $confirmSnapshots
        ) {
            Button("Delete Snapshots", role: .destructive) { model.deleteSnapshots() }
        } message: {
            Text("Your Time Machine backups on other disks aren't affected. macOS will ask for an administrator password.")
        }
    }

    private var snapshotText: String {
        if model.snapshots.isEmpty {
            return "None right now. When Time Machine is on, macOS keeps hourly snapshots of your disk for about a day. They count as purgeable space."
        }
        let dates = model.snapshots.compactMap(\.date).sorted()
        var text = "Hourly snapshots Time Machine keeps on this disk so you can restore recent files. macOS deletes them automatically when space runs low, but they can hold many gigabytes in the meantime (macOS doesn't report how much)."
        if let first = dates.first {
            text += " Oldest: \(first.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }
}

private struct ManagedRow: View {
    let symbol: String
    let title: String
    let detail: String
    let bytes: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(formatBytes(bytes))
                .font(.body.weight(.semibold))
                .sizeStyle()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Scan details

private struct ScanDetailsCard: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport
    @State private var showUnreadable = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scanned \(report.tree.displayName): \(report.tree.root.fileCount.formatted()) files, \(formatBytes(report.totalBytes)), in \(duration). Finished \(report.scannedAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if report.unreadableCount > 0 {
                    DisclosureGroup(isExpanded: $showUnreadable) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(report.unreadablePaths.prefix(40), id: \.self) { path in
                                Text(MacSystem.abbreviate(path))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            if report.unreadablePaths.count > 40 || report.unreadableCount > report.unreadablePaths.count {
                                Text("…and more").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("\(report.unreadableCount.formatted()) item\(report.unreadableCount == 1 ? "" : "s") couldn't be read. \(model.hasFullDiskAccess ? "These are protected by macOS itself." : "Full Disk Access would reveal most of them.")")
                            .font(.callout)
                    }
                }
            }
        }
    }

    private var duration: String {
        let seconds = Int(report.duration.rounded())
        if seconds < 60 { return "\(max(1, seconds)) second\(seconds == 1 ? "" : "s")" }
        return "\(seconds / 60) min \(seconds % 60) s"
    }
}
