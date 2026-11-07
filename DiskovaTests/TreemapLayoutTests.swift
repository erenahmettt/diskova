import Foundation
import CoreGraphics
import Testing

@testable import Diskova

/// The layout is a pure function over numbers, so it can be held to the
/// properties a treemap must have rather than to a screenshot: the rectangles
/// must fill the space exactly, never overlap, never escape, and have areas in
/// proportion to the sizes they stand for.
@Suite("Treemap layout")
struct TreemapLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)

    // MARK: - The squarify primitive

    @Test("Rectangles fill the bounds exactly")
    func coversTheWholeArea() {
        let weights: [Double] = [50, 30, 12, 5, 2, 1]
        let rects = TreemapLayout.squarify(weights: weights, in: bounds)

        let covered = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        let expected = Double(bounds.width * bounds.height)
        #expect(abs(covered - expected) < expected * 0.001)
    }

    @Test("No rectangle escapes the bounds")
    func staysInsideBounds() {
        let rects = TreemapLayout.squarify(weights: [40, 25, 20, 10, 5], in: bounds)
        for rect in rects {
            #expect(rect.minX >= bounds.minX - 0.01)
            #expect(rect.minY >= bounds.minY - 0.01)
            #expect(rect.maxX <= bounds.maxX + 0.01)
            #expect(rect.maxY <= bounds.maxY + 0.01)
        }
    }

    @Test("No two rectangles overlap")
    func rectanglesDoNotOverlap() {
        let rects = TreemapLayout.squarify(weights: [38, 22, 17, 11, 7, 3, 2], in: bounds)
        for (index, first) in rects.enumerated() {
            for second in rects[(index + 1)...] {
                let overlap = first.insetBy(dx: 0.01, dy: 0.01).intersection(second.insetBy(dx: 0.01, dy: 0.01))
                #expect(overlap.isNull || overlap.width <= 0 || overlap.height <= 0)
            }
        }
    }

    @Test("Area is proportional to weight")
    func areaTracksWeight() {
        let weights: [Double] = [60, 30, 10]
        let rects = TreemapLayout.squarify(weights: weights, in: bounds)
        let totalArea = Double(bounds.width * bounds.height)

        for (weight, rect) in zip(weights, rects) {
            let share = Double(rect.width * rect.height) / totalArea
            #expect(abs(share - weight / 100) < 0.005)
        }
    }

    @Test("Tiles stay close to square, which is the whole point")
    func aspectRatiosAreReasonable() {
        // Slice-and-dice on this input produces slivers thinner than 1:20.
        let weights: [Double] = [30, 25, 20, 10, 8, 4, 3]
        let rects = TreemapLayout.squarify(weights: weights, in: bounds)

        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 5)
    }

    @Test("Order of the input is preserved in the output")
    func preservesOrder() {
        let weights: [Double] = [10, 20, 30]
        let rects = TreemapLayout.squarify(weights: weights, in: bounds)
        #expect(rects.count == weights.count)
        // Biggest weight must have the biggest area even though it is last.
        let areas = rects.map { Double($0.width * $0.height) }
        #expect(areas[2] > areas[1])
        #expect(areas[1] > areas[0])
    }

    // MARK: - Degenerate input

    @Test("Empty input produces no rectangles")
    func handlesEmptyInput() {
        #expect(TreemapLayout.squarify(weights: [], in: bounds).isEmpty)
    }

    @Test("A zero-size canvas produces empty rectangles rather than nonsense")
    func handlesZeroBounds() {
        let rects = TreemapLayout.squarify(weights: [1, 2], in: .zero)
        #expect(rects.count == 2)
        #expect(rects.allSatisfy { $0 == .zero })
    }

    @Test("Non-positive weights get an empty rectangle and do not shift the rest")
    func skipsNonPositiveWeights() {
        let rects = TreemapLayout.squarify(weights: [50, 0, 50], in: bounds)
        #expect(rects.count == 3)
        #expect(rects[1] == .zero)

        let covered = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(covered - Double(bounds.width * bounds.height)) < 100)
    }

    @Test("A single item fills everything")
    func singleItemFillsBounds() {
        let rects = TreemapLayout.squarify(weights: [7], in: bounds)
        #expect(rects.count == 1)
        #expect(abs(rects[0].width - bounds.width) < 0.01)
        #expect(abs(rects[0].height - bounds.height) < 0.01)
    }

    // MARK: - Laying out a real tree

    @Test("Folders big enough to open are nested and marked")
    func nestsLargeFolders() {
        let tree = FileNode.directory(url: URL(fileURLWithPath: "/tmp/root"), children: [
            FileNode.directory(url: URL(fileURLWithPath: "/tmp/root/big"), children: [
                .file(url: URL(fileURLWithPath: "/tmp/root/big/a.mov"), byteSize: 700, kind: .video),
                .file(url: URL(fileURLWithPath: "/tmp/root/big/b.mov"), byteSize: 200, kind: .video),
            ]),
            .file(url: URL(fileURLWithPath: "/tmp/root/c.txt"), byteSize: 100, kind: .document),
        ])

        let tiles = TreemapLayout.tiles(for: tree, in: bounds)
        let folderTile = try? #require(tiles.first { $0.node.name == "big" })

        #expect(folderTile?.isOpened == true)
        #expect(folderTile?.hasHeader == true)
        // Its two children are laid out as well, one level deeper.
        #expect(tiles.contains { $0.node.name == "a.mov" && $0.depth == 1 })
        #expect(tiles.contains { $0.node.name == "b.mov" && $0.depth == 1 })
    }

    @Test("A folder too small to open is drawn as a solid block")
    func doesNotNestTinyFolders() {
        var children: [FileNode] = [
            FileNode.directory(url: URL(fileURLWithPath: "/tmp/root/tiny"), children: [
                .file(url: URL(fileURLWithPath: "/tmp/root/tiny/x"), byteSize: 1, kind: .other),
            ]),
        ]
        // Swamp it so its tile ends up only a few points across.
        for index in 0 ..< 12 {
            children.append(.file(
                url: URL(fileURLWithPath: "/tmp/root/big\(index)"),
                byteSize: 100_000,
                kind: .video
            ))
        }
        let tree = FileNode.directory(url: URL(fileURLWithPath: "/tmp/root"), children: children)

        let tiles = TreemapLayout.tiles(for: tree, in: CGRect(x: 0, y: 0, width: 300, height: 200))
        if let tiny = tiles.first(where: { $0.node.name == "tiny" }) {
            #expect(tiny.isOpened == false)
        }
        #expect(tiles.contains { $0.node.name == "tiny/x" } == false)
    }

    @Test("Nesting stops at the configured depth")
    func respectsMaximumDepth() {
        var node = FileNode.file(url: URL(fileURLWithPath: "/tmp/deep/leaf"), byteSize: 1_000, kind: .other)
        for level in (0 ..< 10).reversed() {
            node = FileNode.directory(url: URL(fileURLWithPath: "/tmp/deep/\(level)"), children: [node])
        }

        var configuration = TreemapLayout.Configuration.default
        configuration.maximumDepth = 3
        let tiles = TreemapLayout.tiles(for: node, in: bounds, configuration: configuration)

        #expect(tiles.allSatisfy { $0.depth < 3 })
        #expect(tiles.isEmpty == false)
    }

    @Test("Hit testing picks the deepest tile under the point")
    func hitTestPrefersDeepestTile() {
        let tree = FileNode.directory(url: URL(fileURLWithPath: "/tmp/root"), children: [
            FileNode.directory(url: URL(fileURLWithPath: "/tmp/root/outer"), children: [
                .file(url: URL(fileURLWithPath: "/tmp/root/outer/inner.bin"), byteSize: 1_000, kind: .code),
            ]),
        ])
        let tiles = TreemapLayout.tiles(for: tree, in: bounds)
        let inner = try? #require(tiles.first { $0.node.name == "inner.bin" })
        let point = CGPoint(x: inner?.rect.midX ?? 0, y: inner?.rect.midY ?? 0)

        #expect(tiles.tile(at: point)?.node.name == "inner.bin")
    }

    @Test("Hit testing outside every tile finds nothing")
    func hitTestMissesEmptySpace() {
        let tree = FileNode.directory(url: URL(fileURLWithPath: "/tmp/root"), children: [
            .file(url: URL(fileURLWithPath: "/tmp/root/a"), byteSize: 10, kind: .other),
        ])
        let tiles = TreemapLayout.tiles(for: tree, in: bounds)
        #expect(tiles.tile(at: CGPoint(x: -5, y: -5)) == nil)
    }
}
