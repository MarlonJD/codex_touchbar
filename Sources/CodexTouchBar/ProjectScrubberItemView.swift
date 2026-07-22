import AppKit

@MainActor
final class ProjectScrubberItemView: NSScrubberItemView {
    private let contentView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(title: String, count: Int, isPlaceholder: Bool = false) {
        let displayTitle = count > 1 ? "\(title) · \(count)" : title
        contentView.image = TouchBarImageRenderer.image(
            title: displayTitle,
            symbolName: isPlaceholder ? "pause.circle" : "folder.fill",
            font: .systemFont(ofSize: 12, weight: .medium),
            textColor: isPlaceholder ? NSColor.white.withAlphaComponent(0.6) : .white
        )
        setAccessibilityLabel(displayTitle)
    }

    private func configureView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.imageScaling = .scaleProportionallyDown
        contentView.imageAlignment = .alignLeft
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}
