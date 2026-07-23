import AppKit

struct ProjectCellPresentation {
    let title: String
    let textColor: NSColor
    let trailingDotColor: NSColor?
    let backgroundColor: NSColor?
    let cornerRadius: CGFloat
}

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

    static func displayTitle(
        title: String,
        count: Int,
        hasUnread: Bool,
        isSelected: Bool = false
    ) -> String {
        presentation(
            title: title,
            count: count,
            hasUnread: hasUnread,
            isSelected: isSelected,
            isPlaceholder: false
        ).title
    }

    static func presentation(
        title: String,
        count: Int,
        hasUnread: Bool,
        isSelected: Bool,
        isPlaceholder: Bool
    ) -> ProjectCellPresentation {
        ProjectCellPresentation(
            title: count > 1 ? "\(title) · \(count)" : title,
            textColor: isPlaceholder ? NSColor.white.withAlphaComponent(0.6) : .white,
            trailingDotColor: hasUnread && !isPlaceholder ? .systemPurple : nil,
            backgroundColor: isSelected && !isPlaceholder
                ? TouchBarControlStyle.backgroundColor
                : nil,
            cornerRadius: TouchBarControlStyle.cornerRadius
        )
    }

    func configure(
        title: String,
        count: Int,
        hasUnread: Bool = false,
        isSelected: Bool = false,
        isPlaceholder: Bool = false
    ) {
        let presentation = Self.presentation(
            title: title,
            count: count,
            hasUnread: hasUnread,
            isSelected: isSelected,
            isPlaceholder: isPlaceholder
        )
        contentView.image = TouchBarImageRenderer.image(
            title: presentation.title,
            symbolName: isPlaceholder ? "pause.circle" : "folder.fill",
            font: .systemFont(ofSize: 12, weight: .medium),
            textColor: presentation.textColor,
            trailingDotColor: presentation.trailingDotColor
        )
        wantsLayer = true
        layer?.backgroundColor = presentation.backgroundColor?.cgColor
        layer?.cornerRadius = presentation.cornerRadius
        layer?.masksToBounds = true
        var accessibilityLabel = presentation.title
        if isSelected {
            accessibilityLabel += ", current project"
        }
        if hasUnread {
            accessibilityLabel += ", unread result available"
        }
        setAccessibilityLabel(accessibilityLabel)
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
