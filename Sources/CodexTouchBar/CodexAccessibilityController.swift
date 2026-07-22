import AppKit
import ApplicationServices
import CodexTouchBarCore

@MainActor
final class CodexAccessibilityController {
    private static let codexBundleIdentifier = "com.openai.codex"

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

    func apply(speed choice: SpeedChoice) async throws {
        try prepareCommandBridge()
        let targetServiceTier = choice.rawValue
        if currentServiceTier() == targetServiceTier {
            return
        }
        try await send([.toggleFastMode])

        if currentServiceTier() != nil {
            for _ in 0..<12 {
                if currentServiceTier() == targetServiceTier {
                    return
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw ControllerError.actionFailed
        }
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

    private func currentServiceTier() -> String? {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8),
              let expression = try? NSRegularExpression(
                  pattern: #"(?m)^\s*service_tier\s*=\s*\"([^\"]+)\""#
              ),
              let match = expression.firstMatch(
                  in: contents,
                  range: NSRange(contents.startIndex..., in: contents)
              ),
              let valueRange = Range(match.range(at: 1), in: contents) else {
            return nil
        }
        return String(contents[valueRange])
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
                guard !actions.isEmpty || keywords.contains(where: snapshot.text.contains) else {
                    return nil
                }
                return "role=\(snapshot.role) actions=\(actions.joined(separator: ",")) text=\(snapshot.text)"
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
        let role: String
        let text: String
        let canPress: Bool
    }

    private func enableEnhancedAccessibility(for application: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(
            application,
            AccessibilityRuntimePolicy.activationAttribute as CFString,
            kCFBooleanTrue
        )
    }

    private func accessibilityElements(in application: AXUIElement) -> [ElementSnapshot] {
        let roots: [AXUIElement]
        if let focusedWindow = attribute(kAXFocusedWindowAttribute, of: application),
           CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            roots = [unsafeDowncast(focusedWindow, to: AXUIElement.self)]
        } else if let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] {
            roots = windows
        } else {
            roots = [application]
        }

        var result: [ElementSnapshot] = []
        var queue = roots.map { ($0, 0) }
        var cursor = 0
        var visited: Set<CFHashCode> = []

        while cursor < queue.count, result.count < 5_000 {
            let (element, depth) = queue[cursor]
            cursor += 1

            let elementHash = CFHash(element)
            guard visited.insert(elementHash).inserted else {
                continue
            }

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
            result.append(
                ElementSnapshot(
                    element: element,
                    role: role,
                    text: normalized(text),
                    canPress: actions.contains(kAXPressAction as String)
                )
            )

            guard depth < 20 else {
                continue
            }
            for childAttribute in AccessibilityRuntimePolicy.childAttributeNames {
                guard let children = attribute(childAttribute, of: element) as? [AXUIElement] else {
                    continue
                }
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }

        return result
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
