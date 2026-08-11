#!/usr/bin/env swift
import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let artworkURL = rootURL.appendingPathComponent("design/icon-reference/app-icon-source.png")
let statusTemplateSourceURL = rootURL.appendingPathComponent("design/icon-reference/statusbar-template.png")
let referenceURL = resourcesURL.appendingPathComponent("AppIconReference.png")
let originalURL = resourcesURL.appendingPathComponent("AppIconOriginal.png")
let sourceURL = resourcesURL.appendingPathComponent("AppIconSource.png")
let previewURL = resourcesURL.appendingPathComponent("AppIcon-1024.png")
let statusBarTemplateURL = resourcesURL.appendingPathComponent("StatusBarIconTemplate.png")
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

let opticalScale: CGFloat = 0.82

try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

guard let artwork = NSImage(contentsOf: artworkURL) else {
    fputs("Missing icon artwork reference: \(artworkURL.path)\n", stderr)
    exit(1)
}

guard FileManager.default.fileExists(atPath: statusTemplateSourceURL.path) else {
    fputs("Missing status bar template reference: \(statusTemplateSourceURL.path)\n", stderr)
    exit(1)
}

func bitmap(pixelSize: Int) throws -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap"])
    }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [.interlaced: false]) else {
        throw NSError(domain: "AppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }

    try data.write(to: url)
}

func renderAppPNG(to url: URL, pixelSize: Int) throws {
    let rep = try bitmap(pixelSize: pixelSize)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "AppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.interpolationQuality = .high
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)

    NSColor.clear.setFill()
    let canvasRect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    canvasRect.fill()

    let inset = CGFloat(pixelSize) * (1 - opticalScale) / 2
    let artworkRect = canvasRect.insetBy(dx: inset, dy: inset)
    artwork.draw(
        in: artworkRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()
    try writePNG(rep, to: url)
}

try renderAppPNG(to: sourceURL, pixelSize: 1024)
try renderAppPNG(to: originalURL, pixelSize: 1024)
try renderAppPNG(to: referenceURL, pixelSize: 1024)
try renderAppPNG(to: previewURL, pixelSize: 1024)
try? FileManager.default.removeItem(at: statusBarTemplateURL)
try FileManager.default.copyItem(at: statusTemplateSourceURL, to: statusBarTemplateURL)

let iconFiles: [(String, Int)] = [
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

for (fileName, pixelSize) in iconFiles {
    try renderAppPNG(to: iconsetURL.appendingPathComponent(fileName), pixelSize: pixelSize)
}

try? FileManager.default.removeItem(at: icnsURL)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus != 0 {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(iconutil.terminationStatus)
}

print("Generated \(icnsURL.path)")
