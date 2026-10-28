import Foundation

/// Finds the `skillcask` binary: a bundled copy next to the app executable, then the path from Settings, then the
/// search path of `EnvironmentPolicy`. Nothing is executed here; `CLIClient.version` does the gate.
public struct Locator: Sendable {
    public enum Choice: Hashable, Sendable {
        case bundled(URL)
        case configured(URL)
        case onPath(URL)

        public var url: URL {
            switch self {
            case .bundled(let url), .configured(let url), .onPath(let url): url
            }
        }
    }

    public var policy: EnvironmentPolicy
    /// `Contents/MacOS/skillcask` of the running app bundle when the release ships one; nil for `swift run`.
    public var bundled: URL?
    public var isExecutable: @Sendable (URL) -> Bool

    public init(
        policy: EnvironmentPolicy = .default,
        bundled: URL? = Bundle.main.url(forAuxiliaryExecutable: "skillcask"),
        isExecutable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
        self.policy = policy
        self.bundled = bundled
        self.isExecutable = isExecutable
    }

    /// `configured` wins over the bundle so a developer can point the app at a build; an unusable configured path
    /// is an error rather than a silent fallback, because the user asked for that file.
    public func locate(configured: String?) throws(CLIError) -> Choice {
        if let configured = configured?.trimmingCharacters(in: .whitespaces), !configured.isEmpty {
            let url = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
            guard isExecutable(url) else { throw .binaryMissing(searched: [url.path]) }
            return .configured(url)
        }
        if let bundled, isExecutable(bundled) {
            return .bundled(bundled)
        }
        let candidates = policy.searchPath(from: ProcessInfo.processInfo.environment["PATH"])
            .map { URL(fileURLWithPath: $0).appending(path: "skillcask") }
        if let found = candidates.first(where: isExecutable) {
            return .onPath(found)
        }
        throw .binaryMissing(searched: (bundled.map { [$0.path] } ?? []) + candidates.map(\.path))
    }
}
