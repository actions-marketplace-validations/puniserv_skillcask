import SwiftUI

extension PreviewRegistry {
    /// Proves the render tool end to end: SwiftUI drawing plus AppKit-backed controls, system colours only.
    static let probe: [Entry] = [
        Entry(id: "probe", state: "basic", size: CGSize(width: 320, height: 200)) { AnyView(ProbeView()) }
    ]
}

/// A coloured shape, text, a button and a toggle: enough to tell a real render from a placeholder.
private struct ProbeView: View {
    @State private var enabled = true

    /// The probe's swatch: any non-empty size proves shapes draw; not a design metric.
    private static let swatch = CGSize(width: 96, height: 32)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            RoundedRectangle(cornerRadius: Radius.l)
                .fill(Color.accentColor)
                .frame(width: Self.swatch.width, height: Self.swatch.height)
            Text("Render probe")
                .font(Font.Token.body)
                .foregroundStyle(Color.primary)
            HStack(spacing: Spacing.m) {
                Button("Button") {}
                Toggle("Toggle", isOn: $enabled)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
