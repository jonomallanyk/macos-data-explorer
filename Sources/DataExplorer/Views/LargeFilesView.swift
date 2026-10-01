import AppKit
import SwiftUI
import DataExplorerCore

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<FoundItem.ID>()
    @State private var hideProtected = true

    var body: some View {
        Group {
            if let report = model.report {
                content(report)
            } else {
                EmptyState(
                    systemImage: "doc.badge.ellipsis",
                    title: "No large files yet",
                    message: "Scan your Mac to list every file over 100 MB, with an explanation of what each one is."
                ) {
                    ScanButtons()
                }
            }
        }
        .navigationTitle("Large Files")
    }

    private func content(_ report: ScanReport) -> some View {
        let items = report.largeFiles.filter { !hideProtected || $0.target != nil }
        let selectedTargets = items.filter { selection.contains($0.id) }.compactMap(\.target)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Files over 100 MB, largest first. Big files are often forgotten downloads, videos, disk images or virtual machines.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Toggle("Hide files that can't be deleted here", isOn: $hideProtected)
                    .toggleStyle(.checkbox)
                Button("Add \(selectedTargets.count) to Cleanup List") {
                    for target in selectedTargets where !model.isSelected(target) {
                        model.toggle(target)
                    }
                    selection.removeAll()
                }
                .disabled(selectedTargets.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            Table(items, selection: $selection) {
                TableColumn("") { item in
                    if let target = item.target {
                        CheckboxButton(state: model.isSelected(target) ? .checked : .unchecked) {
                            model.toggle(target)
                        }
                    } else {
                        Image(systemName: "lock")
                            .foregroundStyle(.tertiary)
                            .help(model.policy.check(item.path, kind: .item).reason ?? "")
                    }
                }
                .width(24)

                TableColumn("Name") { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(MacSystem.abbreviate((item.path as NSString).deletingLastPathComponent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(item.path)
                }
                .width(min: 200, ideal: 320)

                TableColumn("Size") { item in
                    Text(formatBytes(item.size))
                        .sizeStyle()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 80, max: 100)

                TableColumn("What it is") { item in
                    let explanation = model.explanation(forPath: item.path, isDirectory: false)
                    HStack(spacing: 6) {
                        SafetyBadge(level: item.safety, compact: true)
                        Text(explanation.headline)
                            .lineLimit(1)
                    }
                    .help(explanation.whatItIs)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Modified") { item in
                    Text(item.modified?.formatted(date: .abbreviated, time: .omitted) ?? "")
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100, max: 130)
            }
            .contextMenu(forSelectionType: FoundItem.ID.self) { ids in
                if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                    Button("Show in Finder") { MacSystem.revealInFinder(item.path) }
                    Button("Show in Explore") { model.showInExplore(item.path) }
                    Button("Copy Path") { MacSystem.copyToPasteboard(item.path) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                    MacSystem.revealInFinder(item.path)
                }
            }

            if items.isEmpty {
                Text("No files over 100 MB.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}
