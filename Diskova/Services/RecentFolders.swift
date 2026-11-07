import Foundation

/// Remembers the last few folders that were scanned.
///
/// Paths rather than security-scoped bookmarks, because Diskova is not
/// sandboxed and therefore needs no bookmark to re-open a folder. Entries that
/// have since been deleted or unmounted are filtered out on read instead of
/// being pruned eagerly, so an external drive that is merely unplugged comes
/// back by itself next time it is connected.
/// `UserDefaults` is documented as thread-safe but is not marked `Sendable`,
/// so the conformance is unchecked rather than unsound.
struct RecentFolders: @unchecked Sendable {
    private static let storageKey = "recentScanFolders"
    private static let limit = 8

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Most recently scanned first, excluding anything no longer reachable.
    var folders: [URL] {
        let paths = defaults.stringArray(forKey: Self.storageKey) ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
    }

    /// Moves `url` to the front of the list, dropping the oldest entries past
    /// the limit.
    func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = defaults.stringArray(forKey: Self.storageKey) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        defaults.set(Array(paths.prefix(Self.limit)), forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
