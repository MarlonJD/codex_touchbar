import CodexTouchBarCore
import Testing

@Test func settingPickerUsesAnInlineModeAndReturnsToProjects() {
    var state = TouchBarLayoutState()

    #expect(state.mode == .projects)

    state.show(.effort)
    #expect(state.mode == .setting(.effort))

    state.completeSelection()
    #expect(state.mode == .projects)
}

@Test func settingPickerCanBeCancelled() {
    var state = TouchBarLayoutState()

    state.show(.speed)
    #expect(state.mode == .setting(.speed))

    state.cancel()
    #expect(state.mode == .projects)
}

@Test func projectBrowserExpandsAndCollapses() {
    var state = TouchBarLayoutState()

    state.expandProjects()
    #expect(state.mode == .expandedProjects)

    state.collapseProjects()
    #expect(state.mode == .projects)
}

@Test func projectStripMakesRoomForNavigationAndExpandsDeterministically() {
    #expect(
        TouchBarProjectStripMetrics.width(for: .projects, hasWeeklyLimit: true)
            == TouchBarProjectStripMetrics.compactWidthWithWeeklyLimit
    )
    #expect(
        TouchBarProjectStripMetrics.compactWidthWithWeeklyLimit
            + TouchBarProjectStripMetrics.navigationSlotWidth
            == 390
    )
    #expect(
        TouchBarProjectStripMetrics.width(for: .expandedProjects, hasWeeklyLimit: true)
            == TouchBarProjectStripMetrics.expandedWidth
    )
    #expect(
        TouchBarProjectStripMetrics.expandedWidth
            > TouchBarProjectStripMetrics.compactWidth
    )
}

@Test func helperKeepsTheSystemCloseBoxForTheNativeControlStrip() {
    var state = TouchBarLayoutState()
    #expect(state.showsSystemCloseBox)

    state.show(.effort)
    #expect(state.showsSystemCloseBox)
}

@Test func closeBoxPolicyIsReappliedAfterPresentation() {
    let state = TouchBarLayoutState()

    #expect(state.closeBoxVisibility(afterPresentationSucceeded: true))
    #expect(state.closeBoxVisibility(afterPresentationSucceeded: false))
}

@Test func mainSettingTitleStaysCompactAfterASelection() {
    #expect(TouchBarSettingTitle.mainTitle(
        baseTitle: "Çaba",
        selectedTitle: "Çok Yüksek"
    ) == "Çaba")
    #expect(TouchBarSettingTitle.mainTitle(
        baseTitle: "Hız",
        selectedTitle: "Hızlı"
    ) == "Hız")
}
