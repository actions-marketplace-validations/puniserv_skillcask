/// How a child process ended.
public enum ExitStatus: Hashable, Sendable {
    case exited(Int32)
    case signaled(Int32)

    public var isSuccess: Bool {
        self == .exited(0)
    }

    /// The exit code, nil when the child was killed by a signal.
    public var code: Int32? {
        if case .exited(let code) = self { code } else { nil }
    }
}
