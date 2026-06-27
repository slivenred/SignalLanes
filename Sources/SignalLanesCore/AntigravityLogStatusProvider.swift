import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct AntigravityLogStatusProvider: TaskHintProviding {
    private static let webviewMessageMarker = "Received message from webview: "
    private static let claudeActivityMarkers = [
        "[API REQUEST]",
        "Stream started",
        "tool_dispatch_start",
        "tool_dispatch_end",
        "Spawning shell",
        "Writing to temp file",
        "written atomically"
    ]
    private static let timestampCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }()

    private struct SessionStatus {
        var sessionID: String
        var title: String?
        var projectPath: String?
        var state: LightState
        var fallbackState: LightState?
        var reason: String
        var updatedAt: Date
        var pendingPermissionAt: Date?
        var activeObservedAt: Date?
    }

    private struct LaunchContext {
        var cwd: String?
        var resume: String?
        var launchedAt: Date
    }

    private struct PendingPermission {
        var title: String?
        var reason: String
        var updatedAt: Date
    }

    private struct RenameContext {
        var title: String?
        var hasPendingPermissions: Bool
        var updatedAt: Date
    }

    private struct LogFile {
        var url: URL
        var modifiedAt: Date
        var size: UInt64
    }

    private final class ParseCache: @unchecked Sendable {
        private struct Entry {
            var modifiedAt: Date
            var size: UInt64
            var maxTailBytes: UInt64
            var statuses: [SessionStatus]
        }

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        func statuses(
            for path: String,
            modifiedAt: Date,
            size: UInt64,
            maxTailBytes: UInt64
        ) -> [SessionStatus]? {
            lock.lock()
            defer { lock.unlock() }

            guard let entry = entries[path],
                  entry.modifiedAt == modifiedAt,
                  entry.size == size,
                  entry.maxTailBytes == maxTailBytes
            else {
                return nil
            }

            return entry.statuses
        }

        func store(
            _ statuses: [SessionStatus],
            for path: String,
            modifiedAt: Date,
            size: UInt64,
            maxTailBytes: UInt64
        ) {
            lock.lock()
            defer { lock.unlock() }

            entries[path] = Entry(
                modifiedAt: modifiedAt,
                size: size,
                maxTailBytes: maxTailBytes,
                statuses: statuses
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

    private let agentID: String
    private let sourceName: String
    private let rootURLs: [URL]
    private let maxLogFileAge: TimeInterval
    private let maxStatusAge: TimeInterval
    private let maxPendingPermissionAge: TimeInterval
    private let maxActiveStatusAge: TimeInterval
    private let maxTailBytes: UInt64
    private let maxFiles: Int
    private let parseCache: ParseCache
    private let visibleWindowTitlesProvider: (@Sendable () -> [String]?)?

    public init(
        agentID: String = "antigravity",
        sourceName: String = "Antigravity",
        rootURLs: [URL]? = nil,
        maxLogFileAge: TimeInterval = 36 * 60 * 60,
        maxStatusAge: TimeInterval = 12 * 60 * 60,
        maxPendingPermissionAge: TimeInterval = 5 * 60,
        maxActiveStatusAge: TimeInterval = 10 * 60,
        maxTailBytes: UInt64 = 2_000_000,
        maxFiles: Int = 12,
        visibleWindowTitlesProvider: (@Sendable () -> [String]?)? = nil
    ) {
        self.agentID = agentID
        self.sourceName = sourceName
        if let rootURLs {
            self.rootURLs = rootURLs
        } else {
            let applicationSupport = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.rootURLs = [
                applicationSupport.appendingPathComponent("Antigravity", isDirectory: true),
                applicationSupport.appendingPathComponent("Antigravity IDE", isDirectory: true)
            ]
        }
        self.maxLogFileAge = maxLogFileAge
        self.maxStatusAge = maxStatusAge
        self.maxPendingPermissionAge = maxPendingPermissionAge
        self.maxActiveStatusAge = maxActiveStatusAge
        self.maxTailBytes = maxTailBytes
        self.maxFiles = maxFiles
        self.visibleWindowTitlesProvider = visibleWindowTitlesProvider
        parseCache = ParseCache()
    }

    public func taskHints(now: Date) -> [TaskHint] {
        let visibleWindowTitles = visibleWindowTitlesProvider.flatMap { $0() }
        let statuses = logFiles(now: now).reduce(into: [String: SessionStatus]()) { partial, logFile in
            for status in parseLogFile(logFile) {
                guard status.updatedAt >= now.addingTimeInterval(-maxStatusAge) else {
                    continue
                }

                if let existing = partial[status.sessionID], existing.updatedAt > status.updatedAt {
                    continue
                }
                partial[status.sessionID] = status
            }
        }

        return statuses.values.compactMap { status in
            let visibleStatus = outputStatus(for: status, now: now)
            guard let reconciledStatus = reconcileWithVisibleWindowTitles(
                visibleStatus,
                visibleWindowTitles: visibleWindowTitles
            ),
                  shouldReport(reconciledStatus)
            else {
                return nil
            }

            return TaskHint(
                agentID: agentID,
                sessionID: reconciledStatus.sessionID,
                title: reconciledStatus.title,
                projectPath: reconciledStatus.projectPath,
                state: reconciledStatus.state,
                reason: reconciledStatus.reason,
                updatedAt: reconciledStatus.updatedAt
            )
        }
    }

    private func reconcileWithVisibleWindowTitles(
        _ status: SessionStatus,
        visibleWindowTitles: [String]?
    ) -> SessionStatus? {
        guard let visibleWindowTitles else {
            return status
        }

        let windowTitles = visibleWindowTitles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !windowTitles.isEmpty,
              let windowTitle = windowTitles.first(where: { visibleWindowTitleMatches($0, status: status) })
        else {
            return nil
        }

        guard let projectPath = status.projectPath,
              let projectName = visibleWindowProjectName(from: windowTitle),
              let canonicalProjectPath = canonicalProjectPath(projectPath, matchingVisibleProjectName: projectName)
        else {
            return status
        }

        var reconciledStatus = status
        reconciledStatus.projectPath = canonicalProjectPath
        return reconciledStatus
    }

    private func shouldReport(_ status: SessionStatus) -> Bool {
        if status.state == .idle,
           status.title == nil,
           status.activeObservedAt == nil,
           status.pendingPermissionAt == nil {
            return false
        }

        return status.state != .idle || status.projectPath != nil || status.title != nil
    }

    private func outputStatus(for status: SessionStatus, now: Date) -> SessionStatus {
        guard status.state == .working,
              status.updatedAt < now.addingTimeInterval(-maxActiveStatusAge)
        else {
            return outputPermissionStatus(for: status, now: now)
        }

        let fallbackState: LightState = .idle
        return SessionStatus(
            sessionID: status.sessionID,
            title: status.title,
            projectPath: status.projectPath,
            state: fallbackState,
            fallbackState: nil,
            reason: reason(for: fallbackState, title: status.title),
            updatedAt: status.updatedAt,
            pendingPermissionAt: nil,
            activeObservedAt: status.activeObservedAt
        )
    }

    private func outputPermissionStatus(for status: SessionStatus, now: Date) -> SessionStatus {
        guard status.state == .waitingForPermission,
              let pendingPermissionAt = status.pendingPermissionAt,
              pendingPermissionAt < now.addingTimeInterval(-maxPendingPermissionAge)
        else {
            return status
        }

        let fallbackState = status.fallbackState ?? .working
        let visibleState: LightState = fallbackState == .working
            && status.updatedAt < now.addingTimeInterval(-maxActiveStatusAge)
            ? .idle
            : fallbackState
        return SessionStatus(
            sessionID: status.sessionID,
            title: status.title,
            projectPath: status.projectPath,
            state: visibleState,
            fallbackState: nil,
            reason: reason(for: visibleState, title: status.title),
            updatedAt: status.updatedAt,
            pendingPermissionAt: nil,
            activeObservedAt: status.activeObservedAt
        )
    }

    private func logFiles(now: Date) -> [LogFile] {
        let cutoff = now.addingTimeInterval(-maxLogFileAge)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var candidates: [LogFile] = []

        for rootURL in rootURLs {
            let logsURL = rootURL.appendingPathComponent("logs", isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: logsURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent == "Claude VSCode.log",
                      fileURL.path.contains("Anthropic.claude-code")
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
                candidates.append(LogFile(
                    url: fileURL,
                    modifiedAt: modifiedAt,
                    size: UInt64(max(fileSize, 0))
                ))
            }
        }

        return Array(candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFiles))
    }

    private func parseLogFile(_ logFile: LogFile) -> [SessionStatus] {
        if let cachedStatuses = parseCache.statuses(
            for: logFile.url.path,
            modifiedAt: logFile.modifiedAt,
            size: logFile.size,
            maxTailBytes: maxTailBytes
        ) {
            return cachedStatuses
        }

        guard let text = readTail(logFile.url, fileSize: logFile.size) else {
            return []
        }

        let logSessionID = fallbackSessionID(for: logFile.url)
        var statuses: [String: SessionStatus] = [:]
        var pendingPermissions: [String: PendingPermission] = [:]
        var lastLaunch: LaunchContext?
        var lastSessionID: String?
        var lastRename: RenameContext?

        for line in text.split(separator: "\n") {
            let webviewMessageRange = line.range(of: Self.webviewMessageMarker)
            let isActivityLine = webviewMessageRange == nil && isClaudeActivityLine(line)
            guard webviewMessageRange != nil || isActivityLine else {
                continue
            }

            guard let timestamp = parseTimestamp(from: line) else {
                continue
            }

            guard let messageRange = webviewMessageRange,
                  let message = parseWebviewMessage(from: line, markerRange: messageRange)
            else {
                if isActivityLine {
                    let sessionID = lastSessionID ?? logSessionID
                    let existing = statuses[sessionID]
                    let pendingPermission = recentPendingPermission(
                        pendingPermissions[sessionID],
                        at: timestamp
                    )
                    if pendingPermission == nil {
                        pendingPermissions.removeValue(forKey: sessionID)
                    }

                    let state: LightState = pendingPermission == nil ? .working : .waitingForPermission
                    let projectPath = lastLaunch?.cwd ?? projectPathFromActivityLine(line)
                    statuses[sessionID] = merge(
                        existing: existing,
                        sessionID: sessionID,
                        title: pendingPermission?.title ?? existing?.title,
                        projectPath: projectPath,
                        state: state,
                        fallbackState: state == .waitingForPermission ? .working : fallbackState(from: existing),
                        reason: pendingPermission?.reason ?? "\(sourceName) Claude log shows recent activity.",
                        updatedAt: timestamp,
                        pendingPermissionAt: pendingPermission?.updatedAt,
                        activeObservedAt: timestamp
                    )
                }
                continue
            }

            if message["type"] as? String == "launch_claude" {
                let cwd = normalizeLogPath(message["cwd"] as? String)
                let resume = normalizeResume(message["resume"] as? String)
                lastLaunch = LaunchContext(cwd: cwd, resume: resume, launchedAt: timestamp)

                if let resume {
                    statuses[resume] = merge(
                        existing: statuses[resume],
                        sessionID: resume,
                        title: statuses[resume]?.title,
                        projectPath: cwd,
                        state: statuses[resume]?.state ?? .working,
                        fallbackState: statuses[resume]?.fallbackState,
                        reason: "\(sourceName) Claude session launched.",
                        updatedAt: timestamp,
                        pendingPermissionAt: statuses[resume]?.pendingPermissionAt
                    )
                }
                continue
            }

            guard message["type"] as? String == "request",
                  let request = message["request"] as? [String: Any],
                  let requestType = request["type"] as? String
            else {
                continue
            }

            switch requestType {
            case "update_session_state":
                guard let sessionID = request["sessionId"] as? String,
                      let stateName = request["state"] as? String
                else {
                    continue
                }

                let state = lightState(forAntigravityState: stateName)
                let existing = statuses[sessionID]
                let launchedProjectPath = projectPath(
                    from: lastLaunch,
                    matching: sessionID,
                    at: timestamp
                )
                let title = request["title"] as? String ?? existing?.title

                if let rename = lastRename, timestamp.timeIntervalSince(rename.updatedAt) <= 2 {
                    if rename.hasPendingPermissions {
                        pendingPermissions[sessionID] = PendingPermission(
                            title: rename.title ?? title,
                            reason: "Claude is requesting permission.",
                            updatedAt: rename.updatedAt
                        )
                    } else {
                        pendingPermissions.removeValue(forKey: sessionID)
                    }
                }

                let pendingPermission = recentPendingPermission(
                    pendingPermissions[sessionID],
                    at: timestamp
                )
                if pendingPermission == nil {
                    pendingPermissions.removeValue(forKey: sessionID)
                }

                let visibleState = pendingPermission == nil ? state : .waitingForPermission
                let fallbackState = visibleState == .waitingForPermission ? state : nil
                statuses[sessionID] = merge(
                    existing: existing,
                    sessionID: sessionID,
                    title: pendingPermission?.title ?? title,
                    projectPath: launchedProjectPath,
                    state: visibleState,
                    fallbackState: fallbackState,
                    reason: pendingPermission?.reason ?? reason(for: state, title: title),
                    updatedAt: timestamp,
                    pendingPermissionAt: pendingPermission?.updatedAt
                )
                lastSessionID = sessionID
                lastRename = nil

            case "show_notification":
                guard let messageText = request["message"] as? String,
                      messageText.localizedCaseInsensitiveContains("requesting permission"),
                      let sessionID = lastSessionID
                else {
                    continue
                }

                let existing = statuses[sessionID]
                let pendingPermission = PendingPermission(
                    title: existing?.title,
                    reason: messageText,
                    updatedAt: timestamp
                )
                pendingPermissions[sessionID] = pendingPermission
                statuses[sessionID] = merge(
                    existing: existing,
                    sessionID: sessionID,
                    title: existing?.title,
                    projectPath: existing?.projectPath,
                    state: .waitingForPermission,
                    fallbackState: existing?.fallbackState ?? fallbackState(from: existing),
                    reason: messageText,
                    updatedAt: timestamp,
                    pendingPermissionAt: pendingPermission.updatedAt
                )

            case "rename_tab":
                guard let hasPendingPermissions = request["hasPendingPermissions"] as? Bool else {
                    continue
                }

                let title = request["title"] as? String
                lastRename = RenameContext(
                    title: title,
                    hasPendingPermissions: hasPendingPermissions,
                    updatedAt: timestamp
                )

            default:
                continue
            }
        }

        let parsedStatuses = deduplicatedStatuses(statuses, fallbackSessionID: logSessionID)
        parseCache.store(
            parsedStatuses,
            for: logFile.url.path,
            modifiedAt: logFile.modifiedAt,
            size: logFile.size,
            maxTailBytes: maxTailBytes
        )
        return parsedStatuses
    }

    private func deduplicatedStatuses(
        _ statuses: [String: SessionStatus],
        fallbackSessionID: String
    ) -> [SessionStatus] {
        guard let fallbackStatus = statuses[fallbackSessionID],
              let fallbackProjectPath = fallbackStatus.projectPath
        else {
            return statuses.values.sorted { $0.updatedAt > $1.updatedAt }
        }

        let concreteStatuses = statuses.values.filter { status in
            status.sessionID != fallbackSessionID
                && (status.projectPath == fallbackProjectPath || status.projectPath == nil)
        }
        if concreteStatuses.count == 1, var concreteStatus = concreteStatuses.first {
            let mergedState = max(concreteStatus.state, fallbackStatus.state)
            let usesFallbackActivity = fallbackStatus.state > concreteStatus.state
                || (fallbackStatus.state == concreteStatus.state && fallbackStatus.updatedAt > concreteStatus.updatedAt)
            concreteStatus.state = mergedState
            concreteStatus.projectPath = concreteStatus.projectPath ?? fallbackProjectPath
            concreteStatus.fallbackState = mergedState == .waitingForPermission
                ? concreteStatus.fallbackState ?? fallbackStatus.fallbackState
                : nil
            concreteStatus.reason = usesFallbackActivity ? fallbackStatus.reason : concreteStatus.reason
            concreteStatus.updatedAt = max(concreteStatus.updatedAt, fallbackStatus.updatedAt)
            if let fallbackActiveObservedAt = fallbackStatus.activeObservedAt,
               concreteStatus.activeObservedAt.map({ fallbackActiveObservedAt > $0 }) ?? true {
                concreteStatus.activeObservedAt = fallbackActiveObservedAt
            }
            if let fallbackPendingPermissionAt = fallbackStatus.pendingPermissionAt,
               concreteStatus.pendingPermissionAt.map({ fallbackPendingPermissionAt > $0 }) ?? true {
                concreteStatus.pendingPermissionAt = fallbackPendingPermissionAt
            }

            return statuses.values
                .compactMap { status in
                    if status.sessionID == fallbackSessionID {
                        return nil
                    }

                    if status.sessionID == concreteStatus.sessionID {
                        return concreteStatus
                    }

                    return status
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        let hasConcreteStatus = concreteStatuses.contains { $0.state >= fallbackStatus.state }

        return statuses.values
            .filter { !hasConcreteStatus || $0.sessionID != fallbackSessionID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func projectPathFromActivityLine(_ line: Substring) -> String? {
        let text = String(line)
        let markers = [
            "Writing to temp file",
            "written atomically",
            "Renaming",
            "Captured baseline diagnostics for",
            "No new diagnostics found for"
        ]

        for marker in markers {
            guard let range = text.range(of: marker, options: .caseInsensitive) else {
                continue
            }

            let fragment = marker == "written atomically" ? text : String(text[range.upperBound...])
            if let path = projectPathFromPathFragment(fragment) {
                return path
            }
        }

        return nil
    }

    private func projectPathFromPathFragment(_ fragment: String) -> String? {
        var fragments = [fragment]
        if let range = fragment.range(of: " to ") {
            fragments.append(String(fragment[..<range.lowerBound]))
            fragments.append(String(fragment[range.upperBound...]))
        }

        for fragment in fragments {
            guard let pathStart = fragment.firstIndex(of: "/") else {
                continue
            }

            for candidate in cleanedPathCandidates(String(fragment[pathStart...])) {
                guard let path = normalizeActivityPath(candidate),
                      let projectPath = inferredProjectPath(fromActivityPath: path)
                else {
                    continue
                }

                return projectPath
            }
        }

        return nil
    }

    private func cleanedPathCandidates(_ rawValue: String) -> [String] {
        let terminators = [
            " source=",
            " requestId=",
            " tool=",
            " toolUseId=",
            " permissionDecisionMs=",
            " durationMs=",
            " elapsed=",
            " [",
            "\t",
            "\r",
            "\n"
        ]
        var candidates = [rawValue]

        for terminator in terminators {
            if let range = rawValue.range(of: terminator) {
                candidates.append(String(rawValue[..<range.lowerBound]))
            }
        }

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let trimmed = candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>.,:"))
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }

    private func normalizeActivityPath(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func inferredProjectPath(fromActivityPath path: String) -> String? {
        guard !isUserConfigActivityPath(path) else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let directoryURL: URL
        if path.hasSuffix("/") {
            directoryURL = fileURL
        } else if fileURL.lastPathComponent.contains(".") {
            directoryURL = fileURL.deletingLastPathComponent()
        } else {
            directoryURL = fileURL
        }

        let directoryPath = directoryURL.path
        guard !directoryPath.isEmpty, directoryPath != "/" else {
            return nil
        }

        return inferredWorkspaceRoot(fromDirectoryPath: directoryPath) ?? directoryPath
    }

    private func isUserConfigActivityPath(_ path: String) -> Bool {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == homePath {
            return true
        }

        guard path.hasPrefix(homePath + "/") else {
            return false
        }

        let relativePath = String(path.dropFirst(homePath.count + 1))
        return relativePath.hasPrefix(".")
            || relativePath.hasPrefix("Library/")
    }

    private func inferredWorkspaceRoot(fromDirectoryPath directoryPath: String) -> String? {
        let markerComponents = Set([
            ".github",
            "Sources",
            "Source",
            "Tests",
            "Test",
            "src",
            "app",
            "apps",
            "components",
            "frontend",
            "backend",
            "lib",
            "packages",
            "pages",
            "audits",
            "ios",
            "macos",
            "android",
            "analysis",
            "output"
        ])
        let components = directoryPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard let markerIndex = components.firstIndex(where: markerComponents.contains),
              markerIndex >= 2
        else {
            return nil
        }

        let rootPath = "/" + components[..<markerIndex].joined(separator: "/")
        guard rootPath != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path else {
            return nil
        }

        return rootPath
    }

    private func readTail(_ fileURL: URL, fileSize: UInt64? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        let size = fileSize ?? ((try? handle.seekToEnd()) ?? 0)
        if size > maxTailBytes {
            try? handle.seek(toOffset: size - maxTailBytes)
        } else {
            try? handle.seek(toOffset: 0)
        }

        let data = handle.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func parseTimestamp(from line: Substring) -> Date? {
        let bytes = Array(line.utf8.prefix(23))
        guard bytes.count == 23,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes[10] == 32,
              bytes[13] == 58,
              bytes[16] == 58,
              bytes[19] == 46,
              let year = fourDigits(bytes, at: 0),
              let month = twoDigits(bytes, at: 5),
              let day = twoDigits(bytes, at: 8),
              let hour = twoDigits(bytes, at: 11),
              let minute = twoDigits(bytes, at: 14),
              let second = twoDigits(bytes, at: 17),
              let millisecond = threeDigits(bytes, at: 20)
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Self.timestampCalendar
        components.timeZone = Self.timestampCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = millisecond * 1_000_000
        return Self.timestampCalendar.date(from: components)
    }

    private func twoDigits(_ bytes: [UInt8], at index: Int) -> Int? {
        guard let first = digit(bytes[index]),
              let second = digit(bytes[index + 1])
        else {
            return nil
        }

        return first * 10 + second
    }

    private func threeDigits(_ bytes: [UInt8], at index: Int) -> Int? {
        guard let first = digit(bytes[index]),
              let second = digit(bytes[index + 1]),
              let third = digit(bytes[index + 2])
        else {
            return nil
        }

        return first * 100 + second * 10 + third
    }

    private func fourDigits(_ bytes: [UInt8], at index: Int) -> Int? {
        guard let first = digit(bytes[index]),
              let second = digit(bytes[index + 1]),
              let third = digit(bytes[index + 2]),
              let fourth = digit(bytes[index + 3])
        else {
            return nil
        }

        return first * 1_000 + second * 100 + third * 10 + fourth
    }

    private func digit(_ byte: UInt8) -> Int? {
        guard byte >= 48, byte <= 57 else {
            return nil
        }

        return Int(byte - 48)
    }

    private func parseWebviewMessage(
        from line: Substring,
        markerRange: Range<Substring.Index>
    ) -> [String: Any]? {
        let jsonText = String(line[markerRange.upperBound...])
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        return dictionary
    }

    private func fallbackSessionID(for fileURL: URL) -> String {
        let components = fileURL.pathComponents
        if let logsIndex = components.lastIndex(of: "logs"),
           components.count > logsIndex + 2 {
            let logRun = components[logsIndex + 1]
            let window = components[logsIndex + 2]
            if window.hasPrefix("window") {
                return "log:\(logRun)/\(window)"
            }

            return "log:" + components[(logsIndex + 1)..<components.count - 1].joined(separator: "/")
        }

        return "log:" + fileURL.deletingLastPathComponent().lastPathComponent
    }

    private func isClaudeActivityLine(_ line: Substring) -> Bool {
        guard line.contains("From claude:") else {
            return false
        }

        return Self.claudeActivityMarkers.contains { line.contains($0) }
    }

    private func lightState(forAntigravityState state: String) -> LightState {
        switch state {
        case "waiting_input":
            return .waitingForPermission
        case "running":
            return .working
        default:
            return .idle
        }
    }

    private func reason(for state: LightState, title: String?) -> String {
        let suffix = title.map { " \($0)" } ?? ""
        switch state {
        case .waitingForPermission:
            return "\(sourceName) is waiting for permission.\(suffix)"
        case .working:
            return "\(sourceName) session is running.\(suffix)"
        case .idle:
            return "\(sourceName) session is idle.\(suffix)"
        }
    }

    private func visibleWindowTitleMatches(_ title: String, status: SessionStatus) -> Bool {
        let candidates = [
            status.title,
            status.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent },
            status.projectPath
        ].compactMap { $0 }

        return candidates.contains { windowTitleMatches(title, candidate: $0) }
    }

    private func windowTitleMatches(_ windowTitle: String, candidate: String) -> Bool {
        let normalizedTitle = normalizedWindowMatchString(windowTitle)
        let normalizedCandidate = normalizedWindowMatchString(candidate)
        guard !normalizedCandidate.isEmpty else {
            return false
        }

        if normalizedTitle.contains(normalizedCandidate) {
            return true
        }

        let prefixLength = min(18, normalizedCandidate.count)
        guard prefixLength >= 10 else {
            return false
        }

        let prefix = String(normalizedCandidate.prefix(prefixLength))
        return normalizedTitle.contains(prefix)
    }

    private func visibleWindowProjectName(from windowTitle: String) -> String? {
        let separators = [" — ", " – ", " - "]
        for separator in separators {
            if let range = windowTitle.range(of: separator) {
                let projectName = String(windowTitle[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return projectName.isEmpty ? nil : projectName
            }
        }

        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    private func canonicalProjectPath(_ projectPath: String, matchingVisibleProjectName projectName: String) -> String? {
        let normalizedProjectName = normalizedWindowMatchString(projectName)
        guard !normalizedProjectName.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: projectPath).standardizedFileURL
        let components = url.pathComponents
        guard components.count > 1 else {
            return nil
        }

        for index in stride(from: components.count - 1, through: 1, by: -1) {
            let component = components[index]
            guard normalizedWindowMatchString(component) == normalizedProjectName else {
                continue
            }

            return URL(fileURLWithPath: "/" + components[1...index].joined(separator: "/"))
                .standardizedFileURL
                .path
        }

        return nil
    }

    private func normalizedWindowMatchString(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "…", with: "")
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func visibleAntigravityWindowTitles() -> [String]? {
        let coreGraphicsTitles = coreGraphicsAntigravityWindowTitles()
        if !coreGraphicsTitles.isEmpty {
            return coreGraphicsTitles
        }

        let accessibilityTitles = accessibilityAntigravityWindowTitles()
        if !accessibilityTitles.isEmpty {
            return accessibilityTitles
        }

        return isAntigravityRunning() ? nil : []
    }

    private static func coreGraphicsAntigravityWindowTitles() -> [String] {
        let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return uniqueNonEmptyTitles(windowList.compactMap { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "Antigravity IDE",
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let title = window[kCGWindowName as String] as? String
            else {
                return nil
            }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedTitle.isEmpty ? nil : trimmedTitle
        })
    }

    private static func accessibilityAntigravityWindowTitles() -> [String] {
        uniqueNonEmptyTitles(antigravityApplications().flatMap { application -> [String] in
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement]
            else {
                return []
            }

            return windows.compactMap { window in
                var titleValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                      let title = titleValue as? String
                else {
                    return nil
                }

                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedTitle.isEmpty ? nil : trimmedTitle
            }
        })
    }

    private static func antigravityApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard !application.isTerminated else {
                return false
            }

            if let bundleIdentifier = application.bundleIdentifier?.lowercased(),
               [
                "com.google.antigravity",
                "com.google.antigravity-ide",
                "com.googlelabs.antigravity",
                "com.googlelabs.antigravityide"
               ].contains(bundleIdentifier) {
                return true
            }

            return application.localizedName == "Antigravity IDE"
                || application.bundleURL?.deletingPathExtension().lastPathComponent == "Antigravity IDE"
        }
    }

    private static func isAntigravityRunning() -> Bool {
        !antigravityApplications().isEmpty
    }

    private static func uniqueNonEmptyTitles(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        return titles.compactMap { title in
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, seen.insert(trimmedTitle).inserted else {
                return nil
            }

            return trimmedTitle
        }
    }

    private func recentPendingPermission(_ pendingPermission: PendingPermission?, at timestamp: Date) -> PendingPermission? {
        guard let pendingPermission,
              timestamp.timeIntervalSince(pendingPermission.updatedAt) <= maxPendingPermissionAge
        else {
            return nil
        }

        return pendingPermission
    }

    private func fallbackState(from status: SessionStatus?) -> LightState? {
        guard let status else {
            return nil
        }

        if status.state == .waitingForPermission {
            return status.fallbackState
        }

        return status.state
    }

    private func projectPath(
        from launch: LaunchContext?,
        matching sessionID: String,
        at timestamp: Date
    ) -> String? {
        guard let launch else {
            return nil
        }

        if launch.resume == sessionID {
            return launch.cwd
        }

        guard launch.resume == nil,
              timestamp.timeIntervalSince(launch.launchedAt) <= 10
        else {
            return nil
        }

        return launch.cwd
    }

    private func merge(
        existing: SessionStatus?,
        sessionID: String,
        title: String?,
        projectPath: String?,
        state: LightState,
        fallbackState: LightState?,
        reason: String,
        updatedAt: Date,
        pendingPermissionAt: Date?,
        activeObservedAt: Date? = nil
    ) -> SessionStatus {
        SessionStatus(
            sessionID: sessionID,
            title: title ?? existing?.title,
            projectPath: preferredProjectPath(existing: existing?.projectPath, candidate: projectPath),
            state: state,
            fallbackState: fallbackState ?? existing?.fallbackState,
            reason: reason,
            updatedAt: updatedAt,
            pendingPermissionAt: pendingPermissionAt,
            activeObservedAt: activeObservedAt ?? existing?.activeObservedAt
        )
    }

    private func preferredProjectPath(existing: String?, candidate: String?) -> String? {
        guard let candidate else {
            return existing
        }

        guard let existing else {
            return candidate
        }

        if isAncestorPath(candidate, of: existing) {
            return candidate
        }

        if isAncestorPath(existing, of: candidate) {
            return existing
        }

        return existing
    }

    private func isAncestorPath(_ ancestor: String, of path: String) -> Bool {
        ancestor == path || path.hasPrefix(ancestor + "/")
    }

    private func normalizeLogPath(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "undefined"
        else {
            return nil
        }

        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }

        value = value.removingPercentEncoding ?? value
        guard value.hasPrefix("/") else {
            return nil
        }

        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private func normalizeResume(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "undefined"
        else {
            return nil
        }

        return value
    }
}
