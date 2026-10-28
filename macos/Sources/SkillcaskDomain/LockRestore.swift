import SkillcaskCore

/// A locked skill whose folder does not match skills.lock, as `audit` reports it (rule `modified`,
/// `src/commands.rs` `audit()`): either the files differ from the locked tree, or the folder is not there at all
/// (message `not installed`). `install --frozen` re-places exactly these skills (every locked skill failing
/// `installed_ok`) without rewriting the lock, so this list is what a reinstall from the lock touches.
public struct LockRestore: Hashable, Sendable, Identifiable {
    /// Why the folder does not match the lock.
    public enum Reason: Hashable, Sendable {
        /// The files differ from the locked tree: someone edited them, or the install was altered. Reinstalling
        /// replaces them.
        case changed
        /// The locked skill has no folder on disk: installing adds it, nothing is replaced.
        case notInstalled
    }

    /// The skill's name.
    public let skill: String
    public let reason: Reason
    /// The CLI's message, kept as printed (`not installed`, `modified after skillcask installed it; …`).
    public let message: String

    public init(skill: String, reason: Reason, message: String) {
        self.skill = skill
        self.reason = reason
        self.message = message
    }

    public var id: String {
        skill
    }

    /// The exact message `audit` prints for a locked skill without a folder (`src/commands.rs` `audit()`).
    public static let notInstalledMessage = "not installed"
}

extension AuditDocument.Finding {
    /// What a `modified` finding says about the folder; nil for any other rule.
    public var lockRestoreReason: LockRestore.Reason? {
        guard isModified else { return nil }
        return message == LockRestore.notInstalledMessage ? .notInstalled : .changed
    }
}

extension SkillEntry {
    /// The skill is installed from skills.lock (a package skill or a dependency's), the only kind `audit` checks
    /// against the lock and `install` puts back.
    public var isLocked: Bool {
        switch kind {
        case .package, .dependency: true
        case .packageOnly, .project, .handWritten, .notManaged: false
        }
    }

    /// The row's `modified` finding as a restore, when the row is a locked skill; nil otherwise.
    public var lockRestore: LockRestore? {
        guard isLocked, let finding = findings.first(where: \.isModified), let reason = finding.lockRestoreReason
        else { return nil }
        return LockRestore(skill: name, reason: reason, message: finding.message)
    }
}

extension ScopeSnapshot {
    /// Every locked skill whose folder does not match the lock, in list order, one per skill name: what
    /// `install --frozen` will put back in this scope.
    public var lockRestores: [LockRestore] {
        LockRestore.restores(in: entries)
    }
}

extension LockRestore {
    /// The restores of `entries`, in their order, one per skill name.
    public static func restores(in entries: [SkillEntry]) -> [LockRestore] {
        var seen: Set<String> = []
        return entries.compactMap(\.lockRestore).filter { seen.insert($0.skill).inserted }
    }
}
