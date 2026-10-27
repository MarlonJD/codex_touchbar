import AppKit
import CodexTouchBarCore

@MainActor
enum TouchBarControlStyle {
    static let backgroundColor = NSColor.white.withAlphaComponent(0.2)
    static let cornerRadius: CGFloat = 6
    static let navigationBackgroundColor = NSColor(srgbRed: 70 / 255, green: 70 / 255, blue: 70 / 255, alpha: 1)

    static func makeNavigationButton(
        symbolName: String,
        accessibilityLabel: String,
        target: AnyObject?,
        action: Selector?
    ) -> NSButton {
        let size = NSSize(
            width: TouchBarProjectStripMetrics.navigationButtonWidth,
            height: TouchBarProjectStripMetrics.navigationButtonHeight
        )
        let pointsRight = symbolName == "chevron.forward"
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            let outerX: CGFloat = pointsRight ? 5.5 : 11
            let innerX: CGFloat = pointsRight ? 11 : 5.5
            path.move(to: NSPoint(x: outerX, y: 7))
            path.line(to: NSPoint(x: innerX, y: 15))
            path.line(to: NSPoint(x: outerX, y: 23))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = false
        let button = NSButton(image: image, target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.backgroundColor = navigationBackgroundColor.cgColor
        button.layer?.cornerRadius = cornerRadius
        button.layer?.maskedCorners = pointsRight
            ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        button.layer?.masksToBounds = true
        button.setAccessibilityLabel(accessibilityLabel)
        button.widthAnchor.constraint(
            equalToConstant: CGFloat(TouchBarProjectStripMetrics.navigationButtonWidth)
        ).isActive = true
        button.heightAnchor.constraint(equalToConstant: size.height).isActive = true
        return button
    }
}
