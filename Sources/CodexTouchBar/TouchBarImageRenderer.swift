import AppKit

@MainActor
enum TouchBarImageRenderer {
    static func image(
        title: String,
        symbolName: String? = nil,
        font: NSFont = .systemFont(ofSize: 13, weight: .medium),
        textColor: NSColor = .white,
        trailingDotColor: NSColor? = nil
    ) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let symbolSize = NSSize(width: 16, height: 16)
        let symbolSpacing: CGFloat = symbolName == nil ? 0 : 6
        let indicatorDiameter: CGFloat = 7
        let indicatorSpacing: CGFloat = trailingDotColor == nil ? 0 : 6
        let width = ceil(textSize.width)
            + (symbolName == nil ? 0 : symbolSize.width + symbolSpacing)
            + (trailingDotColor == nil ? 0 : indicatorSpacing + indicatorDiameter)
        let height = max(18, ceil(textSize.height))
        let size = NSSize(width: max(width, 1), height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            var textX: CGFloat = 0
            if let symbolName,
               let symbol = NSImage(
                   systemSymbolName: symbolName,
                   accessibilityDescription: title
               )?.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                       .applying(NSImage.SymbolConfiguration(paletteColors: [textColor]))
               ) {
                symbol.draw(
                    in: NSRect(
                        x: 0,
                        y: floor((rect.height - symbolSize.height) / 2),
                        width: symbolSize.width,
                        height: symbolSize.height
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                textX = symbolSize.width + symbolSpacing
            }

            (title as NSString).draw(
                at: NSPoint(x: textX, y: floor((rect.height - textSize.height) / 2)),
                withAttributes: attributes
            )
            if let trailingDotColor {
                trailingDotColor.setFill()
                NSBezierPath(
                    ovalIn: NSRect(
                        x: textX + ceil(textSize.width) + indicatorSpacing,
                        y: floor((rect.height - indicatorDiameter) / 2),
                        width: indicatorDiameter,
                        height: indicatorDiameter
                    )
                ).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
