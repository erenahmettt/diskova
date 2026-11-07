import SwiftUI

/// Shown while a scan is running.
///
/// There is no percentage, because there cannot be one: the only way to know
/// how much of a disk is left to walk is to walk it. Showing a fake bar that
/// crawls and then jumps would be worse than showing the real counts, which at
/// least prove the thing is working.
struct ScanningView: View {
    let progress: ScanProgress

    @Environment(ScanStore.self) private var store

    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 5) {
                Text("Measuring…")
                    .font(.title3.weight(.semibold))
                Text(progress.currentPath.isEmpty
                     ? " "
                     : Format.path(URL(fileURLWithPath: progress.currentPath), maximumLength: 72))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 460)
            }

            HStack(spacing: 28) {
                Tally(value: Format.bytes(progress.byteSize), label: "measured")
                Tally(value: Format.count(progress.fileCount), label: "files")
                Tally(value: Format.count(progress.directoryCount), label: "folders")
            }

            Button("Stop", role: .cancel) { store.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Tally: View {
    let value: String
    let label: LocalizedStringResource

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 86)
    }
}
