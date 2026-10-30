import AppKit

extension AppUpdateStore.System {
    /// AppKit: the general pasteboard, the default browser, `NSWorkspace.openApplication` for Terminal (no
    /// AppleScript, so no Automation prompt) and Finder's selection.
    @MainActor public static var live: Self {
        Self(
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            open: { NSWorkspace.shared.open($0) },
            openApplication: {
                NSWorkspace.shared.openApplication(at: $0, configuration: .init(), completionHandler: nil)
            },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })
    }
}
