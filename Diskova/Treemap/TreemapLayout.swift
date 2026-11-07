import CoreGraphics

/// One rectangle in a laid-out treemap.
struct TreemapTile: Sendable {
    /// The entry this rectangle stands for.
    let node: FileNode
    /// Where to draw it, already inset for the gap between neighbours.
    let rect: CGRect
    /// How many folders down from the view's root this tile sits. 0 is a direct
    /// child of whatever is currently being shown.
    let depth: Int
    /// `true` when this folder's contents are drawn inside it. Such a tile is
    /// painted as a translucent container rather than a solid block, because
    /// its children will cover most of it.
    let isOpened: Bool
    /// `true` when the tile is large enough that a strip was reserved along its
    /// top for the folder's name.
    let hasHeader: Bool
}

/// Turns a folder's contents into rectangles whose areas are proportional to
/// their sizes.
///
/// ## Why squarified
///
/// The naive treemap — slice the rectangle, then slice each slice the other way
/// — produces long thin slivers. Slivers are unusable: you cannot compare their
/// areas by eye, you cannot read a label in them, and you cannot reliably click
/// one. The squarified algorithm (Bruls, Huizing and van Wijk, 2000) instead
/// greedily packs items into rows, extending a row only while doing so keeps
/// the worst aspect ratio in that row from getting worse. The result is tiles
/// that are close to square, which is what makes a treemap readable at all.
///
/// The trade-off is that squarified layouts are not stable under small changes
/// to the data and do not preserve ordering. Neither matters here: a disk scan
/// is a snapshot, and size order is already conveyed by area.
///
/// ## Nesting
///
/// Folders are not just coloured blocks — their contents are drawn inside them,
/// recursively, which is what lets you see that a 40 GB folder is one enormous
/// file rather than a million small ones. Nesting stops when a tile gets too
/// small to show anything meaningful, so the cost stays proportional to the
/// pixels on screen rather than to the number of files on the disk.
enum TreemapLayout {
    struct Configuration: Sendable {
        /// Space left between neighbouring tiles, in points.
        var gap: CGFloat = 1
        /// How far inside a folder tile its children are drawn, leaving a
        /// visible border that reads as "these belong to that".
        var nestedInset: CGFloat = 3
        /// A folder smaller than this on either edge is drawn as a solid block
        /// instead of being opened up.
        var minimumNestedEdge: CGFloat = 26
        /// Height of the strip reserved along the top of an opened folder for
        /// its name.
        var headerHeight: CGFloat = 16
        /// An opened folder only gets a name strip once it is at least this
        /// big; below it, the strip would eat most of the tile.
        var minimumHeaderSize = CGSize(width: 108, height: 52)
        /// Tiles thinner than this on either edge are dropped. They would be
        /// invisible and unclickable, and laying out their children would be
        /// wasted work.
        var minimumTileEdge: CGFloat = 2
        /// Hard cap on nesting, so one absurdly deep tree cannot make layout
        /// cost unbounded.
        var maximumDepth: Int = 6

        static let `default` = Configuration()
    }

    /// Lays out the children of `node` inside `bounds`.
    ///
    /// - Returns: tiles in drawing order — a folder always comes before the
    ///   children drawn on top of it. For hit testing, search from the end:
    ///   see ``Swift/Array/tile(at:)``.
    static func tiles(
        for node: FileNode,
        in bounds: CGRect,
        configuration: Configuration = .default
    ) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        appendTiles(
            for: node,
            in: bounds,
            depth: 0,
            configuration: configuration,
            into: &tiles
        )
        return tiles
    }

    private static func appendTiles(
        for parent: FileNode,
        in bounds: CGRect,
        depth: Int,
        configuration: Configuration,
        into tiles: inout [TreemapTile]
    ) {
        guard depth < configuration.maximumDepth,
              bounds.width > 0,
              bounds.height > 0
        else { return }

        // Zero-byte entries get no area, which would make their aspect ratio
        // infinite and poison the row heuristic. They are empty files, empty
        // folders, or the second name of a hard-linked file that has already
        // been charged elsewhere — nothing worth a rectangle.
        let children = parent.children.filter { $0.byteSize > 0 }
        guard !children.isEmpty else { return }

        let rects = squarify(
            weights: children.map { Double($0.byteSize) },
            in: bounds
        )

        for (child, rect) in zip(children, rects) {
            let inset = rect.insetBy(dx: configuration.gap / 2, dy: configuration.gap / 2)
            guard inset.width >= configuration.minimumTileEdge,
                  inset.height >= configuration.minimumTileEdge
            else { continue }

            let canNest = child.isDirectory
                && !child.children.isEmpty
                && depth + 1 < configuration.maximumDepth
                && inset.width >= configuration.minimumNestedEdge
                && inset.height >= configuration.minimumNestedEdge

            let hasHeader = canNest
                && inset.width >= configuration.minimumHeaderSize.width
                && inset.height >= configuration.minimumHeaderSize.height

            tiles.append(TreemapTile(
                node: child,
                rect: inset,
                depth: depth,
                isOpened: canNest,
                hasHeader: hasHeader
            ))

            guard canNest else { continue }

            let interior: CGRect = hasHeader
                ? CGRect(
                    x: inset.minX + configuration.nestedInset,
                    y: inset.minY + configuration.headerHeight,
                    width: inset.width - configuration.nestedInset * 2,
                    height: inset.height - configuration.headerHeight - configuration.nestedInset
                  )
                : inset.insetBy(dx: configuration.nestedInset, dy: configuration.nestedInset)

            appendTiles(
                for: child,
                in: interior,
                depth: depth + 1,
                configuration: configuration,
                into: &tiles
            )
        }
    }

    /// The squarified treemap itself: packs `weights` into `bounds` so that each
    /// rectangle's area is proportional to its weight.
    ///
    /// Works best when `weights` is sorted largest first, which is how
    /// ``FileNode/children`` always arrives. Unsorted input still produces a
    /// correct layout, just a less square one.
    ///
    /// - Returns: one rectangle per weight, in the same order. Non-positive
    ///   weights get `CGRect.zero`.
    static func squarify(weights: [Double], in bounds: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: weights.count)
        guard bounds.width > 0, bounds.height > 0 else { return rects }

        // Keep track of where each weight came from, so zero-weight entries can
        // be skipped without shifting everything after them.
        let positive = weights.enumerated().filter { $0.element > 0 }
        guard !positive.isEmpty else { return rects }

        let total = positive.reduce(0.0) { $0 + $1.element }
        let scale = Double(bounds.width) * Double(bounds.height) / total
        let areas = positive.map { $0.element * scale }

        var remaining = bounds
        var index = 0

        while index < areas.count {
            let shortSide = Double(min(remaining.width, remaining.height))
            guard shortSide > .ulpOfOne else { break }

            // Grow the row for as long as adding one more item does not make
            // the worst aspect ratio in it worse. This single greedy rule is
            // the whole of the squarified algorithm.
            var rowCount = 1
            var rowArea = areas[index]
            var bestWorst = worstAspectRatio(
                areas: areas[index ..< index + 1],
                rowArea: rowArea,
                shortSide: shortSide
            )

            while index + rowCount < areas.count {
                let candidateArea = rowArea + areas[index + rowCount]
                let candidateWorst = worstAspectRatio(
                    areas: areas[index ..< index + rowCount + 1],
                    rowArea: candidateArea,
                    shortSide: shortSide
                )
                if candidateWorst > bestWorst { break }
                bestWorst = candidateWorst
                rowArea = candidateArea
                rowCount += 1
            }

            let isHorizontalRow = remaining.width <= remaining.height
            let available = isHorizontalRow ? remaining.height : remaining.width
            // Clamp against accumulated floating-point drift so the final row
            // lands exactly on the edge instead of a hair past it.
            let thickness = min(CGFloat(rowArea / shortSide), available)

            var offset: CGFloat = isHorizontalRow ? remaining.minX : remaining.minY
            let rowEnd: CGFloat = isHorizontalRow ? remaining.maxX : remaining.maxY

            for position in 0 ..< rowCount {
                let area = areas[index + position]
                let isLastInRow = position == rowCount - 1
                var extent = thickness > 0 ? CGFloat(area / Double(thickness)) : 0
                if isLastInRow {
                    // Absorb the rounding error into the last tile so rows
                    // always tile their strip exactly.
                    extent = max(0, rowEnd - offset)
                }

                let rect: CGRect = isHorizontalRow
                    ? CGRect(x: offset, y: remaining.minY, width: extent, height: thickness)
                    : CGRect(x: remaining.minX, y: offset, width: thickness, height: extent)

                rects[positive[index + position].offset] = rect
                offset += extent
            }

            if isHorizontalRow {
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + thickness,
                    width: remaining.width,
                    height: max(0, remaining.height - thickness)
                )
            } else {
                remaining = CGRect(
                    x: remaining.minX + thickness,
                    y: remaining.minY,
                    width: max(0, remaining.width - thickness),
                    height: remaining.height
                )
            }

            index += rowCount
        }

        return rects
    }

    /// The worst (furthest from 1) width-to-height ratio among the tiles a row
    /// would contain, if that row were `rowArea` laid along `shortSide`.
    private static func worstAspectRatio(
        areas: ArraySlice<Double>,
        rowArea: Double,
        shortSide: Double
    ) -> Double {
        guard rowArea > 0, shortSide > 0 else { return .infinity }
        let thickness = rowArea / shortSide
        guard thickness > 0 else { return .infinity }

        var worst = 1.0
        for area in areas {
            guard area > 0 else { return .infinity }
            let extent = area / thickness
            guard extent > 0 else { return .infinity }
            worst = max(worst, max(thickness / extent, extent / thickness))
        }
        return worst
    }
}

extension Array where Element == TreemapTile {
    /// The tile under `point`, preferring the most deeply nested one.
    ///
    /// Layout emits parents before children, so the last match is the deepest —
    /// which is what a click should select, since that is what is drawn on top
    /// and therefore what the person can see.
    func tile(at point: CGPoint) -> TreemapTile? {
        last { $0.rect.contains(point) }
    }
}
