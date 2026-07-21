import AppKit

@MainActor
final class ProjectScrubberItemView: NSScrubberItemView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(title: String, count: Int, isPlaceholder: Bool = false) {
        label.stringValue = count > 1 ? "\(title) · \(count)" : title
        label.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor
        iconView.image = NSImage(
            systemSymbolName: isPlaceholder ? "pause.circle" : "folder.fill",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = isPlaceholder ? .secondaryLabelColor : .controlAccentColor
        setAccessibilityLabel(label.stringValue)
    }

    private func configureView() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
