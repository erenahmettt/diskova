import SwiftUI

/// The first screen: pick somewhere to look.
struct WelcomeView: View {
    @Environment(ScanStore.self) private var store
    @State private var isTargetedForDrop = false

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(ScanTarget.suggested) { target in
                        TargetTile(target: target) { store.scan(target.url) }
                    }
                }

                if !store.recentFolders.isEmpty {
                    recentSection
                }

                Button("Choose Another Folder…") {
                    if let folder = FileActions.chooseFolder() {
                        store.scan(folder)
                    }
                }
                .keyboardShortcut("o")
            }
            .padding(36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(isTargetedForDrop ? Color.accentColor.opacity(0.08) : .clear)
        .overlay {
            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(12)
            }
        }
        // Dragging a folder from the Finder is the fastest way in, so it is
        // supported everywhere on this screen rather than in one small well.
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }) else { return false }
            store.scan(folder)
            return true
        } isTargeted: { isTargetedForDrop = $0 }
        .onAppear { store.refreshRecentFolders() }
    }

    private var header: some View {
        VStack(spacing: 7) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Where did the space go?")
                .font(.system(size: 24, weight: .semibold))
            Text("Pick a folder or a disk. Diskova maps it so the biggest things are the biggest shapes — then you can throw them away from here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text("Or drag a folder anywhere onto this window.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(store.recentFolders.enumerated()), id: \.element) { index, url in
                    if index > 0 { Divider() }
                    Button {
                        store.scan(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(Format.path(url, maximumLength: 64))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One of the suggested starting points.
private struct TargetTile: View {
    let target: ScanTarget
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: target.symbolName)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text(target.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quaternary.opacity(0.4)),
                in: .rect(cornerRadius: 10)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text("Scan \(target.displayName)"))
    }
}
