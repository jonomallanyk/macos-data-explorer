import AppKit
import SwiftUI
import DataExplorerCore

struct ExploreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let report = model.report {
                ExploreBrowser(tree: report.tree, folder: model.exploreFolder ?? report.tree.root)
            } else {
                EmptyState(
                    systemImage: "folder",
                    title: "Nothing to explore yet",
                    message: "Scan your Mac, then browse folder by folder. Every item is labelled with what it is and whether it's safe to delete."
                ) {
                    ScanButtons()
                }
            }
        }
        .navigationTitle("Explore")
    }
}

private struct ExploreBrowser: View {
    @Environment(AppModel.self) private var model
    let tree: FileTree
    let folder: FileNode

    private let rowLimit = 1_000

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(tree: tree, folder: folder)
            Divider()
            HSplitView {
                list
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                InspectorPanel(node: selectedNode ?? folder, tree: tree, folder: folder)
                    .frame(minWidth: 280, idealWidth: 330, maxWidth: 460, maxHeight: .infinity)
            }
        }
    }

    private var selectedNode: FileNode? {
        guard let id = model.exploreSelection else { return nil }
        return folder.children.first { $0.id == id }
    }

    private func node(for id: FileNode.ID?) -> FileNode? {
        guard let id else { return nil }
        return folder.children.first { $0.id == id }
    }

    private var list: some View {
        @Bindable var model = model
        let children = Array(folder.children.prefix(rowLimit))
        let hiddenCount = folder.children.count - children.count
        return List(selection: $model.exploreSelection) {
            if folder.isUnreadable {
                Label("macOS didn't let Data Explorer look inside this folder. Full Disk Access may help; some system folders are off-limits to every app.", systemImage: "eye.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(children) { child in
                NodeRow(node: child, parentSize: folder.size)
                    .tag(child.id)
            }
            if hiddenCount > 0 {
                Text("…and \(hiddenCount.formatted()) smaller items")
                    .foregroundStyle(.secondary)
            }
            if folder.looseFileCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.looseFileCount == 1 ? "1 small file" : "\(folder.looseFileCount.formatted()) small files")
                        Text("Files under 1 MB are counted together to keep scans fast.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(folder.looseFileSize))
                        .foregroundStyle(.secondary)
                        .sizeStyle()
                }
                .padding(.vertical, 2)
            }
            if children.isEmpty && folder.looseFileCount == 0 && !folder.isUnreadable {
                Text("This folder is empty.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            if let node = node(for: ids.first) {
                if node.isDirectory {
                    Button("Open") { model.open(node) }
                }
                Button("Show in Finder") { MacSystem.revealInFinder(model.path(of: node)) }
                Button("Copy Path") { MacSystem.copyToPasteboard(model.path(of: node)) }
                if let target = model.target(for: node) {
                    Divider()
                    Button(model.isSelected(target) ? "Remove from Cleanup List" : "Add to Cleanup List") {
                        model.toggle(target)
                    }
                }
            }
        } primaryAction: { ids in
            if let node = node(for: ids.first), node.isDirectory {
                model.open(node)
            }
        }
    }
}

private struct BreadcrumbBar: View {
    @Environment(AppModel.self) private var model
    let tree: FileTree
    let folder: FileNode

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(folder === tree.root)
            .help("Go to the enclosing folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(tree.ancestors(of: folder).enumerated()), id: \.offset) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .foregroundStyle(.tertiary)
                        }
                        Button(index == 0 ? tree.displayName : AppNames.friendly(node.name)) {
                            model.open(node)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(node === folder ? Color.primary : Color.secondary)
                        .fontWeight(node === folder ? .semibold : .regular)
                    }
                }
            }
            Spacer(minLength: 8)
            Text("\(formatBytes(folder.size)) · \(folder.fileCount.formatted()) files")
                .foregroundStyle(.secondary)
                .sizeStyle()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct NodeIcon: View {
    let node: FileNode
    let path: String
    let color: Color
    var size: CGFloat = 18

    var body: some View {
        if node.isDirectory && node.pathExtension == "app" {
            Image(nsImage: FileIcons.icon(forPath: path))
                .resizable()
                .frame(width: size + 2, height: size + 2)
        } else {
            Image(systemName: node.isDirectory ? (node.isPackage ? "shippingbox.fill" : "folder.fill") : "doc.fill")
                .font(.system(size: size * 0.85))
                .foregroundStyle(node.isDirectory ? color : Color.secondary)
                .frame(width: size + 2, height: size + 2)
        }
    }
}

private struct NodeRow: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    let parentSize: Int64

    var body: some View {
        let path = model.path(of: node)
        let explanation = model.explanation(forPath: path, isDirectory: node.isDirectory)
        let target = model.target(for: node)
        HStack(spacing: 10) {
            NodeIcon(node: node, path: path, color: explanation.category.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(AppNames.friendly(node.name))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if node.isUnreadable {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.orange)
                            .help("Couldn't be read, so its size is incomplete.")
                    }
                }
                Text(explanation.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            SafetyBadge(level: explanation.safety, compact: true)
            SizeBar(fraction: Double(node.size) / Double(max(1, parentSize)), color: explanation.category.color)
                .frame(width: 80)
            Text(formatBytes(node.size))
                .sizeStyle()
                .frame(width: 70, alignment: .trailing)
            if let target {
                CheckboxButton(state: model.isSelected(target) ? .checked : .unchecked) {
                    model.toggle(target)
                }
            } else {
                Image(systemName: "lock")
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InspectorPanel: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    let tree: FileTree
    let folder: FileNode

    var body: some View {
        let path = tree.path(of: node)
        let explanation = model.explanation(forPath: path, isDirectory: node.isDirectory)
        let verdict = model.verdict(for: node)
        let friendly = AppNames.friendly(node.name)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    NodeIcon(node: node, path: path, color: explanation.category.color, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node === tree.root ? tree.displayName : friendly)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if friendly != node.name && node !== tree.root {
                            Text(node.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(formatBytes(node.size))
                    .font(.system(size: 30, weight: .semibold))
                    .sizeStyle()

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    if node.isDirectory {
                        GridRow {
                            Text("Contains").foregroundStyle(.secondary)
                            Text("\(node.fileCount.formatted()) file\(node.fileCount == 1 ? "" : "s")")
                        }
                    }
                    if node.modified > 0 {
                        GridRow {
                            Text("Modified").foregroundStyle(.secondary)
                            Text(node.modificationDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    GridRow {
                        Text("Category").foregroundStyle(.secondary)
                        Label(explanation.category.title, systemImage: explanation.category.symbolName)
                    }
                    GridRow(alignment: .top) {
                        Text("Location").foregroundStyle(.secondary)
                        Text(MacSystem.abbreviate(path))
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(explanation.headline).font(.headline)
                    Text(explanation.whatItIs)
                        .fixedSize(horizontal: false, vertical: true)
                    SafetyBadge(level: explanation.safety)
                    Text(explanation.safety.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledText(label: "If you delete it:", text: explanation.ifDeleted)
                    if let steps = explanation.manualSteps {
                        ManualStepsBox(steps: steps)
                    }
                    if explanation.countsAsSystemData {
                        Label("System Settings counts this as System Data.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    if let target = model.target(for: node) {
                        Button {
                            model.toggle(target)
                        } label: {
                            Label(
                                model.isSelected(target) ? "Remove from Cleanup List" : "Add to Cleanup List",
                                systemImage: model.isSelected(target) ? "minus.circle" : "plus.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    } else if let reason = verdict.reason {
                        Label(reason, systemImage: "lock")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        if node.isDirectory && node !== folder {
                            Button("Open") { model.open(node) }
                        }
                        Button("Show in Finder") { MacSystem.revealInFinder(path) }
                        Button("Copy Path") { MacSystem.copyToPasteboard(path) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
