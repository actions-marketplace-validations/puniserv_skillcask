import Foundation
import SkillcaskCore
import SkillcaskDomain

/// What the Versions tab shows for one row (Versions and Versions-States boards), as a pure value so every state
/// is testable without a view: the callout, the label/version/detail rows, the state's footnote, and the full
/// list once `info <package>` has answered. Built from `VersionsModel`; all words come from `VersionsCopy`.
///
/// "Needs a range change" is a callout sentence and never an action (S6 note: policy may forbid editing
/// skills.toml here). The tab's actions are the cooldown callout's "Read the changes…" (the Review sheet) and the
/// Allowed range row's "Reveal skills.toml"; an update within range is offered by the header's strip, not a row.
struct VersionsContent: Hashable {
    /// The callout above the rows.
    struct Callout: Hashable {
        let kind: MessageStrip.Kind
        /// The bold lead.
        let title: String
        let text: String
        /// A fragment of `text` drawn in mono (`^2.0`).
        let mono: String?
        /// An SF Symbol replacing the kind's default (the cooldown's hourglass, the moved tag's crossed-out tag).
        var symbol: String? = nil
        /// The trailing link in the status text colour, which opens the Review sheet (the cooldown's "Read the
        /// changes…").
        var link: String? = nil
    }

    /// How a row's version is coloured: the board tints the version a row is about.
    enum Tone: Hashable {
        case primary
        case update
        case warning
        case neutral
    }

    /// The fourth column of a row.
    enum Trailing: Hashable {
        /// Secondary text: "Waiting", "Linked into Claude Code, Cursor".
        case quiet(String)
        /// The accent link that reveals the scope's skills.toml in Finder.
        case reveal(String)
    }

    /// One row of the version card.
    struct Row: Hashable, Identifiable {
        let label: String
        let version: String
        let tone: Tone
        let detail: String
        /// Fragments of `detail` drawn in mono (a range, two commits).
        let monos: [String]
        let trailing: Trailing?

        var id: String { label }
    }

    let model: VersionsModel
    let callout: Callout?
    let rows: [Row]
    /// The state's own last line (Versions-States within range and tag moved); nil for the others.
    let footnote: String?

    /// - Parameters:
    ///   - model: The Domain facts.
    ///   - versions: `info.versions` when known (the session cache), for "skipped 1.3.0".
    ///   - agents: The scope's agent names for the Installed row's "Linked into …".
    ///   - checkedAt: When `outdated` answered, for the up-to-date callout.
    ///   - revealsManifest: Whether the scope has a skills.toml to reveal, for the Allowed range row's link.
    init(
        model: VersionsModel, versions: [String]?, agents: [String], checkedAt: Date?, now: Date,
        revealsManifest: Bool = false
    ) {
        self.model = model
        callout = Self.callout(model, checkedAt: checkedAt, now: now)
        rows = Self.rows(model, versions: versions ?? [], agents: agents, revealsManifest: revealsManifest)
        switch model.status {
        case .available: footnote = VersionsCopy.reviewFootnote
        case .tagMoved: footnote = VersionsCopy.tagMovedFootnote
        case .unchecked, .cooldown, .outsideRange, .upToDate: footnote = nil
        }
    }

    // MARK: - Callout

    private static func callout(_ model: VersionsModel, checkedAt: Date?, now: Date) -> Callout? {
        switch model.status {
        case .unchecked:
            return Callout(
                kind: .info, title: VersionsCopy.notCheckedTitle, text: VersionsCopy.notCheckedBody, mono: nil)
        case .upToDate:
            guard let version = model.installed else { return nil }
            return Callout(
                kind: .ok, title: VersionsCopy.newestVersion(version),
                text: checkedAt.map { VersionsCopy.checked($0, now: now) } ?? "", mono: nil)
        case .available:
            // The header's update strip already says "1.4.0 is available … Review changes…" on every tab.
            return nil
        case .cooldown(let cooldown):
            return Callout(
                kind: .warning, title: VersionsCopy.cooldownTitle(cooldown.version, eligible: cooldown.eligible),
                text: VersionsCopy.cooldownBody(minimumAge: model.minimumAge, released: cooldown.released), mono: nil,
                symbol: MessageStrip.cooldownSymbol, link: VersionsCopy.readChanges)
        case .outsideRange(let version):
            return Callout(
                kind: .neutral, title: VersionsCopy.needsRangeChange(version),
                text: VersionsCopy.rangeChangeBody(range: model.allowedRange), mono: model.allowedRange)
        case .tagMoved(let move):
            return Callout(
                kind: .warning, title: VersionsCopy.tagMovedTitle(move.tag), text: VersionsCopy.tagMovedBody,
                mono: nil, symbol: MessageStrip.tagMovedSymbol)
        }
    }

    // MARK: - Rows

    private static func rows(
        _ model: VersionsModel, versions: [String], agents: [String], revealsManifest: Bool
    ) -> [Row] {
        var rows: [Row] = []
        if let installed = model.installed {
            rows.append(
                Row(
                    label: VersionsCopy.installed, version: installed, tone: .primary,
                    detail: VersionsCopy.installedDetail(released: model.installedReleased), monos: [],
                    trailing: agents.isEmpty ? nil : .quiet(VersionsCopy.linkedInto(agents))))
        }
        if let range = model.allowedRange {
            rows.append(
                Row(
                    label: VersionsCopy.allowedRange, version: range, tone: .primary,
                    detail: VersionsCopy.rangeDetail(range), monos: [],
                    trailing: revealsManifest ? .reveal(ShellCopy.revealManifest) : nil))
        }
        if model.showsInRangeRow, let row = inRangeRow(model, versions: versions) {
            rows.append(row)
        }
        if let row = newestRow(model) {
            rows.append(row)
        }
        return rows
    }

    private static func inRangeRow(_ model: VersionsModel, versions: [String]) -> Row? {
        guard let version = model.inRangeVersion else { return nil }
        switch model.status {
        case .cooldown(let cooldown):
            let age = model.minimumAge.map { OverviewCopy.policyValue($0.value) }
            return Row(
                label: VersionsCopy.availableInRange, version: version, tone: .warning,
                detail: VersionsCopy.cooldownDetail(
                    released: cooldown.released, eligible: cooldown.eligible, minimumAge: age),
                monos: [], trailing: .quiet(VersionsCopy.waiting))
        case .available:
            return Row(
                label: VersionsCopy.availableInRange, version: version, tone: .update,
                detail: VersionsCopy.availableDetail(
                    released: model.inRangeReleased, skipped: model.skipped(in: versions)),
                monos: [], trailing: nil)
        case .tagMoved(let move):
            return Row(
                label: VersionsCopy.availableInRange, version: version, tone: .warning,
                detail: VersionsCopy.tagMovedDetail(move),
                monos: [VersionsCopy.shortCommit(move.from), VersionsCopy.shortCommit(move.to)],
                trailing: nil)
        case .outsideRange:
            return Row(
                label: VersionsCopy.availableInRange, version: version, tone: .primary,
                detail: VersionsCopy.nothingNewer(below: model.nextMajor), monos: [], trailing: nil)
        case .unchecked, .upToDate:
            return nil
        }
    }

    private static func newestRow(_ model: VersionsModel) -> Row? {
        guard let latest = model.latest else { return nil }
        if case .unchecked = model.status {
            return nil
        }
        let sameAsInRange = model.latestIsInRange || (model.inRangeVersion == nil && latest == model.installed)
        if sameAsInRange || latest == model.within {
            let isCooldown = if case .cooldown = model.status { true } else { false }
            return Row(
                label: VersionsCopy.newestOverall, version: latest, tone: .primary,
                detail: isCooldown ? VersionsCopy.sameAsAbove : VersionsCopy.same, monos: [], trailing: nil)
        }
        return Row(
            label: VersionsCopy.newestOverall, version: latest, tone: .neutral,
            detail: VersionsCopy.outsideDetail(released: model.latestReleased, range: model.allowedRange),
            monos: model.allowedRange.map { [$0] } ?? [], trailing: nil)
    }
}
