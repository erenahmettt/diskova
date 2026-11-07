import Foundation
import Observation

/// All of the app's state, and the only place it changes.
///
/// There is exactly one of these per window. The scan runs off the main actor
/// inside ``DiskScanner``; this type lives *on* the main actor and is the single
/// point where its results land, which is why nothing else in the app needs to
/// think about concurrency at all.
@MainActor
@Observable
final class ScanStore {
    /// What the window is currently showing.
    enum Phase {
        /// Nothing scanned yet — the welcome screen.
        case idle
        /// A scan is running, with its latest tally.
        case scanning(ScanProgress)
        /// A scan finished and its tree is being browsed.
        case results(ScanOutcome)
        /// A scan could not start.
        case failed(ScanFailure)
    }

    private(set) var phase: Phase = .idle

    /// Options applied to the *next* scan. Changing them does not disturb the
    /// results already on screen; the toolbar offers a rescan instead, because
    /// silently throwing away a two-minute scan would be rude.
    var options: ScanOptions = .default

    /// The chain of folders from the scan root down to what is on screen.
    /// Always starts at the root and is never empty while results are shown.
    private(set) var trail: [FileNode] = []

    /// The entry the inspector is describing.
    var selection: FileNode?

    /// The entry under the pointer, shown in the status bar.
    var hovered: FileNode?

    private(set) var recentFolders: [URL] = []

    /// Set when a move to the Trash fails, cleared on the next successful one.
    var trashFailureReason: String?

    /// The entry a confirmation dialog is currently asking about.
    ///
    /// The request lives here rather than in the context menu that raised it: a
    /// dialog presented from inside a menu disappears with the menu, so the
    /// window has to own it.
    var pendingTrashTarget: FileNode?

    private var scanTask: Task<Void, Never>?
    private var scannedURL: URL?
    private let recents = RecentFolders()

    /// Reloads the recent-folder list from disk.
    ///
    /// Called when the welcome screen appears rather than in an initialiser, so
    /// that creating a store never touches the filesystem.
    func refreshRecentFolders() {
        recentFolders = recents.folders
    }

    // MARK: - Derived state

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var outcome: ScanOutcome? {
        if case .results(let outcome) = phase { return outcome }
        return nil
    }

    var root: FileNode? { outcome?.root }

    /// The folder whose contents fill the treemap right now.
    var currentFolder: FileNode? { trail.last }

    /// Total size of the scan, used as the denominator for every percentage so
    /// that "3%" means 3% of the whole scan rather than 3% of whatever folder
    /// happens to be open.
    var totalByteSize: Int64 { root?.byteSize ?? 0 }

    var canGoUp: Bool { trail.count > 1 }

    // MARK: - Scanning

    /// Starts a scan, replacing anything already on screen.
    func scan(_ url: URL) {
        let target = url.standardizedFileURL
        scanTask?.cancel()

        selection = nil
        hovered = nil
        trail = []
        trashFailureReason = nil
        scannedURL = target
        phase = .scanning(ScanProgress())

        recents.remember(target)
        recentFolders = recents.folders

        let options = options
        scanTask = Task { [weak self] in
            // `Task` here inherits the main actor, so every assignment below is
            // already on the right actor — no hopping, no locks.
            for await event in DiskScanner.scan(target, options: options) {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    // Ignore stragglers that arrive after a scan was replaced.
                    if case .scanning = self.phase {
                        self.phase = .scanning(progress)
                    }
                case .completed(let outcome):
                    self.phase = .results(outcome)
                    self.trail = [outcome.root]
                case .failed(let failure):
                    self.phase = .failed(failure)
                }
            }
        }
    }

    /// Scans the same folder again, keeping the place in the tree if it still
    /// exists afterwards.
    func rescan() {
        guard let scannedURL else { return }
        let previousFolder = currentFolder?.url
        scan(scannedURL)

        guard let previousFolder else { return }
        Task { [weak self] in
            // Wait for the scan this call just started, then restore the trail.
            while let self, self.isScanning {
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard let self, let root = self.root else { return }
            if let restored = root.path(to: previousFolder) {
                self.trail = restored
            }
        }
    }

    /// Stops a running scan and returns to the welcome screen.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        trail = []
        selection = nil
        hovered = nil
    }

    // MARK: - Navigation

    /// Opens a folder, if there is anything inside it to see.
    func descend(into node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        trail.append(node)
        selection = nil
        hovered = nil
    }

    /// Goes back to a folder in the breadcrumb trail.
    func ascend(to node: FileNode) {
        guard let index = trail.firstIndex(of: node) else { return }
        trail = Array(trail.prefix(through: index))
        selection = nil
        hovered = nil
    }

    /// Goes up one level.
    func goUp() {
        guard canGoUp else { return }
        trail.removeLast()
        selection = nil
        hovered = nil
    }

    /// Opens whatever is selected, if it is a folder.
    func descendIntoSelection() {
        guard let selection, selection.isDirectory, !selection.children.isEmpty else { return }
        descend(into: selection)
    }

    // MARK: - Acting on files

    /// Asks for confirmation before trashing an entry.
    func requestTrash(_ node: FileNode) {
        pendingTrashTarget = node
    }

    /// Trashes whatever ``pendingTrashTarget`` is set to.
    func confirmPendingTrash() {
        guard let target = pendingTrashTarget else { return }
        pendingTrashTarget = nil
        moveToTrash(target)
    }

    /// Moves an entry to the Trash and updates the tree in place.
    ///
    /// No rescan: ``FileNode/removingDescendant(at:)`` rebuilds only the
    /// folders along one path, so sizes and percentages everywhere above the
    /// deleted item correct themselves immediately. On a disk that took two
    /// minutes to scan, that difference is the whole experience.
    func moveToTrash(_ node: FileNode) {
        guard case .results(let outcome) = phase else { return }

        switch FileActions.moveToTrash(node.url) {
        case .failed(_, let reason):
            trashFailureReason = reason

        case .moved(let removedURL):
            trashFailureReason = nil
            let updatedRoot = outcome.root.removingDescendant(at: removedURL)
            phase = .results(
                ScanOutcome(
                    root: updatedRoot,
                    unreadablePaths: outcome.unreadablePaths,
                    elapsed: outcome.elapsed,
                    options: outcome.options
                )
            )
            restoreTrailAndSelection(in: updatedRoot, afterRemoving: removedURL)
        }
    }

    /// Re-anchors the breadcrumb trail and the selection onto a rebuilt tree.
    ///
    /// Node objects are immutable, so the rebuilt tree contains *different*
    /// objects for every folder along the changed path. Holding on to the old
    /// ones would show stale sizes, so both are looked up again by path.
    private func restoreTrailAndSelection(in updatedRoot: FileNode, afterRemoving removedURL: URL) {
        let currentURL = currentFolder?.url
        if let currentURL,
           currentURL != removedURL,
           let restored = updatedRoot.path(to: currentURL) {
            trail = restored
        } else {
            // The folder being browsed was itself deleted: fall back to the
            // root rather than showing a tree that no longer exists.
            trail = [updatedRoot]
        }

        if let selectedURL = selection?.url, selectedURL != removedURL {
            selection = updatedRoot.path(to: selectedURL)?.last
        } else {
            selection = nil
        }
        hovered = nil
    }
}
