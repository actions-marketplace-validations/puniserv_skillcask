import SwiftUI

extension PreviewRegistry {
    /// The P1-1 token sheet: every colour swatch with its hex, the type scale, spacing, radii and fixed sizes,
    /// sized like the Tokens board so nothing scrolls.
    static let tokens: [Entry] = [
        Entry(id: "P1-1", state: "tokens", size: CGSize(width: 1280, height: 1700)) { AnyView(TokensPreview()) }
    ]
}
