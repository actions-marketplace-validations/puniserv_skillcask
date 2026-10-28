/// One line the child printed, with the stream it came from; the Activity drawer shows both.
public enum OutputLine: Hashable, Sendable {
    case stdout(String)
    case stderr(String)

    public var text: String {
        switch self {
        case .stdout(let text), .stderr(let text): text
        }
    }
}
