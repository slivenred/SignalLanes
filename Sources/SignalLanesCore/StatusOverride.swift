import Foundation

public struct StatusOverride: Codable, Equatable, Sendable {
    public let agentID: String
    public let state: LightState
    public let reason: String?
    public let updatedAt: Date
    public let expiresAt: Date?

    public init(
        agentID: String,
        state: LightState,
        reason: String?,
        updatedAt: Date,
        expiresAt: Date?
    ) {
        self.agentID = agentID
        self.state = state
        self.reason = reason
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    public func isActive(now: Date) -> Bool {
        guard let expiresAt else {
            return true
        }

        return expiresAt > now
    }
}

public protocol StatusOverrideProviding {
    func activeOverrides(now: Date) throws -> [StatusOverride]
}

public final class FileStatusOverrideStore: StatusOverrideProviding {
    private struct OverrideFile: Codable {
        var overrides: [StatusOverride]
    }

    public let fileURL: URL

    public var directoryURL: URL {
        fileURL.deletingLastPathComponent()
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".signal-lanes", isDirectory: true)
            .appendingPathComponent("status.json", isDirectory: false)
    }

    public func activeOverrides(now: Date) throws -> [StatusOverride] {
        try readAll().filter { $0.isActive(now: now) }
    }

    public func readAll() throws -> [StatusOverride] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OverrideFile.self, from: data).overrides
    }

    public func set(
        agentID: String,
        state: LightState,
        reason: String?,
        now: Date = Date(),
        expiresAt: Date?
    ) throws {
        var overrides = try readAll().filter { $0.agentID != agentID }
        overrides.append(StatusOverride(
            agentID: agentID,
            state: state,
            reason: reason,
            updatedAt: now,
            expiresAt: expiresAt
        ))
        try writeAll(overrides)
    }

    public func clear(agentID: String) throws {
        let overrides = try readAll().filter { $0.agentID != agentID }
        try writeAll(overrides)
    }

    public func writeAll(_ overrides: [StatusOverride]) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(OverrideFile(overrides: overrides))
        try data.write(to: fileURL, options: [.atomic])
    }
}
