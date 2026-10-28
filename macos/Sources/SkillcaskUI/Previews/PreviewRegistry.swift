import SwiftUI

/// The views the `SkillcaskRender` tool renders to PNG in both colour schemes for the design gate.
///
/// Each task registers its own previews in its own file, `Previews/<Task>Previews.swift`, as an
/// `extension PreviewRegistry { static let <task>: [Entry] = […] }`, and `all` concatenates the lists; adding a
/// task is one new file plus one name appended to `all`. Entries are plain values so the registry can be
/// enumerated from a command-line executable without SwiftUI's `#Preview` machinery.
public enum PreviewRegistry {
    /// One renderable view: `id` is the task or component (`probe`, `components/badge`), `state` the variant
    /// (`basic`, `empty`, `error`); the PNG lands at `<out>/<id>/{light,dark}/<state>.png`.
    public struct Entry: Sendable {
        public let id: String
        public let state: String
        /// Points at 1×; the tool renders at exactly 2× (`size.width * 2` pixels wide).
        public let size: CGSize
        /// Builds a fresh view for every render so light and dark never share state.
        public let make: @MainActor @Sendable () -> AnyView

        public init(id: String, state: String, size: CGSize, make: @escaping @MainActor @Sendable () -> AnyView) {
            self.id = id
            self.state = state
            self.size = size
            self.make = make
        }
    }

    /// Every registered entry, in registration order.
    public static var all: [Entry] {
        probe + tokens + progress + statusDot + chips + badges + detailHeader + rows + cards + diff + outcomes + strips
            + emptyStates + shell + list + detail + overview + contents + security + versions + reviewUpdate
            + adopt + addSkill
    }
}
