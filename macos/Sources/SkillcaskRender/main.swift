import AppKit
import Foundation
import SkillcaskUI

// Renders the registered previews to PNG for the design gate; see RenderOptions.usage. No run loop is started:
// everything draws offscreen, so the tool exits as soon as the last file is written.

/// Smaller than this and the PNG is blank or a placeholder, not a render.
let minimumBytes = 5 * 1024

/// Prints the error and exits 1; the only way the tool fails.
func fail(_ error: RenderError) -> Never {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

/// Writes every scheme of `entry` under `out` and returns the paths; stops the tool on the first bad file.
@MainActor
func render(_ entry: SkillcaskUI.PreviewRegistry.Entry, into out: URL, with renderer: RenderOptions.Renderer) throws {
    for scheme in PreviewRenderer.Scheme.allCases {
        let directory = out.appendingPathComponent(entry.id).appendingPathComponent(scheme.rawValue)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(entry.state).png")
        let name = "\(entry.id)/\(scheme.rawValue)/\(entry.state)"
        guard let png = PreviewRenderer.png(for: entry, scheme: scheme, renderer: renderer) else {
            fail(.renderFailed(name))
        }
        try png.write(to: file)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            let bytes = attributes[.size] as? Int
        else { fail(.missing(path: file.path)) }
        guard bytes >= minimumBytes else { fail(.tooSmall(path: file.path, bytes: bytes)) }
        print("\(file.path) \(bytes) bytes")
    }
}

let options: RenderOptions
do {
    options = try RenderOptions(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as RenderError {
    fail(error)
}

let selected = SkillcaskUI.PreviewRegistry.all.filter { options.selects($0.id) }
if options.list {
    for entry in selected {
        print("\(entry.id)/\(entry.state) \(Int(entry.size.width))x\(Int(entry.size.height))")
    }
    exit(0)
}
guard !selected.isEmpty else { fail(.noMatch(options.filters)) }
guard let out = options.out else { fail(.usage("--out is required")) }

// AppKit controls need an application object; `.prohibited` keeps the tool out of the Dock and off the screen.
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

let outURL = URL(fileURLWithPath: out)
for entry in selected {
    do {
        try render(entry, into: outURL, with: options.renderer)
    } catch {
        fail(.renderFailed("\(entry.id)/\(entry.state): \(error)"))
    }
}
