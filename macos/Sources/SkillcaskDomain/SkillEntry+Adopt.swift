extension SkillEntry {
    /// The location a not managed row's `adopt` spec names, without its scheme (D38's two shapes):
    /// `github:juliusbrussee/caveman` reads `juliusbrussee/caveman`, `git:https://…` reads the URL. Nil for any
    /// other kind or when the CLI printed no spec.
    public var adoptLocation: String? {
        guard case .notManaged(let adopt?) = kind else { return nil }
        return Self.location(ofAdoptSpec: adopt)
    }

    /// `spec` without a leading `github:` or `git:` scheme, case-insensitive, trimmed. Anything else (an `https:`
    /// URL, a bare `owner/repo`) is returned as the CLI printed it, so no other scheme is ever cut.
    public static func location(ofAdoptSpec spec: String) -> String {
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        for scheme in adoptSchemes where lower.hasPrefix(scheme) {
            return String(trimmed.dropFirst(scheme.count))
        }
        return trimmed
    }

    private static let adoptSchemes = ["github:", "git:"]
}
