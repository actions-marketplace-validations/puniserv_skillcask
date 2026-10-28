import Foundation
import SkillcaskDomain

/// The words of the detail's Overview tab (Main and Detail-States boards): the label/value rows, the sentences
/// of the dependency and not-managed strips, the security line, and the footnote. The `info --json` `why` lines
/// are reworded here, never in a view.
public enum DetailOverviewCopy {
    // MARK: - Row labels

    public static let skillsInPackage = "Skills in this package"
    public static let license = "License"
    public static let requiredBy = "Required by"
    public static let requires = "Requires"
    public static let repository = "Repository"
    public static let newest = "Newest"
    public static let kind = "Kind"
    public static let availableTo = "Available to"
    public static let location = "Location"
    public static let foundIn = "Found in"
    public static let security = "Security"

    // MARK: - Row values

    public static let addedDirectly = "Nothing. Added directly to this project."
    public static let noOtherSkills = "No other skills."

    /// `pdf · installed`: the selected skill's pill among the package's skills (Main board).
    public static func installedSkill(_ name: String) -> String {
        "\(name) · installed"
    }

    /// The quiet text after the package's skill pills (Main board).
    public static let addOthers = "— add others with Add Skill…"

    /// The Kind row of a project skill (Detail-States).
    public static let projectKind = "Project skill, committed with this repository. Not in skills.lock; no versions."
    /// The Kind row of a local (hand-written) skill. No board draws one; worded after `projectKind`.
    public static let localKind = "Local skill, written in this folder. Not in skills.lock; no versions."

    /// The Location row's link (Main, Detail-States): opens the folder in Finder.
    public static let openFolder = "Open folder"

    /// The Security row's link to the Security tab (Main, Detail-States).
    public static let seeSecurity = "See Security"

    /// `3.0.0 exists but needs a range change (allowed: ^2.0)` (Detail-States abandoned); without a known range
    /// the parenthesis is left out.
    public static func newest(_ version: String, allowed range: String?) -> String {
        guard let range else { return "\(version) exists but needs a range change" }
        return "\(version) exists but needs a range change (allowed: \(range))"
    }

    /// `github.com/anthropics/skills`: a repository URL as the Main board writes it, without the scheme and the
    /// trailing slash.
    public static func repositoryText(_ url: String) -> String {
        var text = url
        for scheme in ["https://", "http://"] where text.lowercased().hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

    /// `~/work/api/.skillcask/skills/pdf`: a folder with the home directory as `~`, never absolute.
    public static func path(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Security row

    /// The security line of the Overview: the findings count, or what a clean audit means for this row, then the
    /// reach half of the boards (`No findings. Mentions 3 commands and 1 path.`, `1 finding · mentions 2 hosts`).
    /// A row `audit` did not list (`reach` nil, no findings) is not audited, in the Security tab's words, never
    /// "No findings". Offline keeps its own sentence; a not managed skill whose text mentions nothing keeps "You can
    /// read it before adopting".
    public static func security(findings: Int, notManaged: Bool, offline: Bool, reach: Reach?) -> String {
        let mentions = mentions(reach)
        if findings > 0 {
            return Labels.findings(findings) + (mentions.map { " · mentions \($0)" } ?? "")
        }
        if reach == nil {
            let reason = notManaged ? SecurityCopy.notAuditedNotManaged : SecurityCopy.notAuditedOther
            return SecurityCopy.notAuditedTitle + " " + reason
        }
        if offline {
            return "No findings (audit runs locally)"
        }
        if let mentions {
            return "No findings. Mentions \(mentions)."
        }
        return notManaged ? "No findings. You can read it before adopting." : "No findings."
    }

    /// `3 commands and 1 path`: the first two non-empty reach lists in the boards' order (commands, hosts, paths,
    /// variables, scripts), counted; nil when the text mentions nothing or was not audited. The boards name at
    /// most two kinds in this one line; the Security tab lists them all.
    public static func mentions(_ reach: Reach?) -> String? {
        guard let reach else { return nil }
        let counts: [(Int, String, String)] = [
            (reach.commands.count, "command", "commands"), (reach.network.count, "host", "hosts"),
            (reach.paths.count, "path", "paths"), (reach.env.count, "variable", "variables"),
            (reach.scripts.count, "script", "scripts"),
        ]
        let phrases = counts.filter { $0.0 > 0 }.prefix(2).map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        return phrases.isEmpty ? nil : phrases.joined(separator: " and ")
    }

    // MARK: - Strips

    /// `safe-refactor is here because caveman requires it. Remove caveman to drop it.` (Detail-States).
    public static func dependency(_ skill: String, requiredBy requirers: [String]) -> String {
        let names = OutcomeCopy.list(requirers)
        let verb = requirers.count == 1 ? "requires" : "require"
        return "\(skill) is here because \(names) \(verb) it. Remove \(names) to drop it."
    }

    /// `Show caveman`: the dependency strip's link to the requiring skill.
    public static func show(_ skill: String) -> String {
        "Show \(skill)"
    }

    /// `Installed by another tool from github:juliusbrussee/caveman. …` (Detail-States, `status.adopt`).
    public static func installedByAnotherTool(from spec: String) -> String {
        "Installed by another tool from \(spec). Not in skills.toml, so it gets no updates or security checks "
            + "until adopted."
    }

    /// The bold lead of the source-unknown strip (Detail-States).
    public static let sourceUnknownTitle = "Source unknown."
    /// The sentence after `sourceUnknownTitle`.
    public static let sourceUnknownBody =
        "Nothing recorded where this came from. Adopt asks you for a source; or keep it as a local skill."

    // MARK: - info `why` lines

    /// The Required by value from `info`'s `why` lines: `juliusbrussee/safe-refactor: required by
    /// juliusbrussee/caveman (4.0.1)` reads `caveman (4.0.1)`, the requiring package named by its skills in this
    /// scope (`skillNames`) or by itself when it has none here. `in skills.toml as "^1.2"` lines are the package's
    /// own entry, not a requirer. Nil when nothing requires it: the row then reads `addedDirectly`. A line of any
    /// other shape is shown without its `package:` prefix, as the CLI printed it.
    public static func requiredBy(why: [String], skillNames: (String) -> [String]) -> String? {
        let lines = why.compactMap { line -> String? in
            let reason = reason(of: line)
            if reason.hasPrefix(manifestPrefix) {
                return nil
            }
            guard reason.hasPrefix(requiredByPrefix) else { return reason }
            let requirer = String(reason.dropFirst(requiredByPrefix.count))
            let package: String
            let suffix: String
            if let open = requirer.range(of: " (") {
                package = String(requirer[..<open.lowerBound])
                suffix = String(requirer[open.lowerBound...])
            } else {
                package = requirer
                suffix = ""
            }
            let names = skillNames(package)
            return (names.isEmpty ? package : names.joined(separator: ", ")) + suffix
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The constraint of the package's own `why` line (`in skills.toml as "^2.0"` → `^2.0`); nil when no line
    /// names one.
    public static func allowedRange(why: [String]) -> String? {
        for line in why {
            let reason = reason(of: line)
            guard reason.hasPrefix(manifestPrefix) else { continue }
            let range = reason.dropFirst(manifestPrefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !range.isEmpty {
                return range
            }
        }
        return nil
    }

    private static let manifestPrefix = "in skills.toml as"
    private static let requiredByPrefix = "required by "

    /// A `why` line without its leading `package: `.
    private static func reason(of line: String) -> String {
        guard let colon = line.range(of: ": ") else { return line }
        return String(line[colon.upperBound...])
    }

    // MARK: - Footnote

    /// The mono word of the footnote.
    public static let lockFile = "skills.lock"

    /// `Last checked 4 min ago from skills.lock. Numbers come from the command-line tool, never estimated.`
    public static func lastChecked(_ date: Date, now: Date = .now) -> String {
        "Last checked \(checkedAgo(date, now: now)) from \(lockFile). Numbers come from the command-line tool, never "
            + "estimated."
    }

    /// `just now`, `1 min ago`, `4 min ago`, or `30 Oct` after an hour: when the footnote's documents were read.
    static func checkedAgo(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case 1: return "1 min ago"
        case ..<60: return "\(minutes) min ago"
        default: return Formatters.dayMonth(date)
        }
    }
}
