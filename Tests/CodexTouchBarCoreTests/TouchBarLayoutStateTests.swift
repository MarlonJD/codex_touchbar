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
