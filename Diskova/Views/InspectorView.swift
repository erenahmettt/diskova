import SwiftUI

/// The details panel. Describes whatever is selected, or summarises the folder
/// on screen when nothing is.
struct InspectorView: View {
    @Environment(ScanStore.self) private var store
    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selection = store.selection {
                    EntryDetails(node: selection, total: store.totalByteSize)
                } else if let folder = store.currentFolder {
                    FolderSummary(folder: folder, total: store.totalByteSize)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Facts and actions for one selected entry.
private struct EntryDetails: View {
    let node: FileNode
    let total: Int64

    @Environment(ScanStore.self) private var store
    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: node.isDirectory ? "folder.fill" : node.kind.symbolName)
                        .foregroundStyle((node.isDirectory ? node.dominantKind : node.kind).fillColor(palette: palette))
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Text(Format.bytes(node.byteSize))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                Text("\(Format.percent(node.fraction(of: total))) of everything scanned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if node.kind.isUsuallyReclaimable {
                Callout(
                    symbolName: "arrow.clockwise.circle.fill",
                    text: "This is build output or a cache. It regenerates itself, so deleting it is usually safe — the tool that made it will just make it again."
                )
            }

            if node.isPackage {
                Callout(
                    symbolName: "shippingbox.fill",
                    text: "This is a bundle shown as one item. Turn off “Treat bundles as single items” in Settings to look inside."
                )
            }

            Facts(node: node)

            VStack(spacing: 6) {
                Button {
                    FileActions.revealInFinder(node.url)
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                if node.isDirectory, !node.children.isEmpty {
                    Button {
                        store.descend(into: node)
                    } label: {
                        Label("Open in Diskova", systemImage: "square.grid.3x3")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button(role: .destructive) {
                    store.requestTrash(node)
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Summary of the folder currently filling the map.
private struct FolderSummary: View {
    let folder: FileNode
    let total: Int64

    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed
    @State private var breakdown: [LegendEntry: Int64] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(folder.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(Format.bytes(folder.byteSize))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                Text("\(Format.count(folder.fileCount)) files · \(Format.count(folder.directoryCount)) folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is in here")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    // Ordered by the palette, not by size, so the rows stay put
                    // between folders instead of reshuffling as you browse.
                    ForEach(palette.legendEntries) { entry in
                        if let bytes = breakdown[entry], bytes > 0 {
                            KindRow(
                                entry: entry,
                                byteSize: bytes,
                                fraction: folder.byteSize > 0 ? Double(bytes) / Double(folder.byteSize) : 0,
                                palette: palette
                            )
                        }
                    }
                }
            }

            Text("Select a tile to see what it is and act on it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .task(id: "\(folder.url.path)-\(folder.byteSize)-\(palette.rawValue)") {
            await computeBreakdown()
        }
    }

    /// Totals every category below this folder, off the main actor: it visits
    /// the whole subtree, which for a scan of `/` is millions of nodes.
    private func computeBreakdown() async {
        let folder = folder
        let entries = palette.legendEntries
        breakdown = await Task.detached(priority: .userInitiated) {
            let byKind = Dictionary(
                folder.sizeByKind().map { ($0.kind, $0.byteSize) },
                uniquingKeysWith: +
            )
            var totals: [LegendEntry: Int64] = [:]
            for entry in entries {
                let sum = entry.kinds.reduce(Int64(0)) { $0 + (byKind[$1] ?? 0) }
                if sum > 0 { totals[entry] = sum }
            }
            return totals
        }.value
    }
}

private struct KindRow: View {
    let entry: LegendEntry
    let byteSize: Int64
    let fraction: Double
    let palette: TreemapPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: entry.symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(entry.title)
                    .font(.caption)
                Spacer(minLength: 4)
                Text(Format.bytes(byteSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProportionBar(
                fraction: fraction,
                color: entry.representativeKind.fillColor(palette: palette)
            )
        }
    }
}

/// Key-value facts about an entry.
private struct Facts: View {
    let node: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if node.isDirectory {
                Fact(label: "Files inside", value: Format.count(node.fileCount))
                Fact(label: "Folders inside", value: Format.count(node.directoryCount))
                if node.ownByteSize > 0 {
                    Fact(label: "Folder entry itself", value: Format.bytes(node.ownByteSize))
                }
            }
            Fact(label: "Kind", value: String(localized: node.kind.displayName))
            Fact(label: "Where", value: Format.path(node.url.deletingLastPathComponent(), maximumLength: 54))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))
    }
}

private struct Fact: View {
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// A short note with an icon, for things worth saying once.
private struct Callout: View {
    let symbolName: String
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbolName)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 7))
    }
}

extension LegendEntry: Hashable {
    static func == (lhs: LegendEntry, rhs: LegendEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
