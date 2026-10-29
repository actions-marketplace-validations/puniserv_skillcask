/// The Security tab's reach groups ("This skill's text mentions"), verbatim from the Components board
/// "Chip groups": one label per `audit` list, and the "Label · n" title every group draws.
public enum ReachCopy {
    /// The five `audit --json` reach lists, in board order.
    public enum Group: CaseIterable, Hashable, Sendable {
        /// `audit.commands`
        case commands
        /// `audit.network`
        case network
        /// `audit.paths`
        case paths
        /// `audit.env`
        case env
        /// `audit.scripts`
        case scripts
    }

    /// The group label.
    public static func label(_ group: Group) -> String {
        switch group {
        case .commands: "Commands"
        case .network: "Hosts"
        case .paths: "Paths"
        case .env: "Environment variables"
        case .scripts: "Scripts"
        }
    }

    /// "Commands · 3": a label and its count, middle-dotted like every count on the boards.
    public static func title(_ label: String, count: Int) -> String {
        "\(label) · \(count)"
    }
}
