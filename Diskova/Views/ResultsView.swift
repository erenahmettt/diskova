import SwiftUI

/// The main screen once a scan has finished.
struct ResultsView: View {
    @Environment(ScanStore.self) private var store
    @AppStorage("showsInspector") private var showsInspector = true
    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 232, ideal: 288, max: 420)
        } detail: {
            detail
        }
        .navigationTitle(store.currentFolder?.name ?? "Diskova")
        .navigationSubtitle(store.root.map { Format.bytes($0.byteSize) } ?? "")
        .toolbar { toolbarContent }
        .confirmationDialog(
            Text("Move “\(store.pendingTrashTarget?.name ?? "")” to the Trash?"),
            isPresented: Binding(
                get: { store.pendingTrashTarget != nil },
                set: { if !$0 { store.pendingTrashTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { store.confirmPendingTrash() }
            Button("Cancel", role: .cancel) { store.pendingTrashTarget = nil }
        } message: {
            if let target = store.pendingTrashTarget {
                Text("This frees \(Format.bytes(target.byteSize)). You can put it back from the Trash.")
            }
        }
        .alert(
            "Could not move that to the Trash",
            isPresented: Binding(
                get: { store.trashFailureReason != nil },
                set: { if !$0 { store.trashFailureReason = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.trashFailureReason = nil }
        } message: {
            Text(store.trashFailureReason ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            BreadcrumbBar()
            Divider()

            if let folder = store.currentFolder {
                if folder.children.contains(where: { $0.byteSize > 0 }) {
                    TreemapView(
                        folder: folder,
                        selection: $store.selection,
                        hovered: $store.hovered,
                        onOpen: { store.descend(into: $0) }
                    )
                } else {
                    emptyFolderNotice(folder)
                }
            }

            Divider()
            LegendStrip()
            Divider()
            StatusBar()
        }
        .inspector(isPresented: $showsInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 248, ideal: 292, max: 400)
        }
    }

    private func emptyFolderNotice(_ folder: FileNode) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing here takes up space.")
                .foregroundStyle(.secondary)
            if folder.fileCount > 0 {
                Text("\(Format.count(folder.fileCount)) empty files")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TreemapTheme.canvas)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                store.goUp()
            } label: {
                Label("Up", systemImage: "chevron.up")
            }
            .disabled(!store.canGoUp)
            .help(Text("Go to the enclosing folder"))

            Button {
                store.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help(Text("Scan this folder again"))

            Button {
                if let folder = FileActions.chooseFolder(startingAt: store.currentFolder?.url) {
                    store.scan(folder)
                }
            } label: {
                Label("New Scan", systemImage: "folder.badge.plus")
            }
            .help(Text("Scan a different folder"))
        }

        ToolbarItemGroup {
            Menu {
                Picker("Colours", selection: $palette) {
                    ForEach(TreemapPalette.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Colours", systemImage: "paintpalette")
            }
            .help(Text("Choose how tiles are coloured"))

            Button {
                showsInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help(Text("Show or hide details"))
        }
    }
}

/// The path from the scan root to the folder on screen, as buttons.
struct BreadcrumbBar: View {
    @Environment(ScanStore.self) private var store

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(store.trail.enumerated()), id: \.element) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        store.ascend(to: node)
                    } label: {
                        Text(index == 0 ? Format.path(node.url, maximumLength: 36) : node.name)
                            .font(.callout.weight(index == store.trail.count - 1 ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == store.trail.count - 1 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .scrollIndicators(.never)
        // Keep the deepest crumb visible as you drill in.
        .defaultScrollAnchor(.trailing)
    }
}

/// Always-present key to the colours, so a tile is never identified by hue
/// alone — the point the palette's own measurements make unavoidable.
struct LegendStrip: View {
    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 13) {
                ForEach(palette.legendEntries) { entry in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.representativeKind.fillColor(palette: palette))
                            .frame(width: 9, height: 9)
                        Image(systemName: entry.symbolName)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                        Text(entry.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.never)
    }
}

/// Whatever the pointer is on, plus the facts about the scan as a whole.
struct StatusBar: View {
    @Environment(ScanStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if let focus = store.hovered ?? store.selection {
                Image(systemName: focus.isDirectory ? "folder" : focus.kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.path(focus.url, maximumLength: 70))
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(Format.bytes(focus.byteSize)) · \(Format.percent(focus.fraction(of: store.totalByteSize))) of scan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let outcome = store.outcome {
                Text("\(Format.count(outcome.root.fileCount)) files in \(Format.count(outcome.root.directoryCount)) folders · scanned in \(Format.seconds(outcome.elapsed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let outcome = store.outcome, !outcome.unreadablePaths.isEmpty {
                UnreadableBadge(count: outcome.unreadablePaths.count)
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 12)
    }
}

/// Warns that part of the disk was invisible to the scan — the one error a disk
/// analyser must never swallow, because silently under-reporting looks exactly
/// like a correct answer.
private struct UnreadableBadge: View {
    let count: Int

    var body: some View {
        Button {
            FileActions.openFullDiskAccessSettings()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8.5))
                Text("\(Format.count(count)) folders blocked")
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .help(Text("macOS blocked these folders, so their contents are missing from the totals. Grant Diskova Full Disk Access to include them."))
    }
}
