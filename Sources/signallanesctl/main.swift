import Darwin
import Foundation
import SignalLanesCore

private let store = FileStatusOverrideStore()

private func usage(_ localized: SignalLanesLocalization) -> Never {
    print(localized.cliUsage)
    exit(2)
}

private func fail(_ message: String) -> Never {
    fputs("signallanesctl: \(message)\n", stderr)
    exit(1)
}

private func parseLanguageArguments(
    _ arguments: [String],
    defaultLanguage: AppLanguage
) -> (language: AppLanguage, arguments: [String]) {
    var language = defaultLanguage
    var remainingArguments: [String] = []
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--lang" {
            guard index + 1 < arguments.count,
                  let parsedLanguage = AppLanguage.parse(arguments[index + 1])
            else {
                fail(SignalLanesLocalization(language: language).missingLanguageValue)
            }

            language = parsedLanguage
            index += 2
        } else if argument.hasPrefix("--lang=") {
            let value = String(argument.dropFirst("--lang=".count))
            guard let parsedLanguage = AppLanguage.parse(value) else {
                fail(SignalLanesLocalization(language: language).missingLanguageValue)
            }

            language = parsedLanguage
            index += 1
        } else {
            remainingArguments.append(argument)
            index += 1
        }
    }

    return (language, remainingArguments)
}

private let environmentLanguage = AppLanguage.parse(ProcessInfo.processInfo.environment["SIGNALLANES_LANG"])
    ?? .defaultLanguage
private let parsedArguments = parseLanguageArguments(
    Array(CommandLine.arguments.dropFirst()),
    defaultLanguage: environmentLanguage
)
private let localized = SignalLanesLocalization(language: parsedArguments.language)
private let arguments = parsedArguments.arguments
guard let command = arguments.first else {
    usage(localized)
}

do {
    switch command {
    case "set":
        guard arguments.count >= 3 else {
            usage(localized)
        }

        let agentID = arguments[1]
        guard let state = LightState.parse(arguments[2]) else {
            fail(localized.unknownState(arguments[2]))
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
                    fail(localized.ttlRequiresPositiveSeconds)
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
        print(localized.setMessage(agentID: agentID, state: state))

    case "clear":
        guard arguments.count == 2 else {
            usage(localized)
        }

        try store.clear(agentID: arguments[1])
        print(localized.clearedMessage(agentID: arguments[1]))

    case "list":
        let now = Date()
        let overrides = try store.activeOverrides(now: now).sorted { $0.agentID < $1.agentID }
        if overrides.isEmpty {
            print(localized.noActiveOverrides)
        } else {
            for override in overrides {
                let expiry = override.expiresAt.map(localized.expiresMessage) ?? localized.noExpiry
                let reason = override.reason.map { " - \($0)" } ?? ""
                print("\(override.agentID): \(localized.stateDisplayName(override.state)), \(expiry)\(reason)")
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
        print("\(localized.overall): \(localized.stateDisplayName(result.overallState))")
        printQueueSection(
            title: localized.waitingForPermission,
            tasks: result.tasks(in: .waitingForPermission),
            localized: localized
        )
        printQueueSection(title: localized.running, tasks: result.tasks(in: .working), localized: localized)
        printQueueSection(title: localized.stopped, tasks: result.tasks(in: .idle), localized: localized)

    case "agents":
        for definition in defaultAgentDefinitions {
            print("\(definition.id)\t\(definition.displayName)")
        }

    default:
        usage(localized)
    }
} catch {
    fail(String(describing: error))
}

private func printQueueSection(
    title: String,
    tasks: [TaskReport],
    localized: SignalLanesLocalization
) {
    print("\n\(title) (\(tasks.count))")
    if tasks.isEmpty {
        print("  \(localized.none)")
        return
    }

    for task in tasks {
        let project = task.projectPath.map { " - \($0)" } ?? " - \(localized.projectNotExposed)"
        print("  \(task.displayName)\(project) [\(localized.sourceName(task.source))]")
        if let title = task.title {
            print("    \(localized.titleLabel): \(title)")
        }
        if let sessionID = task.sessionID {
            print("    \(localized.session): \(sessionID)")
        }
        print("    \(localized.localizedReason(task.reason))")
        for process in task.processes.prefix(3) {
            let processSummary = localized.processSummary(
                pid: process.pid,
                cpuPercent: process.cpuPercent,
                state: process.state
            )
            print("    \(processSummary)")
        }
    }
}
