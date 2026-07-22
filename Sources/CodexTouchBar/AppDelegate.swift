import AppKit
import CodexTouchBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let enabledDefaultsKey = "touchBarEnabled"

    private let scanner = RolloutScanner()
    private let grouper = ProjectGrouper()
    private let touchBarController = TouchBarController()
    private let accessibilityController = CodexAccessibilityController()
    private var cycler = ThreadCycler()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var refreshInFlight = false
    private var latestGroups: [ProjectGroup]?
    private var latestGroupCount = 0
    private var latestThreadCount = 0
    private var transientStatus: (message: String, expiresAt: Date)?

    private var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runningPIDs = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).map(\.processIdentifier)
        if SingleInstancePolicy.shouldTerminate(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            runningPIDs: runningPIDs
        ) {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        LaunchAtLoginController.registerIfNeeded()

        touchBarController.onProjectSelected = { [weak self] group in
            self?.openNextThread(in: group)
        }
        touchBarController.onEffortSelected = { [weak self] choice in
            self?.applyEffort(choice)
        }
        touchBarController.onSpeedSelected = { [weak self] choice in
            self?.applySpeed(choice)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        updateRefreshSchedule()
        requestRefresh()
        updatePresentation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        touchBarController.dismiss()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.and.hand.point.up.left.fill",
                accessibilityDescription: "Codex Touch Bar"
            ) ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex Touch Bar")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let statusMenuItem = NSMenuItem(title: "Looking for active Codex tasks…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let enabledMenuItem = NSMenuItem(
            title: "Show when Codex is active",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledMenuItem.target = self
        enabledMenuItem.state = isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openCodexItem = NSMenuItem(title: "Open Codex", action: #selector(openCodex), keyEquivalent: "o")
        openCodexItem.target = self
        menu.addItem(openCodexItem)

        let accessibilityItem = NSMenuItem(
            title: "Enable Effort & Speed Controls…",
            action: #selector(requestAccessibilityAccess),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Codex Touch Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.statusMenuItem = statusMenuItem
        self.enabledMenuItem = enabledMenuItem

        if !touchBarController.isAvailable {
            statusMenuItem.title = "System-modal Touch Bar API unavailable"
            enabledMenuItem.isEnabled = false
        }
    }

    private func requestRefresh() {
        guard !refreshInFlight else {
            return
        }
        refreshInFlight = true

        Task { [weak self, scanner, grouper] in
            let threads = await scanner.scan()
            guard let self else {
                return
            }
            let groups = grouper.groups(from: threads)
            self.apply(groups: groups)
            self.refreshInFlight = false
        }
    }

    private func apply(groups: [ProjectGroup]) {
        guard RefreshPolicy.shouldApply(previous: latestGroups, next: groups) else {
            updateStatusText()
            return
        }
        latestGroups = groups
        latestGroupCount = groups.count
        latestThreadCount = groups.reduce(0) { $0 + $1.threads.count }
        cycler.retainGroups(Set(groups.map(\.id)))
        touchBarController.update(groups: groups)
        updateStatusText()
    }

    private func updateStatusText() {
        guard touchBarController.isAvailable else {
            statusMenuItem?.title = "System-modal Touch Bar API unavailable"
            return
        }

        if let transientStatus, transientStatus.expiresAt > Date() {
            statusMenuItem?.title = transientStatus.message
            return
        }
        transientStatus = nil

        if latestThreadCount == 0 {
            statusMenuItem?.title = "No active Codex tasks"
        } else {
            let taskWord = latestThreadCount == 1 ? "task" : "tasks"
            let projectWord = latestGroupCount == 1 ? "project" : "projects"
            statusMenuItem?.title = "\(latestThreadCount) active \(taskWord) · \(latestGroupCount) \(projectWord)"
        }
    }

    private func updatePresentation() {
        let codexIsFrontmost = isCodexFrontmost
        if isEnabled && codexIsFrontmost && touchBarController.isAvailable {
            _ = touchBarController.present()
        } else {
            touchBarController.dismiss()
        }
    }

    private var isCodexFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier
    }

    private func updateRefreshSchedule() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard isEnabled,
              let interval = RefreshPolicy.pollInterval(codexIsFrontmost: isCodexFrontmost) else {
            return
        }
        refreshTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func openNextThread(in group: ProjectGroup) {
        guard let thread = cycler.nextThread(in: group),
              let url = URL(string: "codex://threads/\(thread.id)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func applyEffort(_ choice: EffortChoice) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accessibilityController.apply(effort: choice)
                touchBarController.showSelectedEffort(choice)
                showTransientStatus("Effort set to \(choice.title)")
            } catch {
                showSettingError(error)
            }
        }
    }

    private func applySpeed(_ choice: SpeedChoice) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accessibilityController.apply(speed: choice)
                touchBarController.showSelectedSpeed(choice)
                showTransientStatus("Speed set to \(choice.title)")
            } catch {
                showSettingError(error)
            }
        }
    }

    private func showSettingError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showTransientStatus(message, duration: 15)
        NSSound.beep()
    }

    private func showTransientStatus(_ message: String, duration: TimeInterval = 6) {
        transientStatus = (message, Date().addingTimeInterval(duration))
        statusMenuItem?.title = message
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        updateRefreshSchedule()
        if isEnabled && isCodexFrontmost {
            requestRefresh()
        }
        updatePresentation()
    }

    @objc private func refreshTimerFired() {
        requestRefresh()
    }

    @objc private func refreshNow() {
        requestRefresh()
        updatePresentation()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        updateRefreshSchedule()
        if isEnabled && isCodexFrontmost {
            requestRefresh()
        }
        updatePresentation()
    }

    @objc private func openCodex() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func requestAccessibilityAccess() {
        if accessibilityController.requestAccessibilityAccess() {
            showTransientStatus("Accessibility access is enabled")
        } else {
            showTransientStatus(
                "Enable Codex Touch Bar in System Settings → Privacy & Security → Accessibility",
                duration: 15
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
