import Foundation
import Observation
import SkillcaskCore
import SkillcaskDomain

/// The settings that live in the CLI, not in the app (S14): `[search] skills-sh` in config.toml and the GitHub
/// token in git's credential helper (the Keychain on macOS), and the size of the adopted copies' folder. App-lifetime
/// (`AppStore.cliSettings`), so what this session learnt survives closing the Settings window.
///
/// skills.sh goes through `skillcask -g config` where the CLI has it (`Capabilities.Feature.config`, 0.9.4, D48):
/// read as `{"value", "from"}`, written as `config -- search.skills-sh true|false`, nothing else run. An older CLI
/// (0.9.1–0.9.3) has no such command: the app reads config.toml itself and writes through `search --remember`,
/// which also runs one search.
///
/// The token rules: it reaches the CLI only as the stdin of `auth set` (never argv, never the environment); the
/// app never writes it anywhere, never reads it back, never shows it, and keeps no reference once the run is over.
/// No command reports whether a token is stored without returning it (`credential::fill` prints the password), so
/// `gitHub` starts `.unknown` and only this session's own Save or Sign Out changes it.
@MainActor @Observable public final class CLISettingsStore {
    /// What a command needs: the ready client and its capabilities, and the config.toml of the children's
    /// environment. Built by `AppStore.cliContext`.
    public struct Context: Sendable {
        public let client: any CLIClient
        public let capabilities: Capabilities
        public let configFile: URL

        public init(client: any CLIClient, capabilities: Capabilities, configFile: URL) {
            self.client = client
            self.capabilities = capabilities
            self.configFile = configFile
        }
    }

    /// `[search] skills-sh` as config.toml has it.
    public enum SkillsSh: Hashable, Sendable {
        /// Not read yet.
        case unknown
        /// The file does not set it: Add Skill… asks (S8 consent).
        case notSet
        case on
        case off
    }

    /// What the app knows of the GitHub token.
    public enum GitHub: Hashable, Sendable {
        /// Nothing: no command tells without returning the token.
        case unknown
        /// This session's `auth set` succeeded.
        case signedIn
        /// This session's `auth remove` succeeded.
        case signedOut
    }

    /// Where `auth set` said it stored the token: the helper list it prints (`stored a N-character token for <host>
    /// with git's credential helper (<helpers>)`) names osxkeychain, or it does not.
    public enum TokenStorage: Hashable, Sendable {
        case keychain
        case otherHelper
    }

    /// The host the CLI keys GitHub API tokens by (`github::API`), and the username that makes it a Bearer token.
    public static let gitHubHost = "api.github.com"
    public static let gitHubUsername = "oauth2"
    /// The query `search --remember` needs to write the switch on a CLI without `config`.
    public nonisolated static let rememberQuery = "skillcask"
    /// The key `config` names the switch by (D48).
    public nonisolated static let skillsShKey = "search.skills-sh"

    /// Whether flipping the switch on `capabilities` runs a search (no `config`, so `search --remember`).
    public nonisolated static func flipRunsSearch(_ capabilities: Capabilities?) -> Bool {
        capabilities?.supports(.config) != true
    }

    /// Reads a file's text off the main actor; nil when it is missing or unreadable.
    public typealias Reader = @Sendable (URL) async -> String?
    /// Sums a folder off the main actor: `4 folders · 1.2 MB`, nil when it does not exist.
    public typealias Measurer = @Sendable (URL) async -> String?

    private let read: Reader
    private let measure: Measurer

    // MARK: - State

    public private(set) var skillsSh: SkillsSh = .unknown
    /// The value being written while `search --remember` runs.
    public private(set) var pendingSkillsSh: Bool?
    public private(set) var skillsShFailure: UserMessage?
    public private(set) var gitHub: GitHub = .unknown
    /// `auth set` or `auth remove` is running.
    public private(set) var isChangingToken = false
    public private(set) var gitHubFailure: UserMessage?
    /// Where this session's Save stored the token; nil before one.
    public private(set) var tokenStorage: TokenStorage?
    /// The CLI's warnings from that Save (the plain-text `store` helper), masked.
    public private(set) var tokenWarnings: [String] = []
    /// The last measured adopted folder and its summary (`measureAdopted(at:)`).
    public private(set) var adopted: (folder: URL, summary: String?)?

    /// Set by `preload`: a preview's state is not replaced by the file on disk.
    @ObservationIgnored private var isPreloaded = false

    public init(
        read: @escaping Reader = CLISettingsStore.readFile, measure: @escaping Measurer = CLISettingsStore.measureFolder
    ) {
        self.read = read
        self.measure = measure
    }

    /// The live reader: the file's UTF-8 text, nil when missing.
    public static let readFile: Reader = { url in
        await Task.detached { try? String(contentsOf: url, encoding: .utf8) }.value
    }

    // MARK: - skills.sh

    /// Seeds the state a preview draws; later loads keep it.
    func preload(
        skillsSh: SkillsSh, gitHub: GitHub = .unknown, gitHubFailure: UserMessage? = nil,
        tokenStorage: TokenStorage? = nil, tokenWarnings: [String] = []
    ) {
        isPreloaded = true
        self.skillsSh = skillsSh
        self.gitHub = gitHub
        self.gitHubFailure = gitHubFailure
        self.tokenStorage = tokenStorage
        self.tokenWarnings = tokenWarnings
    }

    /// Reads `[search] skills-sh` from `configFile` (a CLI without `config`, or before the CLI is ready).
    public func loadSkillsSh(from configFile: URL) async {
        guard !isPreloaded else { return }
        let text = await read(configFile)
        skillsSh = Self.state(of: text)
    }

    /// Reads the switch through `-g config --json -- search.skills-sh` when the CLI has `config`, else from
    /// `context.configFile`. A `config` that fails (a broken config.toml) falls back to the file as well.
    public func loadSkillsSh(in context: Context) async {
        guard !isPreloaded else { return }
        if context.capabilities.supports(.config), let state = await Self.configState(in: context) {
            skillsSh = state
            return
        }
        await loadSkillsSh(from: context.configFile)
    }

    /// `config --json`'s answer as the switch's state; nil when it did not answer with a document.
    private static func configState(in context: Context) async -> SkillsSh? {
        do throws(CLIError) {
            let invocation = try Invocation(
                .config(key: skillsShKey), in: .personal, capabilities: context.capabilities)
            // Exit 1 with `{"value": null}` when nothing sets it: the document decides, not the exit.
            return state(of: try await context.client.run(invocation).document(ConfigValueDocument.self))
        } catch {
            return nil
        }
    }

    static func state(of document: ConfigValueDocument) -> SkillsSh? {
        switch document.value {
        case .bool(true): .on
        case .bool(false): .off
        case .null: .notSet
        default: nil
        }
    }

    /// Writes the switch, then reads it again: what the CLI reads back decides. With `config`:
    /// `-g config -- search.skills-sh true|false`, nothing else runs. Without: `search --skills-sh|--no-skills-sh
    /// --remember -- skillcask` in the personal scope, then the file, so a search that failed after the CLI saved
    /// the value (offline) still counts, and one that failed before shows why.
    public func setSkillsSh(_ on: Bool, in context: Context) async {
        guard pendingSkillsSh == nil else { return }
        pendingSkillsSh = on
        skillsShFailure = nil
        defer { pendingSkillsSh = nil }
        var failure: CLIError?
        let viaConfig = context.capabilities.supports(.config)
        do throws(CLIError) {
            let command: Invocation.Command =
                viaConfig
                ? .configSet(key: Self.skillsShKey, value: on ? "true" : "false")
                : .search(query: Self.rememberQuery, skillsSh: on ? .include : .exclude, remember: true)
            let result = try await context.client.run(
                Invocation(command, in: .personal, capabilities: context.capabilities))
            if viaConfig {
                failure = result.failure()
            }
        } catch {
            failure = error
        }
        await loadSkillsSh(in: context)
        if skillsSh != (on ? .on : .off) {
            skillsShFailure = ErrorCopy.message(
                for: failure ?? .launchFailed(SettingsCopy.skillsShNotSaved), title: SettingsCopy.couldNotSaveSkillsSh)
            skillsShFailure?.details = nil
        }
    }

    static func state(of text: String?) -> SkillsSh {
        switch text.flatMap(CLIConfig.skillsSh(in:)) {
        case true?: .on
        case false?: .off
        case nil: .notSet
        }
    }

    // MARK: - Adopted copies

    /// Settings › Advanced's "4 folders · 1.2 MB" for `folder` (where adopted copies go); nil until measured, or when
    /// the last measure was of another folder.
    public func adoptedSummary(of folder: URL) -> String? {
        guard let adopted, adopted.folder == folder else { return nil }
        return adopted.summary
    }

    /// Measures `folder` off the main actor (the walk visits every file) and keeps the summary.
    public func measureAdopted(at folder: URL) async {
        let summary = await measure(folder)
        adopted = (folder, summary)
    }

    /// The live measurer: `measure(_:)` on a detached task.
    public static let measureFolder: Measurer = { folder in
        await Task.detached { measure(folder) }.value
    }

    /// `4 folders · 1.2 MB`: the folders directly under `folder`, and the allocated size of every file below it;
    /// nil when `folder` cannot be listed.
    nonisolated static func measure(_ folder: URL) -> String? {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        else { return nil }
        let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        var bytes: Int64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let walk = manager.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in walk {
                let values = try? url.resourceValues(forKeys: keys)
                if values?.isRegularFile == true {
                    bytes += Int64(values?.totalFileAllocatedSize ?? 0)
                }
            }
        }
        return SettingsCopy.adoptedSummary(folders: folders.count, bytes: bytes)
    }

    // MARK: - GitHub token

    /// `auth set api.github.com --username oauth2` with `token` on stdin only. The caller clears its field before
    /// calling; nothing here keeps the token past the run, and the message of a failure never contains it.
    /// Returns whether the CLI stored it.
    @discardableResult public func signIn(token: String, in context: Context) async -> Bool {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !isChangingToken else { return false }
        isChangingToken = true
        gitHubFailure = nil
        defer { isChangingToken = false }
        do throws(CLIError) {
            let invocation = try Invocation(
                .authSet(host: Self.gitHubHost, username: Self.gitHubUsername), in: .personal,
                capabilities: context.capabilities, stdin: .text(token))
            let result = try await context.client.run(invocation)
            if let failure = result.failure() {
                throw failure
            }
            gitHub = .signedIn
            tokenStorage = Self.storage(of: result)
            tokenWarnings = result.report.warnings.map { Self.mask(token, in: $0) }
            return true
        } catch {
            gitHubFailure = Self.redacting(
                token, in: ErrorCopy.message(for: error, title: SettingsCopy.couldNotSignIn))
            return false
        }
    }

    /// `auth remove api.github.com --username oauth2`: drops the token from the Keychain.
    public func signOut(in context: Context) async {
        guard !isChangingToken else { return }
        isChangingToken = true
        gitHubFailure = nil
        defer { isChangingToken = false }
        do throws(CLIError) {
            let invocation = try Invocation(
                .authRemove(host: Self.gitHubHost, username: Self.gitHubUsername), in: .personal,
                capabilities: context.capabilities)
            if let failure = try await context.client.run(invocation).failure() {
                throw failure
            }
            gitHub = .signedOut
            tokenStorage = nil
            tokenWarnings = []
        } catch {
            var message = ErrorCopy.message(for: error, title: SettingsCopy.couldNotSignOut)
            message.details = nil
            gitHubFailure = message
        }
    }

    /// `.keychain` when the CLI's confirmation names the osxkeychain helper.
    static func storage(of result: RunResult) -> TokenStorage {
        result.stdoutText.contains(keychainHelper) ? .keychain : .otherHelper
    }

    /// git's macOS Keychain credential helper.
    static let keychainHelper = "osxkeychain"

    static func mask(_ token: String, in text: String) -> String {
        text.replacingOccurrences(of: token, with: SettingsCopy.redacted)
    }

    /// `message` without its transcript and with every occurrence of `token` masked: the CLI prints only the
    /// token's length, but a helper's own error could echo what it was given.
    static func redacting(_ token: String, in message: UserMessage) -> UserMessage {
        func mask(_ text: String?) -> String? {
            text.map { Self.mask(token, in: $0) }
        }
        var message = message
        message.title = mask(message.title) ?? ""
        message.reason = mask(message.reason)
        message.action = mask(message.action)
        message.details = nil
        message.monoFragment = mask(message.monoFragment)
        return message
    }
}
