/// `projects --json <dirs>` (D40): every directory under `dirs` with a skills.toml.
public struct ProjectsDocument: Decodable, Hashable, Sendable {
    public struct Project: Decodable, Hashable, Sendable {
        public let path: String
    }

    public let projects: [Project]
}
