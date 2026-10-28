import Foundation

/// What the Contents file line says about SKILL.md beyond its text: the name, the size and the modification date,
/// read from the file's attributes (Q6: no CLI document carries them), and where it is. Both may be unknown: an
/// unreadable file has neither.
struct ContentsFile: Hashable, Sendable {
    let url: URL?
    let name: String
    let bytes: Int?
    let modified: Date?

    /// The file name every skill has.
    static let skillFileName = "SKILL.md"

    init(url: URL?, name: String = Self.skillFileName, bytes: Int? = nil, modified: Date? = nil) {
        self.url = url
        self.name = name
        self.bytes = bytes
        self.modified = modified
    }

    /// The path as the unreadable message and Copy path write it: `~/work/api/…/SKILL.md`.
    var displayPath: String? {
        url.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    /// Size and date from `FileManager`; a nonisolated async function runs off the caller's actor (tools 6.0), so
    /// the main actor never waits on the disk (Q6). A missing file keeps both unknown.
    nonisolated static func load(at url: URL) async -> ContentsFile {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue
        let modified = attributes?[.modificationDate] as? Date
        return ContentsFile(url: url, name: url.lastPathComponent, bytes: bytes, modified: modified)
    }
}
