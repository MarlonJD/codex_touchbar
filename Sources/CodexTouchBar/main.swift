import AppKit
import CodexTouchBarCore
import Darwin

@MainActor
private func runApplication() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}

private func runDiagnostics() {
    let scanner = RolloutScanner()
    let grouper = ProjectGrouper()

    Task {
        let threads = await scanner.scan()
        let groups = grouper.groups(from: threads)
        if groups.isEmpty {
            print("No active Codex tasks")
        } else {
            for group in groups {
                print("\(group.name)\t\(group.threads.count)\t\(group.threads.map(\.id).joined(separator: ","))")
            }
        }
        exit(EXIT_SUCCESS)
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--diagnose") {
    runDiagnostics()
} else {
    runApplication()
}
