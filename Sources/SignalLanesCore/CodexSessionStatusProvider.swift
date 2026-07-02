import Foundation

public struct CodexSessionStatusProvider: TaskHintProviding {
    private struct SessionFile {
        var url: URL
        var modifiedAt: Date
        var size: UInt64
    }

    private struct ParsedSession {
        var sessionID: String
        var projectPath: String
        var modifiedAt: Date
        var stateFromTail: LightState?
    }

    private final class ParseCache: @unchecked Sendable {
        enum Lookup {
            case hit(ParsedSession?)
            case miss
        }

        private struct Entry {
            var modifiedAt: Date
            var size: UInt64
            var maxFirstLineBytes: Int
            var maxTailBytes: UInt64
            var parsedSession: ParsedSession?
        }

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        func lookup(
            for path: String,
            modifiedAt: Date,
            size: UInt64,
            maxFirstLineBytes: Int,
            maxTailBytes: UInt64
        ) -> Lookup {
            lock.lock()
            defer { lock.unlock() }

            guard let entry = entries[path],
                  entry.modifiedAt == modifiedAt,
                  entry.size == size,
                  entry.maxFirstLineBytes == maxFirstLineBytes,
                  entry.maxTailBytes == maxTailBytes
            else {
                return .miss
            }

            return .hit(entry.parsedSession)
        }

        func store(
            _ parsedSession: ParsedSession?,
            for path: String,
            modifiedAt: Date,
            size: UInt64,
            maxFirstLineBytes: Int,
            maxTailBytes: UInt64
        ) {
            lock.lock()
            defer { lock.unlock() }

            entries[path] = Entry(
                modifiedAt: modifiedAt,
                size: size,
                maxFirstLineBytes: maxFirstLineBytes,
                maxTailBytes: maxTailBytes,
                parsedSession: parsedSession
            )

            if entries.count > 256 {
                let keysToRemove = entries
                    .sorted { $0.value.modifiedAt < $1.value.modifiedAt }
                    .prefix(entries.count - 128)
                    .map(\.key)
                for key in keysToRemove {
                    entries.removeValue(forKey: key)
                }
            }
        }
    }

    private let rootURL: URL
    private let maxSessionAge: TimeInterval
    private let maxFirstLineBytes: Int
    private let maxTailBytes: UInt64
    private let maxFiles: Int
    private let parseCache: ParseCache

    public init(
        rootURL: URL? = nil,
        maxSessionAge: TimeInterval = 4 * 60 * 60,
        maxActiveAge _: TimeInterval = 2 * 60,
        maxFirstLineBytes: Int = 1_000_000,
        maxTailBytes: UInt64 = 300_000,
        maxFiles: Int = 40
    ) {
        self.rootURL = rootURL
            ?? FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true)
        self.maxSessionAge = maxSessionAge
        self.maxFirstLineBytes = maxFirstLineBytes
        self.maxTailBytes = maxTailBytes
        self.maxFiles = maxFiles
        parseCache = ParseCache()
    }

    public func taskHints(now: Date) -> [TaskHint] {
        sessionFiles(now: now)
            .compactMap { taskHint(from: $0, now: now) }
    }

    private func sessionFiles(now: Date) -> [SessionFile] {
        let cutoff = now.addingTimeInterval(-maxSessionAge)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var candidates: [SessionFile] = []

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  fileURL.lastPathComponent.hasPrefix("rollout-")
            else {
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  let fileSize = values.fileSize,
                  modifiedAt >= cutoff
            else {
                continue
            }
            candidates.append(SessionFile(
                url: fileURL,
                modifiedAt: modifiedAt,
                size: UInt64(max(fileSize, 0))
            ))
        }

        return Array(candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFiles))
    }

    private func taskHint(from sessionFile: SessionFile, now: Date) -> TaskHint? {
        guard let parsedSession = parsedSession(from: sessionFile) else {
            return nil
        }

        guard let state = parsedSession.stateFromTail,
              state != .idle
        else {
            return nil
        }

        return TaskHint(
            agentID: "codex",
            sessionID: parsedSession.sessionID,
            title: nil,
            projectPath: parsedSession.projectPath,
            state: state,
            reason: reason(for: state),
            updatedAt: parsedSession.modifiedAt
        )
    }

    private func parsedSession(from sessionFile: SessionFile) -> ParsedSession? {
        switch parseCache.lookup(
            for: sessionFile.url.path,
            modifiedAt: sessionFile.modifiedAt,
            size: sessionFile.size,
            maxFirstLineBytes: maxFirstLineBytes,
            maxTailBytes: maxTailBytes
        ) {
        case .hit(let cachedSession):
            return cachedSession
        case .miss:
            break
        }

        guard let line = readFirstLine(sessionFile.url),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["type"] as? String == "session_meta",
              let payload = dictionary["payload"] as? [String: Any],
              let sessionID = stringValue(for: "id", in: payload),
              let projectPath = normalizePath(stringValue(for: "cwd", in: payload))
        else {
            parseCache.store(
                nil,
                for: sessionFile.url.path,
                modifiedAt: sessionFile.modifiedAt,
                size: sessionFile.size,
                maxFirstLineBytes: maxFirstLineBytes,
                maxTailBytes: maxTailBytes
            )
            return nil
        }

        let parsedSession = ParsedSession(
            sessionID: sessionID,
            projectPath: projectPath,
            modifiedAt: sessionFile.modifiedAt,
            stateFromTail: stateFromTail(sessionFile.url)
        )
        parseCache.store(
            parsedSession,
            for: sessionFile.url.path,
            modifiedAt: sessionFile.modifiedAt,
            size: sessionFile.size,
            maxFirstLineBytes: maxFirstLineBytes,
            maxTailBytes: maxTailBytes
        )
        return parsedSession
    }

    private func stateFromTail(_ fileURL: URL) -> LightState? {
        var completedCallIDs: Set<String> = []

        for line in readTailLines(fileURL).reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any]
            else {
                continue
            }

            if let callID = completedCallID(in: dictionary) {
                completedCallIDs.insert(callID)
            }

            if isTerminalEvent(dictionary) {
                return .idle
            }

            if isWaitingForPermissionEvent(dictionary, completedCallIDs: completedCallIDs) {
                return .waitingForPermission
            }

            if isWorkingEvent(dictionary) {
                return .working
            }
        }

        return nil
    }

    private func reason(for state: LightState) -> String {
        switch state {
        case .waitingForPermission:
            return "Codex session is waiting for permission."
        case .working:
            return "Codex session is active."
        case .idle:
            return "Codex session is idle."
        }
    }

    private func isTerminalEvent(_ dictionary: [String: Any]) -> Bool {
        if let payload = dictionary["payload"] as? [String: Any],
           payload["phase"] as? String == "final_answer" {
            return true
        }

        if dictionary["type"] as? String == "event_msg",
           let payload = dictionary["payload"] as? [String: Any],
           let type = payload["type"] as? String {
            return type == "task_complete"
                || type == "task_completed"
                || type == "turn_aborted"
        }

        return false
    }

    private func isWorkingEvent(_ dictionary: [String: Any]) -> Bool {
        switch dictionary["type"] as? String {
        case "turn_context":
            return true
        case "response_item":
            guard let payload = dictionary["payload"] as? [String: Any] else {
                return false
            }

            if payload["phase"] as? String == "final_answer" {
                return false
            }

            if payload["type"] as? String == "message" {
                return payload["role"] as? String == "assistant"
            }

            return true
        case "event_msg":
            guard let payload = dictionary["payload"] as? [String: Any],
                  let type = payload["type"] as? String
            else {
                return false
            }

            return type == "task_started"
                || type == "user_message"
                || type == "agent_message"
        default:
            return false
        }
    }

    private func isWaitingForPermissionEvent(
        _ dictionary: [String: Any],
        completedCallIDs: Set<String>
    ) -> Bool {
        guard dictionary["type"] as? String == "response_item",
              let payload = dictionary["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "function_call" || payloadType == "custom_tool_call",
              let callID = stringValue(for: "call_id", in: payload),
              !completedCallIDs.contains(callID)
        else {
            return false
        }

        return isApprovalProneToolCall(payload)
    }

    private func isApprovalProneToolCall(_ payload: [String: Any]) -> Bool {
        let name = stringValue(for: "name", in: payload)?.lowercased() ?? ""
        let arguments = (
            stringValue(for: "arguments", in: payload)
                ?? stringValue(for: "input", in: payload)
                ?? ""
        ).lowercased()

        if arguments.contains("\"sandbox_permissions\"")
            && arguments.contains("require_escalated") {
            return true
        }

        if name == "apply_patch" {
            return true
        }

        return false
    }

    private func completedCallID(in dictionary: [String: Any]) -> String? {
        switch dictionary["type"] as? String {
        case "response_item":
            guard let payload = dictionary["payload"] as? [String: Any],
                  let type = payload["type"] as? String,
                  type == "function_call_output" || type == "custom_tool_call_output"
            else {
                return nil
            }

            return stringValue(for: "call_id", in: payload)

        case "event_msg":
            guard let payload = dictionary["payload"] as? [String: Any],
                  let type = payload["type"] as? String,
                  type == "mcp_tool_call_end" || type == "patch_apply_end"
            else {
                return nil
            }

            return stringValue(for: "call_id", in: payload)

        default:
            return nil
        }
    }

    private func readFirstLine(_ fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        let data = handle.readData(ofLength: maxFirstLineBytes)
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else {
            return nil
        }

        return String(line)
    }

    private func readTailLines(_ fileURL: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }

        defer {
            try? handle.close()
        }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readLength = min(maxTailBytes, fileSize)
        try? handle.seek(toOffset: fileSize - readLength)
        let data = handle.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
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

    private func stringValue(for key: String, in dictionary: [String: Any]) -> String? {
        guard let value = dictionary[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return value
    }
}
