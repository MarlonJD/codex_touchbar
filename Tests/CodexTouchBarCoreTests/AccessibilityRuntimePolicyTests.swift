import CodexTouchBarCore
import Testing

@Test func electronAccessibilityUsesTheSupportedEnhancedUIAttribute() {
    #expect(AccessibilityRuntimePolicy.activationAttribute == "AXEnhancedUserInterface")
}

@Test func electronAccessibilityTraversesNavigationAndSectionChildren() {
    #expect(AccessibilityRuntimePolicy.childAttributeNames == [
        "AXChildren",
        "AXChildrenInNavigationOrder",
        "AXSections",
    ])
}
