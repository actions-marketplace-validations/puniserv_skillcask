import Foundation
import SkillcaskDomain

/// The health strip under the Overview header, as data: `14 skills · 3 need sync · 5 need a decision · 2 updates`
/// then `Checked 4 min ago` and Check Now (Overview), `3 skills · All match the lock` (Overview-States Healthy),
/// `23 skills · 12 not managed` (No projects yet), the dashed `Not set up` (Folder without skills.toml) or
/// `Checking this project…` (Loading). "From status.ok + row counts + app-side lastChecked".
struct OverviewStrip: Hashable {
    /// What sits before a segment's words.
    enum Dot: Hashable {
        case severity(Severity)
        /// The dashed outline of a folder without skills.toml.
        case notSetUp
    }

    /// One count: the number in primary semibold, then its words.
    struct Segment: Hashable {
        let number: Int?
        let words: String
        let dot: Dot?

        init(_ number: Int?, _ words: String, dot: Dot? = nil) {
            self.number = number
            self.words = words
            self.dot = dot
        }

        var text: String {
            number.map { "\($0) \(words)" } ?? words
        }
    }

    let segments: [Segment]
    /// `Checked 4 min ago`; nil hides it and Check Now.
    let checked: String?
    /// The Loading strip: a spinner and a skeleton bar around the words.
    let isLoading: Bool
    /// Check Now after the checked line: the Overview board and Healthy draw it, No projects yet does not.
    var showsCheckNow = false

    /// The strip as one sentence: what VoiceOver reads and the tests compare.
    var sentence: String {
        (segments.map(\.text) + [checked].compactMap { $0 }).joined(separator: RowCopy.separator)
    }

    static let loading = OverviewStrip(
        segments: [Segment(nil, OverviewCopy.checkingProject)], checked: nil, isLoading: true)

    /// A failed first load: nothing to count and nothing loading; the banner below says what went wrong.
    static let failed = OverviewStrip(segments: [], checked: nil, isLoading: false)

    static let notSetUp = OverviewStrip(
        segments: [Segment(nil, OverviewCopy.notSetUp, dot: .notSetUp)], checked: nil, isLoading: false)

    /// The counts of a snapshot. Updates count packages (`availableUpdates`, as the Update All badge does), so
    /// the board's "2 updates" for api. Warnings read "not managed" when every warning row is a skill another tool
    /// installed (My Skills), else "need a decision" (api).
    static func ready(_ snapshot: ScopeSnapshot, now: Date = .now, showsCheckNow: Bool = true) -> OverviewStrip {
        let attention = snapshot.attention
        let updates = snapshot.availableUpdates.count
        var segments = [Segment(snapshot.entries.count, OverviewCopy.skillsWord(snapshot.entries.count))]
        if attention.errors == 0 && attention.warnings == 0 && updates == 0 {
            segments.append(Segment(nil, OverviewCopy.allMatch, dot: .severity(.ok)))
        } else {
            if attention.errors > 0 {
                segments.append(
                    Segment(attention.errors, OverviewCopy.needSyncWord(attention.errors), dot: .severity(.error)))
            }
            if attention.warnings > 0 {
                let warningRows = snapshot.entries.filter { $0.health.severity == .warning }
                let words =
                    warningRows.allSatisfy(\.isNotManaged)
                    ? OverviewCopy.notManagedWord : OverviewCopy.needDecisionWord(attention.warnings)
                segments.append(Segment(attention.warnings, words, dot: .severity(.warning)))
            }
            if updates > 0 {
                segments.append(Segment(updates, OverviewCopy.updatesWord(updates), dot: .severity(.update)))
            }
        }
        let checked =
            snapshot.updatesChecked
            ? OverviewCopy.checked(snapshot.checkedAt, now: now) : OverviewCopy.updatesNotChecked
        return OverviewStrip(segments: segments, checked: checked, isLoading: false, showsCheckNow: showsCheckNow)
    }
}
