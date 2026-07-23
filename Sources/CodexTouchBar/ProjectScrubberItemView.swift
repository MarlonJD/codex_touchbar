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

    static func displayTitle(
        title: String,
        count: Int,
        hasUnread: Bool,
        isSelected: Bool = false
    ) -> String {
        let countedTitle = count > 1 ? "\(title) · \(count)" : title
        let selectedTitle = isSelected ? "▶ \(countedTitle)" : countedTitle
        return hasUnread ? "\(selectedTitle) ●" : selectedTitle
    }

    func configure(
        title: String,
        count: Int,
        hasUnread: Bool = false,
        isSelected: Bool = false,
        isPlaceholder: Bool = false
    ) {
        let displayTitle = Self.displayTitle(
            title: title,
            count: count,
            hasUnread: hasUnread,
            isSelected: isSelected
        )
        let textColor: NSColor
        if isPlaceholder {
            textColor = NSColor.white.withAlphaComponent(0.6)
        } else if isSelected {
            textColor = .systemYellow
        } else if hasUnread {
            textColor = .systemPurple
        } else {
            textColor = .white
        }
        contentView.image = TouchBarImageRenderer.image(
            title: displayTitle,
            symbolName: isPlaceholder ? "pause.circle" : "folder.fill",
            font: .systemFont(ofSize: 12, weight: .medium),
            textColor: textColor
        )
        var accessibilityLabel = displayTitle
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
