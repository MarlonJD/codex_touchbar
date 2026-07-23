import CodexTouchBarCore
import Testing

@Test func electronAccessibilityUsesTheSupportedManualAccessibilityAttribute() {
    #expect(AccessibilityRuntimePolicy.activationAttribute == "AXManualAccessibility")
}

@Test func electronAccessibilityTraversesNavigationAndSectionChildren() {
    #expect(AccessibilityRuntimePolicy.childAttributeNames == [
        "AXChildren",
        "AXChildrenInNavigationOrder",
        "AXSections",
    ])
}

@Test func electronAccessibilityReachesNestedSidebarTaskIndicators() {
    #expect(AccessibilityRuntimePolicy.maximumTraversalDepth >= 24)
}
