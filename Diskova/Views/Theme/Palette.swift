import SwiftUI

extension TreemapPalette {
    /// Key the chosen palette is stored under, shared by every view that needs
    /// it so they cannot drift apart.
    static let storageKey = "treemapPalette"
}

/// Surfaces and ink the treemap draws on, kept together so light and dark are
/// chosen deliberately rather than one being a tint of the other.
enum TreemapTheme {
    /// What shows through the gaps between tiles. The gaps are what separate
    /// one tile from the next, so this reads as structure, not background.
    static let canvas = Color.dynamic(light: 0xF7F7F5, dark: 0x1E1E1E)
    /// Hairline around a folder that has its contents drawn inside it.
    static let folderEdge = Color.dynamic(light: 0x8A8A83, dark: 0x6B6B65)
    /// Ring drawn around the tile under the pointer.
    static let hoverRing = Color.dynamic(light: 0x0B0B0B, dark: 0xFFFFFF)
    /// Ring drawn around the selected tile.
    static let selectionRing = Color.accentColor
}
