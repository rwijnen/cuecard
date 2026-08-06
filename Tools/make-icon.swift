#!/usr/bin/env swift
//
// Renders Cuecard's app icon into an .iconset directory, which build.sh feeds to
// iconutil. Generated rather than committed as binaries so the artwork stays diffable.
//
//   swift Tools/make-icon.swift build/AppIcon.iconset
//
// The mark is abstract rather than literal: a faceted shard, with a lighter sliver trailing
// it for "and then the next one".
//
// It sits on a plate the icon draws itself. A plate-less, transparent icon was tried first —
// the standalone look of icons like Obsidian's — but macOS 26 wraps any such icon in an
// auto-generated light grey plate, which put the mark on a washed-out background nobody
// designed. Drawing the plate deliberately is the only way to control how it looks.
//
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(64)
}
let outputDirectory = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: - Geometry

/// Normalised coordinates, y up, so the artwork is resolution-independent and every size
/// is rendered from the same description rather than scaled from a bitmap.
struct Shape {
    var points: [CGPoint]
    var radius: CGFloat
}

/// The shard: an asymmetric kite pointing right. A plain triangle read as a literal play
/// button; the extra vertex and the asymmetry make it a shape in its own right while
/// keeping the forward lean that suggests playback.
let shardTop = CGPoint(x: 0.290, y: 0.860)
let shardRight = CGPoint(x: 0.750, y: 0.520)
let shardBottom = CGPoint(x: 0.250, y: 0.160)
let shardLeft = CGPoint(x: 0.110, y: 0.500)

let shard = Shape(
    points: [shardTop, shardRight, shardBottom, shardLeft],
    radius: 0.050
)

/// The trailing mark. A plain convex sliver — the concave chevron this replaced collapsed
/// into a blob once its corners were rounded, because the radius exceeded the width of its
/// own notch.
let echo = Shape(
    points: [
        CGPoint(x: 0.792, y: 0.700),
        CGPoint(x: 0.918, y: 0.520),
        CGPoint(x: 0.792, y: 0.340),
    ],
    radius: 0.032
)

/// Where the three facets meet. Off-centre in *both* axes on purpose: with it on the
/// vertical midline the facet edges came out horizontal and the shape read as two stacked
/// colours rather than a cut stone.
let core = CGPoint(x: 0.368, y: 0.585)

/// Maps a normalised point into a target rect, so the mark can be placed inside the plate
/// rather than filling the whole canvas.
func place(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
}

/// Rounded-corner polygon, built from tangent arcs. Starting partway along an edge rather
/// than at a vertex is what lets the first corner round like all the others.
func roundedPath(_ shape: Shape, in rect: CGRect) -> NSBezierPath {
    let points = shape.points.map { place($0, in: rect) }
    let radius = shape.radius * rect.width
    let path = NSBezierPath()
    guard points.count >= 3 else { return path }

    let last = points[points.count - 1]
    path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
    for index in points.indices {
        path.appendArc(
            from: points[index],
            to: points[(index + 1) % points.count],
            radius: radius
        )
    }
    path.close()
    return path
}

func polygon(_ points: [CGPoint], in rect: CGRect) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: place(first, in: rect))
    for point in points.dropFirst() {
        path.line(to: place(point, in: rect))
    }
    path.close()
    return path
}

// MARK: - Palette

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Hue shifts between facets, not just brightness — a purely monochrome split reads as a
// flat shadow rather than planes catching different light. Three facets, lit from upper
// left, kept bright so they carry against the dark plate.
let facetLit = [srgb(0x9C_FFCE), srgb(0x45_E89A)]
let facetMid = [srgb(0x36_D98C), srgb(0x18_A468)]
let facetShade = [srgb(0x1B_9F6B), srgb(0x0A_6547)]

// A deep plate rather than a bright one: it makes the mark read as something luminous set
// into a dark stone, and keeps the icon distinguishable from Spotify's own green tile.
let plateBackground = [srgb(0x10_3A2B), srgb(0x04_1310)]

// MARK: - Drawing

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: CGSize(width: size, height: size))
    image.lockFocusFlipped(false)
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current else { return image }
    context.imageInterpolation = .high

    // macOS app icons are inset from their canvas; matching that keeps Cuecard the same
    // visual weight as its neighbours in the Dock.
    let plate = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.055, dy: size * 0.055)
    let corner = plate.width * 0.235
    let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

    context.saveGraphicsState()
    platePath.addClip()
    NSGradient(colors: plateBackground)?.draw(in: plate, angle: -78)
    // A soft glow behind the mark, so the plate is not a flat slab.
    NSGradient(colors: [srgb(0x2E_C888, alpha: 0.30), srgb(0x2E_C888, alpha: 0)])?.draw(
        in: plate.insetBy(dx: -plate.width * 0.1, dy: -plate.height * 0.1),
        relativeCenterPosition: CGPoint(x: -0.15, y: 0.25)
    )
    context.restoreGraphicsState()

    // The mark, inset within the plate so it has proper margins.
    let mark = plate.insetBy(dx: plate.width * 0.085, dy: plate.height * 0.085)

    // Base fill, over which the facets are drawn.
    srgb(0x24_C07E).setFill()
    roundedPath(shard, in: mark).fill()

    // Facets are drawn clipped to the rounded silhouette: their shared edges stay crisp
    // straight lines while their outer edges pick up the rounding for free.
    // Angles differ per facet so each plane appears to catch the light separately.
    let facets: [(points: [CGPoint], colors: [NSColor], angle: CGFloat)] = [
        ([shardLeft, shardTop, core], facetLit, -50),
        ([shardTop, shardRight, core], facetMid, -75),
        ([shardLeft, core, shardRight, shardBottom], facetShade, -100),
    ]
    for facet in facets {
        context.saveGraphicsState()
        roundedPath(shard, in: mark).addClip()
        let path = polygon(facet.points, in: mark)
        path.addClip()
        NSGradient(colors: facet.colors)?.draw(in: path.bounds, angle: facet.angle)
        context.restoreGraphicsState()
    }

    // Highlight along the two upper edges, clipped to the silhouette so it cannot leak
    // outside. Skipped below 64px, where a hairline turns into grey mush.
    if size >= 64 {
        context.saveGraphicsState()
        roundedPath(shard, in: mark).addClip()
        let edge = NSBezierPath()
        edge.move(to: place(shardLeft, in: mark))
        edge.line(to: place(shardTop, in: mark))
        edge.line(to: place(shardRight, in: mark))
        edge.lineWidth = mark.width * 0.022
        edge.lineJoinStyle = .round
        edge.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.28).setStroke()
        edge.stroke()
        context.restoreGraphicsState()
    }

    // The echo: same family, lighter and semi-transparent so it reads as the next thing
    // rather than a second equal element.
    srgb(0x7C_F5B8, alpha: 0.88).setFill()
    roundedPath(echo, in: mark).fill()

    return image
}

/// The ten entries `iconutil` expects. Missing any one makes it refuse the set.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let image = draw(size: CGFloat(variant.pixels))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("could not render \(variant.name)\n".utf8))
        exit(1)
    }
    try png.write(to: outputDirectory.appendingPathComponent("\(variant.name).png"))
}

print("wrote \(variants.count) images to \(outputDirectory.path)")
