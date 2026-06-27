import Foundation

public enum ReportSource: String, Equatable, Sendable {
    case automatic
    case manualOverride
}

public struct MatchedProcess: Equatable, Sendable {
    public let pid: Int
    public let cpuPercent: Double
    public let state: String
    public let commandPreview: String
    public let projectPaths: [String]
    public let sessionID: String?

    public init(snapshot: ProcessSnapshot, projectPaths: [String] = [], sessionID: String? = nil) {
        pid = snapshot.pid
        cpuPercent = snapshot.cpuPercent
        state = snapshot.state
        commandPreview = String(snapshot.commandLine.prefix(160))
        self.projectPaths = projectPaths
        self.sessionID = sessionID
    }
}

public struct TaskHint: Equatable, Sendable {
    public let agentID: String
    public let sessionID: String
    public let title: String?
    public let projectPath: String?
    public let state: LightState
    public let reason: String
    public let updatedAt: Date

    public init(
        agentID: String,
        sessionID: String,
        title: String?,
        projectPath: String?,
        state: LightState,
        reason: String,
        updatedAt: Date
    ) {
        self.agentID = agentID
        self.sessionID = sessionID
        self.title = title
        self.projectPath = projectPath
        self.state = state
        self.reason = reason
        self.updatedAt = updatedAt
    }
}

public protocol TaskHintProviding: Sendable {
    func taskHints(now: Date) -> [TaskHint]
}

public struct AgentReport: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let state: LightState
    public let reason: String
    public let source: ReportSource
    public let processes: [MatchedProcess]
    public let projectPaths: [String]
    public let taskHints: [TaskHint]

    public init(
        id: String,
        displayName: String,
        state: LightState,
        reason: String,
        source: ReportSource,
        processes: [MatchedProcess],
        projectPaths: [String] = [],
        taskHints: [TaskHint] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.reason = reason
        self.source = source
        self.processes = processes
        self.projectPaths = projectPaths
        self.taskHints = taskHints
    }
}

public struct TaskReport: Equatable, Sendable {
    public let agentID: String
    public let displayName: String
    public let state: LightState
    public let reason: String
    public let source: ReportSource
    public let projectPath: String?
    public let sessionID: String?
    public let title: String?
    public let processes: [MatchedProcess]

    public init(
        agentID: String,
        displayName: String,
        state: LightState,
        reason: String,
        source: ReportSource,
        projectPath: String?,
        sessionID: String? = nil,
        title: String? = nil,
        processes: [MatchedProcess]
    ) {
        self.agentID = agentID
        self.displayName = displayName
        self.state = state
        self.reason = reason
        self.source = source
        self.projectPath = projectPath
        self.sessionID = sessionID
        self.title = title
        self.processes = processes
    }
}

public struct TaskGroupReport: Equatable, Sendable {
    public let agentID: String
    public let displayName: String
    public let state: LightState
    public let projectPath: String?
    public let tasks: [TaskReport]
    public let processes: [MatchedProcess]
    public let sessionIDs: [String]
    public let waitingCount: Int
    public let runningCount: Int
    public let stoppedCount: Int

    public var count: Int {
        tasks.count
    }

    public init(
        agentID: String,
        displayName: String,
        state: LightState,
        projectPath: String?,
        tasks: [TaskReport],
        processes: [MatchedProcess],
        sessionIDs: [String],
        waitingCount: Int,
        runningCount: Int,
        stoppedCount: Int
    ) {
        self.agentID = agentID
        self.displayName = displayName
        self.state = state
        self.projectPath = projectPath
        self.tasks = tasks
        self.processes = processes
        self.sessionIDs = sessionIDs
        self.waitingCount = waitingCount
        self.runningCount = runningCount
        self.stoppedCount = stoppedCount
    }
}

public struct DetectionResult: Equatable, Sendable {
    public let scannedAt: Date
    public let overallState: LightState
    public let reports: [AgentReport]

    public init(scannedAt: Date, overallState: LightState, reports: [AgentReport]) {
        self.scannedAt = scannedAt
        self.overallState = overallState
        self.reports = reports
    }

    public func reports(in state: LightState) -> [AgentReport] {
        reports
            .filter { $0.state == state }
            .sorted { $0.displayName < $1.displayName }
    }

    public var tasks: [TaskReport] {
        reports.flatMap { report -> [TaskReport] in
            if !report.taskHints.isEmpty {
                let attachableProcesses = Self.attachableUnprojectedProcesses(for: report)
                let hintedTasks = report.taskHints.map { hint in
                    let matchingProcesses = report.processes.filter { process in
                        Self.process(process, matches: hint, attachableProcesses: attachableProcesses)
                    }

                    return TaskReport(
                        agentID: report.id,
                        displayName: report.displayName,
                        state: hint.state,
                        reason: hint.reason,
                        source: report.source,
                        projectPath: hint.projectPath,
                        sessionID: hint.sessionID,
                        title: hint.title,
                        processes: matchingProcesses
                    )
                }

                let hintedProcessPIDs = Set(hintedTasks.flatMap { $0.processes.map(\.pid) })
                let hintedSessions = Set(report.taskHints.map(\.sessionID))
                let hintedProjectPaths = Set(report.taskHints.compactMap(\.projectPath))
                let remainingProcesses = report.processes.filter { process in
                    guard !process.projectPaths.isEmpty else {
                        return false
                    }

                    if hintedProcessPIDs.contains(process.pid) {
                        return false
                    }

                    if process.sessionID.map({ hintedSessions.contains($0) }) == true {
                        return false
                    }

                    if process.projectPaths.contains(where: hintedProjectPaths.contains) {
                        return false
                    }

                    return true
                }
                return hintedTasks + Self.processTasks(for: report, processes: remainingProcesses, includeGeneric: false)
            }

            return Self.processTasks(for: report, processes: report.processes, includeGeneric: true)
        }
    }

    private static func process(
        _ process: MatchedProcess,
        matches hint: TaskHint,
        attachableProcesses: [MatchedProcess]
    ) -> Bool {
        if process.sessionID == hint.sessionID {
            return true
        }

        if hint.projectPath.map({ process.projectPaths.contains($0) }) == true {
            return true
        }

        return hint.sessionID.hasPrefix("log:")
            && hint.state != .idle
            && hint.projectPath != nil
            && attachableProcesses.contains { $0.pid == process.pid }
    }

    private static func attachableUnprojectedProcesses(for report: AgentReport) -> [MatchedProcess] {
        let activeLogHints = report.taskHints.filter {
            $0.state != .idle
                && $0.projectPath != nil
                && $0.sessionID.hasPrefix("log:")
        }
        let hintedSessions = Set(report.taskHints.map(\.sessionID))
        let unprojectedSessionProcesses = report.processes.filter {
            guard $0.projectPaths.isEmpty,
                  let sessionID = $0.sessionID,
                  !hintedSessions.contains(sessionID)
            else {
                return false
            }

            return true
        }

        guard activeLogHints.count == 1,
              unprojectedSessionProcesses.count == 1
        else {
            return []
        }

        return unprojectedSessionProcesses
    }

    public func tasks(in state: LightState) -> [TaskReport] {
        tasks
            .filter { $0.state == state }
            .sorted {
                if $0.displayName != $1.displayName {
                    return $0.displayName < $1.displayName
                }

                if ($0.projectPath ?? "") != ($1.projectPath ?? "") {
                    return ($0.projectPath ?? "") < ($1.projectPath ?? "")
                }

                return ($0.sessionID ?? "") < ($1.sessionID ?? "")
            }
    }

    public var taskGroups: [TaskGroupReport] {
        Self.taskGroups(from: tasks)
    }

    public func taskGroups(in state: LightState) -> [TaskGroupReport] {
        taskGroups.filter { $0.state == state }
    }

    private static func taskGroups(from tasks: [TaskReport]) -> [TaskGroupReport] {
        var groups: [String: (
            agentID: String,
            displayName: String,
            state: LightState,
            projectPath: String?,
            tasks: [TaskReport],
            processes: [MatchedProcess],
            sessionIDs: [String],
            waitingCount: Int,
            runningCount: Int,
            stoppedCount: Int
        )] = [:]

        for task in tasks {
            let identity = task.projectPath
                ?? task.sessionID.map { "session:\($0)" }
                ?? task.title.map { "title:\($0)" }
                ?? "open-session"
            let key = "\(task.agentID)|\(identity)"
            var group = groups[key] ?? (
                task.agentID,
                task.displayName,
                task.state,
                task.projectPath,
                [],
                [],
                [],
                0,
                0,
                0
            )

            group.state = max(group.state, task.state)
            group.tasks.append(task)
            group.processes.append(contentsOf: task.processes)
            if let sessionID = task.sessionID, !group.sessionIDs.contains(sessionID) {
                group.sessionIDs.append(sessionID)
            }

            switch task.state {
            case .waitingForPermission:
                group.waitingCount += 1
            case .working:
                group.runningCount += 1
            case .idle:
                group.stoppedCount += 1
            }

            groups[key] = group
        }

        return groups.values
            .map { group in
                TaskGroupReport(
                    agentID: group.agentID,
                    displayName: group.displayName,
                    state: group.state,
                    projectPath: group.projectPath,
                    tasks: group.tasks,
                    processes: uniqueProcesses(group.processes),
                    sessionIDs: group.sessionIDs,
                    waitingCount: group.waitingCount,
                    runningCount: group.runningCount,
                    stoppedCount: group.stoppedCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.displayName != rhs.displayName {
                    return lhs.displayName < rhs.displayName
                }

                if (lhs.projectPath ?? "") != (rhs.projectPath ?? "") {
                    return (lhs.projectPath ?? "") < (rhs.projectPath ?? "")
                }

                return (lhs.sessionIDs.first ?? "") < (rhs.sessionIDs.first ?? "")
            }
    }

    private static func uniqueProcesses(_ processes: [MatchedProcess]) -> [MatchedProcess] {
        var seen = Set<Int>()
        return processes.filter { seen.insert($0.pid).inserted }
    }

    private static func processTasks(
        for report: AgentReport,
        processes: [MatchedProcess],
        includeGeneric: Bool
    ) -> [TaskReport] {
        let taskProcesses = processes.filter { !$0.projectPaths.isEmpty || $0.sessionID != nil }
        guard !taskProcesses.isEmpty else {
            guard includeGeneric else {
                return []
            }

            if report.projectPaths.isEmpty {
                return [
                    TaskReport(
                        agentID: report.id,
                        displayName: report.displayName,
                        state: report.state,
                        reason: report.reason,
                        source: report.source,
                        projectPath: nil,
                        processes: report.processes
                    )
                ]
            }

            return report.projectPaths.map { path in
                let matchingProcesses = report.processes.filter { $0.projectPaths.contains(path) }
                return TaskReport(
                    agentID: report.id,
                    displayName: report.displayName,
                    state: report.state,
                    reason: report.reason,
                    source: report.source,
                    projectPath: path,
                    processes: matchingProcesses.isEmpty ? report.processes : matchingProcesses
                )
            }
        }

        var groups: [String: (path: String?, sessionID: String?, processes: [MatchedProcess])] = [:]
        for process in taskProcesses {
            let paths = process.projectPaths.isEmpty ? [nil] : process.projectPaths.map(Optional.some)
            for path in paths {
                let key = "\(path ?? "")|\(process.sessionID ?? "pid:\(process.pid)")"
                var group = groups[key] ?? (path, process.sessionID, [])
                group.processes.append(process)
                groups[key] = group
            }
        }

        return groups.values.map { group in
            TaskReport(
                agentID: report.id,
                displayName: report.displayName,
                state: report.state,
                reason: report.reason,
                source: report.source,
                projectPath: group.path,
                sessionID: group.sessionID,
                processes: group.processes
            )
        }
    }
}

public final class AgentDetector {
    private struct ProcessMetadata {
        let snapshot: ProcessSnapshot
        let tokens: Set<String>
        let lowercasedCommandLine: String
        let projectPaths: [String]
        let sessionID: String?

        init(snapshot: ProcessSnapshot) {
            self.snapshot = snapshot
            tokens = snapshot.tokens
            lowercasedCommandLine = snapshot.commandLine.lowercased()
            projectPaths = AgentDetector.projectPaths(fromCommandLine: snapshot.commandLine)
            sessionID = AgentDetector.sessionID(fromCommandLine: snapshot.commandLine)
        }
    }

    private let definitions: [AgentDefinition]
    private let processProvider: ProcessSnapshotProviding
    private let overrideProvider: StatusOverrideProviding?
    private let taskHintProvider: TaskHintProviding?
    private let includeKnownIdleReports: Bool
    private let nowProvider: () -> Date

    public init(
        definitions: [AgentDefinition] = defaultAgentDefinitions,
        processProvider: ProcessSnapshotProviding = PSProcessProvider(),
        overrideProvider: StatusOverrideProviding? = nil,
        taskHintProvider: TaskHintProviding? = nil,
        includeKnownIdleReports: Bool = false,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.definitions = definitions
        self.processProvider = processProvider
        self.overrideProvider = overrideProvider
        self.taskHintProvider = taskHintProvider
        self.includeKnownIdleReports = includeKnownIdleReports
        self.nowProvider = nowProvider
    }

    public func detect() throws -> DetectionResult {
        let now = nowProvider()
        let processes = try processProvider.snapshots()
            .map(ProcessMetadata.init)
            .filter { !Self.isOwnToolProcess($0) }
        let processIndex = Dictionary(uniqueKeysWithValues: processes.map { ($0.snapshot.pid, $0) })
        let captureRoots = Self.captureRoots(definitions: definitions, processes: processes)
        let overrides = try overrideProvider?.activeOverrides(now: now) ?? []
        let overridesByID = Dictionary(grouping: overrides, by: \.agentID).compactMapValues {
            $0.sorted { $0.updatedAt > $1.updatedAt }.first
        }
        let definitionIDs = Set(definitions.map(\.id))
        let hintsByID = Dictionary(grouping: taskHintProvider?.taskHints(now: now) ?? [], by: \.agentID)

        var reports: [AgentReport] = []

        for definition in definitions {
            let matchingProcesses = processes.filter {
                Self.matches(
                    process: $0,
                    definition: definition,
                    processIndex: processIndex,
                    captureRoots: captureRoots
                )
            }
            let matchedProcesses = matchingProcesses.map {
                MatchedProcess(
                    snapshot: $0.snapshot,
                    projectPaths: $0.projectPaths,
                    sessionID: $0.sessionID
                )
            }
            let taskHints = hintsByID[definition.id] ?? []

            if let override = overridesByID[definition.id] {
                reports.append(AgentReport(
                    id: definition.id,
                    displayName: definition.displayName,
                    state: override.state,
                    reason: override.reason ?? "Manual override from signallanesctl.",
                    source: .manualOverride,
                    processes: matchedProcesses,
                    projectPaths: Self.unique(matchingProcesses.flatMap(\.projectPaths) + taskHints.compactMap(\.projectPath)),
                    taskHints: taskHints
                ))
                continue
            }

            if matchingProcesses.isEmpty {
                if !taskHints.isEmpty {
                    reports.append(AgentReport(
                        id: definition.id,
                        displayName: definition.displayName,
                        state: taskHints.map(\.state).max() ?? .idle,
                        reason: "Status reported by IDE session logs.",
                        source: .automatic,
                        processes: [],
                        projectPaths: Self.unique(taskHints.compactMap(\.projectPath)),
                        taskHints: taskHints
                    ))
                    continue
                }

                if includeKnownIdleReports {
                    reports.append(AgentReport(
                        id: definition.id,
                        displayName: definition.displayName,
                        state: .idle,
                        reason: "No matching process detected.",
                        source: .automatic,
                        processes: [],
                        projectPaths: []
                    ))
                }
                continue
            }

            let assessment = assess(definition: definition, processes: matchingProcesses)
            let hintState = taskHints.map(\.state).max()
            let shouldUseTaskHintsAsPrimarySignal = definition.activityMode == .cpuOrKeyword
                && hintState != nil
            let state = shouldUseTaskHintsAsPrimarySignal
                ? (hintState ?? .idle)
                : max(assessment.state, hintState ?? assessment.state)
            let reason: String
            if hintState == .waitingForPermission {
                reason = "A tracked IDE session is waiting for permission."
            } else if shouldUseTaskHintsAsPrimarySignal {
                reason = "Status reported by IDE session logs."
            } else {
                reason = assessment.reason
            }
            reports.append(AgentReport(
                id: definition.id,
                displayName: definition.displayName,
                state: state,
                reason: reason,
                source: .automatic,
                processes: matchedProcesses,
                projectPaths: Self.unique(matchingProcesses.flatMap(\.projectPaths) + taskHints.compactMap(\.projectPath)),
                taskHints: taskHints
            ))
        }

        for override in overrides where !definitionIDs.contains(override.agentID) {
            reports.append(AgentReport(
                id: override.agentID,
                displayName: override.agentID,
                state: override.state,
                reason: override.reason ?? "Manual override from signallanesctl.",
                source: .manualOverride,
                processes: [],
                projectPaths: []
            ))
        }

        let overallStates = reports.flatMap { [$0.state] + $0.taskHints.map(\.state) }
        let overallState = overallStates.max() ?? .idle
        return DetectionResult(scannedAt: now, overallState: overallState, reports: reports)
    }

    private func assess(
        definition: AgentDefinition,
        processes: [ProcessMetadata]
    ) -> (state: LightState, reason: String) {
        let commandText = processes.map(\.lowercasedCommandLine).joined(separator: "\n")

        if definition.waitingKeywords.contains(where: { commandText.contains($0) }) {
            return (.waitingForPermission, "Matched a permission or approval keyword.")
        }

        if definition.workingKeywords.contains(where: { commandText.contains($0) }) {
            return (.working, "Matched a work-in-progress keyword.")
        }

        if let busyProcess = processes.max(by: { $0.snapshot.cpuPercent < $1.snapshot.cpuPercent }),
           busyProcess.snapshot.cpuPercent >= definition.minimumBusyCPU {
            return (
                .working,
                "Process \(busyProcess.snapshot.pid) is using \(String(format: "%.1f", busyProcess.snapshot.cpuPercent))% CPU."
            )
        }

        if processes.contains(where: { $0.snapshot.isRunnable }) {
            return (.working, "A matching process is runnable.")
        }

        switch definition.activityMode {
        case .processPresence:
            return (.working, "A matching CLI agent process is running.")
        case .cpuOrKeyword:
            return (.idle, "Process is present, but no busy signal was detected.")
        }
    }

    private static func isOwnToolProcess(_ process: ProcessMetadata) -> Bool {
        let executable = executableName(fromCommandLine: process.snapshot.commandLine)
        return executable == "signallanes"
            || executable == "signallanesctl"
            || process.tokens.contains("signallanesctl")
            || process.snapshot.commandLine.contains(".build/debug/SignalLanes")
            || process.snapshot.commandLine.contains(".build/release/SignalLanes")
    }

    private static func executableName(fromCommandLine commandLine: String) -> String? {
        guard let firstToken = commandLine.split(separator: " ", maxSplits: 1).first else {
            return nil
        }

        return URL(fileURLWithPath: String(firstToken))
            .lastPathComponent
            .lowercased()
    }

    private static func captureRoots(
        definitions: [AgentDefinition],
        processes: [ProcessMetadata]
    ) -> [String: Set<Int>] {
        Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let roots = definition.capturesDescendants
                ? Set(processes.filter { definition.matches(
                    lowercasedCommandLine: $0.lowercasedCommandLine,
                    tokens: $0.tokens
                ) }.map(\.snapshot.pid))
                : []
            return (definition.id, roots)
        })
    }

    private static func matches(
        process: ProcessMetadata,
        definition: AgentDefinition,
        processIndex: [Int: ProcessMetadata],
        captureRoots: [String: Set<Int>]
    ) -> Bool {
        let isDirectMatch = definition.matches(
            lowercasedCommandLine: process.lowercasedCommandLine,
            tokens: process.tokens
        )
        let isCapturedDescendant = definition.capturesDescendants
            && hasAncestor(of: process, in: captureRoots[definition.id] ?? [], processIndex: processIndex)

        guard isDirectMatch || isCapturedDescendant else {
            return false
        }

        return !isCapturedByOtherDefinition(
            process,
            definitionID: definition.id,
            processIndex: processIndex,
            captureRoots: captureRoots
        )
    }

    private static func isCapturedByOtherDefinition(
        _ process: ProcessMetadata,
        definitionID: String,
        processIndex: [Int: ProcessMetadata],
        captureRoots: [String: Set<Int>]
    ) -> Bool {
        captureRoots.contains { id, roots in
            id != definitionID && hasAncestor(of: process, in: roots, processIndex: processIndex)
        }
    }

    private static func hasAncestor(
        of process: ProcessMetadata,
        in rootPIDs: Set<Int>,
        processIndex: [Int: ProcessMetadata]
    ) -> Bool {
        var parentPID = process.snapshot.parentPID
        var visited = Set<Int>()

        while parentPID > 0, visited.insert(parentPID).inserted {
            if rootPIDs.contains(parentPID) {
                return true
            }

            guard let parent = processIndex[parentPID] else {
                return false
            }
            parentPID = parent.snapshot.parentPID
        }

        return false
    }

    private static func projectPaths(fromCommandLine commandLine: String) -> [String] {
        let tokens = commandLine.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else {
            return []
        }

        let optionNames = Set([
            "--cwd",
            "--folder-uri",
            "--path",
            "--project",
            "--project-dir",
            "--root",
            "--workspace",
            "--workspace-folder",
            "--working-dir"
        ])
        var paths: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if optionNames.contains(token), index + 1 < tokens.count {
                let rawValue = collectArgumentValue(from: tokens, startingAt: index + 1)
                if let path = normalizeProjectPath(rawValue) {
                    paths.append(path)
                }
            } else if let equalSignIndex = token.firstIndex(of: "=") {
                let option = String(token[..<equalSignIndex])
                if optionNames.contains(option) {
                    let rawValue = String(token[token.index(after: equalSignIndex)...])
                    if let path = normalizeProjectPath(rawValue) {
                        paths.append(path)
                    }
                }
            }

            index += 1
        }

        paths.append(contentsOf: cdProjectPaths(fromCommandLine: commandLine))
        return unique(paths)
    }

    private static func collectArgumentValue(from tokens: [String], startingAt startIndex: Int) -> String {
        var valueParts: [String] = []
        var index = startIndex

        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("--"), !valueParts.isEmpty {
                break
            }

            valueParts.append(token)
            index += 1
        }

        return valueParts.joined(separator: " ")
    }

    private static func cdProjectPaths(fromCommandLine commandLine: String) -> [String] {
        var paths: [String] = []
        var searchRange = commandLine.startIndex..<commandLine.endIndex

        while let range = commandLine.range(of: "cd ", options: [], range: searchRange) {
            let parsedArgument = cdArgument(in: commandLine[range.upperBound...])
            if let rawPath = parsedArgument.value?
                .replacingOccurrences(of: "\\ ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let path = normalizeProjectPath(rawPath) {
                paths.append(path)
            }
            searchRange = parsedArgument.endIndex..<commandLine.endIndex
        }

        return paths
    }

    private static func cdArgument(in text: Substring) -> (value: String?, endIndex: String.Index) {
        var start = text.startIndex
        while start < text.endIndex, text[start] == " " {
            start = text.index(after: start)
        }

        guard start < text.endIndex else {
            return (nil, text.endIndex)
        }

        if text[start] == "\"" || text[start] == "'" {
            let quote = text[start]
            let valueStart = text.index(after: start)
            var cursor = valueStart
            while cursor < text.endIndex, text[cursor] != quote {
                cursor = text.index(after: cursor)
            }

            let endIndex = cursor < text.endIndex ? text.index(after: cursor) : cursor
            return (String(text[valueStart..<cursor]), endIndex)
        }

        let terminators = [" &&", ";", "'", "\"", "\n"]
            .compactMap { text.range(of: $0)?.lowerBound }
        let valueEnd = terminators.min() ?? text.endIndex
        return (String(text[start..<valueEnd]), valueEnd)
    }

    private static func sessionID(fromCommandLine commandLine: String) -> String? {
        let tokens = commandLine.split(separator: " ").map(String.init)
        let optionNames = ["--resume", "--session-id"]

        for (index, token) in tokens.enumerated() {
            if optionNames.contains(token), index + 1 < tokens.count {
                return normalizeSessionID(tokens[index + 1])
            }

            for option in optionNames where token.hasPrefix("\(option)=") {
                return normalizeSessionID(String(token.dropFirst(option.count + 1)))
            }
        }

        return nil
    }

    private static func normalizeSessionID(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard value.count >= 8 else {
            return nil
        }

        return value
    }

    private static func normalizeProjectPath(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }

        if value.hasPrefix("~/") {
            value = FileManager.default.homeDirectoryForCurrentUser.path + String(value.dropFirst())
        }

        guard value.hasPrefix("/") else {
            return nil
        }

        let excludedPrefixes = [
            "/Applications/",
            "/Library/",
            "/System/",
            "/bin/",
            "/sbin/",
            "/usr/"
        ]
        guard !excludedPrefixes.contains(where: { value.hasPrefix($0) }) else {
            return nil
        }

        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
