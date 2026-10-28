import SwiftUI

/// The bounds of a `CardHeader`'s title, published so a card can anchor a popover on its title (the Health card's
/// results, S12 Health-States "opens from the Health card title") rather than on the whole card.
public struct CardTitleAnchor: PreferenceKey {
    public static var defaultValue: Anchor<CGRect>? { nil }

    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
