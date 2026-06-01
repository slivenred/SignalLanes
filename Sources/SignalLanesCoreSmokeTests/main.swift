import Darwin
import Foundation
import SignalLanesCore

private struct StubProcessProvider: ProcessSnapshotProviding {
    let snapshotsValue: [ProcessSnapshot]

    func snapshots() throws -> [ProcessSnapshot] {
        snapshotsValue
    }
}

private struct StubOverrideProvider: StatusOverrideProviding {
    let overrides: [StatusOverride]

    func activeOverrides(now: Date) throws -> [StatusOverride] {
        overrides.filter { $0.isActive(now: now) }
    }
}

private struct StubTaskHintProvider: TaskHintProviding {
    let hints: [TaskHint]

    func taskHints(now: Date) -> [TaskHint] {
        hints
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func testPSParserKeepsCommandWithSpaces() {
    let output = "123 1 0.0 S /Applications/Visual Studio Code.app/Contents/MacOS/Electron --type=renderer\n"
    let snapshots = PSProcessProvider.parsePSOutput(output)

    expect(snapshots == [
        ProcessSnapshot(
            pid: 123,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            commandLine: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron --type=renderer"
        )
    ], "ps parser should preserve command lines with spaces")
}

private func testCodexCliPresenceIsWorking() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/opt/homebrew/bin/codex"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .working, "codex CLI presence should be working")
    expect(result.reports.first?.id == "codex", "codex report should be present")
    expect(result.reports.first?.source == .automatic, "codex report should be automatic")
}

private func testCodexDesktopProcessDoesNotBecomeGenericCodexTask() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 20,
                state: "R",
                commandLine: "/Applications/Codex.app/Contents/MacOS/Codex"
            ),
            ProcessSnapshot(
                pid: 11,
                parentPID: 10,
                cpuPercent: 20,
                state: "R",
                commandLine: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "Codex Desktop app shell should not become a generic Codex CLI task")
    expect(result.reports.isEmpty, "Codex Desktop app shell should be represented only by session hints")
}

private func testManualWaitingOverrideWinsOverAutomaticWorking() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/opt/homebrew/bin/codex"
            )
        ]),
        overrideProvider: StubOverrideProvider(overrides: [
            StatusOverride(
                agentID: "codex",
                state: .waitingForPermission,
                reason: "approval needed",
                updatedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .waitingForPermission, "manual waiting override should set overall yellow")
    expect(result.reports.first?.state == .waitingForPermission, "codex should be yellow")
    expect(result.reports.first?.source == .manualOverride, "codex should use manual override source")
}

private func testPermissionFlagsDoNotImplyWaiting() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/path/to/claude --permission-prompt-tool stdio --permission-mode default --allow-dangerously-skip-permissions"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .working, "permission-related flags should not imply yellow")
    expect(result.reports.first?.id == "claude", "claude report should be present")
    expect(result.reports.first?.state == .working, "claude process should remain red when present")
}

private func testClaudeDesktopProcessDoesNotBecomeGenericClaudeCodeTask() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/Applications/Claude.app/Contents/MacOS/Claude"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "Claude Desktop app shell should not become a generic Claude Code task")
    expect(result.reports.isEmpty, "Claude Desktop app shell should be represented only by session hints")
}

private func testWorkingDirectoryFlagDoesNotImplyWorking() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-ide"],
                minimumBusyCPU: 3,
                activityMode: .cpuOrKeyword
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/Applications/Sample IDE.app/Contents/MacOS/sample-ide --working-dir /tmp/project"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "--working-dir should not imply red")
    expect(result.reports.first?.state == .idle, "idle IDE process should remain green overall")
}

private func testThinkingTokenFlagDoesNotImplyWorking() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-ide"],
                minimumBusyCPU: 3,
                activityMode: .cpuOrKeyword
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/Applications/Sample IDE.app/Contents/MacOS/sample-ide --max-thinking-tokens 4096"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "--max-thinking-tokens should not imply red")
    expect(result.reports.first?.state == .idle, "idle IDE process should remain green overall")
}

private func testExpiredOverrideIsIgnored() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: []),
        overrideProvider: StubOverrideProvider(overrides: [
            StatusOverride(
                agentID: "codex",
                state: .waitingForPermission,
                reason: nil,
                updatedAt: now.addingTimeInterval(-120),
                expiresAt: now.addingTimeInterval(-60)
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "expired override should not affect overall state")
    expect(result.reports.isEmpty, "expired override should not produce a report")
}

private func testKnownIdleReportsCanBeIncluded() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-ide"],
                activityMode: .cpuOrKeyword
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: []),
        includeKnownIdleReports: true,
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "all-idle queue should be green")
    expect(result.reports.count == 1, "known idle report should be included when requested")
    expect(result.reports.first?.state == .idle, "known idle report should be green")
    expect(result.reports.first?.reason == "No matching process detected.", "known idle report should explain missing process")
}

private func testReportsCanBeGroupedByState() throws {
    let result = DetectionResult(
        scannedAt: Date(timeIntervalSince1970: 100),
        overallState: .waitingForPermission,
        reports: [
            AgentReport(
                id: "b",
                displayName: "Beta",
                state: .working,
                reason: "busy",
                source: .automatic,
                processes: []
            ),
            AgentReport(
                id: "a",
                displayName: "Alpha",
                state: .working,
                reason: "busy",
                source: .automatic,
                processes: []
            ),
            AgentReport(
                id: "c",
                displayName: "Charlie",
                state: .idle,
                reason: "idle",
                source: .automatic,
                processes: []
            )
        ]
    )

    expect(result.reports(in: .working).map(\.displayName) == ["Alpha", "Beta"], "working reports should group and sort by name")
    expect(result.reports(in: .idle).map(\.displayName) == ["Charlie"], "idle reports should group by state")
}

private func testTasksSplitByProjectPath() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-ide"],
                minimumBusyCPU: 3,
                activityMode: .cpuOrKeyword
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 4,
                state: "S",
                commandLine: "/Applications/Sample IDE.app/Contents/MacOS/sample-ide --working-dir /tmp/project-one"
            ),
            ProcessSnapshot(
                pid: 11,
                parentPID: 1,
                cpuPercent: 5,
                state: "S",
                commandLine: "/Applications/Sample IDE.app/Contents/MacOS/sample-ide --working-dir /tmp/project-two"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let tasks = result.tasks(in: .working)

    expect(tasks.map(\.projectPath) == ["/tmp/project-one", "/tmp/project-two"], "task queue should split multiple project paths")
    expect(tasks.first?.processes.map(\.pid) == [10], "first project task should keep its matching process")
    expect(tasks.last?.processes.map(\.pid) == [11], "second project task should keep its matching process")
}

private func testTaskHintsCreateAntigravityWaitingTask() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: []),
        taskHintProvider: StubTaskHintProvider(hints: [
            TaskHint(
                agentID: "antigravity",
                sessionID: "session-a",
                title: "Approve shell command",
                projectPath: "/tmp/project",
                state: .waitingForPermission,
                reason: "Claude is requesting permission.",
                updatedAt: now
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let tasks = result.tasks(in: .waitingForPermission)

    expect(result.overallState == .waitingForPermission, "Antigravity task hint should set overall yellow")
    expect(tasks.count == 1, "Antigravity task hint should create one waiting task")
    expect(tasks.first?.title == "Approve shell command", "Antigravity task hint should preserve the conversation title")
}

private func testIDELogHintsOverrideNoisyProcessAssessment() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-ide"],
                minimumBusyCPU: 3,
                activityMode: .cpuOrKeyword,
                capturesDescendants: true
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 25,
                state: "R",
                commandLine: "/Applications/Sample IDE.app/Contents/MacOS/sample-ide --type=renderer"
            )
        ]),
        taskHintProvider: StubTaskHintProvider(hints: [
            TaskHint(
                agentID: "sample",
                sessionID: "session-a",
                title: "Idle chat",
                projectPath: "/tmp/project",
                state: .idle,
                reason: "session is idle",
                updatedAt: now
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()

    expect(result.overallState == .idle, "IDE session logs should override noisy renderer CPU")
    expect(result.tasks(in: .working).isEmpty, "noisy IDE processes should not create running tasks when logs say idle")
    expect(result.tasks(in: .idle).map(\.sessionID) == ["session-a"], "the logged session should remain visible as stopped")
}

private func testAntigravityCapturesClaudeChildProcess() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 100,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/Applications/Antigravity IDE.app/Contents/MacOS/Electron"
            ),
            ProcessSnapshot(
                pid: 101,
                parentPID: 100,
                cpuPercent: 0,
                state: "S",
                commandLine: "/Applications/Antigravity IDE.app/Contents/Frameworks/Antigravity IDE Helper.app/Contents/MacOS/Antigravity IDE Helper"
            ),
            ProcessSnapshot(
                pid: 102,
                parentPID: 101,
                cpuPercent: 4,
                state: "S",
                commandLine: "/Users/example/.antigravity-ide/extensions/anthropic.claude-code/resources/native-binary/claude --resume session-a"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let antigravity = result.reports.first { $0.id == "antigravity" }

    expect(antigravity?.processes.map(\.pid).contains(102) == true, "Antigravity should own Claude children launched inside the IDE")
    expect(!result.reports.contains { $0.id == "claude" }, "Claude child inside Antigravity should not also become a Claude Code report")
}

private func testTasksSplitBySameProjectSessions() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-agent"],
                activityMode: .processPresence
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/usr/local/bin/sample-agent --working-dir /tmp/project --resume session-a"
            ),
            ProcessSnapshot(
                pid: 11,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/usr/local/bin/sample-agent --working-dir /tmp/project --resume session-b"
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let tasks = result.tasks(in: .working)

    expect(tasks.count == 2, "same-project sessions should be separate queue tasks")
    expect(Set(tasks.compactMap(\.sessionID)) == ["session-a", "session-b"], "queue tasks should preserve each session ID")
}

private func testTaskGroupsRollUpSameProjectToHighestState() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        processProvider: StubProcessProvider(snapshotsValue: []),
        taskHintProvider: StubTaskHintProvider(hints: [
            TaskHint(
                agentID: "antigravity",
                sessionID: "running-session",
                title: "Running chat",
                projectPath: "/tmp/project",
                state: .working,
                reason: "recent activity",
                updatedAt: now
            ),
            TaskHint(
                agentID: "antigravity",
                sessionID: "idle-session",
                title: "Idle chat",
                projectPath: "/tmp/project",
                state: .idle,
                reason: "idle",
                updatedAt: now.addingTimeInterval(-60)
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let groups = result.taskGroups

    expect(result.tasks.count == 2, "raw queue tasks should still preserve separate sessions")
    expect(groups.count == 1, "same IDE and project should roll up into one display group")
    expect(groups.first?.state == .working, "display group should use the highest active state")
    expect(groups.first?.runningCount == 1, "display group should count running sessions")
    expect(groups.first?.stoppedCount == 1, "display group should count stopped sessions")
    expect(result.taskGroups(in: .idle).isEmpty, "lower-priority sessions should not duplicate the project in green")
}

private func testTaskHintsSuppressSameProjectProcessDuplicate() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-agent"],
                activityMode: .processPresence
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/usr/local/bin/sample-agent --working-dir /tmp/project --session-id process-session"
            )
        ]),
        taskHintProvider: StubTaskHintProvider(hints: [
            TaskHint(
                agentID: "sample",
                sessionID: "hint-session",
                title: nil,
                projectPath: "/tmp/project",
                state: .working,
                reason: "session file",
                updatedAt: now
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let tasks = result.tasks(in: .working)

    expect(tasks.count == 1, "same-project task hints should not be duplicated by process-derived tasks")
    expect(tasks.first?.sessionID == "hint-session", "session hint should remain the visible task")
}

private func testActiveLogHintAttachesSingleUnprojectedProcessDuplicate() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-agent"],
                activityMode: .processPresence
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/usr/local/bin/sample-agent --resume process-session"
            )
        ]),
        taskHintProvider: StubTaskHintProvider(hints: [
            TaskHint(
                agentID: "sample",
                sessionID: "log:sample/window1",
                title: nil,
                projectPath: "/tmp/project",
                state: .working,
                reason: "recent log activity",
                updatedAt: now
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let tasks = result.tasks(in: .working)

    expect(tasks.count == 1, "single active log hints should absorb the one unprojected process duplicate")
    expect(tasks.first?.sessionID == "log:sample/window1", "log hint should remain the visible task")
    expect(tasks.first?.processes.map(\.pid) == [10], "absorbed process should remain attached to the log hint")
}

private func testActiveLogHintSuppressesMultipleUnprojectedProcessDuplicates() throws {
    let now = Date(timeIntervalSince1970: 100)
    let detector = AgentDetector(
        definitions: [
            AgentDefinition(
                id: "sample",
                displayName: "Sample IDE",
                tokenMatchers: ["sample-agent"],
                activityMode: .processPresence
            )
        ],
        processProvider: StubProcessProvider(snapshotsValue: [
            ProcessSnapshot(
                pid: 10,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/usr/local/bin/sample-agent --resume process-session-a"
            ),
            ProcessSnapshot(
                pid: 11,
                parentPID: 1,
                cpuPercent: 0,
                state: "S",
                commandLine: "/usr/local/bin/sample-agent --resume process-session-b"
            )
        ]),
        taskHintProvider: StubTaskHintProvider(hints: [
            TaskHint(
                agentID: "sample",
                sessionID: "log:sample/window1",
                title: nil,
                projectPath: "/tmp/project",
                state: .working,
                reason: "recent log activity",
                updatedAt: now
            )
        ]),
        nowProvider: { now }
    )

    let result = try detector.detect()
    let tasks = result.tasks(in: .working)

    expect(tasks.count == 1, "multiple unprojected processes should not create ambiguous open-session duplicates")
    expect(tasks.first?.sessionID == "log:sample/window1", "log hint should remain the visible task")
}

private func testCodexSessionProviderReportsRecentDesktopSession() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("2026/05/30", isDirectory: true)
        .appendingPathComponent("rollout-test.jsonl")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 6_000)
    let jsonl = """
    {"timestamp":"2026-05-30T10:00:00.000Z","type":"session_meta","payload":{"id":"codex-session","cwd":"/tmp/signal-lanes","timestamp":"2026-05-30T10:00:00.000Z"}}
    {"timestamp":"2026-05-30T10:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-a"}}
    """
    try jsonl.write(to: sessionURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
        [.modificationDate: baseDate.addingTimeInterval(5)],
        ofItemAtPath: sessionURL.path
    )

    let provider = CodexSessionStatusProvider(
        rootURL: rootURL,
        maxSessionAge: 600,
        maxActiveAge: 120
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "Codex provider should report recent Desktop sessions")
    expect(hints.first?.agentID == "codex", "Codex provider should attach hints to the Codex report")
    expect(hints.first?.sessionID == "codex-session", "Codex provider should preserve session ID")
    expect(hints.first?.projectPath == "/tmp/signal-lanes", "Codex provider should preserve cwd as project path")
    expect(hints.first?.state == .working, "recent Codex sessions should be working")
}

private func testCodexSessionProviderDoesNotMarkMetadataOnlySessionWorking() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("2026/05/30", isDirectory: true)
        .appendingPathComponent("rollout-metadata-only.jsonl")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 6_100)
    let jsonl = """
    {"timestamp":"2026-05-30T10:00:00.000Z","type":"session_meta","payload":{"id":"metadata-only-codex-session","cwd":"/tmp/metadata-project","timestamp":"2026-05-30T10:00:00.000Z"}}
    {"timestamp":"2026-05-30T10:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user"}}
    """
    try jsonl.write(to: sessionURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
        [.modificationDate: baseDate.addingTimeInterval(5)],
        ofItemAtPath: sessionURL.path
    )

    let provider = CodexSessionStatusProvider(
        rootURL: rootURL,
        maxSessionAge: 600,
        maxActiveAge: 120
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "Codex provider should keep recent Desktop sessions visible")
    expect(hints.first?.state == .idle, "metadata-only Codex sessions should not be treated as active work")
}

private func testCodexSessionProviderMarksCompletedTurnIdleImmediately() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("2026/05/30", isDirectory: true)
        .appendingPathComponent("rollout-complete.jsonl")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 6_500)
    let jsonl = """
    {"timestamp":"2026-05-30T10:00:00.000Z","type":"session_meta","payload":{"id":"complete-codex-session","cwd":"/tmp/complete-project","timestamp":"2026-05-30T10:00:00.000Z"}}
    {"timestamp":"2026-05-30T10:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-a"}}
    {"timestamp":"2026-05-30T10:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-a"}}
    """
    try jsonl.write(to: sessionURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
        [.modificationDate: baseDate.addingTimeInterval(5)],
        ofItemAtPath: sessionURL.path
    )

    let provider = CodexSessionStatusProvider(
        rootURL: rootURL,
        maxSessionAge: 600,
        maxActiveAge: 120
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "Codex provider should keep recent completed sessions visible")
    expect(hints.first?.state == .idle, "completed Codex turns should become idle immediately")
}

private func testCodexSessionProviderMarksAbortedTurnIdleImmediately() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("2026/05/30", isDirectory: true)
        .appendingPathComponent("rollout-aborted.jsonl")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 6_700)
    let jsonl = """
    {"timestamp":"2026-05-30T10:00:00.000Z","type":"session_meta","payload":{"id":"aborted-codex-session","cwd":"/tmp/aborted-project","timestamp":"2026-05-30T10:00:00.000Z"}}
    {"timestamp":"2026-05-30T10:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-a"}}
    {"timestamp":"2026-05-30T10:00:05.000Z","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-a"}}
    """
    try jsonl.write(to: sessionURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
        [.modificationDate: baseDate.addingTimeInterval(5)],
        ofItemAtPath: sessionURL.path
    )

    let provider = CodexSessionStatusProvider(
        rootURL: rootURL,
        maxSessionAge: 600,
        maxActiveAge: 120
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "Codex provider should keep recent aborted sessions visible")
    expect(hints.first?.state == .idle, "aborted Codex turns should become idle immediately")
}

private func testCodexSessionProviderTailCanStartInsideUTF8Character() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("2026/05/30", isDirectory: true)
        .appendingPathComponent("rollout-utf8-tail.jsonl")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 6_800)
    let terminalLine = #"{"timestamp":"2026-05-30T10:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-a"}}"#
    let jsonl = [
        #"{"timestamp":"2026-05-30T10:00:00.000Z","type":"session_meta","payload":{"id":"utf8-codex-session","cwd":"/tmp/utf8-project","timestamp":"2026-05-30T10:00:00.000Z"}}"#,
        #"{"timestamp":"2026-05-30T10:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-a"}}"#,
        "中",
        terminalLine
    ].joined(separator: "\n")
    try jsonl.data(using: .utf8)!.write(to: sessionURL)
    try fileManager.setAttributes(
        [.modificationDate: baseDate.addingTimeInterval(5)],
        ofItemAtPath: sessionURL.path
    )

    let provider = CodexSessionStatusProvider(
        rootURL: rootURL,
        maxSessionAge: 600,
        maxActiveAge: 120,
        maxTailBytes: UInt64(terminalLine.utf8.count + 2)
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "Codex provider should parse a tail that starts inside a UTF-8 character")
    expect(hints.first?.state == .idle, "Codex tail decoding should preserve terminal events after a partial UTF-8 prefix")
}

private func testCodexSessionProviderSkipsOldSessions() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("2026/05/30", isDirectory: true)
        .appendingPathComponent("rollout-old.jsonl")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 7_000)
    let jsonl = """
    {"timestamp":"2026-05-30T10:00:00.000Z","type":"session_meta","payload":{"id":"old-codex-session","cwd":"/tmp/old-project","timestamp":"2026-05-30T10:00:00.000Z"}}
    """
    try jsonl.write(to: sessionURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
        [.modificationDate: baseDate.addingTimeInterval(-1_000)],
        ofItemAtPath: sessionURL.path
    )

    let provider = CodexSessionStatusProvider(
        rootURL: rootURL,
        maxSessionAge: 600,
        maxActiveAge: 120
    )
    let hints = provider.taskHints(now: baseDate)

    expect(hints.isEmpty, "Codex provider should skip sessions older than the scan window")
}

private func testAntigravityLogKeepsRecentPermissionOverRunningUpdate() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 1_000)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ json: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] Received message from webview: \(json)"
    }

    let log = [
        line(offset: 0, #"{"type":"launch_claude","cwd":"/tmp/project","permissionMode":"default","thinkingLevel":"default_on"}"#),
        line(offset: 1, #"{"type":"request","requestId":"1","request":{"type":"update_session_state","sessionId":"session-a","state":"running","title":"Check quota"}}"#),
        line(offset: 2, #"{"type":"request","requestId":"2","request":{"type":"rename_tab","title":"Check quota","hasPendingPermissions":true,"hasUnseenCompletion":false}}"#),
        line(offset: 2.001, #"{"type":"request","requestId":"3","request":{"type":"update_session_state","sessionId":"session-a","state":"waiting_input","title":"Check quota"}}"#),
        line(offset: 2.002, #"{"type":"request","requestId":"4","request":{"type":"show_notification","message":"Claude is requesting permission to use Bash","severity":"info","buttons":["View"],"onlyIfNotVisible":true}}"#),
        line(offset: 3, #"{"type":"request","requestId":"5","request":{"type":"update_session_state","sessionId":"session-a","state":"running","title":"Check quota"}}"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(
        rootURLs: [rootURL],
        maxStatusAge: 600,
        maxPendingPermissionAge: 300
    )
    let freshHints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(freshHints.first?.state == .waitingForPermission, "recent Antigravity permission should stay yellow even after a running update")
    expect(freshHints.first?.projectPath == "/tmp/project", "Antigravity log hint should preserve the launched project path")

    let staleProvider = AntigravityLogStatusProvider(
        rootURLs: [rootURL],
        maxStatusAge: 1_000,
        maxPendingPermissionAge: 5
    )
    let staleHints = staleProvider.taskHints(now: baseDate.addingTimeInterval(60))

    expect(staleHints.first?.state == .working, "stale Antigravity permission should fall back instead of staying yellow forever")
}

private func testAntigravityRenamePermissionTargetsFollowingSessionUpdate() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 1_500)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ json: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] Received message from webview: \(json)"
    }

    let log = [
        line(offset: 0, #"{"type":"request","requestId":"1","request":{"type":"update_session_state","sessionId":"previous-session","state":"idle"}}"#),
        line(offset: 1, #"{"type":"request","requestId":"2","request":{"type":"rename_tab","title":"Current task","hasPendingPermissions":true,"hasUnseenCompletion":false}}"#),
        line(offset: 1.001, #"{"type":"request","requestId":"3","request":{"type":"update_session_state","sessionId":"current-session","state":"waiting_input","title":"Current task"}}"#),
        line(offset: 1.002, #"{"type":"request","requestId":"4","request":{"type":"show_notification","message":"Claude is requesting permission to use ExitPlanMode","severity":"info","buttons":["View"],"onlyIfNotVisible":true}}"#),
        line(offset: 20, #"{"type":"request","requestId":"5","request":{"type":"rename_tab","title":"Current task","hasPendingPermissions":false,"hasUnseenCompletion":false}}"#),
        line(offset: 20.001, #"{"type":"request","requestId":"6","request":{"type":"update_session_state","sessionId":"current-session","state":"running","title":"Current task"}}"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(
        rootURLs: [rootURL],
        maxStatusAge: 600,
        maxPendingPermissionAge: 300
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(!hints.contains { $0.sessionID == "previous-session" }, "rename_tab permission should not attach to the previous session")
    expect(hints.first { $0.sessionID == "current-session" }?.state == .working, "following session update should receive and clear the permission state")
}

private func testAntigravityLogActivityAfterIdleMarksRunning() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_000)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ text: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] \(text)"
    }

    let log = [
        line(offset: 0, #"Received message from webview: {"type":"launch_claude","cwd":"/tmp/project","permissionMode":"default","thinkingLevel":"default_on"}"#),
        line(offset: 1, #"Received message from webview: {"type":"request","requestId":"1","request":{"type":"update_session_state","sessionId":"session-a","state":"idle","title":"Background work"}}"#),
        line(offset: 2, #"From claude: 2026-05-30T10:00:02.000Z [DEBUG] [API REQUEST] /api/anthropic/v1/messages source=sdk"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(rootURLs: [rootURL], maxStatusAge: 600)
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.first?.state == .working, "Antigravity Claude activity after an idle webview event should mark the session running")
}

private func testAntigravityLogSessionlessClaudeActivityMarksRunning() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_200)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ text: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] \(text)"
    }

    let log = [
        line(offset: 0, #"From claude: 2026-05-30T10:00:00.000Z [DEBUG] [API REQUEST] /api/anthropic/v1/messages source=agent:builtin:general-purpose"#),
        line(offset: 1, #"From claude: 2026-05-30T10:00:01.000Z [DEBUG] Stream started - received first chunk"#),
        line(offset: 2, #"From claude: 2026-05-30T10:00:02.000Z [INFO] [Stall] tool_dispatch_start tool=Bash toolUseId=call-sessionless permissionDecisionMs=1"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(rootURLs: [rootURL], maxStatusAge: 600)
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "sessionless Antigravity Claude activity should create one task hint")
    expect(hints.first?.sessionID.hasPrefix("log:") == true, "sessionless Antigravity Claude activity should use a log-derived session ID")
    expect(hints.first?.state == .working, "sessionless Antigravity Claude activity should mark the session running")
}

private func testAntigravityLogSessionlessActivityInfersProjectFromFilePath() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let projectURL = rootURL.appendingPathComponent("example project", isDirectory: true)
    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(
        at: projectURL.appendingPathComponent("output", isDirectory: true),
        withIntermediateDirectories: true
    )
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_250)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ text: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] \(text)"
    }

    let filePath = projectURL
        .appendingPathComponent("output", isDirectory: true)
        .appendingPathComponent("article.html.tmp")
        .path
    let log = [
        line(offset: 0, "From claude: 2026-05-30T10:00:00.000Z [INFO] Writing to temp file: \(filePath)"),
        line(offset: 1, #"From claude: 2026-05-30T10:00:01.000Z [DEBUG] Stream started - received first chunk"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(rootURLs: [rootURL], maxStatusAge: 600)
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "sessionless activity with a file path should create one hint")
    expect(
        hints.first?.projectPath == projectURL.standardizedFileURL.path,
        "Antigravity should infer the workspace root from activity file paths"
    )
}

private func testAntigravityLogIgnoresHomeConfigActivityPaths() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_260)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ text: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] \(text)"
    }

    let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json.tmp.123")
        .path
    let log = [
        line(offset: 0, "From claude: 2026-05-30T10:00:00.000Z [DEBUG] Writing to temp file: \(configPath)"),
        line(offset: 1, #"From claude: 2026-05-30T10:00:01.000Z [DEBUG] Stream started - received first chunk"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(rootURLs: [rootURL], maxStatusAge: 600)
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "home config activity should still report a running fallback hint")
    expect(hints.first?.projectPath == nil, "home config activity should not be treated as a project")
}

private func testAntigravityLogMergesSingleProjectFallbackIntoConcreteSession() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let projectURL = rootURL.appendingPathComponent("merge project", isDirectory: true)
    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(
        at: projectURL.appendingPathComponent("Sources", isDirectory: true),
        withIntermediateDirectories: true
    )
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_270)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ text: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] \(text)"
    }

    let filePath = projectURL
        .appendingPathComponent("Sources", isDirectory: true)
        .appendingPathComponent("App.swift.tmp")
        .path
    let log = [
        line(offset: 0, "From claude: 2026-05-30T10:00:00.000Z [INFO] Writing to temp file: \(filePath)"),
        line(offset: 1, #"Received message from webview: {"type":"launch_claude","cwd":"\#(projectURL.path)","permissionMode":"default","thinkingLevel":"default_on"}"#),
        line(offset: 2, #"Received message from webview: {"type":"request","requestId":"1","request":{"type":"update_session_state","sessionId":"session-a","state":"idle","title":"Merged work"}}"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(rootURLs: [rootURL], maxStatusAge: 600)
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "single-project fallback activity should merge into the concrete session")
    expect(hints.first?.sessionID == "session-a", "merged fallback should preserve the concrete session ID")
    expect(hints.first?.state == .working, "merged fallback activity should keep the concrete session red")
}

private func testAntigravityLogTailCanStartInsideUTF8Character() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_300)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let activityLine = "\(formatter.string(from: baseDate)) [info] From claude: 2026-05-30T10:00:00.000Z [DEBUG] [API REQUEST] /api/anthropic/v1/messages source=sdk"
    let prefix = "中\n"
    try (prefix + activityLine).data(using: .utf8)!.write(to: logURL)

    let provider = AntigravityLogStatusProvider(
        rootURLs: [rootURL],
        maxStatusAge: 600,
        maxTailBytes: UInt64(activityLine.utf8.count + 2)
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.first?.state == .working, "Antigravity log tail should decode even if it starts inside a UTF-8 character")
}

private func testAntigravityLogSkipsTransientIdleSessionWithoutTitleOrActivity() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 2_500)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ json: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] Received message from webview: \(json)"
    }

    let log = [
        line(offset: 0, #"{"type":"launch_claude","cwd":"/tmp/project","permissionMode":"default","thinkingLevel":"default_on"}"#),
        line(offset: 1, #"{"type":"request","requestId":"1","request":{"type":"update_session_state","sessionId":"session-a","state":"running","title":"Active project"}}"#),
        line(offset: 120, #"{"type":"launch_claude","cwd":"/tmp/project","permissionMode":"default","thinkingLevel":"default_on"}"#),
        line(offset: 120.5, #"{"type":"request","requestId":"2","request":{"type":"update_session_state","sessionId":"session-b","state":"idle"}}"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(
        rootURLs: [rootURL],
        maxStatusAge: 600,
        maxActiveStatusAge: 600
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(130))

    expect(hints.count == 1, "Antigravity should skip transient idle sessions without title or activity")
    expect(hints.first?.sessionID == "session-a", "Antigravity should keep the launched session")
    expect(hints.first?.projectPath == "/tmp/project", "Antigravity should keep the project path for the active session")
}

private func testClaudeVSCodeLogProviderCanUseOtherIDEAgentIDs() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let logURL = rootURL
        .appendingPathComponent("logs/20260530T120000/window1/exthost/Anthropic.claude-code", isDirectory: true)
        .appendingPathComponent("Claude VSCode.log")
    try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 3_000)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    func line(offset: TimeInterval, _ json: String) -> String {
        "\(formatter.string(from: baseDate.addingTimeInterval(offset))) [info] Received message from webview: \(json)"
    }

    let log = [
        line(offset: 0, #"{"type":"launch_claude","cwd":"/tmp/cursor-project","permissionMode":"default","thinkingLevel":"default_on"}"#),
        line(offset: 1, #"{"type":"request","requestId":"1","request":{"type":"update_session_state","sessionId":"session-cursor","state":"running","title":"Cursor work"}}"#)
    ].joined(separator: "\n")
    try log.write(to: logURL, atomically: true, encoding: .utf8)

    let provider = AntigravityLogStatusProvider(
        agentID: "cursor",
        sourceName: "Cursor",
        rootURLs: [rootURL],
        maxStatusAge: 600
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.first?.agentID == "cursor", "Claude VS Code log provider should be reusable for Cursor")
    expect(hints.first?.projectPath == "/tmp/cursor-project", "Cursor Claude log hint should preserve project path")
    expect(hints.first?.state == .working, "Cursor Claude log hint should preserve session state")
}

private func testClaudeDesktopProviderReportsSelectedFolders() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("local-agent-mode-sessions/account/workspace", isDirectory: true)
        .appendingPathComponent("local_session-a.json")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 4_000)
    let lastActivityMilliseconds = Int(baseDate.addingTimeInterval(5).timeIntervalSince1970 * 1_000)
    let json = """
    {
      "sessionId": "local_session-a",
      "cliSessionId": "cli-session-a",
      "title": "Review project",
      "cwd": "/Users/example/Library/Application Support/Claude/local-agent-mode-sessions/account/workspace/local_session-a/outputs",
      "userSelectedFolders": ["/tmp/claude-project"],
      "lastActivityAt": \(lastActivityMilliseconds),
      "isArchived": false
    }
    """
    try json.write(to: sessionURL, atomically: true, encoding: .utf8)

    let provider = ClaudeDesktopStatusProvider(
        rootURLs: [rootURL],
        maxSessionAge: 600,
        maxActiveAge: 120
    )
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.count == 1, "Claude Desktop provider should report active local sessions")
    expect(hints.first?.agentID == "claude", "Claude Desktop provider should attach hints to the Claude report")
    expect(hints.first?.sessionID == "cli-session-a", "Claude Desktop provider should prefer the CLI session ID")
    expect(hints.first?.projectPath == "/tmp/claude-project", "Claude Desktop provider should use selected folders as project paths")
    expect(hints.first?.state == .working, "recent Claude Desktop sessions should be working")
}

private func testClaudeDesktopProviderSkipsArchivedSessions() throws {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("signal-lanes-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let sessionURL = rootURL
        .appendingPathComponent("local-agent-mode-sessions/account/workspace", isDirectory: true)
        .appendingPathComponent("local_session-b.json")
    try fileManager.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let baseDate = Date(timeIntervalSince1970: 5_000)
    let lastActivityMilliseconds = Int(baseDate.addingTimeInterval(5).timeIntervalSince1970 * 1_000)
    let json = """
    {
      "sessionId": "local_session-b",
      "title": "Archived task",
      "userSelectedFolders": ["/tmp/archived-project"],
      "lastActivityAt": \(lastActivityMilliseconds),
      "isArchived": true
    }
    """
    try json.write(to: sessionURL, atomically: true, encoding: .utf8)

    let provider = ClaudeDesktopStatusProvider(rootURLs: [rootURL], maxSessionAge: 600)
    let hints = provider.taskHints(now: baseDate.addingTimeInterval(30))

    expect(hints.isEmpty, "Claude Desktop provider should not show archived sessions")
}

do {
    testPSParserKeepsCommandWithSpaces()
    try testCodexCliPresenceIsWorking()
    try testCodexDesktopProcessDoesNotBecomeGenericCodexTask()
    try testManualWaitingOverrideWinsOverAutomaticWorking()
    try testPermissionFlagsDoNotImplyWaiting()
    try testClaudeDesktopProcessDoesNotBecomeGenericClaudeCodeTask()
    try testWorkingDirectoryFlagDoesNotImplyWorking()
    try testThinkingTokenFlagDoesNotImplyWorking()
    try testExpiredOverrideIsIgnored()
    try testKnownIdleReportsCanBeIncluded()
    try testReportsCanBeGroupedByState()
    try testTasksSplitByProjectPath()
    try testTaskHintsCreateAntigravityWaitingTask()
    try testIDELogHintsOverrideNoisyProcessAssessment()
    try testAntigravityCapturesClaudeChildProcess()
    try testTasksSplitBySameProjectSessions()
    try testTaskGroupsRollUpSameProjectToHighestState()
    try testTaskHintsSuppressSameProjectProcessDuplicate()
    try testActiveLogHintAttachesSingleUnprojectedProcessDuplicate()
    try testActiveLogHintSuppressesMultipleUnprojectedProcessDuplicates()
    try testCodexSessionProviderReportsRecentDesktopSession()
    try testCodexSessionProviderDoesNotMarkMetadataOnlySessionWorking()
    try testCodexSessionProviderMarksCompletedTurnIdleImmediately()
    try testCodexSessionProviderMarksAbortedTurnIdleImmediately()
    try testCodexSessionProviderTailCanStartInsideUTF8Character()
    try testCodexSessionProviderSkipsOldSessions()
    try testAntigravityLogKeepsRecentPermissionOverRunningUpdate()
    try testAntigravityRenamePermissionTargetsFollowingSessionUpdate()
    try testAntigravityLogActivityAfterIdleMarksRunning()
    try testAntigravityLogSessionlessClaudeActivityMarksRunning()
    try testAntigravityLogSessionlessActivityInfersProjectFromFilePath()
    try testAntigravityLogIgnoresHomeConfigActivityPaths()
    try testAntigravityLogMergesSingleProjectFallbackIntoConcreteSession()
    try testAntigravityLogTailCanStartInsideUTF8Character()
    try testAntigravityLogSkipsTransientIdleSessionWithoutTitleOrActivity()
    try testClaudeVSCodeLogProviderCanUseOtherIDEAgentIDs()
    try testClaudeDesktopProviderReportsSelectedFolders()
    try testClaudeDesktopProviderSkipsArchivedSessions()
    print("SignalLanesCoreSmokeTests passed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
