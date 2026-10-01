import AppKit
import SwiftUI
import DataExplorerCore

struct CleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false
    @State private var showFailures = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let outcome = model.lastOutcome {
                OutcomeBanner(outcome: outcome, showFailures: $showFailures)
            }
            if model.basket.isEmpty {
                if model.lastOutcome == nil {
                    EmptyState(
                        systemImage: "checklist",
                        title: "Nothing selected yet",
                        message: "Tick the things you'd like to remove in Suggestions, Explore or Large Files. They'll be collected here so you can review everything before anything is deleted."
                    ) {
                        Button("Go to Suggestions") { model.selection = .suggestions }
                            .disabled(model.report == nil)
                    }
                } else {
                    Spacer()
                }
            } else {
                list
                Divider()
                footer
            }
        }
        .navigationTitle("Review & Delete")
        .confirmationDialog(confirmTitle, isPresented: $confirming) {
            Button(model.cleanupMode == .moveToTrash ? "Move to Trash" : "Delete Immediately", role: .destructive) {
                model.performCleanup()
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private var groupedTargets: [(level: SafetyLevel, targets: [CleanupTarget])] {
        SafetyLevel.allCases.compactMap { level -> (level: SafetyLevel, targets: [CleanupTarget])? in
            let targets = model.basket.targets.filter { $0.safety == level }.sorted { $0.size > $1.size }
            return targets.isEmpty ? nil : (level, targets)
        }
    }

    private var list: some View {
        List {
            ForEach(groupedTargets, id: \.level) { group in
                Section {
                    ForEach(group.targets) { target in
                        TargetRow(target: target)
                    }
                } header: {
                    HStack {
                        SafetyBadge(level: group.level)
                        Text(group.level.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Text(formatBytes(group.targets.reduce(Int64(0)) { $0 + $1.size }))
                            .sizeStyle()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        @Bindable var model = model
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $model.cleanupMode) {
                    ForEach(CleanupMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
                Text(model.cleanupMode == .moveToTrash
                     ? "Items go to the Trash so you can put them back. Space is freed when you empty the Trash."
                     : "Items are deleted right away and can't be recovered. Space is freed immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isCleaning {
                ProgressView(value: Double(model.cleanupDone), total: Double(max(1, model.cleanupTotal)))
                    .frame(width: 160)
                Text("\(model.cleanupDone) of \(model.cleanupTotal)")
                    .foregroundStyle(.secondary)
                    .sizeStyle()
            } else {
                Button("Clear List") { model.basket.removeAll() }
                Button {
                    confirming = true
                } label: {
                    Label(actionTitle, systemImage: "trash")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.cleanupMode == .deleteImmediately ? .red : .accentColor)
                .controlSize(.large)
                .disabled(model.isReanalyzing)
            }
        }
        .padding(16)
    }

    private var actionTitle: String {
        let count = model.basket.count
        let noun = count == 1 ? "item" : "items"
        let size = formatBytes(model.basket.totalSize)
        return model.cleanupMode == .moveToTrash
            ? "Move \(count) \(noun) to Trash (\(size))"
            : "Delete \(count) \(noun) (\(size))"
    }

    private var confirmTitle: String {
        model.cleanupMode == .moveToTrash
            ? "Move \(model.basket.count) item\(model.basket.count == 1 ? "" : "s") to the Trash?"
            : "Permanently delete \(model.basket.count) item\(model.basket.count == 1 ? "" : "s")?"
    }

    private var confirmMessage: String {
        var lines: [String] = []
        let size = formatBytes(model.basket.totalSize)
        lines.append(model.cleanupMode == .moveToTrash
            ? "About \(size) will move to the Trash."
            : "About \(size) will be deleted. This can't be undone.")
        let cautious = model.basket.targets.filter { $0.safety >= .caution }.count
        let review = model.basket.targets.filter { $0.safety == .review }.count
        if cautious > 0 {
            lines.append("\(cautious) item\(cautious == 1 ? " holds" : "s hold") app data: the app may reset or lose information stored in it.")
        }
        if review > 0 {
            lines.append("\(review) item\(review == 1 ? " is" : "s are") your own files or backups. Make sure you don't need them.")
        }
        lines.append("Quit any apps whose caches you're clearing for best results.")
        return lines.joined(separator: "\n\n")
    }
}

private struct TargetRow: View {
    @Environment(AppModel.self) private var model
    let target: CleanupTarget

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: target.kind == .contents ? "folder.badge.minus" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppNames.friendly(target.title))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(target.kind == .contents
                     ? "Everything inside \(MacSystem.abbreviate(target.path))"
                     : MacSystem.abbreviate(target.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(formatBytes(target.size))
                .sizeStyle()
            Button {
                MacSystem.revealInFinder(target.path)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            Button {
                model.remove(target)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from the list")
            .disabled(model.isCleaning)
        }
        .padding(.vertical, 3)
    }
}

private struct OutcomeBanner: View {
    @Environment(AppModel.self) private var model
    let outcome: CleanupOutcome
    @Binding var showFailures: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: outcome.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(outcome.failures.isEmpty ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.headline)
                    if outcome.mode == .moveToTrash && outcome.bytesHandled > 0 {
                        Text("The space is freed once you empty the Trash.")
                            .foregroundStyle(.secondary)
                    } else if let volume = model.volume {
                        Text("\(formatBytes(volume.available)) is now free.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if outcome.mode == .moveToTrash && outcome.bytesHandled > 0 {
                    Button("Empty Trash") { model.emptyTrash() }
                        .disabled(model.isCleaning)
                }
                Button("Done") { model.lastOutcome = nil }
            }
            if !outcome.failures.isEmpty {
                DisclosureGroup(isExpanded: $showFailures) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(outcome.failures.prefix(100)) { failure in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(MacSystem.abbreviate(failure.path))
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                Text(failure.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("\(outcome.failures.count) item\(outcome.failures.count == 1 ? "" : "s") couldn't be removed")
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var headline: String {
        let size = formatBytes(outcome.bytesHandled)
        let count = outcome.completed.count + outcome.partial.count
        let noun = count == 1 ? "item" : "items"
        switch outcome.mode {
        case .moveToTrash: return "Moved \(count) \(noun) to the Trash (\(size))"
        case .deleteImmediately: return "Deleted \(count) \(noun) (\(size))"
        }
    }
}
