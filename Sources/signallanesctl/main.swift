import Darwin
import Foundation
import SignalLanesCore

private let store = FileStatusOverrideStore()

private func usage() -> Never {
    print("""
    Usage:
      signallanesctl set <agent-id> <green|yellow|red> [--ttl seconds|--no-expire] [reason...]
      signallanesctl clear <agent-id>
      signallanesctl list
      signallanesctl status [--all-known]
      signallanesctl queue [--all-known]
      signallanesctl agents

    Examples:
      signallanesctl set codex yellow "waiting for approval"
      signallanesctl set claude red --ttl 120 "running tests"
      signallanesctl clear codex
    """)
    exit(2)
}

private func fail(_ message: String) -> Never {
    fputs("signallanesctl: \(message)\n", stderr)
    exit(1)
}

private let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    usage()
}

do {
    switch command {
    case "set":
        guard arguments.count >= 3 else {
            usage()
        }

        let agentID = arguments[1]
        guard let state = LightState.parse(arguments[2]) else {
            fail("unknown state '\(arguments[2])'")
        }

        var index = 3
        var expiresAt: Date? = Date().addingTimeInterval(15 * 60)
        var reasonParts: [String] = []

        while index < arguments.count {
            let value = arguments[index]
            switch value {
            case "--ttl":
                guard index + 1 < arguments.count,
                      let seconds = TimeInterval(arguments[index + 1]),
                      seconds > 0
                else {
                    fail("--ttl requires a positive number of seconds")
                }
                expiresAt = Date().addingTimeInterval(seconds)
                index += 2
            case "--no-expire":
                expiresAt = nil
                index += 1
            default:
                reasonParts.append(value)
                index += 1
            }
        }

        let reason = reasonParts.isEmpty ? nil : reasonParts.joined(separator: " ")
        try store.set(agentID: agentID, state: state, reason: reason, expiresAt: expiresAt)
        print("Set \(agentID) to \(state.displayName).")

    case "clear":
        guard arguments.count == 2 else {
            usage()
        }

        try store.clear(agentID: arguments[1])
        print("Cleared \(arguments[1]).")

    case "list":
        let now = Date()
        let overrides = try store.activeOverrides(now: now).sorted { $0.agentID < $1.agentID }
        if overrides.isEmpty {
            print("No active overrides.")
        } else {
            for override in overrides {
                let expiry = override.expiresAt.map { "expires \($0)" } ?? "no expiry"
                let reason = override.reason.map { " - \($0)" } ?? ""
                print("\(override.agentID): \(override.state.displayName), \(expiry)\(reason)")
            }
        }

    case "status", "queue":
        let includeKnownIdleReports = arguments.dropFirst().contains("--all-known")
        let detector = AgentDetector(
            overrideProvider: store,
            taskHintProvider: DefaultTaskHintProvider.make(),
            includeKnownIdleReports: includeKnownIdleReports
        )
        let result = try detector.detect()
        print("Overall: \(result.overallState.displayName)")
        printQueueSection(title: "Waiting for Permission", tasks: result.tasks(in: .waitingForPermission))
        printQueueSection(title: "Running", tasks: result.tasks(in: .working))
        printQueueSection(title: "Stopped", tasks: result.tasks(in: .idle))

    case "agents":
        for definition in defaultAgentDefinitions {
            print("\(definition.id)\t\(definition.displayName)")
        }

    default:
        usage()
    }
} catch {
    fail(String(describing: error))
}

private func printQueueSection(title: String, tasks: [TaskReport]) {
    print("\n\(title) (\(tasks.count))")
    if tasks.isEmpty {
        print("  None")
        return
    }

    for task in tasks {
        let project = task.projectPath.map { " - \($0)" } ?? " - project not exposed"
        print("  \(task.displayName)\(project) [\(task.source.rawValue)]")
        if let title = task.title {
            print("    Title: \(title)")
        }
        if let sessionID = task.sessionID {
            print("    Session: \(sessionID)")
        }
        print("    \(task.reason)")
        for process in task.processes.prefix(3) {
            print("    PID \(process.pid), CPU \(String(format: "%.1f", process.cpuPercent))%, \(process.state)")
        }
    }
}
