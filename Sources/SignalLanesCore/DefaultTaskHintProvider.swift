import Foundation

public enum DefaultTaskHintProvider {
    public static func make() -> CompositeTaskHintProvider {
        let applicationSupport = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return CompositeTaskHintProvider([
            CodexSessionStatusProvider(),
            AntigravityLogStatusProvider(),
            AntigravityLogStatusProvider(
                agentID: "vscode",
                sourceName: "Visual Studio Code",
                rootURLs: [
                    applicationSupport.appendingPathComponent("Code", isDirectory: true),
                    applicationSupport.appendingPathComponent("Code - Insiders", isDirectory: true),
                    applicationSupport.appendingPathComponent("VSCodium", isDirectory: true)
                ]
            ),
            AntigravityLogStatusProvider(
                agentID: "cursor",
                sourceName: "Cursor",
                rootURLs: [
                    applicationSupport.appendingPathComponent("Cursor", isDirectory: true),
                    applicationSupport.appendingPathComponent("Cursor - Insiders", isDirectory: true)
                ]
            ),
            AntigravityLogStatusProvider(
                agentID: "windsurf",
                sourceName: "Windsurf",
                rootURLs: [
                    applicationSupport.appendingPathComponent("Windsurf", isDirectory: true),
                    applicationSupport.appendingPathComponent("Windsurf - Next", isDirectory: true)
                ]
            ),
            ClaudeDesktopStatusProvider()
        ])
    }
}
