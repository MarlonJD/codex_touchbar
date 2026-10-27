import Foundation

public struct ComposerDisplayState: Equatable, Sendable {
    public let modelTitle: String?
    public let speedTitle: String?

    public init(modelTitle: String? = nil, speedTitle: String? = nil) {
        self.modelTitle = modelTitle
        self.speedTitle = speedTitle
    }

    /// Accepts short control labels only, never arbitrary transcript prose or a global default.
    public static func fromControlLabels(_ labels: [String], modelNames: [String]) -> Self {
        let clean = labels.map {
            $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let names = Set(modelNames.map(normalizedModelLabel).filter { !$0.isEmpty })
        let efforts: Set<String> = [
            "none", "minimal", "low", "medium", "high", "extra high", "max", "ultra",
            "düşük", "orta", "yüksek", "çok yüksek", "maksimum",
        ]
        let model = clean.first { label in
            guard label.count <= 80 else { return false }
            let normalized = normalizedModelLabel(label)
            return names.contains { name in
                normalized == name || (normalized.hasPrefix(name + " ")
                    && efforts.contains(String(normalized.dropFirst(name.count + 1))))
            }
        }
        let speed = clean.first {
            $0.range(of: #"^\d+(?:[.,]\d+)?[x×]$"#, options: .regularExpression) != nil
        }?.replacingOccurrences(of: "×", with: "x")
        return Self(modelTitle: model, speedTitle: speed)
    }

    private static func normalizedModelLabel(_ value: String) -> String {
        let normalized = value.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "‑", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("gpt ") ? String(normalized.dropFirst(4)) : normalized
    }

    public func resolving(settings: ComposerSettings?, fastTitle: String? = nil) -> Self {
        let tierTitle: String?
        if let settings {
            tierTitle = settings.serviceTier == nil || settings.serviceTier == "default"
                ? "1x" : fastTitle
        } else { tierTitle = nil }
        return Self(
            modelTitle: modelTitle ?? settings?.modelAndEffortTitle,
            speedTitle: speedTitle ?? tierTitle
        )
    }
}
