import SwiftUI

/// The map itself: every file in the current folder as a rectangle whose area
/// is its share of the space.
///
/// Drawn into a single `Canvas` rather than as a few thousand SwiftUI views.
/// A folder like `~/Library` can produce well over ten thousand visible tiles,
/// and SwiftUI's diffing cost per view would make hovering feel sticky; one
/// canvas redraw is a few milliseconds. The price is that hit testing and
/// labelling have to be written by hand, which is what most of this file is.
struct TreemapView: View {
    /// The folder whose contents fill the canvas.
    let folder: FileNode

    @Binding var selection: FileNode?
    @Binding var hovered: FileNode?

    /// Called when a tile is double-clicked and can be opened.
    let onOpen: (FileNode) -> Void

    @State private var tiles: [TreemapTile] = []

    /// What a laid-out canvas depends on. Layout is recomputed when this
    /// changes and not on every redraw, so hovering costs a repaint rather than
    /// a relayout.
    private struct LayoutKey: Equatable {
        let folder: URL
        let width: CGFloat
        let height: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            let key = LayoutKey(
                folder: folder.url,
                width: geometry.size.width.rounded(),
                height: geometry.size.height.rounded()
            )

            TreemapCanvas(
                tiles: tiles,
                hovered: hovered,
                selection: selection
            )
            .onChange(of: key, initial: true) { _, newKey in
                tiles = TreemapLayout.tiles(
                    for: folder,
                    in: CGRect(x: 0, y: 0, width: newKey.width, height: newKey.height)
                )
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    let node = tiles.tile(at: location)?.node
                    if node != hovered { hovered = node }
                case .ended:
                    hovered = nil
                }
            }
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { event in
                        if let node = tiles.tile(at: event.location)?.node {
                            selection = node
                            onOpen(node)
                        }
                    }
                    .exclusively(
                        before: SpatialTapGesture()
                            .onEnded { event in
                                selection = tiles.tile(at: event.location)?.node
                            }
                    )
            )
        }
        .background(TreemapTheme.canvas)
        .contextMenu {
            // Built when the menu opens, by which point `hovered` is the tile
            // the pointer is over — the same thing a right-click should act on.
            if let target = hovered ?? selection {
                FileContextMenu(node: target, onOpen: onOpen)
            }
        }
        // A canvas is opaque to VoiceOver. The sidebar list beside it carries
        // the same information as focusable rows, so this element only has to
        // describe the whole and point at the alternative.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Treemap of \(folder.name)"))
        .accessibilityValue(Text("\(Format.bytes(folder.byteSize)), \(Format.count(folder.fileCount)) files. Use the contents list for an item-by-item view."))
    }
}

/// The drawing half of the treemap, with no state of its own.
///
/// Split out from ``TreemapView`` so it can be rendered — and checked — without
/// a running window: give it tiles, get pixels. That is what
/// `TreemapRenderingTests` does.
struct TreemapCanvas: View {
    let tiles: [TreemapTile]
    var hovered: FileNode?
    var selection: FileNode?

    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed

    var body: some View {
        Canvas(opaque: true) { context, size in
            paint(&context, size: size)
        }
    }

    // MARK: - Drawing


    private func paint(_ context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(TreemapTheme.canvas)
        )

        for tile in tiles {
            paint(tile: tile, into: &context)
        }

        // Rings go on last so they are never covered by a nested child.
        if let hovered, let tile = tiles.last(where: { $0.node == hovered }) {
            stroke(tile.rect, color: TreemapTheme.hoverRing.opacity(0.65), width: 1.5, in: &context)
        }
        if let selection, let tile = tiles.last(where: { $0.node == selection }) {
            stroke(tile.rect, color: TreemapTheme.selectionRing, width: 2.5, in: &context)
        }
    }

    private func paint(tile: TreemapTile, into context: inout GraphicsContext) {
        let shape = Path(roundedRect: tile.rect, cornerRadius: cornerRadius(for: tile.rect))

        if tile.isOpened {
            // A container: its children will cover the middle, so only a wash
            // and a hairline are needed to read as "these belong together".
            context.fill(shape, with: .color(tile.node.dominantKind.fillColor(palette: palette).opacity(0.22)))
            context.stroke(shape, with: .color(TreemapTheme.folderEdge.opacity(0.45)), lineWidth: 1)
            if tile.hasHeader {
                paintHeader(tile: tile, into: &context)
            }
        } else {
            let kind = tile.node.isDirectory ? tile.node.dominantKind : tile.node.kind
            context.fill(shape, with: .color(kind.fillColor(palette: palette)))
            paintLabel(tile: tile, kind: kind, into: &context)
        }
    }

    /// Name strip along the top of an opened folder.
    private func paintHeader(tile: TreemapTile, into context: inout GraphicsContext) {
        let strip = CGRect(
            x: tile.rect.minX + 5,
            y: tile.rect.minY + 2,
            width: tile.rect.width - 10,
            height: 13
        )
        guard strip.width > 24 else { return }

        let text = context.resolve(
            Text("\(tile.node.name)  ·  \(Format.bytes(tile.node.byteSize))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
        )
        guard text.measure(in: CGSize(width: .infinity, height: strip.height)).width <= strip.width else {
            // Fall back to the name alone before giving up on a label entirely.
            let short = context.resolve(
                Text(tile.node.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
            )
            guard short.measure(in: CGSize(width: .infinity, height: strip.height)).width <= strip.width else { return }
            context.draw(short, at: CGPoint(x: strip.minX, y: strip.minY), anchor: .topLeading)
            return
        }
        context.draw(text, at: CGPoint(x: strip.minX, y: strip.minY), anchor: .topLeading)
    }

    /// Name and size inside a solid tile, when there is room for them.
    private func paintLabel(tile: TreemapTile, kind: FileKind, into context: inout GraphicsContext) {
        let available = tile.rect.insetBy(dx: 4, dy: 3)
        guard available.width >= 42, available.height >= 13 else { return }

        let ink = kind.labelColor(palette: palette)
        let name = context.resolve(
            Text(tile.node.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ink)
        )
        let nameSize = name.measure(in: CGSize(width: available.width, height: available.height))
        guard nameSize.width <= available.width, nameSize.height <= available.height else { return }

        context.draw(
            name,
            at: CGPoint(x: available.minX, y: available.minY),
            anchor: .topLeading
        )

        // The size only goes in if it fits on its own line underneath; a
        // truncated size is worse than none, because a wrong number is read as
        // a right one.
        let remaining = available.height - nameSize.height - 1
        guard remaining >= 12 else { return }
        let size = context.resolve(
            Text(Format.bytes(tile.node.byteSize))
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(ink.opacity(0.85))
        )
        let sizeExtent = size.measure(in: CGSize(width: available.width, height: remaining))
        guard sizeExtent.width <= available.width else { return }
        context.draw(
            size,
            at: CGPoint(x: available.minX, y: available.minY + nameSize.height + 1),
            anchor: .topLeading
        )
    }

    private func stroke(_ rect: CGRect, color: Color, width: CGFloat, in context: inout GraphicsContext) {
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), cornerRadius: cornerRadius(for: rect)),
            with: .color(color),
            lineWidth: width
        )
    }

    /// Corners are rounded in proportion to the tile, so small tiles do not
    /// turn into circles and large ones do not look like raw rectangles.
    private func cornerRadius(for rect: CGRect) -> CGFloat {
        min(3, min(rect.width, rect.height) / 4)
    }
}

/// The actions available on one entry, shared by the treemap's context menu and
/// the sidebar's row menu so both offer exactly the same things.
struct FileContextMenu: View {
    let node: FileNode
    let onOpen: (FileNode) -> Void

    @Environment(ScanStore.self) private var store

    var body: some View {
        if node.isDirectory, !node.children.isEmpty {
            Button("Open in Diskova") { onOpen(node) }
        }
        Button("Open with Default App") { FileActions.open(node.url) }
        Button("Reveal in Finder") { FileActions.revealInFinder(node.url) }
        Button("Copy Path") { FileActions.copyPath(node.url) }
        Divider()
        // Confirmation is raised by the window, not here: see
        // `ScanStore.pendingTrashTarget`.
        Button("Move to Trash…", role: .destructive) { store.requestTrash(node) }
    }
}
