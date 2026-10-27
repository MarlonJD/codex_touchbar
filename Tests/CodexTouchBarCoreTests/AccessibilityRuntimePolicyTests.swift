import CodexTouchBarCore
import Testing

@Test func chromiumAccessibilityUsesTheEnhancedInterfaceAttribute() {
    #expect(AccessibilityRuntimePolicy.activationAttribute == "AXEnhancedUserInterface")
}

@Test func electronAccessibilityTraversesNavigationAndSectionChildren() {
    #expect(AccessibilityRuntimePolicy.childAttributeNames == [
        "AXChildren",
        "AXChildrenInNavigationOrder",
        "AXSections",
    ])
}

@Test func electronAccessibilityReachesDeepComposerControls() {
    let elements = AccessibilityRuntimePolicy.traverse(roots: [0]) {
        $0 < 40 ? [$0 + 1] : []
    }
    #expect(elements.last?.element == 40)
    #expect(elements.last?.depth == 40)
}

@Test func accessibilityTraversalDeduplicatesElementsRatherThanHashValues() {
    struct Element: Hashable {
        let id: Int
        func hash(into hasher: inout Hasher) { hasher.combine(0) }
    }
    let elements = AccessibilityRuntimePolicy.traverse(roots: [Element(id: 0)]) {
        $0.id == 0 ? [Element(id: 1), Element(id: 2), Element(id: 1)] : [Element(id: 0)]
    }
    #expect(elements.map(\.element.id) == [0, 1, 2])
}

@Test func accessibilityTraversalBoundsWideAndDeepTrees() {
    let elements = AccessibilityRuntimePolicy.traverse(roots: [0]) {
        [$0 * 2 + 1, $0 * 2 + 2]
    }
    #expect(elements.count == AccessibilityRuntimePolicy.maximumElementCount)
}
