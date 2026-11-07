import AppKit
import Foundation

/// The small set of things Diskova is allowed to do to a file.
///
/// Note what is absent: there is no delete. Removal always goes through the
/// Trash via `FileManager.trashItem`, so every action Diskova takes is one the
/// person can undo from the Finder. A disk analyser that can destroy data
/// outright is not worth the gigabytes it saves.
@MainActor
enum FileActions {
    /// Shows the entry in the Finder, selected.
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens the entry with whatever app owns it.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Puts the full POSIX path on the clipboard.
    static func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    /// Outcome of trying to move one entry to the Trash.
    enum TrashOutcome: Sendable {
        case moved(URL)
        case failed(URL, reason: String)
    }

    /// Moves an entry to the Trash.
    ///
    /// Deliberately *not* `removeItem`. Everything stays recoverable, and the
    /// system handles the cases that are easy to get wrong by hand: locked
    /// files, items on other volumes, items the Finder has open.
    static func moveToTrash(_ url: URL) -> TrashOutcome {
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            return .moved(url)
        } catch {
            return .failed(url, reason: error.localizedDescription)
        }
    }

    /// Opens System Settings at Privacy & Security › Full Disk Access.
    ///
    /// Shown when a scan hit folders it was not allowed to read, which is the
    /// one problem a disk analyser cannot fix for itself.
    static func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Asks the person to pick a folder to scan.
    ///
    /// - Returns: the chosen folder, or `nil` if they cancelled.
    static func chooseFolder(startingAt startingFolder: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        // Otherwise an `.app` or a photo library cannot be chosen at all, and
        // those are often exactly what someone wants to look inside.
        panel.treatsFilePackagesAsDirectories = true
        panel.message = String(localized: "Choose a folder or volume to map.")
        panel.prompt = String(localized: "Scan")
        if let startingFolder {
            panel.directoryURL = startingFolder
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// A folder offered on the welcome screen as a one-click starting point.
struct ScanTarget: Identifiable, Hashable, Sendable {
    let url: URL
    let symbolName: String

    var id: URL { url }

    /// The name the Finder would show, in the system language — so "Downloads"
    /// appears as "İndirilenler" on a Turkish Mac without Diskova translating
    /// anything itself.
    var displayName: String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }
}

extension ScanTarget {
    /// The places worth offering up front, in the order people actually need
    /// them. Anything that does not exist on this Mac is left out.
    static var suggested: [ScanTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [ScanTarget] = [
            ScanTarget(url: home, symbolName: "house"),
            ScanTarget(url: home.appending(path: "Downloads"), symbolName: "arrow.down.circle"),
            ScanTarget(url: home.appending(path: "Desktop"), symbolName: "menubar.dock.rectangle"),
            ScanTarget(url: home.appending(path: "Documents"), symbolName: "doc"),
            ScanTarget(url: home.appending(path: "Library"), symbolName: "building.columns"),
            ScanTarget(url: URL(fileURLWithPath: "/Applications"), symbolName: "square.grid.2x2"),
            ScanTarget(url: URL(fileURLWithPath: "/"), symbolName: "internaldrive"),
        ]
        return candidates.filter { target in
            (try? target.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
