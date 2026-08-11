import AppKit
import SwiftUI

struct BatteryLogoView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppIconImageProvider.image(size: size))
            .resizable()
            .interpolation(.high)
        .frame(width: size, height: size)
    }
}

struct StatusBarUPSIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: StatusBarUPSIconRenderer.image(width: size * 1.6, height: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size * 1.6, height: size)
    }
}

struct StatusBarUPSImageView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(nsImage: StatusBarUPSIconRenderer.image(width: width, height: height))
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
    }
}

enum StatusBarUPSIconRenderer {
    static func image(width: CGFloat, height: CGFloat) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = CGSize(width: width * scale, height: height * scale)
        let image = NSImage(size: pixelSize)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: pixelSize).fill()

        let bounds = CGRect(origin: .zero, size: pixelSize)
        if let template = sourceTemplateImage() {
            template.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        } else {
            let unit = min(pixelSize.width / 1.6, pixelSize.height)
            let fallbackBounds = CGRect(
                x: bounds.midX - unit * 0.8,
                y: bounds.midY - unit * 0.5,
                width: unit * 1.6,
                height: unit
            )
            drawGraceDownLetters(in: fallbackBounds, unit: unit)
            drawWaveform(in: fallbackBounds, unit: unit)
        }

        image.unlockFocus()
        image.size = CGSize(width: width, height: height)
        image.isTemplate = true
        return image
    }

    private static func sourceTemplateImage() -> NSImage? {
        for url in candidateTemplateURLs() {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                return image
            }
        }

        return nil
    }

    private static func candidateTemplateURLs() -> [URL] {
        var urls: [URL] = []

        if let bundledURL = Bundle.main.url(forResource: "StatusBarIconTemplate", withExtension: "png") {
            urls.append(bundledURL)
        }

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(rootURL.appendingPathComponent("Resources/StatusBarIconTemplate.png"))

        return urls
    }

    private static func drawGraceDownLetters(in bounds: CGRect, unit: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: unit * 0.46, weight: .heavy),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        NSString(string: "GD").draw(
            in: CGRect(
                x: bounds.minX + unit * 0.02,
                y: bounds.minY + unit * 0.36,
                width: unit * 0.96,
                height: unit * 0.46
            ),
            withAttributes: attributes
        )
    }

    private static func drawWaveform(in bounds: CGRect, unit: CGFloat) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX + unit * 0.11, y: bounds.minY + unit * 0.27))
        path.line(to: CGPoint(x: bounds.minX + unit * 0.35, y: bounds.minY + unit * 0.27))
        path.line(to: CGPoint(x: bounds.minX + unit * 0.43, y: bounds.minY + unit * 0.21))
        path.line(to: CGPoint(x: bounds.minX + unit * 0.51, y: bounds.minY + unit * 0.39))
        path.line(to: CGPoint(x: bounds.minX + unit * 0.61, y: bounds.minY + unit * 0.16))
        path.line(to: CGPoint(x: bounds.minX + unit * 0.70, y: bounds.minY + unit * 0.31))
        path.line(to: CGPoint(x: bounds.minX + unit * 0.78, y: bounds.minY + unit * 0.27))

        path.lineWidth = max(1.6, unit * 0.065)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()

        NSColor.black.setFill()
        NSBezierPath(
            ovalIn: CGRect(
                x: bounds.minX + unit * 0.83,
                y: bounds.minY + unit * 0.225,
                width: unit * 0.09,
                height: unit * 0.09
            )
        ).fill()
    }
}

private enum AppIconImageProvider {
    static func image(size: CGFloat) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = CGSize(width: size * scale, height: size * scale)
        let output = NSImage(size: pixelSize)

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: pixelSize).fill()

        if let image = sourceImage() {
            image.draw(
                in: CGRect(origin: .zero, size: pixelSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        } else {
            StatusBarUPSIconRenderer.image(width: size, height: size).draw(
                in: CGRect(origin: .zero, size: pixelSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        output.unlockFocus()
        output.size = CGSize(width: size, height: size)
        output.isTemplate = false
        return output
    }

    private static func sourceImage() -> NSImage? {
        for url in candidateURLs() {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let bundleIconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            urls.append(bundleIconURL)
        }

        if let bundlePNGURL = Bundle.main.url(forResource: "AppIcon-1024", withExtension: "png") {
            urls.append(bundlePNGURL)
        }

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(rootURL.appendingPathComponent("Resources/AppIcon.icns"))
        urls.append(rootURL.appendingPathComponent("Resources/AppIcon-1024.png"))

        return urls
    }
}
