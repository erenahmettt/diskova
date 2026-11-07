import SwiftUI

@main
struct DiskovaApp: App {
    @State private var store = ScanStore()

    var body: some Scene {
        // `Window` rather than `WindowGroup`: Diskova holds one scan at a
        // time, and a second window showing the same scan would only be able
        // to disagree with the first.
        Window("Diskova", id: "main") {
            RootView(store: store)
                // Lets a folder be dropped on the Dock icon, or opened with
                // Finder's "Open With".
                .onOpenURL { url in
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    else { return }
                    store.scan(url)
                }
        }
        .defaultSize(width: 1200, height: 780)
        .commands { DiskovaCommands(store: store) }

        Settings {
            SettingsView(store: store)
        }
    }
}

/// Menu-bar commands. Everything the toolbar and context menus can do is also
/// here with a keyboard shortcut, because a utility you have to reach for the
/// mouse to use gets opened once.
struct DiskovaCommands: Commands {
    let store: ScanStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Scan Folder…") {
                if let folder = FileActions.chooseFolder(startingAt: store.currentFolder?.url) {
                    store.scan(folder)
                }
            }
            .keyboardShortcut("o")
        }

        CommandMenu("Map") {
            Button("Go Up") { store.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!store.canGoUp)

            Button("Open Selected") { store.descendIntoSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!(store.selection?.isDirectory ?? false))

            Divider()

            Button("Rescan") { store.rescan() }
                .keyboardShortcut("r")
                .disabled(store.outcome == nil)

            Divider()

            Button("Reveal in Finder") {
                if let selection = store.selection {
                    FileActions.revealInFinder(selection.url)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(store.selection == nil)

            Button("Copy Path") {
                if let selection = store.selection {
                    FileActions.copyPath(selection.url)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(store.selection == nil)

            Divider()

            Button("Move to Trash…") {
                if let selection = store.selection {
                    store.requestTrash(selection)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(store.selection == nil)
        }

        CommandGroup(replacing: .help) {
            Link("Diskova on GitHub", destination: URL(string: "https://github.com/erenahmettt/diskova")!)
        }
    }
}
