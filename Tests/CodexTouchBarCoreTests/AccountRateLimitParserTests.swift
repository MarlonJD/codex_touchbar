import Foundation
import Testing
@testable import CodexTouchBarCore

@Test func selectsTheCodexWeeklyLimitInsteadOfAnotherMeteredBucket() throws {
    let response = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": {
          "usedPercent": 9,
          "windowDurationMins": 10080,
          "resetsAt": 1785619294
        },
        "secondary": null,
        "credits": {
          "hasCredits": false,
          "unlimited": false,
          "balance": "0"
        },
        "individualLimit": null,
        "planType": "pro",
        "rateLimitReachedType": null
      },
      "rateLimitsByLimitId": {
        "codex_bengalfox": {
          "limitId": "codex_bengalfox",
          "limitName": "GPT-5.3-Codex-Spark",
          "primary": {
            "usedPercent": 0,
            "windowDurationMins": 10080,
            "resetsAt": 1785751173
          },
          "secondary": null,
          "credits": null,
          "individualLimit": null,
          "planType": "pro",
          "rateLimitReachedType": null
        },
        "codex": {
          "limitId": "codex",
          "limitName": null,
          "primary": {
            "usedPercent": 9,
            "windowDurationMins": 10080,
            "resetsAt": 1785619294
          },
          "secondary": null,
          "credits": {
            "hasCredits": false,
            "unlimited": false,
            "balance": "0"
          },
          "individualLimit": null,
          "planType": "pro",
          "rateLimitReachedType": null
        }
      },
      "rateLimitResetCredits": {
        "availableCount": 1,
        "credits": [{
          "id": "RateLimitResetCredit_example",
          "resetType": "codexRateLimits",
          "status": "available",
          "grantedAt": 1783965843,
          "expiresAt": 1786557843,
          "title": "Full reset",
          "description": "Example reset credit"
        }]
      }
    }
    """
    let recordedAt = Date(timeIntervalSince1970: 1_785_230_000)

    let usage = AccountRateLimitParser.weeklyLimit(
        from: Data(response.utf8),
        recordedAt: recordedAt
    )

    #expect(usage?.usedPercent == 9)
    #expect(usage?.remainingPercent == 91)
    #expect(usage?.resetsAt == Date(timeIntervalSince1970: 1_785_619_294))
    #expect(usage?.recordedAt == recordedAt)
}
