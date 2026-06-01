import Foundation

public struct AgentDefinition: Equatable, Sendable {
    public enum ActivityMode: Equatable, Sendable {
        case processPresence
        case cpuOrKeyword
    }

    public let id: String
    public let displayName: String
    public let tokenMatchers: Set<String>
    public let substringMatchers: [String]
    public let excludedSubstringMatchers: [String]
    public let waitingKeywords: [String]
    public let workingKeywords: [String]
    public let minimumBusyCPU: Double
    public let activityMode: ActivityMode
    public let capturesDescendants: Bool

    public init(
        id: String,
        displayName: String,
        tokenMatchers: Set<String>,
        substringMatchers: [String] = [],
        excludedSubstringMatchers: [String] = [],
        waitingKeywords: [String] = AgentDefinition.defaultWaitingKeywords,
        workingKeywords: [String] = AgentDefinition.defaultWorkingKeywords,
        minimumBusyCPU: Double = 3,
        activityMode: ActivityMode,
        capturesDescendants: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.tokenMatchers = Set(tokenMatchers.map { $0.lowercased() })
        self.substringMatchers = substringMatchers.map { $0.lowercased() }
        self.excludedSubstringMatchers = excludedSubstringMatchers.map { $0.lowercased() }
        self.waitingKeywords = waitingKeywords.map { $0.lowercased() }
        self.workingKeywords = workingKeywords.map { $0.lowercased() }
        self.minimumBusyCPU = minimumBusyCPU
        self.activityMode = activityMode
        self.capturesDescendants = capturesDescendants
    }

    public func matches(_ process: ProcessSnapshot) -> Bool {
        matches(
            lowercasedCommandLine: process.commandLine.lowercased(),
            tokens: process.tokens
        )
    }

    func matches(lowercasedCommandLine commandLine: String, tokens processTokens: Set<String>) -> Bool {
        if excludedSubstringMatchers.contains(where: { commandLine.contains($0) }) {
            return false
        }

        if substringMatchers.contains(where: { commandLine.contains($0) }) {
            return true
        }

        return tokenMatchers.contains(where: processTokens.contains)
    }

    public static let defaultWaitingKeywords = [
        "approval required",
        "authorization required",
        "confirmation required",
        "permission required",
        "requires approval",
        "requires authorization",
        "requires confirmation",
        "requires permission",
        "waiting for approval",
        "waiting for permission",
        "waiting on approval",
        "waiting on permission"
    ]

    public static let defaultWorkingKeywords = [
        "building",
        "executing",
        "generating",
        "indexing",
        "running"
    ]
}

public let defaultAgentDefinitions: [AgentDefinition] = [
    AgentDefinition(
        id: "codex",
        displayName: "Codex",
        tokenMatchers: ["codex", "codex-cli"],
        excludedSubstringMatchers: [
            "/applications/codex.app/",
            "/library/application support/codex/",
            "/library/application support/com.openai.codex/"
        ],
        activityMode: .processPresence,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "claude",
        displayName: "Claude Code",
        tokenMatchers: ["claude", "claude-code", "claude_code"],
        substringMatchers: ["claude code.app"],
        excludedSubstringMatchers: ["/applications/claude.app/"],
        activityMode: .processPresence,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "antigravity",
        displayName: "Antigravity",
        tokenMatchers: ["antigravity"],
        substringMatchers: ["antigravity.app", "antigravity ide.app"],
        activityMode: .cpuOrKeyword,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "cursor",
        displayName: "Cursor",
        tokenMatchers: ["cursor"],
        substringMatchers: ["cursor.app"],
        activityMode: .cpuOrKeyword,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "windsurf",
        displayName: "Windsurf",
        tokenMatchers: ["windsurf"],
        substringMatchers: ["windsurf.app"],
        activityMode: .cpuOrKeyword,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "vscode",
        displayName: "Visual Studio Code",
        tokenMatchers: [],
        substringMatchers: ["visual studio code.app", "/applications/visual studio code"],
        activityMode: .cpuOrKeyword,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "zed",
        displayName: "Zed",
        tokenMatchers: ["zed"],
        substringMatchers: ["zed.app"],
        activityMode: .cpuOrKeyword,
        capturesDescendants: true
    ),
    AgentDefinition(
        id: "xcode",
        displayName: "Xcode",
        tokenMatchers: ["xcodebuild"],
        substringMatchers: ["xcode.app"],
        activityMode: .cpuOrKeyword
    ),
    AgentDefinition(
        id: "aider",
        displayName: "Aider",
        tokenMatchers: ["aider"],
        activityMode: .processPresence
    ),
    AgentDefinition(
        id: "gemini",
        displayName: "Gemini CLI",
        tokenMatchers: ["gemini", "gemini-cli"],
        activityMode: .processPresence
    ),
    AgentDefinition(
        id: "opencode",
        displayName: "OpenCode",
        tokenMatchers: ["opencode"],
        activityMode: .processPresence
    ),
    AgentDefinition(
        id: "goose",
        displayName: "Goose",
        tokenMatchers: ["goose"],
        activityMode: .processPresence
    )
]
