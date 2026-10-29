import Foundation
import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// The Remove confirmation (S10, Remove board): a system alert, not a sheet, with a destructive button. `MainWindow`
/// presents it for `AppStore.removal` through `.alert(_:isPresented:presenting:actions:message:)` and pins one value
/// per request, so the plan below is computed once, when the alert is asked for.
///
/// - Managed skills: `remove -- <packages>` through `ActionRunner.run` from the window (S11: an alert has no room
///   for progress, so the list header shows "Removing pdf…" and the run ends in the toast or the failure banner,
///   as Sync does). The message names every skill whose files go (other skills of the package, orphaned
///   dependencies), the agents of the scope's targets and the two files; a package another one still requires is
///   said to stay installed, and when the app has not loaded who requires a package the message hedges.
/// - Not managed skills: the CLI has nothing to remove and the app changes no file of its own (spec D35), so the
///   alert explains that and offers Reveal in Finder (the folder, inside the scope root) and Cancel. The board's
///   "Delete …? / Move to Trash" panel is not built.
/// - Dependency, project and hand-written skills are never removed: the message says why, and when nothing else is
///   selected the alert offers only OK.
@MainActor struct RemoveAlert {
    let skills: [String]
    /// The scope's store, pinned at request time: `remove` runs in its scope.
    let store: ScopeStore
    /// The plan over the snapshot at request time; nil before the scope's first load.
    let plan: RemovePlan?
    /// The not managed skill's folder to reveal, validated to lie inside the scope root; nil when there is none.
    let revealURL: URL?

    /// The directory Reveal is confined to: the scope root (tests pass a temporary one).
    let root: URL

    /// - Parameter root: Where Reveal may point; nil is the scope's root (the home directory for My Skills).
    init(skills: [String], store: ScopeStore, root: URL? = nil) {
        self.skills = skills
        self.store = store
        let why = store.packageInfo.mapValues(\.why)
        let plan = store.snapshot.map { RemovePlan(skills: skills, snapshot: $0, why: why) }
        self.plan = plan
        // Decided once, with links resolved, so the alert never offers a Reveal that would then do nothing.
        let root = root ?? store.scope.root
        self.root = root
        revealURL = plan?.notManaged.first
            .flatMap { entry in Self.folder(of: entry, targets: store.snapshot?.targets, root: root) }
            .flatMap { Self.staysInside($0, root: root) ? $0 : nil }
    }

    /// What the alert offers.
    enum Offer: Equatable {
        /// `remove -- <packages>`; `count` skills' files go.
        case remove(count: Int)
        /// Not managed: reveal the folder.
        case reveal(URL)
        /// Nothing can be done: OK only.
        case nothing
    }

    private var personal: Bool {
        store.scope.isPersonal
    }

    var offer: Offer {
        guard let plan else { return .nothing }
        if plan.removesPackages {
            return .remove(count: plan.removedSkills.count)
        }
        if !plan.notManaged.isEmpty, let revealURL {
            return .reveal(revealURL)
        }
        return .nothing
    }

    // MARK: - Words

    var title: String {
        guard let plan else { return RemoveCopy.title(skills: skills, personal: personal) }
        if plan.removesPackages {
            let named = plan.selected.isEmpty ? plan.kept.flatMap(\.skills) : plan.selected
            return RemoveCopy.title(skills: named, personal: personal)
        }
        if !plan.notManaged.isEmpty {
            return RemoveCopy.notManagedTitle(plan.notManaged.map(\.name))
        }
        return RemoveCopy.cannotTitle(plan.refusals.isEmpty ? skills : plan.refusals.map(\.skill))
    }

    /// The sentences under the title, in the board's order: who loses the skills, what goes along, what stays, and
    /// the two files.
    var messageText: String {
        guard let plan else { return "" }
        var sentences: [String] = []
        if plan.removesPackages {
            if !plan.selected.isEmpty {
                sentences.append(RemoveCopy.unavailable(plan.selected, agents: plan.agents, personal: personal))
            }
            if !plan.siblings.isEmpty {
                let packages = Set(
                    plan.siblings.compactMap { name in store.snapshot?.entries.first { $0.name == name }?.package })
                sentences.append(RemoveCopy.siblings(plan.siblings, packages: max(packages.count, 1)))
            }
            for group in Self.orphanGroups(plan.orphans) {
                sentences.append(RemoveCopy.orphans(group.skills, requirers: group.requirers))
            }
            sentences += plan.kept.map(RemoveCopy.kept)
            let unchecked = plan.unchecked.filter { plan.selected.contains($0) || plan.siblings.contains($0) }
            if !unchecked.isEmpty {
                sentences.append(RemoveCopy.unchecked(unchecked))
            }
        } else if !plan.notManaged.isEmpty {
            sentences.append(RemoveCopy.notManagedBody(plan.notManaged.map(\.name)))
        }
        sentences += plan.refusals.map(RemoveCopy.refusal)
        if plan.removesPackages {
            sentences.append(plan.removedSkills.isEmpty ? RemoveCopy.filesOnly : RemoveCopy.files)
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Alert parts

    /// The destructive button (Remove, Remove 2 Skills) and Cancel; Reveal in Finder and Cancel for a not managed
    /// skill; OK alone when nothing can be done. Every button closes the alert, which clears `AppStore.removal`.
    @ViewBuilder func actions(onRemove: @escaping () -> Void) -> some View {
        switch offer {
        case .remove(let count):
            Button(RemoveCopy.button(count: count), role: .destructive, action: onRemove)
            Button(SheetCopy.cancel, role: .cancel) {}
        case .reveal:
            Button(ShellCopy.revealInFinder, action: onRemove)
            Button(SheetCopy.cancel, role: .cancel) {}
        case .nothing:
            Button(RemoveCopy.ok, role: .cancel) {}
        }
    }

    /// The sentence under the title.
    @ViewBuilder var message: some View {
        Text(messageText)
    }

    // MARK: - Actions

    /// Runs what the button promised: `remove` through the runner from the window, or Reveal in Finder (`reveal`
    /// is injectable for tests). When another command is running, `remove` does not start and the window's banner
    /// says so. The toast reads the CLI's `kept … as a dependency` lines, so it never says "Removed" for a package
    /// the CLI kept.
    @discardableResult func confirm(
        runner: ActionRunner, reveal: @MainActor (URL) -> Void = { Workspace.reveal($0) }
    ) -> Task<Void, Never>? {
        guard let plan else { return nil }
        switch offer {
        case .remove:
            guard let command = plan.command else { return nil }
            let names = plan.removedSkills.isEmpty ? plan.kept.flatMap(\.skills) : plan.removedSkills
            let title = RemoveCopy.removing(names)
            let failure = RemoveCopy.couldNotRemove(names)
            guard !runner.isRunning else {
                runner.outcome = .banner(SheetRun.refusal(failure: failure), id: UUID())
                return nil
            }
            let store = store
            let removed = plan.removedSkills
            var packageOf: [String: String] = [:]
            for entry in store.snapshot?.entries ?? [] {
                packageOf[entry.name] = entry.package
            }
            let packages = packageOf
            return Task {
                // The toast is built from the transcript inside the runner, so a Retry of a failed remove ends
                // with the same toast as the first run would have.
                await runner.run(
                    command, title: title, failure: failure, outcome: { _ in "" },
                    report: { scope, transcript in
                        Self.toast(removed: removed, packageOf: packages, transcript: transcript, scope: scope)
                    },
                    tone: { transcript in Self.keptCopies(in: transcript).isEmpty ? .success : .warning }, in: store)
            }
        case .reveal(let url):
            // Lexically inside the root (checked at request time); here, with the links on disk resolved too.
            if Self.staysInside(url, root: root) {
                reveal(url)
            }
            return nil
        case .nothing:
            return nil
        }
    }

    // MARK: - Helpers

    /// The success toast from the CLI's own lines: a package it printed `kept … as a dependency` for is never
    /// said to be removed, and neither is a skill whose folder it kept (`keptCopies`).
    nonisolated static func toast(
        removed: [String], packageOf: [String: String], transcript: [OutputLine], scope: String
    ) -> String {
        let stdout = transcript.compactMap { line -> String? in
            if case .stdout(let text) = line { text } else { nil }
        }
        let kept = MutationReport(verbLines: stdout.joined(separator: "\n")).kept
        let copies = keptCopies(in: transcript)
        let gone = removed.filter { name in
            !copies.contains(name) && (packageOf[name].map { !kept.contains($0) } ?? true)
        }
        return RemoveCopy.removedToast(
            gone, kept: kept, copies: removed.filter(copies.contains) + copies.subtracting(removed).sorted(),
            scope: scope)
    }

    /// The skills whose folder `remove` left in place: `warning: kept <path>: modified or not installed by
    /// skillcask` on stderr (`src/commands.rs` `materialize`, the store entry `.agents/skills/<skill>`, `~/`-led
    /// for My Skills). Their entry leaves skills.toml and skills.lock and their links go, but the files stay.
    nonisolated static func keptCopies(in transcript: [OutputLine]) -> Set<String> {
        Set(
            transcript.compactMap { line -> String? in
                guard case .stderr(let text) = line,
                    let match = text.wholeMatch(
                        of: #/warning: kept (?<path>.+): modified or not installed by skillcask/#),
                    let skill = match.path.split(separator: "/").last
                else { return nil }
                return String(skill)
            })
    }

    /// The folder of a not managed `entry` inside `root`: its audit `path`, else `<first target>/<name>`. Every
    /// part is validated (`isSafe`), and the result must lie inside `root`; nil otherwise.
    nonisolated static func folder(of entry: SkillEntry, targets: StatusDocument.Targets?, root: URL) -> URL? {
        let relative: String
        if let path = entry.path {
            relative = path
        } else {
            guard let dir = targets?.dirs.first, isSafeName(entry.name) else { return nil }
            relative = "\(dir)/\(entry.name)"
        }
        guard isSafe(relative) else { return nil }
        let base = root.standardizedFileURL
        let url = base.appending(path: relative).standardizedFileURL
        guard url.path.hasPrefix(base.path.hasSuffix("/") ? base.path : base.path + "/") else { return nil }
        return url
    }

    /// `url` still lies inside `root` once every symbolic link in either path is resolved, so a linked component
    /// cannot point Reveal outside the scope.
    nonisolated static func staysInside(_ url: URL, root: URL) -> Bool {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// A relative path of plain components: not empty, not absolute, no `~`, `.` or `..` component.
    nonisolated static func isSafe(_ relative: String) -> Bool {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.hasPrefix("~") else { return false }
        return relative.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." }
    }

    /// One path component: not empty, no `/`, not `.` or `..`.
    nonisolated static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    /// Orphans that share their requirers, so `a and b are only here because caveman requires them` is one sentence.
    static func orphanGroups(_ orphans: [RemovePlan.Orphan]) -> [(skills: [String], requirers: [String])] {
        var groups: [(skills: [String], requirers: [String])] = []
        for orphan in orphans {
            if let index = groups.firstIndex(where: { $0.requirers == orphan.requirers }) {
                groups[index].skills.append(orphan.skill)
            } else {
                groups.append((skills: [orphan.skill], requirers: orphan.requirers))
            }
        }
        return groups
    }
}
