import SwiftUI

/// The window's one job: show whichever of the four states the app is in.
struct RootView: View {
    let store: ScanStore

    var body: some View {
        Group {
            switch store.phase {
            case .idle:
                WelcomeView()
            case .scanning(let progress):
                ScanningView(progress: progress)
            case .results:
                ResultsView()
            case .failed(let failure):
                ScanFailureView(failure: failure)
            }
        }
        .environment(store)
        .frame(minWidth: 880, minHeight: 560)
    }
}

/// Shown when a scan could not even start.
struct ScanFailureView: View {
    let failure: ScanFailure

    @Environment(ScanStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(failure.message)
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                if case .unreadable = failure {
                    Button("Open Full Disk Access Settings…") {
                        FileActions.openFullDiskAccessSettings()
                    }
                }
                Button("Choose Another Folder…") {
                    if let folder = FileActions.chooseFolder() {
                        store.scan(folder)
                    }
                }
                .keyboardShortcut("o")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
