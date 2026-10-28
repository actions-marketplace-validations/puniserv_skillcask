import Foundation
import SkillcaskCore

/// What `outdated` knows about one package. `within` is what `update` would lock; `latest` may sit outside the
/// constraint and is informational.
public struct Update: Hashable, Sendable {
    public let package: String
    public let locked: String?
    public let within: String?
    public let latest: String?
    /// When the cooldown on a newer version ends, from the planned `eligible` key or the `note` text.
    public let eligible: Date?
    public let note: String?

    public init(_ row: OutdatedDocument.Package) {
        package = row.package
        locked = row.locked
        within = row.within
        latest = row.latest
        note = row.note
        eligible = row.eligible.flatMap(Self.date) ?? row.note.flatMap(Self.eligibleDate)
    }

    /// A newer version inside the constraint; nil when the lock is current or the package is not locked yet.
    public var available: (from: String, to: String)? {
        guard let locked, let within, within != locked else { return nil }
        return (locked, within)
    }

    /// A newer version that only a constraint change would reach.
    public var outsideRange: String? {
        guard let latest, latest != within else { return nil }
        return latest
    }

    static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    /// `v4.3.0 eligible 2026-10-26T21:44:27Z`.
    static func eligibleDate(_ note: String) -> Date? {
        guard let range = note.range(of: " eligible ") else { return nil }
        return date(String(note[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }
}
