import Foundation

enum EffortChoice: String, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case ultra

    var title: String {
        switch self {
        case .low: localized(turkish: "Sınırlı", english: "Low")
        case .medium: localized(turkish: "Orta", english: "Medium")
        case .high: localized(turkish: "Yüksek", english: "High")
        case .xhigh: localized(turkish: "Çok Yüksek", english: "Extra High")
        case .ultra: "Ultra"
        }
    }

    var accessibilityLabels: [String] {
        switch self {
        case .low: ["Sınırlı", "Low"]
        case .medium: ["Orta", "Medium"]
        case .high: ["Yüksek", "High"]
        case .xhigh: ["Çok Yüksek", "Extra High", "Very High"]
        case .ultra: ["Ultra"]
        }
    }
}

enum SpeedChoice: String, CaseIterable, Sendable {
    case standard = "default"
    case fast = "priority"

    var title: String {
        switch self {
        case .standard: localized(turkish: "Standart", english: "Standard")
        case .fast: localized(turkish: "Hızlı", english: "Fast")
        }
    }

    var accessibilityLabels: [String] {
        switch self {
        case .standard: ["Standart", "Standard"]
        case .fast: ["Hızlı", "Fast"]
        }
    }
}

private func localized(turkish: String, english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("tr") == true ? turkish : english
}
