public enum AccessibilityRuntimePolicy {
    public static let activationAttribute = "AXEnhancedUserInterface"
    public static let childAttributeNames = [
        "AXChildren",
        "AXChildrenInNavigationOrder",
        "AXSections",
    ]
    public static let maximumElementCount = 5_000

    /// Chromium can nest the composer more deeply than the sidebar. Bound the
    /// number of elements instead of cutting off controls at an arbitrary depth.
    public static func traverse<Element: Hashable>(
        roots: [Element],
        children: (Element) -> [Element]
    ) -> [(element: Element, depth: Int)] {
        var queue: [(element: Element, depth: Int)] = []
        var visited: Set<Element> = []
        func enqueue(_ element: Element, depth: Int) {
            guard queue.count < maximumElementCount, visited.insert(element).inserted else { return }
            queue.append((element, depth))
        }
        for root in roots { enqueue(root, depth: 0) }
        var cursor = 0
        while cursor < queue.count, queue.count < maximumElementCount {
            let (element, depth) = queue[cursor]
            cursor += 1
            for child in children(element) { enqueue(child, depth: depth + 1) }
        }
        return queue
    }
}
