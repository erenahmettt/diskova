import SwiftUI

struct SettingsView: View {
    let store: ScanStore

    @AppStorage(TreemapPalette.storageKey) private var palette: TreemapPalette = .detailed

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Picker("Tile colours", selection: $palette) {
                    ForEach(TreemapPalette.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Appearance")
            } footer: {
                Text("The four-colour set is measured to stay distinguishable with any common form of colour blindness. The eight-colour set is not, which is why every tile also carries a name, and the legend pairs each colour with an icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Include hidden files and folders", isOn: $store.options.includeHiddenEntries)
                Toggle("Treat bundles as single items", isOn: $store.options.treatBundlesAsSingleItems)
                Toggle("Follow mount points onto other disks", isOn: $store.options.crossVolumeBoundaries)
                Toggle("Count hard-linked files only once", isOn: $store.options.countHardLinkedFilesOnce)
            } header: {
                Text("Scanning")
            } footer: {
                Text("Changes apply to the next scan. Counting hard links once keeps totals from exceeding the size of the disk — turn it off only to compare against tools that do not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
