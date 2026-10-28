/// `outdated --json` (D32): per manifest package, the locked version, the newest within the constraint and the
/// newest overall. Needs the network. Exit 1 only with `--strict`, which the app never passes.
public struct OutdatedDocument: Decodable, Hashable, Sendable {
    public struct Package: Decodable, Hashable, Sendable {
        public let package: String
        public let locked: String?
        /// The version `update` would lock; equal to `locked` when nothing is newer within the constraint.
        public let within: String?
        public let latest: String?
        /// Free text such as `v4.3.0 eligible 2026-10-26T21:44:27Z` when a newer version waits for the cooldown.
        public let note: String?
        /// Planned (`outdatedEligible`): the RFC 3339 instant the cooldown ends.
        public let eligible: String?
        /// Planned (`outdatedReleased`): the RFC 3339 instant `latest` was published.
        public let released: String?
    }

    public let packages: [Package]
    /// Packages whose locked version is behind their constraint's newest, by name.
    public let behind: [String]
}
