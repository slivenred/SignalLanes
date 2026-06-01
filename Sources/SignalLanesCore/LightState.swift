import Foundation

public enum LightState: String, Codable, CaseIterable, Comparable, Sendable {
    case idle
    case working
    case waitingForPermission

    public var priority: Int {
        switch self {
        case .idle:
            return 0
        case .working:
            return 1
        case .waitingForPermission:
            return 2
        }
    }

    public var displayName: String {
        switch self {
        case .idle:
            return "Green / idle"
        case .working:
            return "Red / working"
        case .waitingForPermission:
            return "Yellow / waiting for permission"
        }
    }

    public var shortName: String {
        switch self {
        case .idle:
            return "green"
        case .working:
            return "red"
        case .waitingForPermission:
            return "yellow"
        }
    }

    public static func < (lhs: LightState, rhs: LightState) -> Bool {
        lhs.priority < rhs.priority
    }

    public static func parse(_ value: String) -> LightState? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "green", "idle", "done", "complete", "completed":
            return .idle
        case "red", "work", "working", "running", "busy":
            return .working
        case "yellow", "wait", "waiting", "permission", "approval", "waitingforpermission":
            return .waitingForPermission
        default:
            return nil
        }
    }
}
