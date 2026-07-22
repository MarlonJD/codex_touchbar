import Foundation

public struct CodexKeyBinding: Codable, Equatable, Sendable {
    public let command: String
    public let key: String?

    public init(command: String, key: String?) {
        self.command = command
        self.key = key
    }
}

public enum CodexCommand: Equatable, Sendable {
    case increaseEffort
    case decreaseEffort
    case toggleFastMode
}

public enum CodexCommandKeymap {
    public static let increaseEffortBinding = CodexKeyBinding(
        command: "composer.increaseReasoningEffort",
        key: "Cmd+Ctrl+Alt+F17"
    )
    public static let decreaseEffortBinding = CodexKeyBinding(
        command: "composer.decreaseReasoningEffort",
        key: "Cmd+Ctrl+Alt+F18"
    )
    public static let toggleFastModeBinding = CodexKeyBinding(
        command: "composer.toggleFastMode",
        key: "Cmd+Ctrl+Alt+F19"
    )

    public static let privateBindings = [
        increaseEffortBinding,
        decreaseEffortBinding,
        toggleFastModeBinding,
    ]

    public static func mergingPrivateBindings(into existingData: Data?) throws -> Data {
        let decoder = JSONDecoder()
        var bindings: [CodexKeyBinding]
        if let existingData, !existingData.isEmpty {
            bindings = try decoder.decode([CodexKeyBinding].self, from: existingData)
        } else {
            bindings = []
        }

        for privateBinding in privateBindings where !bindings.contains(privateBinding) {
            bindings.append(privateBinding)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bindings)
    }
}

public enum CodexCommandPlan {
    public static func effort(targetIndex: Int, optionCount: Int) -> [CodexCommand] {
        guard optionCount > 0, (0..<optionCount).contains(targetIndex) else {
            return []
        }
        return Array(repeating: .decreaseEffort, count: optionCount)
            + Array(repeating: .increaseEffort, count: targetIndex)
    }
}

public enum CodexCommandBridgeRuntime {
    public static func requiresRestart(
        codexLaunchDate: Date?,
        keymapModificationDate: Date?
    ) -> Bool {
        guard let codexLaunchDate, let keymapModificationDate else {
            return false
        }
        return keymapModificationDate > codexLaunchDate
    }
}
