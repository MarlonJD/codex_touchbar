import AppKit
import ApplicationServices
import CodexTouchBarCore
import OSLog

@MainActor
final class CodexAccessibilityController {
    private static let codexBundleIdentifier = "com.openai.codex"
    private let logger = Logger(subsystem: "dev.marlonjd.CodexTouchBar", category: "composer-reader")
    private var lastReadStatus: String?
    private var activatedProcessIdentifier: pid_t?

    enum ControlKind {
        case effort
        case speed

        var openerKeywords: [String] {
            switch self {
            case .effort:
                ["çaba", "effort", "reasoning"]
            case .speed:
                ["hız", "speed", "service tier"]
            }
        }

        var currentValueLabels: [String] {
            switch self {
            case .effort:
                EffortChoice.allCases.flatMap(\.accessibilityLabels)
            case .speed:
                SpeedChoice.allCases.flatMap(\.accessibilityLabels)
            }
        }
    }

    enum ControllerError: LocalizedError {
        case accessibilityPermissionRequired
        case codexNotRunning
        case codexMustBeFrontmost
        case codexRestartRequired
        case commandBridgeUnavailable(String)
        case controlNotFound(ControlKind)
        case optionNotFound(String)
        case actionFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                "Enable Codex Touch Bar in System Settings → Privacy & Security → Accessibility, then try again."
            case .codexNotRunning:
                "Codex is not running."
            case .codexMustBeFrontmost:
                "Open the task in Codex, then try again."
            case .codexRestartRequired:
                "Quit and reopen Codex once to enable the Effort and Speed controls."
            case let .commandBridgeUnavailable(message):
                "Codex command bridge could not be prepared: \(message)"
            case .controlNotFound(.effort):
                "The effort control was not found in the visible Codex task."
            case .controlNotFound(.speed):
                "The speed control was not found in the visible Codex task."
            case let .optionNotFound(option):
                "The Codex option “\(option)” was not found."
            case .actionFailed:
                "Codex did not accept the setting change."
            }
        }
    }

    func requestAccessibilityAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    struct VisibleContext {
        let projectName: String?
        let selectedTaskLabel: String?
        let composer: ComposerDisplayState
    }

    func visibleContext() -> VisibleContext {
        guard AXIsProcessTrusted() else {
            reportReadStatus("accessibilityPermission=false")
            return VisibleContext(projectName: nil, selectedTaskLabel: nil, composer: .init())
        }
        guard let application = NSRunningApplication.runningApplications(
                  withBundleIdentifier: Self.codexBundleIdentifier
              ).first else {
            reportReadStatus("codexRunning=false")
            return VisibleContext(projectName: nil, selectedTaskLabel: nil, composer: .init())
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        let activation = enableEnhancedAccessibility(for: root)
        var appSettable = DarwinBoolean(false)
        let appCapability = AXUIElementIsAttributeSettable(root, AccessibilityRuntimePolicy.activationAttribute as CFString, &appSettable)
        var windowSettable = DarwinBoolean(false)
        var windowCapability = AXError.invalidUIElement
        if let value = attribute(kAXFocusedWindowAttribute, of: root), CFGetTypeID(value) == AXUIElementGetTypeID() {
            windowCapability = AXUIElementIsAttributeSettable(unsafeDowncast(value, to: AXUIElement.self), AccessibilityRuntimePolicy.activationAttribute as CFString, &windowSettable)
        }
        let elements = accessibilityElements(in: root)
        let windowFrame = elements.first.flatMap { frame(of: $0.element) }
        let sidebarLeft = windowFrame?.minX ?? 0
        var selectedTask: String?
        var controlLabels: [String] = []
        var frameCount = 0
        var currentCount = 0
        var menuCount = 0
        for snapshot in elements {
            guard let frame = frame(of: snapshot.element), frame.height > 0 else { continue }
            frameCount += 1
            if isCurrentPage(snapshot.element) { currentCount += 1 }
            let classes = stringListAttribute("AXDOMClassList", of: snapshot.element)
            if frame.minX < sidebarLeft + 300,
               isCurrentPage(snapshot.element),
               !classes.contains("group/folder-row") {
                let label = primaryLabel(of: snapshot.element)
                if !label.isEmpty { selectedTask = label }
            }
            // Model and speed are menu controls. Restrict reads to their accessible labels.
            guard snapshot.canPress, frame.minX >= sidebarLeft + 300,
                  frame.maxY >= (windowFrame?.midY ?? 0) else { continue }
            if snapshot.role == (kAXPopUpButtonRole as String)
                || attribute("AXHasPopup", of: snapshot.element) != nil
                || attribute("AXExpanded", of: snapshot.element) != nil {
                menuCount += 1
                let text = controlText(in: snapshot.element).joined(separator: " ")
                if !text.isEmpty { controlLabels.append(text) }
                let label = primaryLabel(of: snapshot.element)
                if !label.isEmpty { controlLabels.append(label) }
            }
        }
        let composer = ComposerDisplayState.fromControlLabels(controlLabels, modelNames: CodexModelCatalog.modelNames())
        let status = "activation=\(activation.rawValue) appCapability=\(appCapability.rawValue)/\(appSettable.boolValue) windowCapability=\(windowCapability.rawValue)/\(windowSettable.boolValue) elements=\(elements.count) depth=\(elements.last?.depth ?? 0) frames=\(frameCount) windowFrame=\(windowFrame != nil) current=\(currentCount) menus=\(menuCount) selectedLabel=\(selectedTask != nil) model=\(composer.modelTitle != nil) speed=\(composer.speedTitle != nil)"
        reportReadStatus(status)
        return VisibleContext(
            projectName: selectedSidebarProjectName(from: elements, sidebarLeft: sidebarLeft),
            selectedTaskLabel: selectedTask,
            composer: composer
        )
    }

    private func reportReadStatus(_ status: String) {
        guard status != lastReadStatus else { return }
        lastReadStatus = status
        logger.notice("Composer reader: \(status, privacy: .public)")
    }

    private func controlText(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 12 else { return [] }
        if stringAttribute(kAXRoleAttribute, of: element) == kAXStaticTextRole as String {
            let text = primaryLabel(of: element)
            return text.isEmpty ? [] : [text]
        }
        let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
        return children.flatMap { controlText(in: $0, depth: depth + 1) }
    }

    private func primaryLabel(of element: AXUIElement) -> String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            let value = stringAttribute(name, of: element)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func selectedSidebarProjectName(from elements: [ElementSnapshot], sidebarLeft: CGFloat) -> String? {
        let rows = elements.compactMap {
            snapshot -> SidebarSelectionRow? in
            guard let frame = frame(of: snapshot.element),
                  frame.minX < sidebarLeft + 300 else {
                return nil
            }

            let classes = stringListAttribute("AXDOMClassList", of: snapshot.element)
            if classes.contains("group/folder-row"), !snapshot.rawText.isEmpty {
                if isCurrentPage(snapshot.element) {
                    return .selectedProject(
                        name: primaryLabel(of: snapshot.element),
                        minY: frame.minY,
                        height: frame.height
                    )
                } else {
                    return .project(
                        name: primaryLabel(of: snapshot.element),
                        minY: frame.minY,
                        height: frame.height
                    )
                }
            }
            if isCurrentPage(snapshot.element) {
                return .selectedTask(minY: frame.minY, height: frame.height)
            }
            return nil
        }
        return SidebarSelectionResolver.projectName(from: rows)
    }

    private func isCurrentPage(_ element: AXUIElement) -> Bool {
        stringAttribute("AXARIACurrent", of: element) == "page"
            || booleanAttribute(kAXSelectedAttribute, of: element)
    }

    func apply(effort choice: EffortChoice) async throws {
        try prepareCommandBridge()
        let commands = CodexCommandPlan.effort(
            targetIndex: choice.commandTargetIndex,
            optionCount: EffortChoice.commandOptionCount
        )
        guard !commands.isEmpty else {
            throw ControllerError.actionFailed
        }
        try await send(commands)
    }

    func apply(speed choice: SpeedChoice, readSettings: () -> ComposerSettings?) async throws {
        try prepareCommandBridge()
        guard let settings = readSettings() else {
            throw ControllerError.controlNotFound(.speed)
        }
        if (settings.serviceTier ?? "default") == choice.rawValue {
            return
        }
        try await send([.toggleFastMode])
        for _ in 0..<20 {
            if let updated = readSettings(), (updated.serviceTier ?? "default") == choice.rawValue {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ControllerError.actionFailed
    }

    private func prepareCommandBridge() throws {
        guard requestAccessibilityAccess() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier else {
            throw ControllerError.codexMustBeFrontmost
        }
        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first else {
            throw ControllerError.codexNotRunning
        }

        let fileManager = FileManager.default
        let codexDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let keymapURL = codexDirectory.appendingPathComponent("keybindings.json")
        do {
            let existingData: Data?
            if fileManager.fileExists(atPath: keymapURL.path) {
                existingData = try Data(contentsOf: keymapURL)
            } else {
                existingData = nil
            }
            let mergedData = try CodexCommandKeymap.mergingPrivateBindings(into: existingData)
            if mergedData != existingData {
                try fileManager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
                try mergedData.write(to: keymapURL, options: .atomic)
            }
            let keymapModificationDate = try keymapURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if CodexCommandBridgeRuntime.requiresRestart(
                codexLaunchDate: codex.launchDate,
                keymapModificationDate: keymapModificationDate
            ) {
                throw ControllerError.codexRestartRequired
            }
        } catch let error as ControllerError {
            throw error
        } catch {
            throw ControllerError.commandBridgeUnavailable(error.localizedDescription)
        }
    }

    private func send(_ commands: [CodexCommand]) async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
        for command in commands {
            guard postKey(for: command) else {
                throw ControllerError.actionFailed
            }
            try await Task.sleep(nanoseconds: 140_000_000)
        }
    }

    private func postKey(for command: CodexCommand) -> Bool {
        let keyCode: CGKeyCode
        switch command {
        case .increaseEffort:
            keyCode = 64 // F17
        case .decreaseEffort:
            keyCode = 79 // F18
        case .toggleFastMode:
            keyCode = 80 // F19
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        let flags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    func diagnosticAccessibilityTree(processIdentifier: pid_t? = nil) throws -> [String] {
        guard AXIsProcessTrusted() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        let targetPID: pid_t
        if let processIdentifier {
            targetPID = processIdentifier
        } else {
            guard let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.codexBundleIdentifier
            ).first else {
                throw ControllerError.codexNotRunning
            }
            targetPID = application.processIdentifier
        }

        let root = AXUIElementCreateApplication(targetPID)
        let activationError = enableEnhancedAccessibility(for: root)
        let keywords = ["çaba", "effort", "reasoning", "yüksek", "high", "hız", "speed"]
        var lines = [
            "enhancedActivation.error=\(activationError.rawValue)",
            "application.attributes=\(attributeNames(of: root).joined(separator: ","))",
        ]
        if let focusedWindow = attribute(kAXFocusedWindowAttribute, of: root),
           CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            let window = unsafeDowncast(focusedWindow, to: AXUIElement.self)
            lines.append("window.attributes=\(attributeNames(of: window).joined(separator: ","))")
        }
        if let focusedValue = attribute(kAXFocusedUIElementAttribute, of: root),
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
            lines.append("focused.role=\(stringAttribute(kAXRoleAttribute, of: focused))")
            lines.append("focused.text=\(stringAttribute(kAXTitleAttribute, of: focused)) \(stringAttribute(kAXDescriptionAttribute, of: focused)) \(stringAttribute(kAXValueAttribute, of: focused))")
            lines.append("focused.actions=\(actionNames(of: focused).joined(separator: ","))")
            lines.append("focused.attributes=\(attributeNames(of: focused).joined(separator: ","))")
        }
        lines.append(contentsOf: accessibilityElements(in: root)
            .compactMap { snapshot -> String? in
                let actions = actionNames(of: snapshot.element)
                let frame = rectAttribute("AXFrame", of: snapshot.element)
                let isInSidebar = frame.map { $0.minX < 650 } ?? false
                guard isInSidebar || keywords.contains(where: snapshot.text.contains) else {
                    return nil
                }
                let classes = stringListAttribute("AXDOMClassList", of: snapshot.element)
                let selected = booleanAttribute(kAXSelectedAttribute, of: snapshot.element)
                let frameText = frame.map {
                    "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))"
                } ?? "-"
                return "depth=\(snapshot.depth) role=\(snapshot.role) selected=\(selected) frame=\(frameText) classes=\(classes.joined(separator: ",")) actions=\(actions.joined(separator: ",")) text=\(snapshot.text)"
            })
        return lines
    }

    private func select(kind: ControlKind, labels: [String], displayName: String) async throws {
        guard requestAccessibilityAccess() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier else {
            throw ControllerError.codexMustBeFrontmost
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first else {
            throw ControllerError.codexNotRunning
        }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        _ = enableEnhancedAccessibility(for: root)
        let initialElements = accessibilityElements(in: root)
        guard let opener = bestOpener(for: kind, among: initialElements) else {
            throw ControllerError.controlNotFound(kind)
        }
        guard AXUIElementPerformAction(opener, kAXPressAction as CFString) == .success else {
            throw ControllerError.actionFailed
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let expandedElements = accessibilityElements(in: root)
        guard let option = bestOption(matching: labels, excluding: opener, among: expandedElements) else {
            throw ControllerError.optionNotFound(displayName)
        }
        guard AXUIElementPerformAction(option, kAXPressAction as CFString) == .success else {
            throw ControllerError.actionFailed
        }
    }

    private struct ElementSnapshot {
        let element: AXUIElement
        let depth: Int
        let role: String
        let rawText: String
        let text: String
        let canPress: Bool
    }

    private func enableEnhancedAccessibility(for application: AXUIElement) -> AXError {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(application, &processIdentifier) == .success else { return .invalidUIElement }
        if activatedProcessIdentifier == processIdentifier { return .success }
        let result = AXUIElementSetAttributeValue(
            application,
            AccessibilityRuntimePolicy.activationAttribute as CFString,
            kCFBooleanTrue
        )
        if result == .success,
           booleanAttribute(AccessibilityRuntimePolicy.activationAttribute, of: application) {
            activatedProcessIdentifier = processIdentifier
        }
        return result
    }

    private func accessibilityElements(
        in application: AXUIElement
    ) -> [ElementSnapshot] {
        let roots: [AXUIElement]
        if let focusedWindow = attribute(kAXFocusedWindowAttribute, of: application),
           CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            roots = [unsafeDowncast(focusedWindow, to: AXUIElement.self)]
        } else if let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] {
            roots = windows
        } else {
            roots = [application]
        }

        let elements = AccessibilityRuntimePolicy.traverse(roots: roots) { element in
            AccessibilityRuntimePolicy.childAttributeNames.flatMap {
                attribute($0, of: element) as? [AXUIElement] ?? []
            }
        }
        return elements.map { element, depth in
            let role = stringAttribute(kAXRoleAttribute, of: element)
            let text = [
                stringAttribute(kAXTitleAttribute, of: element),
                stringAttribute(kAXDescriptionAttribute, of: element),
                stringAttribute(kAXHelpAttribute, of: element),
                stringAttribute(kAXValueAttribute, of: element),
                stringAttribute(kAXIdentifierAttribute, of: element),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            let actions = actionNames(of: element)
            return ElementSnapshot(
                element: element,
                depth: depth,
                role: role,
                rawText: text,
                text: normalized(text),
                canPress: actions.contains(kAXPressAction as String)
            )
        }
    }

    private func bestOpener(for kind: ControlKind, among elements: [ElementSnapshot]) -> AXUIElement? {
        let keywords = kind.openerKeywords.map(normalized)
        let values = kind.currentValueLabels.map(normalized)

        return elements
            .compactMap { snapshot -> (AXUIElement, Int)? in
                guard snapshot.canPress else {
                    return nil
                }
                var score = 0
                if keywords.contains(where: snapshot.text.contains) {
                    score += 100
                }
                if values.contains(where: { snapshot.text == $0 || snapshot.text.hasPrefix("\($0) ") }) {
                    score += 45
                }
                if snapshot.role == (kAXPopUpButtonRole as String) || snapshot.role == (kAXButtonRole as String) {
                    score += 10
                }
                return score >= 55 ? (snapshot.element, score) : nil
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func bestOption(
        matching labels: [String],
        excluding opener: AXUIElement,
        among elements: [ElementSnapshot]
    ) -> AXUIElement? {
        let normalizedLabels = labels.map(normalized)

        return elements
            .compactMap { snapshot -> (AXUIElement, Int)? in
                guard snapshot.canPress, !CFEqual(snapshot.element, opener) else {
                    return nil
                }

                var score = 0
                if normalizedLabels.contains(snapshot.text) {
                    score += 100
                } else if normalizedLabels.contains(where: {
                    snapshot.text.hasPrefix("\($0) ") || snapshot.text.contains(" \($0) ")
                }) {
                    score += 70
                }
                if snapshot.role == (kAXMenuItemRole as String) || snapshot.role == (kAXRadioButtonRole as String) {
                    score += 15
                }
                return score >= 70 ? (snapshot.element, score) : nil
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String {
        guard let value = attribute(name, of: element) else {
            return ""
        }
        if let string = value as? String {
            return string
        }
        return ""
    }

    private func stringListAttribute(_ name: String, of element: AXUIElement) -> [String] {
        attribute(name, of: element) as? [String] ?? []
    }

    private func booleanAttribute(_ name: String, of element: AXUIElement) -> Bool {
        attribute(name, of: element) as? Bool ?? false
    }

    private func rectAttribute(_ name: String, of element: AXUIElement) -> CGRect? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(
            unsafeDowncast(value, to: AXValue.self),
            .cgRect,
            &rect
        ) else {
            return nil
        }
        return rect
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element),
              let size = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    private func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
