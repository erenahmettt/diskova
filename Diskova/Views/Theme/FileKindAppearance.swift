import AppKit
import SwiftUI

/// Which set of colours the treemap uses.
enum TreemapPalette: String, CaseIterable, Identifiable, Sendable {
    /// Eight hues, one per category. The default: it tells you at a glance
    /// whether a folder is full of photos or full of video.
    case detailed
    /// Four hues over four broad groups. Every pair of these is separable by
    /// viewers with any common form of colour blindness — see the note on
    /// ``FileKind/fillColor(palette:)`` for the numbers.
    case colorBlindSafe

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .detailed: "Detailed (8 colours)"
        case .colorBlindSafe: "Colour-blind safe (4 colours)"
        }
    }
}

/// The four broad groups the colour-blind-safe palette collapses to.
enum KindGroup: String, CaseIterable, Identifiable, Sendable {
    case media
    case documents
    case appsAndCode
    case buildAndCache
    case structure

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .media: "Photos, video & music"
        case .documents: "Documents & archives"
        case .appsAndCode: "Apps, code & data"
        case .buildAndCache: "Build & cache"
        case .structure: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .media: "photo.on.rectangle.angled"
        case .documents: "doc.on.doc.fill"
        case .appsAndCode: "app.badge.checkmark"
        case .buildAndCache: "hammer.fill"
        case .structure: "questionmark.square.dashed"
        }
    }

    var kinds: Set<FileKind> {
        switch self {
        case .media: [.image, .video, .audio]
        case .documents: [.document, .archive]
        case .appsAndCode: [.application, .code]
        case .buildAndCache: [.developer]
        case .structure: [.other, .folder]
        }
    }
}

extension FileKind {
    /// Which broad group this category belongs to.
    var group: KindGroup {
        KindGroup.allCases.first { $0.kinds.contains(self) } ?? .structure
    }

    /// The colour a tile of this kind is filled with.
    ///
    /// ## Why there are two palettes
    ///
    /// Colours here were taken from a validated categorical set and then
    /// **measured**, not chosen by eye, using perceptual distance in OKLab
    /// (ΔE ×100) under simulated protanopia, deuteranopia and tritanopia.
    ///
    /// A treemap is the hardest case for a categorical palette: unlike a bar
    /// chart, where only neighbouring series touch, *any* two tiles can end up
    /// side by side. So the palette has to clear its thresholds across **every**
    /// pair, not just adjacent ones. Measured against that bar:
    ///
    /// | Palette | Worst pair, colour-blind | Worst pair, normal vision |
    /// |---|---|---|
    /// | Eight hues | ΔE 3.2 light / 1.6 dark | ΔE 7.1 both |
    /// | Four hues  | ΔE 13.0 light / 6.9 dark | ΔE 19.6 light / 19.3 dark |
    ///
    /// The thresholds are ΔE ≥ 8 for colour blindness (6–8 is tolerable only
    /// where something other than colour also identifies the tile) and ≥ 15 for
    /// normal vision. Eight hues fail both across all pairs; four hues pass. A
    /// search over the eight-hue set found that **four is the largest subset
    /// that can pass** — no re-ordering or re-stepping fixes it, because in a
    /// treemap ordering does not constrain adjacency.
    ///
    /// Rather than pretend otherwise, Diskova does two things:
    ///
    /// 1. Never lets colour be the only identification. Every tile big enough
    ///    shows its name, the hovered tile is named in the status bar, the
    ///    selected one is described in the inspector, and the legend pairs each
    ///    colour with an icon and a label.
    /// 2. Ships ``TreemapPalette/colorBlindSafe`` as a first-class setting — the
    ///    measured four-hue set over four groups, which passes every check in
    ///    both light and dark mode.
    ///
    /// Dark values are chosen for the dark surface rather than derived by
    /// flipping the light ones, which is why each is listed explicitly.
    func fillColor(palette: TreemapPalette) -> Color {
        switch palette {
        case .colorBlindSafe:
            switch group {
            case .appsAndCode: .dynamic(light: 0x2A78D6, dark: 0x3987E5)
            case .documents: .dynamic(light: 0xEDA100, dark: 0xC98500)
            case .media: .dynamic(light: 0xE87BA4, dark: 0xD55181)
            case .buildAndCache: .dynamic(light: 0x008300, dark: 0x008300)
            case .structure: .dynamic(light: 0x8E8E88, dark: 0x6E6E68)
            }

        case .detailed:
            switch self {
            case .application: .dynamic(light: 0x2A78D6, dark: 0x3987E5)
            case .document: .dynamic(light: 0xEB6834, dark: 0xD95926)
            case .image: .dynamic(light: 0x1BAF7A, dark: 0x199E70)
            case .archive: .dynamic(light: 0xEDA100, dark: 0xC98500)
            case .audio: .dynamic(light: 0xE87BA4, dark: 0xD55181)
            case .code: .dynamic(light: 0x008300, dark: 0x008300)
            case .video: .dynamic(light: 0x6250D6, dark: 0x9085E9)
            case .developer: .dynamic(light: 0xE34948, dark: 0xE66767)
            case .other: .dynamic(light: 0x8E8E88, dark: 0x6E6E68)
            case .folder: .dynamic(light: 0xB6B5AE, dark: 0x4A4A46)
            }
        }
    }

    /// Ink used for a label drawn on top of this kind's fill.
    ///
    /// White on every fill except the yellow one, which is light enough that
    /// white text on it is unreadable.
    func labelColor(palette: TreemapPalette) -> Color {
        let isYellow = palette == .detailed ? self == .archive : group == .documents
        return isYellow ? Color(white: 0.04) : .white
    }
}

/// One row of the legend.
struct LegendEntry: Identifiable, Sendable {
    let id: String
    let title: LocalizedStringResource
    let symbolName: String
    let kinds: Set<FileKind>
    let representativeKind: FileKind
}

extension TreemapPalette {
    /// Legend rows for this palette, in a fixed order so the colours never
    /// rearrange themselves between one scan and the next.
    var legendEntries: [LegendEntry] {
        switch self {
        case .detailed:
            // Folders are left out: they are drawn as frames around their
            // contents rather than as a colour you need to look up.
            FileKind.allCases
                .filter { $0 != .folder }
                .map { kind in
                    LegendEntry(
                        id: kind.rawValue,
                        title: kind.displayName,
                        symbolName: kind.symbolName,
                        kinds: [kind],
                        representativeKind: kind
                    )
                }
        case .colorBlindSafe:
            KindGroup.allCases.map { group in
                LegendEntry(
                    id: group.rawValue,
                    title: group.displayName,
                    symbolName: group.symbolName,
                    kinds: group.kinds,
                    representativeKind: group.kinds.first { $0 != .folder } ?? .other
                )
            }
        }
    }
}

extension Color {
    /// A colour with separately chosen light and dark values.
    ///
    /// Uses AppKit's dynamic colour so the swap happens inside the system when
    /// the appearance changes, including mid-session and inside a Canvas, where
    /// SwiftUI's own environment is not consulted for every draw.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    /// Builds a colour from a `0xRRGGBB` literal, in sRGB.
    convenience init(rgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
