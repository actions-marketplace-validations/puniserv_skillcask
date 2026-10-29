import Foundation

/// Everything that makes the tool exit 1, each with the one line it prints.
enum RenderError: Error, CustomStringConvertible {
    case usage(String?)
    case noMatch([String])
    case renderFailed(String)
    case tooSmall(path: String, bytes: Int)
    case missing(path: String)

    var description: String {
        switch self {
        case .usage(let detail):
            return detail.map { "error: \($0)\n\(RenderOptions.usage)" } ?? RenderOptions.usage
        case .noMatch(let filters):
            return "error: no preview matches \(filters.joined(separator: " ")); try --list"
        case .renderFailed(let what):
            return "error: could not render \(what)"
        case .tooSmall(let path, let bytes):
            return "error: \(path) is only \(bytes) bytes (minimum 5 KB), the render is probably blank"
        case .missing(let path):
            return "error: \(path) was not written"
        }
    }
}
