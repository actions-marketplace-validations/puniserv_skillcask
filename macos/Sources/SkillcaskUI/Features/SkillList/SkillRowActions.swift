import SkillcaskDomain

/// The hover controls of one list row (S2 note: "Hover: Update… / ⋯ (Remove…, Adopt…, Reveal in Finder)";
/// Components board "hover with actions"). Pure, so the tests pin it per row kind.
///
/// Update… shows only for a row with an update while online (offline, `outdated` has not answered). The ⋯ menu
/// carries Remove… (hidden for dependency, project and hand-written skills, as the detail header hides it),
/// Adopt… (not-managed rows only) and Reveal in Finder (when the row has a folder on disk).
public struct SkillRowActions: Hashable, Sendable {
    /// One item of the ⋯ menu, in menu order.
    public enum MenuItem: Hashable, Sendable, CaseIterable {
        case remove
        case adopt
        case revealInFinder
    }

    /// The package Update… opens the Review Update sheet for; nil hides the button.
    public let updatePackage: String?
    public let menu: [MenuItem]

    public init(updatePackage: String?, menu: [MenuItem]) {
        self.updatePackage = updatePackage
        self.menu = menu
    }

    public var showsUpdate: Bool { updatePackage != nil }

    /// The controls of `entry`; `offline` hides Update….
    public static func resolve(_ entry: SkillEntry, offline: Bool) -> SkillRowActions {
        let actions = DetailActions.resolve(entry, offline: offline)
        var package: String?
        if case .update = actions.primary {
            package = entry.package
        }
        var menu: [MenuItem] = []
        if actions.showsRemove {
            menu.append(.remove)
        }
        if entry.isNotManaged {
            menu.append(.adopt)
        }
        if entry.path != nil {
            menu.append(.revealInFinder)
        }
        return SkillRowActions(updatePackage: package, menu: menu)
    }
}
