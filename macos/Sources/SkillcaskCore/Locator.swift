import Foundation

/// Finds the `skillcask` binary: the path from Settings, then a bundled copy in the app bundle, then the search path
/// of `EnvironmentPolicy`. Nothing is executed here; `CLIClient.version` does the gate.
///
/// No candidate may be the running app itself. Under `swift run` the GUI binary is `Skillcask` in the build products
/// directory, and on case-insensitive APFS a lookup of `skillcask` there finds it: probing it with `--version`
/// started another app, which probed itself again, without end. So every candidate is compared by file identity
/// (device and inode, after symlinks) against the running executable and skipped, or refused when configured.
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
    /// The `PATH` the search path starts from (the app's own by default); `policy.extraPaths` follow it.
    public var path: String?
    /// `Contents/Helpers/skillcask` of the running app when it runs from a `.app` bundle (`bundledInApp`); nil when it
    /// does not, e.g. under `swift run`, so a build products directory is never searched as a bundle. Not
    /// `Contents/MacOS/`: on case-insensitive APFS `skillcask` there is the app's own `Skillcask`.
    public var bundled: URL?
    public var isExecutable: @Sendable (URL) -> Bool
    /// Whether `url` is the running executable; such a candidate is never chosen (see the type's doc).
    public var isSelf: @Sendable (URL) -> Bool

    public init(
        policy: EnvironmentPolicy = .default,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        bundled: URL? = Locator.bundledInApp(),
        isExecutable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
        isSelf: @escaping @Sendable (URL) -> Bool = Locator.isRunningExecutable()
    ) {
        self.policy = policy
        self.path = path
        self.bundled = bundled
        self.isExecutable = isExecutable
        self.isSelf = isSelf
    }

    /// `configured` wins over the bundle so a developer can point the app at a build; an unusable configured path
    /// is an error rather than a silent fallback, because the user asked for that file: `.binaryMissing` when it is
    /// missing or not executable, `.binaryIsApp` when it is the app itself.
    public func locate(configured: String?) throws(CLIError) -> Choice {
        if let configured = configured?.trimmingCharacters(in: .whitespaces), !configured.isEmpty {
            let url = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
            guard isExecutable(url) else { throw .binaryMissing(searched: [url.path]) }
            guard !isSelf(url) else { throw .binaryIsApp(path: url.path) }
            return .configured(url)
        }
        if let bundled, usable(bundled) {
            return .bundled(bundled)
        }
        let candidates = policy.searchPath(from: path)
            .map { URL(fileURLWithPath: $0).appending(path: "skillcask") }
        if let found = candidates.first(where: usable) {
            return .onPath(found)
        }
        throw .binaryMissing(searched: (bundled.map { [$0.path] } ?? []) + candidates.map(\.path))
    }

    private func usable(_ url: URL) -> Bool {
        isExecutable(url) && !isSelf(url)
    }

    /// `Contents/Helpers/skillcask` when `bundle` is a `.app`; nil otherwise (a bare executable, as under `swift run`).
    public static func bundledInApp(_ bundle: Bundle = .main) -> URL? {
        bundledInApp(bundleURL: bundle.bundleURL)
    }

    static func bundledInApp(bundleURL: URL) -> URL? {
        guard bundleURL.pathExtension.lowercased() == "app" else { return nil }
        return bundleURL.appending(path: "Contents/Helpers/skillcask")
    }

    /// Device and inode of a file after symlinks; nil when it cannot be read.
    struct FileIdentity: Hashable, Sendable {
        let device: UInt64
        let inode: UInt64

        init?(_ url: URL) {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
                let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            else { return nil }
            self.device = device
            self.inode = inode
        }
    }

    /// A check against the files in `executables` (by default the running executable, from the bundle and from
    /// `argv[0]`), read once. A candidate whose identity cannot be read is not self.
    public static func isRunningExecutable(
        _ executables: [URL?] = [
            Bundle.main.executableURL,
            ProcessInfo.processInfo.arguments.first.map { URL(fileURLWithPath: $0) },
        ]
    ) -> @Sendable (URL) -> Bool {
        let selves = Set(executables.compactMap { $0.flatMap(FileIdentity.init) })
        return { url in FileIdentity(url).map(selves.contains) ?? false }
    }
}
