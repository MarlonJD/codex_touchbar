import AppKit
@testable import CodexTouchBar
import Testing

@MainActor
@Test func imageRendererCombinesAnIconAndTitleIntoOneDrawableImage() {
    let image = TouchBarImageRenderer.image(
        title: "Effort",
        symbolName: "brain.head.profile"
    )

    #expect(image.size.width > 45)
    #expect(image.size.height >= 16)
    #expect(!image.isTemplate)
}

@MainActor
@Test func imageRendererCanDrawATextOnlyOption() {
    let image = TouchBarImageRenderer.image(title: "Ultra")

    #expect(image.size.width > 20)
    #expect(image.size.height >= 16)
}

@MainActor
@Test func imageRendererDrawsTheWeeklyLimitWithAnIcon() {
    let image = TouchBarImageRenderer.image(
        title: "%94 kaldı",
        symbolName: "calendar"
    )

    #expect(image.size.width > 70)
    #expect(image.size.height >= 16)
}

@MainActor
@Test func unreadProjectTitleIncludesAnAttentionDot() {
    #expect(
        ProjectScrubberItemView.displayTitle(
            title: "aviaSurveil360",
            count: 2,
            hasUnread: true
        ) == "aviaSurveil360 · 2 ●"
    )
}

@Test func effortChoicesMatchCodexWhileUltraTargetsTheHiddenMaxStep() {
    #expect(EffortChoice.allCases.map(\.rawValue) == [
        "low",
        "medium",
        "high",
        "xhigh",
        "ultra",
    ])
    #expect(EffortChoice.commandOptionCount == 6)
    #expect(EffortChoice.ultra.commandTargetIndex == 5)
}
