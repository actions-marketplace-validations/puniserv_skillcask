import SwiftUI

extension FocusedValues {
    /// The stores of the focused window, for the menu bar (SUI-11); every entry is optional, as `FocusedValues`
    /// requires, and nil when no window has focus.
    @Entry var appStore: AppStore?
    @Entry var scopeStore: ScopeStore?
    @Entry var actionRunner: ActionRunner?
    /// Moves keyboard focus to the list's search field (⌘F).
    @Entry var focusSearch: FocusSearchAction?
}

/// A closure the list registers so the Find menu item can focus its search field.
struct FocusSearchAction {
    let perform: @MainActor () -> Void
}
