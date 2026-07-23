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
@Test func unreadProjectKeepsWhiteContentAndUsesOnlyAPurpleDot() {
    let presentation = ProjectScrubberItemView.presentation(
        title: "aviaCore",
        count: 2,
        hasUnread: true,
        isSelected: false,
        isPlaceholder: false
    )

    #expect(presentation.title == "aviaCore · 2")
    #expect(presentation.textColor == .white)
    #expect(presentation.trailingDotColor == .systemPurple)
}

@MainActor
@Test func selectedProjectDoesNotAddAnArrowOrYellowText() {
    let presentation = ProjectScrubberItemView.presentation(
        title: "codex_touchbar",
        count: 1,
        hasUnread: false,
        isSelected: true,
        isPlaceholder: false
    )

    #expect(presentation.title == "codex_touchbar")
    #expect(presentation.textColor == .white)
    #expect(presentation.trailingDotColor == nil)
}

@MainActor
@Test func trailingDotAddsIndependentIndicatorWidth() {
    let plain = TouchBarImageRenderer.image(title: "Project")
    let unread = TouchBarImageRenderer.image(
        title: "Project",
        trailingDotColor: .systemPurple
    )

    #expect(unread.size.width > plain.size.width)
    #expect(unread.size.height == plain.size.height)
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
