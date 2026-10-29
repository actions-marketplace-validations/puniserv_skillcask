/// Whether the app was started as if it were the CLI. The app owns no command-line arguments at all; macOS and
/// Xcode pass only Cocoa defaults (`-Key value`, `-psn_…`). A `--flag` (the `--version` probe) or a bare word as
/// the first argument (a subcommand) means something mistook the app for `skillcask`; the entry point then exits
/// with `refusalStatus` before SwiftUI starts, so a misdirected probe can never open a window or probe again.
///
/// That includes deliberate starts: `open -a Skillcask --args --anything` exits 64 too. Anyone giving the app a
/// `--flag` of its own must teach `isCLIInvocation` to let exactly that flag through, with a test.
public enum LaunchArguments {
    /// `EX_USAGE` from sysexits.h.
    public static let refusalStatus: Int32 = 64

    /// `arguments` without the executable path (`CommandLine.arguments.dropFirst()`).
    public static func isCLIInvocation(_ arguments: some Collection<String>) -> Bool {
        if let first = arguments.first, !first.hasPrefix("-") {
            return true
        }
        return arguments.contains { $0.hasPrefix("--") }
    }
}
