import Foundation

/// Command line of the render tool, parsed by hand: the tool has no other dependencies and three flags.
struct RenderOptions {
    /// Which drawing path produces the pixels.
    enum Renderer: String {
        /// `NSHostingView` in an offscreen window: real AppKit controls, appearance per window. The default.
        case host
        /// SwiftUI's `ImageRenderer`: pure drawing only, AppKit-backed controls become placeholders.
        case image
    }

    static let usage = """
        usage: SkillcaskRender --out <dir> [--renderer host|image] [id-or-prefix ...]
               SkillcaskRender --list
        Renders every registered preview whose id equals or starts with an argument (all when none) in light
        and dark at 2x into <dir>/<id>/{light,dark}/<state>.png; exits 1 if any PNG is missing or under 5 KB.
        """

    var out: String?
    var renderer: Renderer = .host
    var list = false
    var filters: [String] = []

    /// Parses `arguments` without the executable path; throws `RenderError.usage` on anything unexpected.
    init(arguments: [String]) throws {
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--out":
                guard let value = rest.popFirst() else { throw RenderError.usage("--out needs a directory") }
                out = value
            case "--renderer":
                guard let value = rest.popFirst(), let renderer = Renderer(rawValue: value) else {
                    throw RenderError.usage("--renderer takes host or image")
                }
                self.renderer = renderer
            case "--list":
                list = true
            case "--help", "-h":
                throw RenderError.usage(nil)
            default:
                guard !argument.hasPrefix("-") else { throw RenderError.usage("unknown option \(argument)") }
                filters.append(argument)
            }
        }
        guard list || out != nil else { throw RenderError.usage("--out is required unless --list is given") }
    }

    /// True when `id` is selected by the positional arguments (all ids when there are none).
    func selects(_ id: String) -> Bool {
        filters.isEmpty || filters.contains { id == $0 || id.hasPrefix($0) }
    }
}
