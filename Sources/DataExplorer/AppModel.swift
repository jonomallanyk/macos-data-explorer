import AppKit
import Observation
import DataExplorerCore

enum ScanScope: Hashable {
    case entireMac
    case home
    case folder(String)

    var title: String {
        switch self {
        case .entireMac: return "Entire Mac"
        case .home: return "Home Folder"
        case .folder(let path): return (path as NSString).lastPathComponent
        }
    }
}

enum SidebarItem: Hashable {
    case overview
    case suggestions
    case explore
    case largeFiles
    case developer
    case cleanup
}

enum CheckState {
    case unchecked
    case mixed
    case checked
    case unavailable
}

/// A thread-safe "stop" flag shared with background work.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case analyzing
        case done
        case failed(String)
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    let home = NSHomeDirectory()
    let knowledge: KnowledgeBase
    let policy: SafetyPolicy

    // Scanning
    var phase: Phase = .idle
    var scope: ScanScope = .entireMac
    var scannedScope: ScanScope?
    var progress: ScanProgress?
    var scanStartedAt: Date?
    var report: ScanReport?
    var isReanalyzing = false

    // System information
    var volume: VolumeCapacity?
    var container: APFSContainer?
    var snapshots: [LocalSnapshot] = []
    var hasFullDiskAccess = false
    var isDeletingSnapshots = false

    // Navigation
    var selection: SidebarItem? = .overview
    var exploreFolder: FileNode?
    var exploreSelection: FileNode.ID?
    var suggestionCategory: StorageCategory?
    var focusedFindingID: String?

    // Cleanup
    var basket = CleanupBasket()
    var cleanupMode: CleanupMode = .moveToTrash
    var isCleaning = false
    var cleanupDone = 0
    var cleanupTotal = 0
    var lastOutcome: CleanupOutcome?
    var notice: Notice?

    @ObservationIgnored private var activeScan: CancellationFlag?
    @ObservationIgnored private var installedAppIDs: Set<String>?

    init() {
        knowledge = KnowledgeBase.standard(home: home)
        policy = SafetyPolicy(knowledge: knowledge)
        refreshAccess()
        refreshSystemInfo()
    }

    var isScanning: Bool { phase == .scanning || phase == .analyzing }

    // MARK: - System information

    func refreshAccess() {
        hasFullDiskAccess = MacSystem.hasFullDiskAccess()
    }

    func refreshSystemInfo() {
        volume = VolumeCapacity.current()
        let model = self
        Task.detached(priority: .utility) {
            let container = APFSInfo.startupContainer()
            let snapshots = LocalSnapshots.list()
            await model.applySystemInfo(container: container, snapshots: snapshots)
        }
    }

    private func applySystemInfo(container: APFSContainer?, snapshots: [LocalSnapshot]) {
        self.container = container
        self.snapshots = snapshots
    }

    func deleteSnapshots() {
        guard let command = LocalSnapshots.deletionCommand(for: snapshots) else { return }
        isDeletingSnapshots = true
        let model = self
        Task.detached(priority: .userInitiated) {
            let result = MacSystem.runWithAdministratorPrivileges(command)
            await model.finishDeletingSnapshots(success: result.success, message: result.message)
        }
    }

    private func finishDeletingSnapshots(success: Bool, message: String) {
        isDeletingSnapshots = false
        if !success && message != "Cancelled." {
            notice = Notice(title: "Couldn't delete snapshots", message: message)
        }
        refreshSystemInfo()
    }

    // MARK: - Scanning

    func startScan(scope newScope: ScanScope? = nil) {
        if let newScope { scope = newScope }
        activeScan?.cancel()

        let options: ScanOptions
        switch scope {
        case .entireMac:
            options = .entireDisk(displayName: volume?.name ?? "Macintosh HD")
        case .home:
            options = ScanOptions(rootPath: home, displayName: "Home (\((home as NSString).lastPathComponent))")
        case .folder(let path):
            options = .folder(path)
        }

        let flag = CancellationFlag()
        activeScan = flag
        phase = .scanning
        progress = nil
        scanStartedAt = Date()
        refreshAccess()

        let knowledge = self.knowledge
        let policy = self.policy
        let model = self
        let scanScope = self.scope
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let output = try DiskScanner.scan(options, isCancelled: { flag.isCancelled }) { progress in
                    Task { @MainActor in model.updateProgress(progress, flag: flag) }
                }
                Task { @MainActor in model.markAnalyzing(flag: flag) }
                let installed = InstalledApps.bundleIdentifiers()
                let analyzer = ScanAnalyzer(knowledge: knowledge, policy: policy, installedAppIDs: installed)
                let report = analyzer.analyze(output)
                Task { @MainActor in model.finishScan(report, scope: scanScope, installed: installed, flag: flag) }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let cancelled: Bool
                if case ScanError.cancelled = error { cancelled = true } else { cancelled = false }
                Task { @MainActor in model.failScan(message, cancelled: cancelled, flag: flag) }
            }
        }
    }

    func cancelScan() {
        activeScan?.cancel()
        activeScan = nil
        phase = report == nil ? .idle : .done
        progress = nil
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(scope: .folder(url.path))
        }
    }

    private func updateProgress(_ progress: ScanProgress, flag: CancellationFlag) {
        guard flag === activeScan, phase == .scanning else { return }
        self.progress = progress
    }

    private func markAnalyzing(flag: CancellationFlag) {
        guard flag === activeScan else { return }
        phase = .analyzing
    }

    private func finishScan(_ report: ScanReport, scope: ScanScope, installed: Set<String>, flag: CancellationFlag) {
        guard flag === activeScan, !flag.isCancelled else { return }
        activeScan = nil
        self.report = report
        scannedScope = scope
        installedAppIDs = installed
        phase = .done
        progress = nil
        exploreFolder = report.tree.root
        exploreSelection = nil
        basket.removeAll()
        lastOutcome = nil
        volume = VolumeCapacity.current()
        if selection == nil || selection == .cleanup { selection = .overview }
    }

    private func failScan(_ message: String, cancelled: Bool, flag: CancellationFlag) {
        // Ignore scans that were replaced by a newer one or already cancelled by the user.
        guard flag === activeScan else { return }
        activeScan = nil
        progress = nil
        phase = cancelled ? (report == nil ? .idle : .done) : .failed(message)
    }

    /// Re-runs the analysis after files were deleted, so totals and suggestions stay current.
    private func reanalyze() {
        guard let report else { return }
        isReanalyzing = true
        let output = ScanOutput(
            tree: report.tree,
            unreadableCount: report.unreadableCount,
            unreadablePaths: report.unreadablePaths,
            duration: report.duration,
            finishedAt: report.scannedAt
        )
        let analyzer = ScanAnalyzer(knowledge: knowledge, policy: policy, installedAppIDs: installedAppIDs)
        let model = self
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = analyzer.analyze(output)
            Task { @MainActor in model.applyReanalysis(updated) }
        }
    }

    private func applyReanalysis(_ updated: ScanReport) {
        isReanalyzing = false
        guard report?.tree === updated.tree else { return }
        report = updated
    }

    // MARK: - Explanations

    func path(of node: FileNode) -> String {
        report?.tree.path(of: node) ?? node.name
    }

    func explanation(for node: FileNode) -> Explanation {
        knowledge.explain(path: path(of: node), isDirectory: node.isDirectory)
    }

    func explanation(forPath path: String, isDirectory: Bool) -> Explanation {
        knowledge.explain(path: path, isDirectory: isDirectory)
    }

    func verdict(for node: FileNode) -> SafetyPolicy.Verdict {
        policy.check(path(of: node), kind: .item)
    }

    func target(for node: FileNode) -> CleanupTarget? {
        let path = path(of: node)
        guard policy.check(path, kind: .item).isAllowed else { return nil }
        let explanation = knowledge.explain(path: path, isDirectory: node.isDirectory)
        return CleanupTarget(path: path, kind: .item, title: node.name, size: node.size, safety: explanation.safety)
    }

    // MARK: - Navigation

    func open(_ node: FileNode) {
        guard node.isDirectory else { return }
        exploreFolder = node
        exploreSelection = nil
    }

    func goUp() {
        guard let folder = exploreFolder, let parent = folder.parent else { return }
        exploreFolder = parent
        exploreSelection = folder.id
    }

    /// Jumps to a path in the Explore view.
    func showInExplore(_ path: String) {
        guard let node = report?.tree.node(atPath: path) else {
            MacSystem.revealInFinder(path)
            return
        }
        exploreFolder = node.isDirectory ? node : node.parent
        exploreSelection = node.isDirectory ? nil : node.id
        selection = .explore
    }

    func showSuggestions(for category: StorageCategory?) {
        suggestionCategory = category
        focusedFindingID = nil
        selection = category == .developer ? .developer : .suggestions
    }

    func showFinding(_ id: String) {
        suggestionCategory = nil
        focusedFindingID = id
        selection = .suggestions
    }

    // MARK: - Cleanup list

    func isSelected(_ target: CleanupTarget) -> Bool {
        basket.isCovered(target)
    }

    func toggle(_ target: CleanupTarget) {
        if basket.contains(target) {
            basket.remove(target)
        } else if basket.isCovered(target) {
            // Something containing this is selected; deselecting means dropping that too.
            for other in basket.targets where other.covers(target) {
                basket.remove(other)
            }
        } else {
            basket.add(target)
        }
    }

    private func selectableTargets(_ finding: Finding) -> [CleanupTarget] {
        finding.wholeTargets.isEmpty ? finding.items.compactMap(\.target) : finding.wholeTargets
    }

    func checkState(for finding: Finding) -> CheckState {
        let targets = selectableTargets(finding)
        guard !targets.isEmpty else { return .unavailable }
        let covered = targets.filter { basket.isCovered($0) }.count
        if covered == targets.count { return .checked }
        let anyItemSelected = finding.items.contains { item in
            guard let target = item.target else { return false }
            return basket.isCovered(target)
        }
        if covered > 0 || anyItemSelected {
            return .mixed
        }
        return .unchecked
    }

    func toggle(_ finding: Finding) {
        let targets = selectableTargets(finding)
        if checkState(for: finding) == .checked {
            for target in targets { basket.removeCovered(by: target) }
            for item in finding.items {
                if let target = item.target { basket.remove(target) }
            }
        } else {
            for target in targets { basket.add(target) }
        }
    }

    func toggle(_ item: FoundItem, in finding: Finding) {
        guard let target = item.target else { return }
        if basket.contains(target) {
            basket.remove(target)
        } else if basket.isCovered(target) {
            // The whole folder is selected: switch to selecting every other item individually.
            for whole in finding.wholeTargets where whole.covers(target) {
                basket.remove(whole)
            }
            for other in finding.items where other.id != item.id {
                if let otherTarget = other.target, !basket.isCovered(otherTarget) {
                    basket.add(otherTarget)
                }
            }
        } else {
            basket.add(target)
        }
    }

    func remove(_ target: CleanupTarget) {
        basket.remove(target)
    }

    // MARK: - Deleting

    func performCleanup() {
        let targets = basket.targets
        guard !targets.isEmpty, !isCleaning, !isReanalyzing else { return }
        isCleaning = true
        cleanupDone = 0
        cleanupTotal = targets.count
        lastOutcome = nil

        let engine = CleanupEngine(policy: policy, remover: MacFileRemover())
        let mode = cleanupMode
        let model = self
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = engine.run(targets, mode: mode) { done, total, _ in
                Task { @MainActor in model.updateCleanupProgress(done: done, total: total) }
            }
            Task { @MainActor in model.finishCleanup(outcome) }
        }
    }

    private func updateCleanupProgress(done: Int, total: Int) {
        cleanupDone = done
        cleanupTotal = total
    }

    private func finishCleanup(_ outcome: CleanupOutcome) {
        isCleaning = false
        lastOutcome = outcome
        for target in outcome.completed {
            basket.remove(target)
        }
        applyRemovals(outcome)
        volume = VolumeCapacity.current()
    }

    /// Updates the scan results to reflect deleted items.
    private func applyRemovals(_ outcome: CleanupOutcome) {
        guard let tree = report?.tree else { return }
        for path in outcome.clearedFolders {
            if let node = tree.node(atPath: path) { tree.removeContents(of: node) }
        }
        for path in outcome.removedPaths {
            if let node = tree.node(atPath: path) { tree.remove(node) }
        }
        if let folder = exploreFolder, tree.ancestors(of: folder).first !== tree.root {
            exploreFolder = tree.root
            exploreSelection = nil
        }
        reanalyze()
    }

    func emptyTrash() {
        guard !isCleaning else { return }
        isCleaning = true
        cleanupDone = 0
        cleanupTotal = 1
        let trash = CleanupTarget(path: home + "/.Trash", kind: .contents, title: "Trash", size: 0, safety: .safe)
        let engine = CleanupEngine(policy: policy, remover: MacFileRemover())
        let model = self
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = engine.run([trash], mode: .deleteImmediately)
            Task { @MainActor in model.finishEmptyingTrash(outcome) }
        }
    }

    private func finishEmptyingTrash(_ outcome: CleanupOutcome) {
        if !outcome.failures.isEmpty, let error = MacSystem.emptyTrashWithFinder() {
            notice = Notice(title: "Couldn't empty the Trash", message: error)
        }
        isCleaning = false
        lastOutcome = nil
        applyRemovals(outcome)
        volume = VolumeCapacity.current()
        notice = notice ?? Notice(title: "Trash emptied", message: "Free space is now \(ByteFormatter.string(volume?.available ?? 0)).")
    }
}
