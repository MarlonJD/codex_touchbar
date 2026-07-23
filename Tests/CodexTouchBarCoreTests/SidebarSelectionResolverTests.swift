@testable import CodexTouchBarCore
import Testing

@Test func resolvesTheProjectContainingTheVisibleSelectedTask() {
    let rows = [
        SidebarSelectionRow.project(name: "codex_touchbar", minY: 451, height: 30),
        SidebarSelectionRow.project(name: "aviaSurveil360", minY: 522, height: 30),
        SidebarSelectionRow.project(name: "aviaCore", minY: 593, height: 30),
        SidebarSelectionRow.selectedTask(minY: 625, height: 30),
    ]

    #expect(SidebarSelectionResolver.projectName(from: rows) == "aviaCore")
}

@Test func selectedProjectHeaderWinsOverTaskPositionFallback() {
    let rows = [
        SidebarSelectionRow.project(name: "codex_touchbar", minY: 451, height: 30),
        SidebarSelectionRow.selectedProject(name: "aviaCore", minY: 593, height: 30),
        SidebarSelectionRow.selectedTask(minY: 793, height: 30),
        SidebarSelectionRow.project(name: "flutter_scene_viewer", minY: 742, height: 30),
    ]

    #expect(SidebarSelectionResolver.projectName(from: rows) == "aviaCore")
}

@Test func resolvesASelectedTopLevelTaskAsTasksGroup() {
    let rows = [
        SidebarSelectionRow.selectedTask(minY: 380, height: 30),
        SidebarSelectionRow.project(name: "codex_touchbar", minY: 451, height: 30),
    ]

    #expect(SidebarSelectionResolver.projectName(from: rows) == "Görevler")
}

@Test func ignoresOffscreenZeroHeightRows() {
    let rows = [
        SidebarSelectionRow.project(name: "aviaCore", minY: 593, height: 30),
        SidebarSelectionRow.selectedTask(minY: 625, height: 30),
        SidebarSelectionRow.project(name: "offscreen", minY: 983, height: 0),
    ]

    #expect(SidebarSelectionResolver.projectName(from: rows) == "aviaCore")
}
