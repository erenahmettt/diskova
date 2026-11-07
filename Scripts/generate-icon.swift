#!/usr/bin/env swift
//
//  generate-icon.swift
//
//  Draws Diskova's app icon and writes every size the asset catalogue asks for.
//
//  The icon is generated rather than committed as binary blobs so that changing
//  it is a code review rather than a "trust me" pull request — and so the ten
//  PNGs can never drift out of sync with each other.
//
//  Usage:
//      swift Scripts/generate-icon.swift [output-directory]
//
//  Defaults to Diskova/Resources/Assets.xcassets/AppIcon.appiconset.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Design

/// Fractions of the full canvas, following Apple's macOS icon grid: the rounded
/// square sits inside a ~10% margin so icons of different shapes still look the
/// same size next to each other in the Dock.
private enum Design {
    static let squareInset = 0.0977
    static let cornerRatio = 0.2247
    /// Padding between the rounded square and the blocks inside it.
    static let contentInset = 0.085

    static let backgroundTop = (r: 0.212, g: 0.235, b: 0.267)
    static let backgroundBottom = (r: 0.098, g: 0.110, b: 0.129)

    /// The four hues of Diskova's colour-blind-safe palette, so the icon is
    /// made of the same colours the app actually draws with.
    static let blue = (r: 0.165, g: 0.471, b: 0.839)
    static let yellow = (r: 0.929, g: 0.631, b: 0.000)
    static let magenta = (r: 0.910, g: 0.482, b: 0.643)
    static let green = (r: 0.000, g: 0.514, b: 0.000)

    /// A miniature treemap: one dominant block and three smaller ones. Kept to
    /// four blocks because the icon has to survive being drawn at 16 points.
    /// Coordinates are fractions of the content area, with the origin top-left.
    static let blocks: [(x: Double, y: Double, w: Double, h: Double, color: (r: Double, g: Double, b: Double))] = [
        (0.000, 0.000, 0.560, 1.000, blue),
        (0.605, 0.000, 0.395, 0.455, yellow),
        (0.605, 0.500, 0.395, 0.215, magenta),
        (0.605, 0.760, 0.395, 0.240, green),
    ]
}

// MARK: - Drawing

private func makeIcon(pixelSize: Int) -> CGImage? {
    let size = Double(pixelSize)
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Work in top-left origin coordinates, like every other drawing API here.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let inset = size * Design.squareInset
    let squareSide = size - inset * 2
    let square = CGRect(x: inset, y: inset, width: squareSide, height: squareSide)
    let squarePath = CGPath(
        roundedRect: square,
        cornerWidth: squareSide * Design.cornerRatio,
        cornerHeight: squareSide * Design.cornerRatio,
        transform: nil
    )

    // Background: a vertical gradient, dark enough that the blocks read clearly
    // against both a light and a dark Dock.
    context.saveGState()
    context.addPath(squarePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(srgbRed: Design.backgroundTop.r, green: Design.backgroundTop.g, blue: Design.backgroundTop.b, alpha: 1),
            CGColor(srgbRed: Design.backgroundBottom.r, green: Design.backgroundBottom.g, blue: Design.backgroundBottom.b, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: square.midX, y: square.minY),
        end: CGPoint(x: square.midX, y: square.maxY),
        options: []
    )
    context.restoreGState()

    // The blocks.
    let contentInset = squareSide * Design.contentInset
    let content = square.insetBy(dx: contentInset, dy: contentInset)
    let blockCorner = min(content.width, content.height) * 0.055

    for block in Design.blocks {
        let rect = CGRect(
            x: content.minX + content.width * block.x,
            y: content.minY + content.height * block.y,
            width: content.width * block.w,
            height: content.height * block.h
        )
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: blockCorner,
            cornerHeight: blockCorner,
            transform: nil
        ))
        context.setFillColor(CGColor(srgbRed: block.color.r, green: block.color.g, blue: block.color.b, alpha: 1))
        context.fillPath()
    }

    // A hairline highlight along the top edge, which is what keeps the icon
    // from looking like a flat sticker at large sizes.
    context.saveGState()
    context.addPath(squarePath)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    context.setLineWidth(max(1, size * 0.004))
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

private func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw IconError.cannotWrite(url)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.cannotWrite(url)
    }
}

enum IconError: Error, CustomStringConvertible {
    case cannotRender(Int)
    case cannotWrite(URL)

    var description: String {
        switch self {
        case .cannotRender(let size): "Could not render the icon at \(size)px."
        case .cannotWrite(let url): "Could not write \(url.path)."
        }
    }
}

// MARK: - Entry point

/// The ten files a macOS app icon set is made of: five point sizes at 1× and 2×.
private let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "Diskova/Resources/Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// Render each pixel size once, even though some are used by two entries.
var rendered: [Int: CGImage] = [:]
for variant in variants {
    let image: CGImage
    if let cached = rendered[variant.pixels] {
        image = cached
    } else {
        guard let fresh = makeIcon(pixelSize: variant.pixels) else {
            throw IconError.cannotRender(variant.pixels)
        }
        rendered[variant.pixels] = fresh
        image = fresh
    }
    try write(image, to: outputDirectory.appending(path: variant.name))
    print("wrote \(variant.name) (\(variant.pixels)×\(variant.pixels))")
}
