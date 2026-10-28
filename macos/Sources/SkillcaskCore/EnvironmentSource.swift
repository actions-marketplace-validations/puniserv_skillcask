import os

/// The live `EnvironmentPolicy`, shared by reference: Settings writes it, `ProcessRunner` reads it at every spawn,
/// so a change applies to the next run without rebuilding the client. Locked, so any thread may read it.
public final class EnvironmentSource: Sendable {
    private let state: OSAllocatedUnfairLock<EnvironmentPolicy>

    public init(_ policy: EnvironmentPolicy = .default) {
        state = OSAllocatedUnfairLock(initialState: policy)
    }

    /// The policy the next child gets.
    public var policy: EnvironmentPolicy {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
