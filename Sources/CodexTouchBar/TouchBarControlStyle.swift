import AppKit
import CodexTouchBarCore

@MainActor
enum TouchBarControlStyle {
    static let backgroundColor = NSColor.white.withAlphaComponent(0.2)
    static let cornerRadius: CGFloat = 6

    static func makeNavigationButton(
        symbolName: String,
        accessibilityLabel: String,
        target: AnyObject?,
        action: Selector?
    ) -> NSButton {
        let image = TouchBarImageRenderer.image(
            title: "",
            symbolName: symbolName
        )
        let button = NSButton(image: image, target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        button.wantsLayer = true
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.cornerRadius = cornerRadius
        button.layer?.masksToBounds = true
        button.setAccessibilityLabel(accessibilityLabel)
        button.widthAnchor.constraint(
            equalToConstant: CGFloat(TouchBarProjectStripMetrics.navigationButtonWidth)
        ).isActive = true
        return button
    }
}
