import Foundation

/// How a scan should behave. All defaults are the ones that give the most
/// honest answer to "what is taking up my space?".
struct ScanOptions: Sendable, Equatable, Codable {
    /// Include dotfiles and hidden folders. On by default: hidden caches are
    /// often exactly what is eating the disk, so hiding them would defeat the
    /// purpose.
    var includeHiddenEntries: Bool = true

    /// Show bundles — `.app`, `.photoslibrary`, `.pages` — as one item instead
    /// of letting you walk around inside them. On by default, because "Xcode is
    /// 12 GB" is the useful fact, not the 40,000 files inside it.
    var treatBundlesAsSingleItems: Bool = true

    /// Follow mount points into other disks. Off by default: scanning your
    /// startup disk should not wander onto an external drive or a network share
    /// and quietly take ten minutes.
    var crossVolumeBoundaries: Bool = false

    /// Count a file with several hard links only the first time it is seen.
    /// On by default, otherwise totals come out larger than the disk itself —
    /// a common and confusing failure of simpler tools.
    var countHardLinkedFilesOnce: Bool = true

    static let `default` = ScanOptions()
}

/// A running tally, emitted while a scan is in flight.
struct ScanProgress: Sendable, Equatable {
    var fileCount: Int = 0
    var directoryCount: Int = 0
    var byteSize: Int64 = 0
    /// The folder being read right now, so the UI can show movement.
    var currentPath: String = ""
}

/// What a finished scan produced.
struct ScanOutcome: Sendable {
    let root: FileNode
    /// Folders that could not be read, almost always because macOS privacy
    /// protection blocked them. Surfaced so the app can explain itself instead
    /// of silently under-reporting.
    let unreadablePaths: [URL]
    let elapsed: TimeInterval
    let options: ScanOptions
}

/// Why a scan could not start.
enum ScanFailure: Error, Sendable, Equatable {
    case notAFolder(URL)
    case unreadable(URL)

    var message: LocalizedStringResource {
        switch self {
        case .notAFolder:
            "That is not a folder, so there is nothing to map."
        case .unreadable:
            "That folder could not be opened. Granting Diskova Full Disk Access usually fixes it."
        }
    }
}

/// Everything a scan reports back, in order: progress updates, then exactly one
/// terminal event.
enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case completed(ScanOutcome)
    case failed(ScanFailure)
}

/// A file's identity on disk: which volume, and which inode on it.
///
/// Two paths with the same identity are the same bytes reached through
/// different names — a hard link. macOS uses hard links heavily inside system
/// locations and Time Machine snapshots, so without this, totals can exceed the
/// capacity of the drive being measured.
struct FileIdentity: Hashable, Sendable {
    let device: dev_t
    let inode: ino_t

    init?(url: URL) {
        var info = stat()
        let succeeded = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else { return false }
            return lstat(pointer, &info) == 0
        }
        guard succeeded else { return nil }
        self.device = info.st_dev
        self.inode = info.st_ino
    }
}
