import AppKit
import ApplicationServices

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
        try await select(kind: .effort, labels: choice.accessibilityLabels, displayName: choice.title)
    }

    func apply(speed choice: SpeedChoice) async throws {
        try await select(kind: .speed, labels: choice.accessibilityLabels, displayName: choice.title)
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

        while cursor < queue.count, result.count < 5_000 {
            let (element, depth) = queue[cursor]
            cursor += 1

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

            guard depth < 20,
                  let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
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

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
