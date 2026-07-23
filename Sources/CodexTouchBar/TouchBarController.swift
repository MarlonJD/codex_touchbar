@preconcurrency import AppKit
import CodexTouchBarCore
import PrivateTouchBar

@MainActor
final class TouchBarController: NSObject {
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.marlonjd.CodexTouchBar.projects")
    private static let projectsItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.projects.item")
    private static let expandProjectsItemIdentifier = NSTouchBarItem.Identifier(
        "dev.marlonjd.CodexTouchBar.projects.expand"
    )
    private static let collapseProjectsItemIdentifier = NSTouchBarItem.Identifier(
        "dev.marlonjd.CodexTouchBar.projects.collapse"
    )
    private static let trayItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.tray")
    private static let scrubberItemIdentifier = NSUserInterfaceItemIdentifier("dev.marlonjd.CodexTouchBar.project-cell")
    private static let weeklyLimitItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.weekly-limit")
    private static let effortItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.effort")
    private static let speedItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.speed")
    private static let backItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.settings.back")

    var onProjectSelected: ((ProjectGroup) -> Void)?
    var onEffortSelected: ((EffortChoice) -> Void)?
    var onSpeedSelected: ((SpeedChoice) -> Void)?

    private(set) var isAvailable = false
    private(set) var isPresented = false
    private var groups: [ProjectGroup] = []
    private let touchBar = NSTouchBar()
    private let scrubber = NSScrubber()
    private let trayItem: NSCustomTouchBarItem
    private var trayItemWasAdded = false
    private var layoutState = TouchBarLayoutState()
    private var weeklyLimit: WeeklyLimitUsage?
    private var projectStripWidthConstraint: NSLayoutConstraint?
    private var settingSelections: [NSTouchBarItem.Identifier: SettingSelection] = [:]
    private lazy var weeklyLimitButton = makeWeeklyLimitButton()
    private lazy var effortButton = makeMainSettingButton(
        title: effortTitle,
        symbolName: "brain.head.profile",
        action: #selector(showEffortOptions)
    )
    private lazy var speedButton = makeMainSettingButton(
        title: speedTitle,
        symbolName: "speedometer",
        action: #selector(showSpeedOptions)
    )

    private enum SettingSelection {
        case effort(EffortChoice)
        case speed(SpeedChoice)
    }

    override init() {
        let trayIdentifier = Self.trayItemIdentifier
        let item = NSCustomTouchBarItem(identifier: trayIdentifier)
        let button = NSButton(
            image: NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex Touch Bar") ?? NSImage(),
            target: nil,
            action: nil
        )
        button.bezelStyle = .texturedRounded
        item.view = button
        trayItem = item

        super.init()

        button.target = self
        button.action = #selector(showFromTray)
        configureTouchBar()
    }

    deinit {
        MainActor.assumeIsolated {
            if isPresented {
                CTBDismissSystemModalTouchBar(touchBar)
                CTBSetCloseBoxVisible(true)
            }
            if trayItemWasAdded {
                CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
                CTBRemoveSystemTrayItem(trayItem)
            }
        }
    }

    func update(groups: [ProjectGroup]) {
        self.groups = groups
        scrubber.reloadData()
        scrubber.selectedIndex = groups.firstIndex(where: \.isSelected) ?? -1
        if groups.first?.hasUnread == true || groups.first?.isSelected == true {
            DispatchQueue.main.async { [weak self] in
                self?.scrubber.scrollItem(at: 0, to: .leading)
            }
        }
        enforceCloseBoxVisibility()
    }

    func showSelectedEffort(_ choice: EffortChoice) {
        let selectedTitle = "\(effortTitle): \(choice.title)"
        effortButton.image = TouchBarImageRenderer.image(
            title: TouchBarSettingTitle.mainTitle(
                baseTitle: effortTitle,
                selectedTitle: choice.title
            ),
            symbolName: "brain.head.profile"
        )
        effortButton.setAccessibilityLabel(selectedTitle)
    }

    func showWeeklyLimit(_ usage: WeeklyLimitUsage?) {
        let visibilityChanged = (weeklyLimit == nil) != (usage == nil)
        weeklyLimit = usage
        updateProjectStripWidth()

        if let usage {
            let title = weeklyLimitTitle(remainingPercent: usage.remainingPercent)
            weeklyLimitButton.image = TouchBarImageRenderer.image(
                title: title,
                symbolName: "calendar"
            )
            weeklyLimitButton.setAccessibilityLabel(weeklyLimitAccessibilityLabel(
                remainingPercent: usage.remainingPercent
            ))
        }

        if visibilityChanged, layoutState.mode == .projects {
            updateVisibleItems()
        }
    }

    func showSelectedSpeed(_ choice: SpeedChoice) {
        let selectedTitle = "\(speedTitle): \(choice.title)"
        speedButton.image = TouchBarImageRenderer.image(
            title: TouchBarSettingTitle.mainTitle(
                baseTitle: speedTitle,
                selectedTitle: choice.title
            ),
            symbolName: "speedometer"
        )
        speedButton.setAccessibilityLabel(selectedTitle)
    }

    @discardableResult
    func present() -> Bool {
        if isPresented {
            enforceCloseBoxVisibility()
            return true
        }
        guard isAvailable else {
            return false
        }
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, true)
        }
        CTBSetCloseBoxVisible(layoutState.showsSystemCloseBox)
        isPresented = CTBPresentSystemModalTouchBar(touchBar, Self.trayItemIdentifier.rawValue)
        CTBSetCloseBoxVisible(
            layoutState.closeBoxVisibility(afterPresentationSucceeded: isPresented)
        )
        enforceCloseBoxVisibility()
        if !isPresented {
            if trayItemWasAdded {
                CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
            }
        }
        return isPresented
    }

    func dismiss() {
        guard isPresented else {
            return
        }
        CTBDismissSystemModalTouchBar(touchBar)
        CTBSetCloseBoxVisible(true)
        isPresented = false
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    private func configureTouchBar() {
        isAvailable = CTBPrivateTouchBarIsAvailable()
        guard isAvailable else {
            return
        }

        touchBar.customizationIdentifier = Self.barIdentifier
        touchBar.delegate = self
        registerSettingSelections()
        updateVisibleItems()

        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = CGFloat(TouchBarProjectStripMetrics.itemSpacing)
        layout.itemSize = NSSize(width: 120, height: 30)
        scrubber.scrubberLayout = layout
        scrubber.mode = .free
        scrubber.itemAlignment = .none
        scrubber.isContinuous = false
        scrubber.showsArrowButtons = false
        scrubber.showsAdditionalContentIndicators = true
        scrubber.selectionBackgroundStyle = nil
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.register(ProjectScrubberItemView.self, forItemIdentifier: Self.scrubberItemIdentifier)
        scrubber.frame = NSRect(
            x: 0,
            y: 0,
            width: projectStripWidth,
            height: 30
        )
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        let projectStripWidthConstraint = scrubber.widthAnchor.constraint(
            equalToConstant: projectStripWidth
        )
        self.projectStripWidthConstraint = projectStripWidthConstraint
        NSLayoutConstraint.activate([
            projectStripWidthConstraint,
            scrubber.heightAnchor.constraint(equalToConstant: 30),
        ])
        scrubber.setAccessibilityLabel("Active Codex projects")

        CTBSetCloseBoxVisible(layoutState.showsSystemCloseBox)
        trayItemWasAdded = CTBAddSystemTrayItem(trayItem)
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    @objc private func showFromTray() {
        _ = present()
    }

    @objc private func showEffortOptions() {
        layoutState.show(.effort)
        updateVisibleItems()
    }

    @objc private func showSpeedOptions() {
        layoutState.show(.speed)
        updateVisibleItems()
    }

    @objc private func showExpandedProjects() {
        layoutState.expandProjects()
        updateVisibleItems()
    }

    @objc private func hideExpandedProjects() {
        layoutState.collapseProjects()
        updateVisibleItems()
    }

    @objc private func cancelSettingSelection() {
        layoutState.cancel()
        updateVisibleItems()
    }

    @objc private func settingOptionPressed(_ sender: NSButton) {
        guard let rawIdentifier = sender.identifier?.rawValue,
              let selection = settingSelections[NSTouchBarItem.Identifier(rawIdentifier)] else {
            return
        }

        switch selection {
        case let .effort(choice):
            layoutState.completeSelection()
            updateVisibleItems()
            onEffortSelected?(choice)
        case let .speed(choice):
            layoutState.completeSelection()
            updateVisibleItems()
            onSpeedSelected?(choice)
        }
    }

    private var effortTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "Çaba" : "Effort"
    }

    private var speedTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "Hız" : "Speed"
    }

    private var backTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "Geri" : "Back"
    }

    private var expandProjectsTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true
            ? "Projeleri genişlet"
            : "Expand projects"
    }

    private var collapseProjectsTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true
            ? "Projeleri daralt"
            : "Collapse projects"
    }

    private var projectStripWidth: CGFloat {
        CGFloat(TouchBarProjectStripMetrics.width(
            for: layoutState.mode,
            hasWeeklyLimit: weeklyLimit != nil
        ))
    }

    private func weeklyLimitTitle(remainingPercent: Int) -> String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true
            ? "%\(remainingPercent) kaldı"
            : "\(remainingPercent)% left"
    }

    private func weeklyLimitAccessibilityLabel(remainingPercent: Int) -> String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true
            ? "Haftalık limitin yüzde \(remainingPercent) kadarı kaldı"
            : "\(remainingPercent) percent of weekly limit remaining"
    }

    private func makeWeeklyLimitButton() -> NSButton {
        let button = NSButton(image: NSImage(), target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        return button
    }

    private func makeMainSettingButton(title: String, symbolName: String, action: Selector) -> NSButton {
        let image = TouchBarImageRenderer.image(title: title, symbolName: symbolName)
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(title)
        return button
    }

    private func registerSettingSelections() {
        for (index, choice) in EffortChoice.allCases.enumerated() {
            settingSelections[settingIdentifier(prefix: "effort", index: index)] = .effort(choice)
        }
        for (index, choice) in SpeedChoice.allCases.enumerated() {
            settingSelections[settingIdentifier(prefix: "speed", index: index)] = .speed(choice)
        }
    }

    private func updateVisibleItems() {
        updateProjectStripWidth()
        switch layoutState.mode {
        case .projects:
            var identifiers: [NSTouchBarItem.Identifier] = [
                Self.projectsItemIdentifier,
                Self.expandProjectsItemIdentifier,
                .flexibleSpace,
            ]
            if weeklyLimit != nil {
                identifiers.append(Self.weeklyLimitItemIdentifier)
            }
            identifiers.append(contentsOf: [
                Self.effortItemIdentifier,
                Self.speedItemIdentifier,
            ])
            touchBar.defaultItemIdentifiers = identifiers
        case .expandedProjects:
            touchBar.defaultItemIdentifiers = [
                Self.projectsItemIdentifier,
                .flexibleSpace,
                Self.collapseProjectsItemIdentifier,
            ]
        case .setting(.effort):
            touchBar.defaultItemIdentifiers = [Self.backItemIdentifier]
                + EffortChoice.allCases.indices.map { settingIdentifier(prefix: "effort", index: $0) }
        case .setting(.speed):
            touchBar.defaultItemIdentifiers = [
                Self.backItemIdentifier,
                .flexibleSpace,
            ]
                + SpeedChoice.allCases.indices.map { settingIdentifier(prefix: "speed", index: $0) }
                + [.flexibleSpace]
        }
        enforceCloseBoxVisibility()
    }

    private func updateProjectStripWidth() {
        projectStripWidthConstraint?.constant = projectStripWidth
    }

    private func settingIdentifier(prefix: String, index: Int) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.\(prefix).\(index)")
    }

    private func enforceCloseBoxVisibility() {
        guard isPresented else {
            return
        }
        CTBSetCloseBoxVisible(layoutState.showsSystemCloseBox)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else {
                return
            }
            CTBSetCloseBoxVisible(self.layoutState.showsSystemCloseBox)
        }
    }
}

@MainActor
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.projectsItemIdentifier else {
            if identifier == Self.expandProjectsItemIdentifier {
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.customizationLabel = expandProjectsTitle
                item.view = TouchBarControlStyle.makeNavigationButton(
                    symbolName: "chevron.forward",
                    accessibilityLabel: expandProjectsTitle,
                    target: self,
                    action: #selector(showExpandedProjects)
                )
                return item
            }
            if identifier == Self.collapseProjectsItemIdentifier {
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.customizationLabel = collapseProjectsTitle
                item.view = TouchBarControlStyle.makeNavigationButton(
                    symbolName: "chevron.backward",
                    accessibilityLabel: collapseProjectsTitle,
                    target: self,
                    action: #selector(hideExpandedProjects)
                )
                return item
            }
            if identifier == Self.weeklyLimitItemIdentifier {
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.customizationLabel = "Weekly Limit"
                item.view = weeklyLimitButton
                return item
            }
            if identifier == Self.effortItemIdentifier {
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.customizationLabel = effortTitle
                item.view = effortButton
                return item
            }
            if identifier == Self.speedItemIdentifier {
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.customizationLabel = speedTitle
                item.view = speedButton
                return item
            }
            if identifier == Self.backItemIdentifier {
                let item = NSCustomTouchBarItem(identifier: identifier)
                let image = TouchBarImageRenderer.image(
                    title: backTitle,
                    symbolName: "chevron.backward"
                )
                let button = NSButton(image: image, target: self, action: #selector(cancelSettingSelection))
                button.bezelStyle = .texturedRounded
                button.imagePosition = .imageOnly
                button.setAccessibilityLabel(backTitle)
                item.view = button
                return item
            }
            guard let selection = settingSelections[identifier] else {
                return nil
            }

            let title: String
            switch selection {
            case let .effort(choice): title = choice.title
            case let .speed(choice): title = choice.title
            }
            let item = NSCustomTouchBarItem(identifier: identifier)
            let image = TouchBarImageRenderer.image(title: title)
            let button = NSButton(image: image, target: self, action: #selector(settingOptionPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
            button.bezelStyle = .texturedRounded
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(title)
            item.view = button
            return item
        }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Active Codex Projects"
        item.view = scrubber
        return item
    }
}

@MainActor
extension TouchBarController: NSScrubberDataSource, @preconcurrency NSScrubberFlowLayoutDelegate {
    func numberOfItems(for scrubber: NSScrubber) -> Int {
        max(groups.count, 1)
    }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        guard let view = scrubber.makeItem(withIdentifier: Self.scrubberItemIdentifier, owner: nil) as? ProjectScrubberItemView else {
            return NSScrubberItemView()
        }

        if groups.isEmpty {
            view.configure(title: "No active Codex tasks", count: 0, isPlaceholder: true)
        } else {
            let group = groups[index]
            view.configure(
                title: group.displayName(),
                count: group.threads.count,
                hasUnread: group.hasUnread,
                isSelected: group.isSelected
            )
        }
        return view
    }

    func scrubber(
        _ scrubber: NSScrubber,
        layout: NSScrubberFlowLayout,
        sizeForItemAt itemIndex: Int
    ) -> NSSize {
        let title: String
        if groups.isEmpty {
            title = "No active Codex tasks"
        } else {
            let group = groups[itemIndex]
            title = ProjectScrubberItemView.displayTitle(
                title: group.displayName(),
                count: group.threads.count,
                hasUnread: group.hasUnread,
                isSelected: group.isSelected
            )
        }

        let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ]).width
        let unreadIndicatorWidth: CGFloat
        if groups.indices.contains(itemIndex), groups[itemIndex].hasUnread {
            unreadIndicatorWidth = 13
        } else {
            unreadIndicatorWidth = 0
        }
        return NSSize(
            width: min(max(70, ceil(textWidth) + 39 + unreadIndicatorWidth), 190),
            height: 30
        )
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        guard groups.indices.contains(selectedIndex) else {
            scrubber.selectedIndex = -1
            return
        }

        onProjectSelected?(groups[selectedIndex])
    }
}
