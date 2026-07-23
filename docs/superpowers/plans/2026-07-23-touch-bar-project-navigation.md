# Touch Bar Project Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace loud project status colors with native selection styling and add a compact/expanded project browser controlled by trailing chevron buttons.

**Architecture:** `TouchBarLayoutState` owns compact, expanded-project, and settings modes plus deterministic project-strip metrics. `TouchBarController` maps those modes to native Touch Bar items and persists the selected project through `NSScrubber.selectedIndex`. `ProjectScrubberItemView` and `TouchBarImageRenderer` keep project content white while rendering an independently colored unread dot.

**Tech Stack:** Swift 6, AppKit (`NSTouchBar`, `NSScrubber`, `NSButton`, `NSImage`), Swift Testing, Swift Package Manager.

## Global Constraints

- Minimum supported macOS version remains 13.0.
- Do not add third-party dependencies.
- Compact mode keeps weekly limit, Effort, and Speed visible.
- Expanded mode dedicates the available custom Touch Bar width to projects and a trailing collapse button.
- Selected projects use the scrubber's native rounded background; no yellow text and no `▶`.
- Unread projects keep white folder/name/count content and use only a purple trailing dot.
- Existing live project ordering, tapping, unread synchronization, and accessibility labels remain intact.

---

### Task 1: Add Expanded Project Layout State and Metrics

**Files:**
- Modify: `Sources/CodexTouchBarCore/TouchBarLayoutState.swift`
- Modify: `Tests/CodexTouchBarCoreTests/TouchBarLayoutStateTests.swift`

**Interfaces:**
- Consumes: Existing `TouchBarLayoutMode.projects` and `.setting(_:)`.
- Produces: `TouchBarLayoutMode.expandedProjects`, `TouchBarLayoutState.expandProjects()`, `TouchBarLayoutState.collapseProjects()`, and `TouchBarProjectStripMetrics.width(for:hasWeeklyLimit:) -> Double`.

- [ ] **Step 1: Write failing layout-state and metric tests**

Add tests equivalent to:

```swift
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
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFT_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift test --disable-sandbox --filter TouchBarLayoutStateTests
```

Expected: compilation fails because `.expandedProjects`, the transition methods, and `TouchBarProjectStripMetrics` do not exist.

- [ ] **Step 3: Implement the minimal state and metrics**

Add the expanded mode and explicit dimensions:

```swift
public enum TouchBarLayoutMode: Equatable, Sendable {
    case projects
    case expandedProjects
    case setting(TouchBarSettingPicker)
}

public enum TouchBarProjectStripMetrics {
    public static let navigationButtonWidth = 44.0
    public static let itemSpacing = 4.0
    public static let navigationSlotWidth = navigationButtonWidth + itemSpacing
    public static let compactWidth = 392.0
    public static let compactWidthWithWeeklyLimit = 342.0
    public static let expandedWidth = 590.0

    public static func width(
        for mode: TouchBarLayoutMode,
        hasWeeklyLimit: Bool
    ) -> Double {
        switch mode {
        case .expandedProjects:
            expandedWidth
        case .projects, .setting:
            hasWeeklyLimit ? compactWidthWithWeeklyLimit : compactWidth
        }
    }
}
```

Add state transitions:

```swift
public mutating func expandProjects() {
    mode = .expandedProjects
}

public mutating func collapseProjects() {
    mode = .projects
}
```

Keep `completeSelection()` and `cancel()` returning to `.projects`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: all `TouchBarLayoutStateTests` pass.

- [ ] **Step 5: Commit the state layer**

```bash
git add Sources/CodexTouchBarCore/TouchBarLayoutState.swift \
  Tests/CodexTouchBarCoreTests/TouchBarLayoutStateTests.swift
git commit -m "feat: add expanded project layout state"
```

### Task 2: Render Minimal Project Status

**Files:**
- Modify: `Sources/CodexTouchBar/TouchBarImageRenderer.swift`
- Modify: `Sources/CodexTouchBar/ProjectScrubberItemView.swift`
- Modify: `Tests/CodexTouchBarUITests/TouchBarImageRendererTests.swift`

**Interfaces:**
- Consumes: `ProjectGroup.hasUnread`, `ProjectGroup.isSelected`, and the existing image renderer.
- Produces: `ProjectScrubberItemView.presentation(title:count:hasUnread:isSelected:isPlaceholder:) -> ProjectCellPresentation` and `TouchBarImageRenderer.image(..., trailingDotColor:)`.

- [ ] **Step 1: Write failing presentation and renderer tests**

Add a presentation model test:

```swift
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
```

Add a renderer sizing test:

```swift
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
```

- [ ] **Step 2: Run focused UI tests and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFT_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift test --disable-sandbox --filter TouchBarImageRendererTests
```

Expected: compilation fails because `ProjectCellPresentation`, `presentation(...)`, and `trailingDotColor` do not exist.

- [ ] **Step 3: Implement presentation mapping and dot rendering**

Add:

```swift
struct ProjectCellPresentation {
    let title: String
    let textColor: NSColor
    let trailingDotColor: NSColor?
}
```

Resolve project content without embedding state markers in the title:

```swift
static func presentation(
    title: String,
    count: Int,
    hasUnread: Bool,
    isSelected _: Bool,
    isPlaceholder: Bool
) -> ProjectCellPresentation {
    ProjectCellPresentation(
        title: count > 1 ? "\(title) · \(count)" : title,
        textColor: isPlaceholder ? NSColor.white.withAlphaComponent(0.6) : .white,
        trailingDotColor: hasUnread && !isPlaceholder ? .systemPurple : nil
    )
}
```

Update `configure(...)` to pass `presentation.title`, white `presentation.textColor`, and `presentation.trailingDotColor` to the renderer. Continue appending `current project` and `unread result available` to the accessibility label.

Extend the renderer signature:

```swift
static func image(
    title: String,
    symbolName: String? = nil,
    font: NSFont = .systemFont(ofSize: 13, weight: .medium),
    textColor: NSColor = .white,
    trailingDotColor: NSColor? = nil
) -> NSImage
```

Reserve 13 points when a dot exists: 6 points of spacing plus a 7-point circle. Draw the circle vertically centered with `NSBezierPath(ovalIn:)` and the supplied color.

- [ ] **Step 4: Run focused UI tests and verify GREEN**

Run the command from Step 2.

Expected: all `TouchBarImageRendererTests` pass.

- [ ] **Step 5: Commit the minimal status styling**

```bash
git add Sources/CodexTouchBar/TouchBarImageRenderer.swift \
  Sources/CodexTouchBar/ProjectScrubberItemView.swift \
  Tests/CodexTouchBarUITests/TouchBarImageRendererTests.swift
git commit -m "style: simplify project status indicators"
```

### Task 3: Wire Native Selection and Expand/Collapse Buttons

**Files:**
- Modify: `Sources/CodexTouchBar/TouchBarController.swift`
- Modify: `Tests/CodexTouchBarCoreTests/TouchBarLayoutStateTests.swift`

**Interfaces:**
- Consumes: `TouchBarLayoutMode.expandedProjects`, `TouchBarProjectStripMetrics`, `ProjectCellPresentation`, and existing project groups.
- Produces: compact `[projects, expand, flexibleSpace, weekly?, effort, speed]` and expanded `[projects, flexibleSpace, collapse]` Touch Bar layouts.

- [ ] **Step 1: Add a failing state regression for settings return behavior**

Add:

```swift
@Test func settingCompletionReturnsToCompactProjects() {
    var state = TouchBarLayoutState()
    state.expandProjects()
    state.show(.effort)
    state.completeSelection()

    #expect(state.mode == .projects)
}
```

- [ ] **Step 2: Run the focused state tests and verify RED or missing UI wiring**

Run:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFT_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift test --disable-sandbox --filter TouchBarLayoutStateTests
```

Expected before Task 1 implementation: RED for missing expanded state. If Task 1 already made this state test green, continue to the controller wiring and use the physical Touch Bar as the integration gate.

- [ ] **Step 3: Add native navigation items**

In `TouchBarController`, add identifiers:

```swift
private static let expandProjectsItemIdentifier =
    NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.projects.expand")
private static let collapseProjectsItemIdentifier =
    NSTouchBarItem.Identifier("dev.marlonjd.CodexTouchBar.projects.collapse")
```

Create image-only native buttons:

```swift
private func makeProjectNavigationButton(
    symbolName: String,
    accessibilityLabel: String,
    action: Selector
) -> NSButton {
    let image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: accessibilityLabel
    ) ?? NSImage()
    let button = NSButton(image: image, target: self, action: action)
    button.bezelStyle = .texturedRounded
    button.imagePosition = .imageOnly
    button.refusesFirstResponder = true
    button.setAccessibilityLabel(accessibilityLabel)
    button.widthAnchor.constraint(
        equalToConstant: CGFloat(TouchBarProjectStripMetrics.navigationButtonWidth)
    ).isActive = true
    return button
}
```

Add `showExpandedProjects` and `hideExpandedProjects` actions that mutate `layoutState`, update the scrubber width, and call `updateVisibleItems()`.

- [ ] **Step 4: Map modes to Touch Bar item arrays and widths**

Use:

```swift
case .projects:
    touchBar.defaultItemIdentifiers = [
        Self.projectsItemIdentifier,
        Self.expandProjectsItemIdentifier,
        .flexibleSpace,
    ] + weeklyIdentifiers + [
        Self.effortItemIdentifier,
        Self.speedItemIdentifier,
    ]
case .expandedProjects:
    touchBar.defaultItemIdentifiers = [
        Self.projectsItemIdentifier,
        .flexibleSpace,
        Self.collapseProjectsItemIdentifier,
    ]
```

Set `projectStripWidthConstraint?.constant` from `TouchBarProjectStripMetrics.width(for:hasWeeklyLimit:)` whenever mode or weekly-limit visibility changes.

In the delegate, return custom items backed by `chevron.forward` and `chevron.backward` buttons for the new identifiers.

- [ ] **Step 5: Persist native scrubber selection**

After every group reload, set:

```swift
scrubber.selectedIndex = groups.firstIndex(where: \.isSelected) ?? -1
```

Keep `scrubber.selectionBackgroundStyle = .roundedBackground`. Remove the unconditional `selectedIndex = -1` after a valid project tap so the native background remains visible until the next live project-state refresh.

Update item sizing to add 13 points only when `group.hasUnread` so the separately rendered dot is not clipped.

- [ ] **Step 6: Run all automated verification**

Run:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFT_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift test --disable-sandbox
plutil -lint Resources/Info.plist
bash -n script/build_and_run.sh script/build_release.sh
git diff --check
```

Expected: all tests pass, plist is valid, shell syntax is valid, and `git diff --check` is silent.

- [ ] **Step 7: Build and physically verify the Touch Bar**

Run:

```bash
./script/build_and_run.sh --verify
```

Verify on the physical Touch Bar:

1. Selected project has a native rounded dark background, white folder/name/count, and no yellow or arrow.
2. Unread project has a purple dot only.
3. Compact mode shows the trailing `>` while weekly limit, Effort, and Speed remain visible.
4. `>` opens the wider project-only scrubber with trailing `<`.
5. `<` restores compact mode without losing live project state.
6. Project taps still open/cycle Codex tasks.

- [ ] **Step 8: Commit controller wiring**

```bash
git add Sources/CodexTouchBar/TouchBarController.swift \
  Tests/CodexTouchBarCoreTests/TouchBarLayoutStateTests.swift \
  docs/superpowers/specs/2026-07-23-touch-bar-project-navigation-design.md
git commit -m "feat: add expanded Touch Bar project browser"
```
