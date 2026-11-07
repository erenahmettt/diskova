import Foundation
import Testing

@testable import Diskova

@Suite("File tree")
struct FileNodeTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("A folder sums its children and sorts them largest first")
    func foldersAggregate() {
        let folder = FileNode.directory(url: url("/t"), children: [
            .file(url: url("/t/small.txt"), byteSize: 10, kind: .document),
            .file(url: url("/t/large.mov"), byteSize: 900, kind: .video),
            .file(url: url("/t/middle.png"), byteSize: 90, kind: .image),
        ], ownByteSize: 1)

        #expect(folder.byteSize == 1_001)
        #expect(folder.fileCount == 3)
        #expect(folder.directoryCount == 0)
        #expect(folder.children.map(\.name) == ["large.mov", "middle.png", "small.txt"])
    }

    @Test("Nested folders are counted at every level")
    func countsNestedFolders() {
        let tree = FileNode.directory(url: url("/t"), children: [
            FileNode.directory(url: url("/t/a"), children: [
                FileNode.directory(url: url("/t/a/b"), children: [
                    .file(url: url("/t/a/b/f"), byteSize: 5, kind: .other),
                ]),
            ]),
        ])

        #expect(tree.directoryCount == 2)
        #expect(tree.fileCount == 1)
        #expect(tree.byteSize == 5)
    }

    // MARK: - Containment

    @Test("Containment compares whole path components, not string prefixes")
    func containmentRespectsComponentBoundaries() {
        let folder = FileNode.directory(url: url("/Users/a"), children: [])

        #expect(folder.contains(url("/Users/a")))
        #expect(folder.contains(url("/Users/a/Documents")))
        // The bug this guards: "/Users/ab" starts with "/Users/a" as a string.
        #expect(folder.contains(url("/Users/ab")) == false)
        #expect(folder.contains(url("/Users")) == false)
    }

    @Test("Containment works at the root of a volume")
    func containmentAtVolumeRoot() {
        let root = FileNode.directory(url: url("/"), children: [])
        #expect(root.contains(url("/Applications")))
        #expect(root.contains(url("/")))
    }

    // MARK: - Queries

    @Test("The biggest files come back in order and folders are left out")
    func findsLargestFiles() {
        let tree = FileNode.directory(url: url("/t"), children: [
            FileNode.directory(url: url("/t/media"), children: [
                .file(url: url("/t/media/one.mov"), byteSize: 500, kind: .video),
                .file(url: url("/t/media/two.mov"), byteSize: 300, kind: .video),
            ]),
            .file(url: url("/t/three.zip"), byteSize: 400, kind: .archive),
            .file(url: url("/t/four.txt"), byteSize: 10, kind: .document),
        ])

        let largest = tree.largestFiles(limit: 3)
        #expect(largest.map(\.name) == ["one.mov", "three.zip", "two.mov"])
        #expect(largest.allSatisfy { !$0.isDirectory })
    }

    @Test("Asking for no files returns none")
    func largestFilesHonoursZeroLimit() {
        let tree = FileNode.directory(url: url("/t"), children: [
            .file(url: url("/t/a"), byteSize: 1, kind: .other),
        ])
        #expect(tree.largestFiles(limit: 0).isEmpty)
    }

    @Test("The limit is respected even when far more files exist")
    func largestFilesRespectsLimit() {
        let children = (0 ..< 500).map { index in
            FileNode.file(url: url("/t/f\(index)"), byteSize: Int64(index), kind: .other)
        }
        let tree = FileNode.directory(url: url("/t"), children: children)

        let largest = tree.largestFiles(limit: 10)
        #expect(largest.count == 10)
        #expect(largest.first?.byteSize == 499)
        #expect(largest.last?.byteSize == 490)
        #expect(largest.map(\.byteSize) == largest.map(\.byteSize).sorted(by: >))
    }

    @Test("Sizes group by kind")
    func groupsSizesByKind() {
        let tree = FileNode.directory(url: url("/t"), children: [
            .file(url: url("/t/a.mov"), byteSize: 100, kind: .video),
            .file(url: url("/t/b.mov"), byteSize: 50, kind: .video),
            .file(url: url("/t/c.png"), byteSize: 70, kind: .image),
        ])

        let totals = tree.sizeByKind()
        #expect(totals.first?.kind == .video)
        #expect(totals.first?.byteSize == 150)
        #expect(totals.count == 2)
    }

    @Test("The dominant kind follows the largest thing inside")
    func findsDominantKind() {
        let tree = FileNode.directory(url: url("/t"), children: [
            FileNode.directory(url: url("/t/inner"), children: [
                .file(url: url("/t/inner/huge.mov"), byteSize: 9_000, kind: .video),
            ]),
            .file(url: url("/t/small.txt"), byteSize: 1, kind: .document),
        ])

        #expect(tree.dominantKind == .video)
    }

    @Test("An empty folder reports its own kind")
    func dominantKindOfEmptyFolder() {
        let folder = FileNode.directory(url: url("/t/node_modules"), children: [])
        #expect(folder.dominantKind == .developer)
    }

    @Test("A path to a descendant lists every node along the way")
    func findsPathToDescendant() {
        let leaf = FileNode.file(url: url("/t/a/b/leaf"), byteSize: 1, kind: .other)
        let b = FileNode.directory(url: url("/t/a/b"), children: [leaf])
        let a = FileNode.directory(url: url("/t/a"), children: [b])
        let root = FileNode.directory(url: url("/t"), children: [a])

        let path = root.path(to: url("/t/a/b/leaf"))
        #expect(path?.map(\.name) == ["t", "a", "b", "leaf"])
        #expect(root.path(to: url("/t/nope")) == nil)
    }

    // MARK: - Removal

    @Test("Removing an entry corrects every ancestor's size")
    func removalUpdatesAncestorSizes() {
        let inner = FileNode.directory(url: url("/t/a"), children: [
            .file(url: url("/t/a/keep"), byteSize: 100, kind: .other),
            .file(url: url("/t/a/drop"), byteSize: 900, kind: .other),
        ])
        let root = FileNode.directory(url: url("/t"), children: [
            inner,
            .file(url: url("/t/other"), byteSize: 50, kind: .other),
        ])
        #expect(root.byteSize == 1_050)

        let updated = root.removingDescendant(at: url("/t/a/drop"))
        #expect(updated.byteSize == 150)
        #expect(updated.fileCount == 2)
        #expect(updated.path(to: url("/t/a/drop")) == nil)
        #expect(updated.path(to: url("/t/a/keep")) != nil)
    }

    @Test("Removal rebuilds only the path it touches and shares the rest")
    func removalSharesUntouchedSubtrees() {
        let untouched = FileNode.directory(url: url("/t/untouched"), children: [
            .file(url: url("/t/untouched/f"), byteSize: 10, kind: .other),
        ])
        let target = FileNode.directory(url: url("/t/target"), children: [
            .file(url: url("/t/target/drop"), byteSize: 10, kind: .other),
            .file(url: url("/t/target/keep"), byteSize: 10, kind: .other),
        ])
        let root = FileNode.directory(url: url("/t"), children: [untouched, target])

        let updated = root.removingDescendant(at: url("/t/target/drop"))
        let rebuiltUntouched = updated.children.first { $0.name == "untouched" }

        // Identity, not equality: the subtree must be the same object, which is
        // what makes removal cheap on a tree with millions of nodes.
        #expect(rebuiltUntouched === untouched)
    }

    @Test("Removing something that is not there changes nothing")
    func removalOfMissingEntryIsANoOp() {
        let root = FileNode.directory(url: url("/t"), children: [
            .file(url: url("/t/a"), byteSize: 1, kind: .other),
        ])
        #expect(root.removingDescendant(at: url("/t/nope")) === root)
        #expect(root.removingDescendant(at: url("/elsewhere/a")) === root)
    }

    @Test("Removing a whole folder removes everything under it")
    func removalOfFolderDropsSubtree() {
        let root = FileNode.directory(url: url("/t"), children: [
            FileNode.directory(url: url("/t/a"), children: [
                .file(url: url("/t/a/x"), byteSize: 500, kind: .other),
            ]),
            .file(url: url("/t/b"), byteSize: 5, kind: .other),
        ])

        let updated = root.removingDescendant(at: url("/t/a"))
        #expect(updated.byteSize == 5)
        #expect(updated.fileCount == 1)
        #expect(updated.directoryCount == 0)
    }

    @Test("Shares of the whole are computed safely")
    func fractionHandlesZeroTotal() {
        let node = FileNode.file(url: url("/t/a"), byteSize: 10, kind: .other)
        #expect(node.fraction(of: 100) == 0.1)
        #expect(node.fraction(of: 0) == 0)
    }
}
