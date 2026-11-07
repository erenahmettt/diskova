import Foundation

/// One entry — file or folder — in a scanned tree.
///
/// `FileNode` is deliberately immutable. Every stored property is a `let`, and
/// the tree is built bottom-up by ``DiskScanner``: a folder's children exist
/// before the folder itself does. That is what makes a whole finished tree
/// `Sendable`, so the scanner can hand it to the main actor without copying it
/// or locking anything.
///
/// There is no `parent` pointer, for the same reason — a parent cannot exist
/// before its children. Walking back up is the view's job instead:
/// ``ScanStore`` keeps the breadcrumb trail of nodes it descended through.
///
/// Because the tree is immutable, "deleting" is expressed as
/// ``removingDescendant(at:)``, which rebuilds only the folders along one path
/// and shares every other subtree with the original. That is what lets the
/// treemap update the instant something is moved to the Trash, instead of
/// making the person sit through another scan.
final class FileNode: Identifiable, Sendable {
    /// Where the entry lives on disk. Doubles as the stable identity of the
    /// node, since two entries in one tree can never share a path.
    let url: URL

    /// Display name, i.e. the last path component.
    let name: String

    /// Space this entry occupies **on disk**, in bytes, including everything
    /// below it. This is allocated size rather than logical size, so it accounts
    /// for block rounding, compression and resource forks — it is the number
    /// that actually changes when you delete the entry.
    let byteSize: Int64

    /// Space attributable to this entry alone, excluding anything below it.
    /// For a file that is its whole size; for a folder it is just the directory
    /// entry, which is small but adds up across hundreds of thousands of them.
    let ownByteSize: Int64

    /// What kind of thing this is, used for colouring and filtering.
    let kind: FileKind

    /// `true` for folders. Bundles reported as a single item (see
    /// ``isPackage``) are *not* directories as far as the rest of the app is
    /// concerned, even though they are folders on disk.
    let isDirectory: Bool

    /// `true` when this is a bundle — an app, a `.photoslibrary`, a Pages
    /// document — that was collapsed into one item because browsing its insides
    /// is almost never what someone wants.
    let isPackage: Bool

    /// Children, already sorted largest first. Empty for files and packages.
    let children: [FileNode]

    /// Number of files anywhere below this node. A file counts as 1.
    let fileCount: Int

    /// Number of folders anywhere below this node, not counting itself.
    let directoryCount: Int

    init(
        url: URL,
        name: String,
        byteSize: Int64,
        ownByteSize: Int64,
        kind: FileKind,
        isDirectory: Bool,
        isPackage: Bool,
        children: [FileNode],
        fileCount: Int,
        directoryCount: Int
    ) {
        self.url = url
        self.name = name
        self.byteSize = byteSize
        self.ownByteSize = ownByteSize
        self.kind = kind
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.children = children
        self.fileCount = fileCount
        self.directoryCount = directoryCount
    }

    /// Builds a leaf node for a file, or for a bundle treated as one.
    static func file(
        url: URL,
        byteSize: Int64,
        kind: FileKind,
        isPackage: Bool = false
    ) -> FileNode {
        FileNode(
            url: url,
            name: url.lastPathComponent,
            byteSize: byteSize,
            ownByteSize: byteSize,
            kind: kind,
            isDirectory: false,
            isPackage: isPackage,
            children: [],
            fileCount: 1,
            directoryCount: 0
        )
    }

    /// Builds a folder node from children that have already been scanned,
    /// summing their sizes and counts and sorting them largest first.
    static func directory(
        url: URL,
        children: [FileNode],
        ownByteSize: Int64 = 0
    ) -> FileNode {
        var total = ownByteSize
        var files = 0
        var directories = 0
        for child in children {
            total += child.byteSize
            files += child.fileCount
            directories += child.directoryCount + (child.isDirectory ? 1 : 0)
        }
        return FileNode(
            url: url,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            byteSize: total,
            ownByteSize: ownByteSize,
            kind: FileKind.forDirectory(named: url.lastPathComponent),
            isDirectory: true,
            isPackage: false,
            children: children.sorted { $0.byteSize > $1.byteSize },
            fileCount: files,
            directoryCount: directories
        )
    }

    var id: URL { url }

    /// `true` when there is nothing to drill into.
    var isLeaf: Bool { children.isEmpty }

    /// This node's share of `total`, as a fraction between 0 and 1.
    func fraction(of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return Double(byteSize) / Double(total)
    }

    /// Whether `other` is this node or lives inside it.
    ///
    /// Compares whole path components, not raw string prefixes: `/Users/ab` is
    /// not inside `/Users/a`, however much it looks like it.
    func contains(_ other: URL) -> Bool {
        if other == url { return true }
        let base = url.path
        let candidate = other.path
        guard candidate.count > base.count else { return false }
        let boundary = base.hasSuffix("/") ? base : base + "/"
        return candidate.hasPrefix(boundary)
    }

    /// The largest individual files anywhere below this node, biggest first.
    ///
    /// Folders are skipped — the point is to surface the single files worth
    /// deleting, not the folders that contain them. Packages count as files,
    /// because that is how they are presented everywhere else.
    func largestFiles(limit: Int = 100) -> [FileNode] {
        guard limit > 0 else { return [] }

        // A sorted buffer of at most `limit` entries, rather than collecting
        // every file and sorting at the end: a full startup volume is millions
        // of files, and all but a hundred of them are irrelevant.
        var best: [FileNode] = []

        func visit(_ node: FileNode) {
            if node.isDirectory {
                for child in node.children { visit(child) }
                return
            }
            if best.count < limit {
                let index = best.firstIndex { $0.byteSize < node.byteSize } ?? best.count
                best.insert(node, at: index)
            } else if let smallest = best.last, node.byteSize > smallest.byteSize {
                best.removeLast()
                let index = best.firstIndex { $0.byteSize < node.byteSize } ?? best.count
                best.insert(node, at: index)
            }
        }

        visit(self)
        return best
    }

    /// The category of the single biggest thing inside this node.
    ///
    /// Used to colour a folder that is shown as a solid block because it is too
    /// small to open up: a closed folder full of video should look like video,
    /// not like a generic grey folder.
    ///
    /// Follows the largest child down rather than totalling every category,
    /// which makes it proportional to the depth of the tree instead of its
    /// size — it is called once per visible tile, so that difference matters.
    var dominantKind: FileKind {
        guard isDirectory, let largest = children.first else { return kind }
        return largest.dominantKind
    }

    /// Total bytes below this node grouped by kind, largest group first.
    func sizeByKind() -> [(kind: FileKind, byteSize: Int64)] {
        var totals: [FileKind: Int64] = [:]

        func visit(_ node: FileNode) {
            if node.isDirectory {
                for child in node.children { visit(child) }
            } else {
                totals[node.kind, default: 0] += node.byteSize
            }
        }

        visit(self)
        return totals
            .map { (kind: $0.key, byteSize: $0.value) }
            .sorted { $0.byteSize > $1.byteSize }
    }

    /// The chain of nodes from this one down to `target`, inclusive, or `nil`
    /// when `target` is not in this subtree.
    ///
    /// Used to restore the breadcrumb trail after a rescan, so refreshing does
    /// not throw you back to the root of the disk.
    func path(to target: URL) -> [FileNode]? {
        if url == target { return [self] }
        guard contains(target) else { return nil }
        for child in children {
            if let tail = child.path(to: target) { return [self] + tail }
        }
        return nil
    }

    /// A copy of this subtree with the entry at `target` removed and every
    /// ancestor's size corrected.
    ///
    /// Only the folders between here and `target` are rebuilt; every other
    /// subtree is shared with the original, so this is proportional to the
    /// depth of the deleted item and the number of its siblings — not to the
    /// size of the tree. Returns `self` unchanged when `target` is not present.
    func removingDescendant(at target: URL) -> FileNode {
        guard isDirectory, !children.isEmpty, contains(target), target != url else { return self }

        var rebuilt: [FileNode] = []
        rebuilt.reserveCapacity(children.count)
        var didChange = false

        for child in children {
            if child.url == target {
                didChange = true
                continue
            }
            guard child.contains(target) else {
                rebuilt.append(child)
                continue
            }
            let updated = child.removingDescendant(at: target)
            if updated !== child { didChange = true }
            rebuilt.append(updated)
        }

        guard didChange else { return self }
        return FileNode.directory(url: url, children: rebuilt, ownByteSize: ownByteSize)
    }
}

extension FileNode: Equatable, Hashable {
    /// Identity comparison. Two nodes are the same node, not merely equal
    /// descriptions of one — the tree is immutable, so this is always the
    /// question being asked.
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
