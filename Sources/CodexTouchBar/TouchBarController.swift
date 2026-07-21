@preconcurrency import AppKit
import CodexTouchBarCore
import PrivateTouchBar

@MainActor
final class TouchBarController: NSObject {
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.marlonjd.CodexTouchBar.projects")
    private static let projectsItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.projects.item")
    private static let trayItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.tray")
    private static let scrubberItemIdentifier = NSUserInterfaceItemIdentifier("dev.marlonjd.CodexTouchBar.project-cell")
    private static let effortItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.effort")
    private static let speedItemIdentifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.speed")

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
    private var settingSelections: [NSTouchBarItem.Identifier: SettingSelection] = [:]
    private lazy var effortPopoverItem = makeEffortPopoverItem()
    private lazy var speedPopoverItem = makeSpeedPopoverItem()

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
    }

    func showSelectedEffort(_ choice: EffortChoice) {
        effortPopoverItem.collapsedRepresentationLabel = "\(effortTitle): \(choice.title)"
    }

    func showSelectedSpeed(_ choice: SpeedChoice) {
        speedPopoverItem.collapsedRepresentationLabel = "\(speedTitle): \(choice.title)"
    }

    @discardableResult
    func present() -> Bool {
        if isPresented {
            return true
        }
        guard isAvailable else {
            return false
        }
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, true)
        }
        CTBSetCloseBoxVisible(true)
        isPresented = CTBPresentSystemModalTouchBar(touchBar, Self.trayItemIdentifier.rawValue)
        if !isPresented {
            CTBSetCloseBoxVisible(true)
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
        touchBar.defaultItemIdentifiers = [
            Self.projectsItemIdentifier,
            .flexibleSpace,
            Self.effortItemIdentifier,
            Self.speedItemIdentifier,
        ]

        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = 4
        layout.itemSize = NSSize(width: 120, height: 30)
        scrubber.scrubberLayout = layout
        scrubber.mode = .free
        scrubber.itemAlignment = .none
        scrubber.isContinuous = false
        scrubber.showsArrowButtons = false
        scrubber.showsAdditionalContentIndicators = true
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.register(ProjectScrubberItemView.self, forItemIdentifier: Self.scrubberItemIdentifier)
        scrubber.frame = NSRect(x: 0, y: 0, width: 440, height: 30)
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrubber.widthAnchor.constraint(equalToConstant: 440),
            scrubber.heightAnchor.constraint(equalToConstant: 30),
        ])
        scrubber.setAccessibilityLabel("Active Codex projects")

        trayItemWasAdded = CTBAddSystemTrayItem(trayItem)
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    @objc private func showFromTray() {
        _ = present()
    }

    @objc private func settingOptionPressed(_ sender: NSButton) {
        guard let rawIdentifier = sender.identifier?.rawValue,
              let selection = settingSelections[NSTouchBarItem.Identifier(rawIdentifier)] else {
            return
        }

        switch selection {
        case let .effort(choice):
            effortPopoverItem.dismissPopover(nil)
            onEffortSelected?(choice)
        case let .speed(choice):
            speedPopoverItem.dismissPopover(nil)
            onSpeedSelected?(choice)
        }
    }

    private var effortTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "Çaba" : "Effort"
    }

    private var speedTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "Hız" : "Speed"
    }

    private func makeEffortPopoverItem() -> NSPopoverTouchBarItem {
        let item = NSPopoverTouchBarItem(identifier: Self.effortItemIdentifier)
        item.customizationLabel = effortTitle
        item.collapsedRepresentationLabel = effortTitle
        item.collapsedRepresentationImage = NSImage(
            systemSymbolName: "brain.head.profile",
            accessibilityDescription: effortTitle
        )
        item.showsCloseButton = true
        item.popoverTouchBar = makeOptionsTouchBar(
            prefix: "effort",
            selections: EffortChoice.allCases.map { ($0.title, .effort($0)) }
        )
        return item
    }

    private func makeSpeedPopoverItem() -> NSPopoverTouchBarItem {
        let item = NSPopoverTouchBarItem(identifier: Self.speedItemIdentifier)
        item.customizationLabel = speedTitle
        item.collapsedRepresentationLabel = speedTitle
        item.collapsedRepresentationImage = NSImage(
            systemSymbolName: "speedometer",
            accessibilityDescription: speedTitle
        )
        item.showsCloseButton = true
        item.popoverTouchBar = makeOptionsTouchBar(
            prefix: "speed",
            selections: SpeedChoice.allCases.map { ($0.title, .speed($0)) }
        )
        return item
    }

    private func makeOptionsTouchBar(
        prefix: String,
        selections: [(title: String, selection: SettingSelection)]
    ) -> NSTouchBar {
        let optionsBar = NSTouchBar()
        optionsBar.delegate = self
        optionsBar.defaultItemIdentifiers = selections.enumerated().map { index, option in
            let identifier = NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.\(prefix).\(index)")
            settingSelections[identifier] = option.selection
            return identifier
        }
        return optionsBar
    }
}

@MainActor
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.projectsItemIdentifier else {
            if identifier == Self.effortItemIdentifier {
                return effortPopoverItem
            }
            if identifier == Self.speedItemIdentifier {
                return speedPopoverItem
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
            let button = NSButton(title: title, target: self, action: #selector(settingOptionPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
            button.bezelStyle = .texturedRounded
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
            view.configure(title: group.displayName(), count: group.threads.count)
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
            title = group.threads.count > 1
                ? "\(group.displayName()) · \(group.threads.count)"
                : group.displayName()
        }

        let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ]).width
        return NSSize(width: min(max(70, ceil(textWidth) + 39), 190), height: 30)
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        guard groups.indices.contains(selectedIndex) else {
            scrubber.selectedIndex = -1
            return
        }

        onProjectSelected?(groups[selectedIndex])
        scrubber.selectedIndex = -1
    }
}
