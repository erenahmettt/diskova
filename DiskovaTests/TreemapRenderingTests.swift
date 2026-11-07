import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Diskova

/// Checks that the treemap actually produces pixels.
///
/// The layout tests prove the geometry is right; these prove the geometry gets
/// drawn. Together they cover the thing that would otherwise only be caught by
/// a person opening the app and looking — a blank canvas, a palette that paints
/// everything the same colour, labels drawn off the edge.
@Suite("Treemap rendering")
@MainActor
struct TreemapRenderingTests {
    private func sampleTree() -> FileNode {
        func file(_ path: String, _ kilobytes: Int64, _ kind: FileKind) -> FileNode {
            .file(url: URL(fileURLWithPath: path), byteSize: kilobytes * 1_024, kind: kind)
        }

        return FileNode.directory(url: URL(fileURLWithPath: "/demo"), children: [
            FileNode.directory(url: URL(fileURLWithPath: "/demo/Movies"), children: [
                file("/demo/Movies/holiday-2024.mov", 1_800, .video),
                file("/demo/Movies/wedding.mp4", 1_200, .video),
                file("/demo/Movies/clip.mkv", 300, .video),
            ]),
            FileNode.directory(url: URL(fileURLWithPath: "/demo/Downloads"), children: [
                file("/demo/Downloads/installer.dmg", 900, .archive),
                file("/demo/Downloads/archive.zip", 350, .archive),
                file("/demo/Downloads/report.pdf", 40, .document),
            ]),
            FileNode.directory(url: URL(fileURLWithPath: "/demo/Photos"), children: [
                file("/demo/Photos/raw.dng", 420, .image),
                file("/demo/Photos/trip.heic", 180, .image),
                file("/demo/Photos/scan.png", 90, .image),
            ]),
            FileNode.directory(url: URL(fileURLWithPath: "/demo/Projects"), children: [
                FileNode.directory(url: URL(fileURLWithPath: "/demo/Projects/node_modules"), children:
                    (0 ..< 24).map { file("/demo/Projects/node_modules/pkg\($0).js", Int64(20 + $0 * 3), .developer) }
                ),
                file("/demo/Projects/main.swift", 5, .code),
            ]),
            FileNode.directory(url: URL(fileURLWithPath: "/demo/Music"), children: [
                file("/demo/Music/album.flac", 260, .audio),
                file("/demo/Music/podcast.mp3", 60, .audio),
            ]),
            file("/demo/Thing.app", 640, .application),
        ])
    }

    private func render(_ tree: FileNode, size: CGSize, palette: TreemapPalette) -> NSBitmapImageRep? {
        UserDefaults.standard.set(palette.rawValue, forKey: TreemapPalette.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: TreemapPalette.storageKey) }

        let tiles = TreemapLayout.tiles(for: tree, in: CGRect(origin: .zero, size: size))
        let renderer = ImageRenderer(
            content: TreemapCanvas(tiles: tiles)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    /// Samples the rendered image on a grid and returns how many distinct
    /// colours appear. A blank or single-colour canvas is the failure this
    /// catches.
    private func distinctColours(in bitmap: NSBitmapImageRep, samples: Int = 40) -> Set<Int> {
        var seen: Set<Int> = []
        for row in 0 ..< samples {
            for column in 0 ..< samples {
                let x = bitmap.pixelsWide * column / samples
                let y = bitmap.pixelsHigh * row / samples
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                let packed = (Int(colour.redComponent * 255) << 16)
                    | (Int(colour.greenComponent * 255) << 8)
                    | Int(colour.blueComponent * 255)
                seen.insert(packed)
            }
        }
        return seen
    }

    @Test("The detailed palette paints a map with many distinct colours")
    func rendersDetailedPalette() throws {
        let bitmap = try #require(render(sampleTree(), size: CGSize(width: 900, height: 560), palette: .detailed))

        #expect(bitmap.pixelsWide == 1_800)
        #expect(bitmap.pixelsHigh == 1_120)

        let colours = distinctColours(in: bitmap)
        // Six categories are present in the sample tree; allowing for tile
        // edges and labels, anything under six means tiles are not being
        // filled.
        #expect(colours.count >= 6, "only \(colours.count) distinct colours — the canvas is probably blank")
    }

    @Test("The colour-blind-safe palette still paints a readable map")
    func rendersAccessiblePalette() throws {
        let bitmap = try #require(render(sampleTree(), size: CGSize(width: 900, height: 560), palette: .colorBlindSafe))
        let colours = distinctColours(in: bitmap)
        #expect(colours.count >= 4)
    }

    @Test("The two palettes do not render identically")
    func palettesDiffer() throws {
        let size = CGSize(width: 600, height: 400)
        let detailed = try #require(render(sampleTree(), size: size, palette: .detailed))
        let accessible = try #require(render(sampleTree(), size: size, palette: .colorBlindSafe))

        #expect(distinctColours(in: detailed) != distinctColours(in: accessible))
    }

    @Test("A canvas with nothing in it renders without crashing")
    func rendersEmptyTree() throws {
        let empty = FileNode.directory(url: URL(fileURLWithPath: "/empty"), children: [])
        let bitmap = render(empty, size: CGSize(width: 200, height: 150), palette: .detailed)
        #expect(bitmap != nil)
    }

    @Test("A very small canvas renders without crashing")
    func rendersTinyCanvas() throws {
        let bitmap = render(sampleTree(), size: CGSize(width: 24, height: 18), palette: .detailed)
        #expect(bitmap != nil)
    }

    /// Regenerates the picture used in the README.
    ///
    /// Off by default — it writes into the working tree, which a test run has
    /// no business doing unless asked. Run it with:
    ///
    /// ```
    /// DISKOVA_SAMPLE_OUTPUT=$PWD/docs/sample-treemap.png \
    ///   xcodebuild -scheme Diskova -destination 'platform=macOS' test \
    ///   -only-testing:DiskovaTests/TreemapRenderingTests
    /// ```
    @Test(
        "Regenerates the sample image for the README",
        .enabled(if: ProcessInfo.processInfo.environment["DISKOVA_SAMPLE_OUTPUT"] != nil)
    )
    func writeSampleImage() throws {
        let path = try #require(ProcessInfo.processInfo.environment["DISKOVA_SAMPLE_OUTPUT"])
        let bitmap = try #require(render(sampleTree(), size: CGSize(width: 960, height: 600), palette: .detailed))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote sample treemap to \(path)")
    }
}
