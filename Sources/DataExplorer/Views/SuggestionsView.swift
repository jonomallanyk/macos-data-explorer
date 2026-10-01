import AppKit
import SwiftUI
import DataExplorerCore

struct SuggestionsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case safe = "Safe to delete"
        case review = "Review first"
        case elsewhere = "Clean up elsewhere"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    let fixedCategory: StorageCategory?
    @State private var filter: Filter = .all
    @State private var expanded: Set<String> = []

    var body: some View {
        Group {
            if let report = model.report {
                content(report)
            } else {
                EmptyState(
                    systemImage: fixedCategory == .developer ? "hammer" : "sparkles",
                    title: "No suggestions yet",
                    message: "Scan your Mac to see what's taking up space, what each thing is, and what can safely go."
                ) {
                    ScanButtons()
                }
            }
        }
        .navigationTitle(fixedCategory == .developer ? "Developer" : "Suggestions")
    }

    private var activeCategory: StorageCategory? {
        fixedCategory ?? model.suggestionCategory
    }

    private func filtered(_ findings: [Finding]) -> [Finding] {
        findings.filter { finding in
            if let category = activeCategory, finding.category != category { return false }
            switch filter {
            case .all: return true
            case .safe: return finding.safety == .safe && finding.isActionable
            case .review: return finding.safety != .safe && finding.isActionable
            case .elsewhere: return !finding.isActionable
            }
        }
    }

    private func content(_ report: ScanReport) -> some View {
        let findings = filtered(report.findings)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header(report: report, shown: findings)
                        .id("suggestions-top")
                    ForEach(findings) { finding in
                        FindingCard(finding: finding, isExpanded: binding(for: finding.id))
                            .id(finding.id)
                    }
                    if findings.isEmpty {
                        Text("Nothing matches this filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
            .task(id: model.focusedFindingID) {
                guard let id = model.focusedFindingID else { return }
                filter = .all
                expanded.insert(id)
                try? await Task.sleep(for: .milliseconds(150))
                // Keep the summary in view when the finding is already at the top of the list.
                let target = filtered(report.findings).first?.id == id ? "suggestions-top" : id
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                model.focusedFindingID = nil
            }
        }
    }

    @ViewBuilder
    private func header(report: ScanReport, shown: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if fixedCategory == .developer {
                Text("Build caches, simulators, package downloads and project folders that coding tools create. Most of it is regenerated automatically.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Everything Data Explorer recognised, biggest first. Tick what you'd like to remove, then review it under Review & Delete. Nothing is deleted until you confirm.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                SummaryNumber(value: shown.filter { $0.safety == .safe && $0.isActionable }.reduce(0) { $0 + $1.totalSize }, label: "safe to delete", color: .green)
                SummaryNumber(value: shown.filter { $0.safety != .safe && $0.isActionable }.reduce(0) { $0 + $1.totalSize }, label: "worth reviewing", color: .blue)
                SummaryNumber(value: shown.filter { !$0.isActionable }.reduce(0) { $0 + $1.totalSize }, label: "to clean up elsewhere", color: .secondary)
                Spacer()
                if !model.basket.isEmpty {
                    Button {
                        model.selection = .cleanup
                    } label: {
                        Label("Review \(model.basket.count) selected (\(formatBytes(model.basket.totalSize)))", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            HStack {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
                if fixedCategory == nil, let category = model.suggestionCategory {
                    Button {
                        model.suggestionCategory = nil
                    } label: {
                        Label(category.title, systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Show all categories")
                }
                Spacer()
                Button(expanded.isEmpty ? "Expand All" : "Collapse All") {
                    if expanded.isEmpty {
                        expanded = Set(shown.map(\.id))
                    } else {
                        expanded.removeAll()
                    }
                }
                .buttonStyle(.link)
            }
        }
        .padding(.bottom, 4)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

private struct SummaryNumber: View {
    let value: Int64
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(formatBytes(value))
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .sizeStyle()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FindingCard: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    @Binding var isExpanded: Bool
    @State private var showAllItems = false

    private let collapsedItemLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                details
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if finding.isActionable {
                CheckboxButton(state: model.checkState(for: finding)) { model.toggle(finding) }
                    .padding(.top, 1)
            } else {
                Image(systemName: "hand.raised")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .help("Clean this up from its own app or setting. Expand for instructions.")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(finding.title).font(.headline)
                    SafetyBadge(level: finding.safety)
                    if finding.countsAsSystemData {
                        Text("System Data")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .help("System Settings counts this as \"System Data\".")
                    }
                }
                Text(finding.whatItIs)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(finding.totalSize))
                    .font(.title3.weight(.semibold))
                    .sizeStyle()
                Text(itemCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .padding(.top, 4)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
    }

    private var realItemCount: Int {
        finding.items.filter { !$0.isSummary }.count
    }

    private var itemCountText: String {
        realItemCount == 1 ? "1 item" : "\(realItemCount) items"
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledText(label: "If you delete it:", text: finding.ifDeleted, systemImage: "info.circle")
            if let steps = finding.manualSteps {
                ManualStepsBox(steps: steps)
            }
            VStack(spacing: 0) {
                ForEach(visibleItems) { item in
                    FoundItemRow(item: item, finding: finding)
                    Divider()
                }
            }
            if finding.items.count > collapsedItemLimit {
                Button(showAllItems ? "Show fewer" : "Show all \(realItemCount) items") {
                    showAllItems.toggle()
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
    }

    private var visibleItems: [FoundItem] {
        showAllItems ? finding.items : Array(finding.items.prefix(collapsedItemLimit))
    }
}

struct FoundItemRow: View {
    @Environment(AppModel.self) private var model
    let item: FoundItem
    let finding: Finding

    var body: some View {
        HStack(spacing: 10) {
            if let target = item.target {
                CheckboxButton(state: model.isSelected(target) ? .checked : .unchecked) {
                    model.toggle(item, in: finding)
                }
            } else {
                Image(systemName: item.isSummary ? "ellipsis" : "lock")
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                    .help(item.isSummary ? "Included when the whole folder is cleaned up." : blockedReason)
            }
            if item.isDirectory && !item.isSummary && item.name.hasSuffix(".app") {
                Image(nsImage: FileIcons.icon(forPath: item.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: item.isSummary ? "doc.on.doc" : (item.isDirectory ? "folder" : "doc"))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.safety != finding.safety {
                SafetyBadge(level: item.safety, compact: true)
            }
            Text(formatBytes(item.size))
                .foregroundStyle(.secondary)
                .sizeStyle()
            if !item.isSummary {
                Button {
                    MacSystem.revealInFinder(item.path)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            if !item.isSummary {
                Button("Show in Finder") { MacSystem.revealInFinder(item.path) }
                Button("Show in Explore") { model.showInExplore(item.path) }
                Button("Copy Path") { MacSystem.copyToPasteboard(item.path) }
            }
        }
    }

    private var displayName: String {
        let friendly = AppNames.friendly(item.name)
        return friendly == item.name ? item.name : "\(friendly) (\(item.name))"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let detail = item.detail {
            parts.append(detail)
        } else if !item.isSummary {
            parts.append(MacSystem.abbreviate(item.path))
        }
        if let modified = item.modified, !item.isSummary {
            parts.append("changed \(modified.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private var blockedReason: String {
        model.policy.check(item.path, kind: .item).reason ?? "Data Explorer won't delete this."
    }
}
