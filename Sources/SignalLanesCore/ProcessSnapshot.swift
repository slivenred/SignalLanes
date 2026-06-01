import Foundation

public struct ProcessSnapshot: Equatable, Sendable {
    public let pid: Int
    public let parentPID: Int
    public let cpuPercent: Double
    public let state: String
    public let commandLine: String

    public init(
        pid: Int,
        parentPID: Int,
        cpuPercent: Double,
        state: String,
        commandLine: String
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.cpuPercent = cpuPercent
        self.state = state
        self.commandLine = commandLine
    }

    public var tokens: Set<String> {
        Self.tokenize(commandLine)
    }

    public var isRunnable: Bool {
        state.uppercased().contains("R")
    }

    public static func tokenize(_ text: String) -> Set<String> {
        let normalizedScalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }

            return " "
        }

        return Set(String(normalizedScalars).split(separator: " ").map(String.init))
    }
}
