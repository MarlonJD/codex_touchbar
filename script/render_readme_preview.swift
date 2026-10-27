import AppKit

/// An illustration with sample data, rendered using the app's image renderer.
@main
struct ReadmePreview {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let size = NSSize(width: 740, height: 54)
        let scale = 2.0
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()

        func draw(_ image: NSImage, at x: CGFloat) {
            image.draw(at: NSPoint(x: x, y: (size.height - image.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
        var x = 12.0
        for (title, symbol, selected, unread) in [
            ("Workspace · 2", "folder.fill", true, false),
            ("Remote", "desktopcomputer", false, true),
        ] {
            let image = TouchBarImageRenderer.image(
                title: title,
                symbolName: symbol,
                font: .systemFont(ofSize: 12, weight: .medium),
                trailingDotColor: unread ? .systemPurple : nil
            )
            let width = image.size.width + 16
            if selected {
                NSColor.white.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 12, width: width, height: 30),
                             xRadius: 6, yRadius: 6).fill()
            }
            draw(image, at: x + 8)
            x += width + 4
        }

        let settings = [
            ("70%", "calendar"),
            ("GPT-6 Astra Max", "brain.head.profile"),
            ("1x", "speedometer"),
        ].map { TouchBarImageRenderer.image(title: $0.0, symbolName: $0.1) }
        let gap = 22.0
        x = size.width - 18 - settings.reduce(0) { $0 + $1.size.width } - gap * 2
        for image in settings {
            draw(image, at: x)
            x += image.size.width + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output)
        print(output.path)
    }
}
