import Foundation

public protocol ProcessSnapshotProviding {
    func snapshots() throws -> [ProcessSnapshot]
}

public enum ProcessSnapshotError: Error, CustomStringConvertible {
    case invalidUTF8
    case psFailed(Int32, String)

    public var description: String {
        switch self {
        case .invalidUTF8:
            return "Unable to decode ps output as UTF-8."
        case let .psFailed(status, message):
            return "ps exited with status \(status): \(message)"
        }
    }
}

public struct PSProcessProvider: ProcessSnapshotProviding {
    public init() {}

    public func snapshots() throws -> [ProcessSnapshot] {
        let process = Foundation.Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pcpu=,stat=,command="]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let error = String(data: errorData, encoding: .utf8) ?? ""
            throw ProcessSnapshotError.psFailed(process.terminationStatus, error)
        }

        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ProcessSnapshotError.invalidUTF8
        }

        return Self.parsePSOutput(output)
    }

    public static func parsePSOutput(_ output: String) -> [ProcessSnapshot] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5,
                  let pid = Int(parts[0]),
                  let parentPID = Int(parts[1]),
                  let cpuPercent = Double(parts[2])
            else {
                return nil
            }

            return ProcessSnapshot(
                pid: pid,
                parentPID: parentPID,
                cpuPercent: cpuPercent,
                state: String(parts[3]),
                commandLine: String(parts[4])
            )
        }
    }
}
