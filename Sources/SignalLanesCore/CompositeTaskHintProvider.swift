import Foundation

public struct CompositeTaskHintProvider: TaskHintProviding {
    private let providers: [any TaskHintProviding]

    public init(_ providers: [any TaskHintProviding]) {
        self.providers = providers
    }

    public func taskHints(now: Date) -> [TaskHint] {
        providers.flatMap { $0.taskHints(now: now) }
    }
}
