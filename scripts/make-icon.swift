#!/usr/bin/env swift
//
// Builds Resources/AppIcon.icns from Resources/bee.png.
//
// The artwork has a transparent background, and an app icon that is only a
// cut-out reads as a stray sticker in the Dock, so it is drawn centred on the
// rounded square macOS expects.
//
// Run from the repository root: swift scripts/make-icon.swift
//
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/bee.png")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

guard let artwork = NSImage(contentsOf: source) else {
    fatalError("cannot read \(source.path)")
}

let background = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
/// Apple's rounded square is a little over a fifth of the icon's width, and the
/// artwork sits inside a margin so nothing touches the corners.
let cornerFraction = 0.2237
let marginFraction = 0.11

func draw(size: Int) -> Data {
    let side = CGFloat(size)
    // The bitmap is made at an exact pixel count, because a Retina display
    // would otherwise hand back a canvas of twice the size asked for.
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("cannot allocate \(size)px bitmap")
    }
    bitmap.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let radius = side * cornerFraction
    let shape = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
                             xRadius: radius, yRadius: radius)
    background.setFill()
    shape.fill()

    let margin = side * marginFraction
    let available = side - margin * 2
    let ratio = artwork.size.width / artwork.size.height
    let width = ratio >= 1 ? available : available * ratio
    let height = ratio >= 1 ? available / ratio : available
    artwork.draw(in: NSRect(x: (side - width) / 2, y: (side - height) / 2,
                            width: width, height: height))

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("cannot render \(size)px")
    }
    return png
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try draw(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

print("wrote \(output.path)")
