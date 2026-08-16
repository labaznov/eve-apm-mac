#!/usr/bin/env swift
//
// Builds Resources/MenuBarIcon.png from Resources/bee.png.
//
// A menu bar icon is a template: macOS throws the colour away and tints what is
// opaque, so the artwork is reduced to coverage. Ink is taken from lightness,
// which keeps the bee's body and wings solid and lets its black outlines and
// stripes read as gaps — the same way a filled SF Symbol does.
//
// Run from the repository root: swift scripts/make-menubar-icon.swift
//
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/bee.png")
let output = root.appendingPathComponent("Resources/MenuBarIcon.png")

/// Twice the 18 point menu bar height, so it is crisp on a Retina display.
let side = 36

guard let artwork = NSImage(contentsOf: source),
      let tiff = artwork.tiffRepresentation,
      let art = NSBitmapImageRep(data: tiff) else {
    fatalError("cannot read \(source.path)")
}

let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

let scale = min(Double(side) / Double(art.pixelsWide), Double(side) / Double(art.pixelsHigh))
let drawnWidth = Double(art.pixelsWide) * scale
let drawnHeight = Double(art.pixelsHigh) * scale
let offsetX = (Double(side) - drawnWidth) / 2
let offsetY = (Double(side) - drawnHeight) / 2

for y in 0..<side {
    for x in 0..<side {
        let sourceX = Int((Double(x) - offsetX) / scale)
        let sourceY = Int((Double(y) - offsetY) / scale)
        var ink = 0.0
        if sourceX >= 0, sourceX < art.pixelsWide, sourceY >= 0, sourceY < art.pixelsHigh,
           let colour = art.colorAt(x: sourceX, y: sourceY) {
            let lightness = Double(colour.redComponent) * 0.299
                + Double(colour.greenComponent) * 0.587
                + Double(colour.blueComponent) * 0.114
            ink = Double(colour.alphaComponent) * min(1.0, lightness * 1.25)
        }
        canvas.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: CGFloat(ink)),
                        atX: x, y: y)
    }
}

try canvas.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path)")
