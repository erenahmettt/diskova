import SwiftUI

/// The list beside the map.
///
/// This is not decoration: it is the accessible, keyboard-navigable version of
/// the same data, which a `Canvas` cannot be. Everything the treemap shows can
/// be reached here with the arrow keys and read by VoiceOver.
struct SidebarView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case contents
        case largestFiles

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .contents: "Contents"
            case .largestFiles: "Biggest files"
            }
        }
    }

    @Environment(ScanStore.self) private var store
    @State private var mode: Mode = .contents
    @State private var largestFiles: [FileNode] = []
    @State private var isFindingLargestFiles = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch mode {
            case .contents:
                contentsList
            case .largestFiles:
                largestFilesList
            }
        }
        .task(id: largestFilesKey) {
            await findLargestFiles()
        }
    }

    // MARK: - Contents of the current folder

    @ViewBuilder
    private var contentsList: some View {
        if let folder = store.currentFolder {
            List(selection: selectionBinding) {
                ForEach(folder.children) { child in
                    EntryRow(node: child, total: store.totalByteSize)
                        .tag(child.url)
                        .contextMenu {
                            FileContextMenu(node: child) { store.descend(into: $0) }
                        }
                }
            }
            .listStyle(.inset)
            // Double-clicking a row should do what double-clicking a tile does.
            .environment(\.defaultMinListRowHeight, 28)
        }
    }

    // MARK: - Biggest files anywhere in the scan

    @ViewBuilder
    private var largestFilesList: some View {
        if isFindingLargestFiles {
            VStack {
                ProgressView().controlSize(.small)
                Text("Looking…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selectionBinding) {
                ForEach(largestFiles) { file in
                    EntryRow(node: file, total: store.totalByteSize, showsEnclosingFolder: true)
                        .tag(file.url)
                        .contextMenu {
                            FileContextMenu(node: file) { store.descend(into: $0) }
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    /// Lets the list drive — and follow — the shared selection, matching URLs
    /// rather than node identity so a rebuilt tree does not drop the highlight.
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { store.selection?.url },
            set: { url in
                guard let url, let root = store.root else {
                    store.selection = nil
                    return
                }
                store.selection = root.path(to: url)?.last
            }
        )
    }

    private var largestFilesKey: String {
        guard mode == .largestFiles, let root = store.root else { return "idle" }
        return "\(root.url.path)-\(root.byteSize)"
    }

    /// Walks the whole tree for the hundred biggest files.
    ///
    /// Off the main actor, because on a full startup disk this visits several
    /// million nodes — fast, but not "while the window is trying to draw" fast.
    /// The tree is immutable and `Sendable`, so handing it to another task
    /// needs no copying.
    private func findLargestFiles() async {
        guard mode == .largestFiles, let root = store.root else { return }
        isFindingLargestFiles = true
        defer { isFindingLargestFiles = false }
        largestFiles = await Task.detached(priority: .userInitiated) {
            root.largestFiles(limit: 100)
        }.value
    }
}

/// One row: name, size, share of the scan, and a bar for comparing at a glance.
struct EntryRow: View {
    let node: FileNode
    let total: Int64
    var showsEnclosingFolder = false

    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed
    @Environment(ScanStore.self) private var store

    private var fraction: Double { node.fraction(of: total) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : node.kind.symbolName)
                .font(.caption)
                .foregroundStyle((node.isDirectory ? node.dominantKind : node.kind).fillColor(palette: palette))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsEnclosingFolder {
                    Text(Format.path(node.url.deletingLastPathComponent(), maximumLength: 46))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ProportionBar(fraction: fraction, color: (node.isDirectory ? node.dominantKind : node.kind).fillColor(palette: palette))
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(node.byteSize))
                    .font(.caption.monospacedDigit())
                Text(Format.percent(fraction))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            if node.isDirectory, !node.children.isEmpty {
                store.descend(into: node)
            } else {
                FileActions.revealInFinder(node.url)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(node.name), \(Format.bytes(node.byteSize)), \(Format.percent(fraction)) of the scan"))
    }
}

/// A hairline bar showing one entry's share. Thin on purpose: it is a
/// comparison aid sitting inside a row, not a chart in its own right.
struct ProportionBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(1.5, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
