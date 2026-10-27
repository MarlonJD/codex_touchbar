import CodexTouchBarCore
import Foundation

enum CodexModelCatalog {
    static func modelNames() -> [String] {
        models().flatMap { model in
            [model["slug"] as? String, model["display_name"] as? String].compactMap { $0 }
        }
    }

    private static func models() -> [[String: Any]] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return models
    }

    static func speedTitle(for settings: ComposerSettings) -> String? {
        guard let tier = settings.serviceTier, tier != "default" else { return "1x" }
        guard let model = models().first(where: { $0["slug"] as? String == settings.model }),
              let tiers = model["service_tiers"] as? [[String: Any]],
              let option = tiers.first(where: { $0["id"] as? String == tier }) else { return nil }
        if let description = option["description"] as? String,
           let range = description.range(of: #"\d+(?:\.\d+)?x\b"#, options: .regularExpression) {
            return String(description[range])
        }
        return option["name"] as? String
    }
}
