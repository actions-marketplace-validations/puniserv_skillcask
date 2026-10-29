import SkillcaskCore

/// Which screen a scope shows. Computed by the store from (snapshot?, last error, refreshing).
public enum Presentation: Hashable, Sendable {
    /// First load, no snapshot yet.
    case loading
    /// A snapshot is on screen, possibly refreshing.
    case ready
    /// A snapshot is on screen; the last network command failed.
    case offline
    case cliMissing(searched: [String])
    case cliTooOld(found: Version, needs: Version)
    /// No skills.toml here (or personal skills never set up): offer Set Up.
    case noManifest
    /// No snapshot and the offline commands failed.
    case error(CLIError)

    /// The presentation a failed first load deserves: `init`'s hint marks a missing manifest.
    public static func forFailedLoad(_ error: CLIError) -> Presentation {
        switch error {
        case .binaryMissing(let searched): .cliMissing(searched: searched)
        case .tooOld(let found, let needs): .cliTooOld(found: found, needs: needs)
        case .failed(.problem, let message, _, _) where message.contains("skills.toml not found"): .noManifest
        default: .error(error)
        }
    }
}
