/// The CLI's exit codes (`src/error.rs`): each one names a kind of failure the UI explains differently.
public enum ExitCode: Hashable, Sendable {
    /// 1: a problem in the manifest, lock or arguments; `status`, `outdated`, `doctor` and `audit` also exit 1 with
    /// their document when they found something.
    case problem
    /// 2: a registry or GitHub refused the request; a token is needed.
    case signIn
    /// 3: the network or a registry is unreachable.
    case network
    /// 4: a hash mismatch; nothing was installed.
    case integrity
    /// 5: a file could not be read or written.
    case file
    /// Anything else, including a crash (101).
    case other(Int32)

    public init(_ status: Int32) {
        switch status {
        case 1: self = .problem
        case 2: self = .signIn
        case 3: self = .network
        case 4: self = .integrity
        case 5: self = .file
        default: self = .other(status)
        }
    }

    public var status: Int32 {
        switch self {
        case .problem: 1
        case .signIn: 2
        case .network: 3
        case .integrity: 4
        case .file: 5
        case .other(let status): status
        }
    }
}
