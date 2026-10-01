import Foundation

/// One entry in a suggestion, e.g. a single app's cache inside "App caches".
public struct FoundItem: Identifiable, Hashable, Sendable {
    public let path: String
    public let name: String
    public let size: Int64
    public let modified: Date?
    /// Extra context, such as which device a backup belongs to.
    public let detail: String?
    public let safety: SafetyLevel
    /// What deleting this item means, or nil when it can't be deleted on its own.
    public let target: CleanupTarget?
    /// A summary row (e.g. "312 smaller files") rather than a real file or folder.
    public let isSummary: Bool
    public let isDirectory: Bool

    public var id: String { isSummary ? path + "#summary" : path }
}

/// A suggestion: a known location (or a pattern, like project build folders) found on disk.
public struct Finding: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let whatItIs: String
    public let ifDeleted: String
    public let category: StorageCategory
    public let safety: SafetyLevel
    public let manualSteps: String?
    public let countsAsSystemData: Bool
    public let paths: [String]
    public let items: [FoundItem]
    /// What "select all" adds to the cleanup list.
    public let wholeTargets: [CleanupTarget]
    public let totalSize: Int64

    public var isActionable: Bool { !wholeTargets.isEmpty || items.contains { $0.target != nil } }
}

/// Everything learned from a scan.
public struct ScanReport: Sendable {
    public let tree: FileTree
    public let categoryTotals: [StorageCategory: Int64]
    /// Bytes in places System Settings usually counts as "System Data".
    public let systemDataBytes: Int64
    public let findings: [Finding]
    public let largeFiles: [FoundItem]
    public let totalBytes: Int64
    /// Space that could be freed from suggestions marked safe.
    public let safeBytes: Int64
    /// Space in suggestions marked "review first".
    public let reviewBytes: Int64
    public let unreadableCount: Int
    public let unreadablePaths: [String]
    public let duration: TimeInterval
    public let scannedAt: Date

    public var sortedCategories: [(category: StorageCategory, bytes: Int64)] {
        categoryTotals
            .map { (category: $0.key, bytes: $0.value) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }
}

/// Turns a raw scan into categories, suggestions and a list of large files.
public struct ScanAnalyzer: Sendable {
    public var knowledge: KnowledgeBase
    public var policy: SafetyPolicy
    /// Bundle IDs of installed apps. When nil, leftover app data isn't detected.
    public var installedAppIDs: Set<String>?
    public var largeFileThreshold: Int64 = 100_000_000
    public var maxLargeFiles = 400
    /// Suggestions smaller than this are hidden.
    public var minimumFindingSize: Int64 = 1_000_000
    public var maxItemsPerFinding = 400

    public init(knowledge: KnowledgeBase, policy: SafetyPolicy, installedAppIDs: Set<String>? = nil) {
        self.knowledge = knowledge
        self.policy = policy
        self.installedAppIDs = installedAppIDs
    }

    private enum ProjectScope {
        case none
        case eligible
    }

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "zip", "rar", "7z", "tgz", "gz", "ipsw"]

    public func analyze(_ output: ScanOutput) -> ScanReport {
        let tree = output.tree
        let trie = knowledge.trie
        let locations = knowledge.locations

        var totals: [StorageCategory: Int64] = [:]
        var systemData: Int64 = 0
        var matches: [Int: [FileNode]] = [:]
        var artifacts: [(node: FileNode, kind: String)] = []
        var largeFiles: [FileNode] = []
        var installers: [FileNode] = []

        let homeNode = tree.node(atPath: knowledge.home)
        let downloadsNode = tree.node(atPath: knowledge.home + "/Downloads")
        let rootLocation = PatternTrie.best(in: trie.advance([trie.root], through: tree.rootPathComponents))?.index

        func walk(_ node: FileNode, states: [PatternTrie.Node], inherited: Int?, project: ProjectScope, inDownloads: Bool) {
            let exact = states.isEmpty ? nil : PatternTrie.best(in: states)?.index
            let effective = exact ?? inherited
            let location = effective.map { locations[$0] } ?? Catalog.unknown

            let own = node.ownSize
            totals[location.category, default: 0] += own
            if location.countsAsSystemData { systemData += own }

            if let exact, locations[exact].suggest {
                matches[exact, default: []].append(node)
            }

            if node.kind == .file {
                if node.size >= largeFileThreshold { largeFiles.append(node) }
                if inDownloads, Self.installerExtensions.contains(node.pathExtension) { installers.append(node) }
                return
            }
            guard node.isDirectory else { return }

            var childProject = project
            if project == .eligible, let kind = Self.projectArtifactKind(node) {
                artifacts.append((node, kind))
                childProject = .none
            }
            if node === homeNode { childProject = .eligible }
            if node.isPackage { childProject = .none }

            let childInDownloads = inDownloads || node === downloadsNode

            for child in node.children {
                var childStates: [PatternTrie.Node] = []
                if node === tree.root {
                    let base = tree.basePathComponents(forTopLevelChild: child.name)
                    childStates = trie.advance(trie.advance([trie.root], through: base), child.name)
                } else if !states.isEmpty {
                    childStates = trie.advance(states, child.name)
                }
                var scope = childProject
                if scope == .eligible, child.name.hasPrefix("."), !Self.hiddenArtifactNames.contains(child.name) {
                    scope = .none
                }
                if node === homeNode, child.name == "Library" { scope = .none }
                walk(child, states: childStates, inherited: effective, project: scope, inDownloads: childInDownloads)
            }
        }

        let rootStates = trie.advance([trie.root], through: tree.rootPathComponents)
        walk(tree.root, states: rootStates, inherited: rootLocation, project: tree.root === homeNode ? .eligible : .none, inDownloads: false)

        var findings: [Finding] = []
        for index in matches.keys.sorted() {
            guard let nodes = matches[index] else { continue }
            if let finding = makeFinding(location: locations[index], nodes: nodes, tree: tree), finding.totalSize >= minimumFindingSize {
                findings.append(finding)
            }
        }
        if let finding = projectArtifactsFinding(artifacts, tree: tree) { findings.append(finding) }
        if let finding = installersFinding(installers, tree: tree) { findings.append(finding) }
        if let installedAppIDs, let finding = leftoversFinding(tree: tree, installed: installedAppIDs) { findings.append(finding) }
        findings.sort { $0.totalSize > $1.totalSize }

        largeFiles.sort { $0.size > $1.size }
        let largeItems = largeFiles.prefix(maxLargeFiles).map { node -> FoundItem in
            let path = tree.path(of: node)
            return makeItem(node: node, path: path, name: node.name, detail: nil, kind: .item)
        }

        let safeBytes = reclaimable(findings.filter { $0.safety == .safe })
        let reviewBytes = reclaimable(findings.filter { $0.safety == .review })

        return ScanReport(
            tree: tree,
            categoryTotals: totals,
            systemDataBytes: systemData,
            findings: findings,
            largeFiles: Array(largeItems),
            totalBytes: tree.root.size,
            safeBytes: safeBytes,
            reviewBytes: reviewBytes,
            unreadableCount: output.unreadableCount,
            unreadablePaths: output.unreadablePaths,
            duration: output.duration,
            scannedAt: output.finishedAt
        )
    }

    /// Total size of the suggestions' targets, without counting overlapping folders twice.
    private func reclaimable(_ findings: [Finding]) -> Int64 {
        var basket = CleanupBasket()
        for finding in findings {
            let targets = finding.wholeTargets.isEmpty ? finding.items.compactMap(\.target) : finding.wholeTargets
            for target in targets { basket.add(target) }
        }
        return basket.totalSize
    }

    // MARK: - Building suggestions

    private func makeItem(node: FileNode, path: String, name: String, detail: String?, kind: CleanupTarget.Kind) -> FoundItem {
        let explanation = knowledge.explain(path: path, isDirectory: node.isDirectory)
        let verdict = policy.check(path, kind: kind)
        let target = verdict.isAllowed
            ? CleanupTarget(path: path, kind: kind, title: name, size: node.size, safety: explanation.safety)
            : nil
        return FoundItem(
            path: path,
            name: name,
            size: node.size,
            modified: node.modified > 0 ? node.modificationDate : nil,
            detail: detail,
            safety: explanation.safety,
            target: target,
            isSummary: false,
            isDirectory: node.isDirectory
        )
    }

    private func displayName(for location: KnownLocation, path: String, node: FileNode) -> String {
        let match = knowledge.match(path: path)
        if let captures = match?.captures, !captures.isEmpty, match?.location.id == location.id {
            return captures.joined(separator: " › ")
        }
        return node.name
    }

    private func makeFinding(location: KnownLocation, nodes: [FileNode], tree: FileTree) -> Finding? {
        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return nil }
        let paths = nodes.map { tree.path(of: $0) }

        var items: [FoundItem] = []
        var wholeTargets: [CleanupTarget] = []

        switch location.cleanup {
        case .trashContents:
            for (node, path) in zip(nodes, paths) where policy.check(path, kind: .contents).isAllowed {
                wholeTargets.append(CleanupTarget(
                    path: path,
                    kind: .contents,
                    title: nodes.count == 1 ? location.title : "\(location.title): \(displayName(for: location, path: path, node: node))",
                    size: node.size,
                    safety: location.safety
                ))
            }
            // A single, fixed folder (like ~/Library/Caches) is shown by what's inside it.
            // Wildcard locations (like every app's container cache) are shown folder by folder.
            let isWildcard = location.paths.contains { $0.contains("*") }
            if nodes.count == 1, !isWildcard, let node = nodes.first, let path = paths.first {
                let children = node.children.prefix(maxItemsPerFinding)
                for child in children where child.size > 0 {
                    let childPath = path + "/" + child.name
                    let details = ItemDetails.describe(locationID: location.id, path: childPath, name: child.name)
                    items.append(makeItem(
                        node: child,
                        path: childPath,
                        name: details?.name ?? child.name,
                        detail: details?.detail,
                        kind: .item
                    ))
                }
                let hiddenChildren = node.children.dropFirst(maxItemsPerFinding)
                let leftoverSize = node.looseFileSize + hiddenChildren.reduce(0) { $0 + $1.size }
                let leftoverCount = node.looseFileCount + hiddenChildren.count
                if leftoverSize > 0 {
                    items.append(FoundItem(
                        path: path,
                        name: leftoverCount == 1 ? "1 other item" : "\(leftoverCount) other items",
                        size: leftoverSize,
                        modified: nil,
                        detail: "Smaller files. Included when you clean up the whole folder.",
                        safety: location.safety,
                        target: nil,
                        isSummary: true,
                        isDirectory: false
                    ))
                }
            } else {
                for (node, path) in zip(nodes, paths) {
                    let name = displayName(for: location, path: path, node: node)
                    let verdict = policy.check(path, kind: .contents)
                    items.append(FoundItem(
                        path: path,
                        name: name,
                        size: node.size,
                        modified: node.modified > 0 ? node.modificationDate : nil,
                        detail: nil,
                        safety: location.safety,
                        target: verdict.isAllowed
                            ? CleanupTarget(path: path, kind: .contents, title: "\(location.title): \(name)", size: node.size, safety: location.safety)
                            : nil,
                        isSummary: false,
                        isDirectory: true
                    ))
                }
            }

        case .trashItem:
            for (node, path) in zip(nodes, paths) {
                let name = displayName(for: location, path: path, node: node)
                let item = makeItem(node: node, path: path, name: name, detail: nil, kind: .item)
                items.append(item)
                if let target = item.target { wholeTargets.append(target) }
            }

        case .manual, .individually:
            for (node, path) in zip(nodes, paths) {
                items.append(FoundItem(
                    path: path,
                    name: displayName(for: location, path: path, node: node),
                    size: node.size,
                    modified: node.modified > 0 ? node.modificationDate : nil,
                    detail: nil,
                    safety: location.safety,
                    target: nil,
                    isSummary: false,
                    isDirectory: node.isDirectory
                ))
            }
        }

        items.sort { $0.size > $1.size }
        return Finding(
            id: location.id,
            title: location.title,
            whatItIs: location.whatItIs,
            ifDeleted: location.ifDeleted,
            category: location.category,
            safety: location.safety,
            manualSteps: location.manualSteps,
            countsAsSystemData: location.countsAsSystemData,
            paths: paths,
            items: items,
            wholeTargets: wholeTargets,
            totalSize: total
        )
    }

    // MARK: - Project build folders

    private static let hiddenArtifactNames: Set<String> = [".venv", ".build", ".next", ".gradle", ".nuxt", ".turbo", ".parcel-cache", ".angular", ".svelte-kit", ".dart_tool"]

    /// Recognises folders that coding tools regenerate. Returns a short description.
    static func projectArtifactKind(_ node: FileNode) -> String? {
        let parentMarkers = node.parent?.markers ?? []
        switch node.name {
        case "node_modules":
            return "Node.js packages"
        case ".venv", "venv", "env", ".env":
            return node.markers.contains(.pyvenvCfg) ? "Python virtual environment" : nil
        case "target":
            return parentMarkers.contains(.cargoToml) ? "Rust build output" : nil
        case "Pods":
            return parentMarkers.contains(.podfile) ? "CocoaPods dependencies" : nil
        case ".build":
            return parentMarkers.contains(.packageSwift) ? "Swift package build output" : nil
        case "build", ".gradle":
            return parentMarkers.contains(.gradleBuild) ? "Gradle build output" : nil
        case ".next", ".nuxt", ".turbo", ".parcel-cache", ".angular", ".svelte-kit":
            return parentMarkers.contains(.packageJSON) ? "JavaScript framework cache" : nil
        case ".dart_tool":
            return "Dart/Flutter build cache"
        case "vendor":
            return parentMarkers.contains(.composerJSON) ? "PHP Composer packages" : nil
        default:
            return nil
        }
    }

    private func projectArtifactsFinding(_ artifacts: [(node: FileNode, kind: String)], tree: FileTree) -> Finding? {
        let location = Catalog.projectArtifacts
        var items: [FoundItem] = []
        for (node, kind) in artifacts where node.size >= 5_000_000 {
            let path = tree.path(of: node)
            let project = node.parent?.name ?? ""
            var detail = "\(kind) in \(project)"
            if let parent = node.parent, parent.modified > 0 {
                detail += " · project changed \(Self.relativeAge(parent.modificationDate))"
            }
            items.append(makeItem(node: node, path: path, name: "\(project) › \(node.name)", detail: detail, kind: .item))
        }
        return finding(for: location, items: items)
    }

    private func installersFinding(_ nodes: [FileNode], tree: FileTree) -> Finding? {
        let items = nodes.map { node -> FoundItem in
            let path = tree.path(of: node)
            let hint = FileTypeHints.hint(forExtension: node.pathExtension, isDirectory: false)
            return makeItem(node: node, path: path, name: node.name, detail: hint?.title, kind: .item)
        }
        return finding(for: Catalog.downloadedInstallers, items: items)
    }

    private func leftoversFinding(tree: FileTree, installed: Set<String>) -> Finding? {
        var items: [FoundItem] = []
        let folders = [
            knowledge.home + "/Library/Containers",
            knowledge.home + "/Library/Application Support",
        ]
        for folder in folders {
            guard let parent = tree.node(atPath: folder) else { continue }
            for child in parent.children where child.isDirectory && child.size >= 10_000_000 {
                let name = child.name
                guard ItemDetails.looksLikeBundleID(name),
                      !name.lowercased().hasPrefix("com.apple."),
                      !InstalledApps.isInstalled(name, in: installed) else { continue }
                let path = folder + "/" + name
                items.append(makeItem(node: child, path: path, name: name, detail: "No installed app uses this ID", kind: .item))
            }
        }
        return finding(for: Catalog.leftoverAppData, items: items)
    }

    private func finding(for location: KnownLocation, items unsorted: [FoundItem]) -> Finding? {
        let items = unsorted.sorted { $0.size > $1.size }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        guard total >= minimumFindingSize else { return nil }
        return Finding(
            id: location.id,
            title: location.title,
            whatItIs: location.whatItIs,
            ifDeleted: location.ifDeleted,
            category: location.category,
            safety: location.safety,
            manualSteps: nil,
            countsAsSystemData: location.countsAsSystemData,
            paths: items.map(\.path),
            items: items,
            wholeTargets: items.compactMap(\.target),
            totalSize: total
        )
    }

    static func relativeAge(_ date: Date, now: Date = Date()) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<31: return "\(days) days ago"
        case 31..<365:
            let months = days / 30
            return months == 1 ? "a month ago" : "\(months) months ago"
        default:
            let years = days / 365
            return years == 1 ? "a year ago" : "\(years) years ago"
        }
    }
}
