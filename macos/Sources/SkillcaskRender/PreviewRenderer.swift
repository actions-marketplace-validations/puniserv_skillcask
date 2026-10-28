import AppKit
import SkillcaskUI
import SwiftUI

/// Turns one registry entry into PNG bytes at exactly 2×, in a given colour scheme, without a window server
/// round trip: the view draws into an offscreen bitmap, so the tool runs headless and inside the sandbox.
@MainActor
enum PreviewRenderer {
    /// Pixels per point of every PNG; fixed so CI and non-Retina machines produce the same files.
    static let scale: CGFloat = 2

    /// The two outputs of every entry, in the order they are rendered.
    enum Scheme: String, CaseIterable {
        case light
        case dark

        var colorScheme: ColorScheme { self == .dark ? .dark : .light }
        var appearance: NSAppearance? { NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
    }

    /// Renders `entry` in `scheme` with the chosen path; `nil` when the pipeline produced no image.
    static func png(
        for entry: SkillcaskUI.PreviewRegistry.Entry, scheme: Scheme, renderer: RenderOptions.Renderer
    ) -> Data? {
        let root = entry.make()
            .frame(width: entry.size.width, height: entry.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        switch renderer {
        case .host: return hostingPNG(root, size: entry.size, scheme: scheme)
        case .image: return imageRendererPNG(root, scheme: scheme)
        }
    }

    /// `NSHostingView` in a borderless offscreen `NSWindow`, drawn into an explicit 2× bitmap: real AppKit
    /// controls, appearance set on the window so system colours and controls follow it.
    private static func hostingPNG(_ root: some View, size: CGSize, scheme: Scheme) -> Data? {
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = scheme.appearance
        let window = KeyAppearanceWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = scheme.appearance
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        let pixelsWide = Int(size.width * scale)
        let pixelsHigh = Int(size.height * scale)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// SwiftUI's `ImageRenderer` with the colour scheme in the environment: pure drawing, no AppKit controls.
    private static func imageRendererPNG(_ root: some View, scheme: Scheme) -> Data? {
        let renderer = ImageRenderer(content: root.environment(\.colorScheme, scheme.colorScheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// Offscreen window that draws its controls as if it were the key window of the active app.
///
/// The render window is never ordered in and the tool never activates (`.prohibited`), so AppKit draws it with
/// inactive appearance: `.borderedProminent` buttons lose their tint fill and look like plain bordered buttons.
/// Overriding public `isKeyWindow`/`canBecomeKey`, setting `controlActiveState`/`appearsActive` in the
/// environment, faking `NSApp.isActive`, or `makeKeyAndOrderFront` far off-screen under `.accessory` do not
/// change that; the cells ask the window's key appearance, which these two AppKit selectors answer (either alone
/// was enough in a probe; both are overridden in case one stops being asked). They are not in the SDK headers, so
/// the overrides are `@objc` by name and fall back to the inactive look if AppKit stops asking. Render tool only.
private final class KeyAppearanceWindow: NSWindow {
    @objc var hasKeyAppearance: Bool { true }
    @objc(_hasKeyAppearance) var underscoredHasKeyAppearance: Bool { true }
}
