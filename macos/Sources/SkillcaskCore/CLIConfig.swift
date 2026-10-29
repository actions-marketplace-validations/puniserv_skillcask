import Foundation

/// The CLI's `config.toml`, by path only: the app never reads or writes it, `-g config` does (D48). Settings ›
/// Advanced opens it.
public enum CLIConfig {
    /// `<config dir>/config.toml`, in the directory `Scope.configDirectory` resolves from the child's environment.
    public static func file(environment: [String: String], home: URL) -> URL {
        Scope.configDirectory(environment: environment, home: home).appending(path: "config.toml")
    }
}
