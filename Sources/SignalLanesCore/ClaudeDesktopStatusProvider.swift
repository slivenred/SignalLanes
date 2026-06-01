import Foundation

public struct ClaudeDesktopStatusProvider: TaskHintProviding {
    private let rootURLs: [URL]
    private let maxSessionAge: TimeInterval
    private let maxActiveAge: TimeInterval
    private let maxFiles: Int

    public init(
        rootURLs: [URL]? = nil,
        maxSessionAge: TimeInterval = 24 * 60 * 60,
        maxActiveAge: TimeInterval = 10 * 60,
        maxFiles: Int = 50
    ) {
        if let rootURLs {
            self.rootURLs = rootURLs
        } else {
            let applicationSupport = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.rootURLs = [
                applicationSupport.appendingPathComponent("Claude", isDirectory: true),
                applicationSupport.appendingPathComponent("Claude-3p", isDirectory: true)
            ]
        }
        self.maxSessionAge = maxSessionAge
        self.maxActiveAge = maxActiveAge
        self.maxFiles = maxFiles
    }

    public func taskHints(now: Date) -> [TaskHint] {
        sessionFiles(now: now)
            .compactMap { taskHint(from: $0, now: now) }
    }

    private func sessionFiles(now: Date) -> [URL] {
        let cutoff = now.addingTimeInterval(-maxSessionAge)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for rootURL in rootURLs {
            let sessionsURL = rootURL.appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: sessionsURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "json",
                      fileURL.lastPathComponent.hasPrefix("local_")
                else {
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff
                else {
                    continue
                }
                candidates.append((fileURL, modifiedAt))
            }
        }

        return candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFiles)
            .map(\.url)
    }

    private func taskHint(from fileURL: URL, now: Date) -> TaskHint? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["isArchived"] as? Bool != true,
              let sessionID = stringValue(for: "cliSessionId", in: dictionary)
                ?? stringValue(for: "sessionId", in: dictionary)
        else {
            return nil
        }

        let updatedAt = dateFromMilliseconds(dictionary["lastActivityAt"])
            ?? fileModificationDate(fileURL)
            ?? now
        guard updatedAt >= now.addingTimeInterval(-maxSessionAge) else {
            return nil
        }

        let title = cleanTitle(
            stringValue(for: "title", in: dictionary)
                ?? stringValue(for: "processName", in: dictionary)
                ?? stringValue(for: "initialMessage", in: dictionary)
        )
        let projectPath = selectedFolderPath(from: dictionary)
            ?? projectPathFromCWD(stringValue(for: "cwd", in: dictionary))
        let state: LightState = updatedAt >= now.addingTimeInterval(-maxActiveAge) ? .working : .idle
        let projectText = projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? title ?? "session"

        return TaskHint(
            agentID: "claude",
            sessionID: sessionID,
            title: title,
            projectPath: projectPath,
            state: state,
            reason: "Claude Desktop session is \(state == .working ? "recently active" : "idle"): \(projectText)",
            updatedAt: updatedAt
        )
    }

    private func selectedFolderPath(from dictionary: [String: Any]) -> String? {
        guard let folders = dictionary["userSelectedFolders"] as? [Any] else {
            return nil
        }

        for folder in folders {
            if let path = normalizePath(folder as? String) {
                return path
            }

            if let object = folder as? [String: Any],
               let path = normalizePath(stringValue(for: "path", in: object) ?? stringValue(for: "uri", in: object)) {
                return path
            }
        }

        return nil
    }

    private func projectPathFromCWD(_ rawValue: String?) -> String? {
        guard let path = normalizePath(rawValue) else {
            return nil
        }

        let lowercasedPath = path.lowercased()
        if lowercasedPath.contains("/library/application support/claude/")
            || lowercasedPath.contains("/library/application support/claude-3p/") {
            return nil
        }

        return path
    }

    private func normalizePath(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }

        value = value.removingPercentEncoding ?? value
        if value.hasPrefix("~/") {
            value = FileManager.default.homeDirectoryForCurrentUser.path + String(value.dropFirst())
        }

        guard value.hasPrefix("/") else {
            return nil
        }

        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private func cleanTitle(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return String(trimmed.prefix(80))
    }

    private func stringValue(for key: String, in dictionary: [String: Any]) -> String? {
        guard let value = dictionary[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return value
    }

    private func dateFromMilliseconds(_ value: Any?) -> Date? {
        if let milliseconds = value as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }

        if let milliseconds = value as? Int {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        }

        if let text = value as? String, let milliseconds = Double(text) {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }

        return nil
    }

    private func fileModificationDate(_ fileURL: URL) -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
