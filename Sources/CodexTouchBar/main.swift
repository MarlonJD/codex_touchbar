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
        let snapshot = await scanner.scanSnapshot()
        if let weeklyLimit = snapshot.weeklyLimit {
            print("Weekly limit\t\(weeklyLimit.remainingPercent)% remaining")
        } else {
            print("Weekly limit\tUnavailable")
        }
        print("Unread project directories\t\(snapshot.unreadWorkingDirectories.count)")

        let groups = grouper.groups(
            from: snapshot.threads,
            unreadWorkingDirectories: snapshot.unreadWorkingDirectories
        )
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

@MainActor
private func runEffortDiagnostic(rawValue: String) {
    guard let choice = EffortChoice(rawValue: rawValue) else {
        print("Unknown effort choice: \(rawValue)")
        exit(EXIT_FAILURE)
    }

    let controller = CodexAccessibilityController()
    Task { @MainActor in
        do {
            try await controller.apply(effort: choice)
            print("Selected effort: \(choice.title)")
            exit(EXIT_SUCCESS)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("Accessibility diagnostic failed: \(message)")
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
}

@MainActor
private func runAccessibilityTreeDiagnostic(processIdentifier: pid_t? = nil) {
    let controller = CodexAccessibilityController()
    do {
        let lines = try controller.diagnosticAccessibilityTree(processIdentifier: processIdentifier)
        lines.forEach { print($0) }
        exit(EXIT_SUCCESS)
    } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        print("Accessibility tree diagnostic failed: \(message)")
        exit(EXIT_FAILURE)
    }
}

switch LaunchCommand(arguments: CommandLine.arguments) {
case .diagnoseRollouts:
    runDiagnostics()
case let .diagnoseEffort(rawValue):
    runEffortDiagnostic(rawValue: rawValue)
case .diagnoseAccessibilityTree:
    runAccessibilityTreeDiagnostic()
case let .diagnoseAccessibilityPID(processIdentifier):
    runAccessibilityTreeDiagnostic(processIdentifier: processIdentifier)
case .diagnoseLoginItem:
    print(LaunchAtLoginController.statusDescription)
case .run:
    runApplication()
}
