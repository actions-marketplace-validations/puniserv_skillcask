import Foundation
import Testing

@testable import SkillcaskUpdates

/// `InstallMethodDetector` with a fake disk: Homebrew, translocated, direct (AC 4 and the brief's rules).
@Suite struct InstallMethodTests {
    func detect(
        _ path: String, exists: Set<String> = [], links: [String: String] = [:], original: String? = nil
    ) -> InstallMethod {
        InstallMethodDetector(
            bundlePath: path, fileExists: { exists.contains($0) }, resolve: { links[$0] ?? $0 },
            originalPath: { _ in original }
        )
        .detect()
    }

    @Test(arguments: InstallMethodDetector.caskrooms)
    func homebrewInApplicationsWithACaskroom(caskroom: String) {
        #expect(detect("/Applications/Skillcask.app", exists: [caskroom]) == .homebrew)
        #expect(detect("/Applications/Skillcask.app/", exists: [caskroom]) == .homebrew)
    }

    @Test func aCaskroomAloneIsNotEnough() {
        let caskroom: Set = ["/opt/homebrew/Caskroom/skillcask-app"]
        #expect(detect("/Applications/Skillcask.app") == .direct, "no Caskroom: the zip")
        #expect(detect("/Users/me/Applications/Skillcask.app", exists: caskroom) == .direct)
        #expect(detect("/Applications/Utilities/Skillcask.app", exists: caskroom) == .direct)
        #expect(detect("/Applications/Skillcask 2.app", exists: caskroom) == .direct)
        #expect(detect("/opt/homebrew/Caskroom/skillcask-app-old/Skillcask.app", exists: caskroom) == .direct)
    }

    /// The resolved path decides: a link in /Applications to a copy elsewhere is direct; a link that resolves to
    /// /Applications/Skillcask.app or into the Caskroom is Homebrew.
    @Test func symlinksAreResolved() {
        let caskroom: Set = ["/usr/local/Caskroom/skillcask-app"]
        #expect(
            detect(
                "/Applications/Skillcask.app", exists: caskroom,
                links: ["/Applications/Skillcask.app": "/Users/me/Skillcask.app"])
                == .direct)
        #expect(
            detect(
                "/Users/me/Desktop/S.app", exists: caskroom,
                links: ["/Users/me/Desktop/S.app": "/Applications/Skillcask.app"])
                == .homebrew)
        #expect(
            detect(
                "/Applications/Skillcask.app",
                links: ["/Applications/Skillcask.app": "/opt/homebrew/Caskroom/skillcask-app/0.10.2/Skillcask.app"])
                == .homebrew)
    }

    /// AC 4: opened from ~/Downloads, Gatekeeper runs a translocated copy.
    @Test func translocated() {
        let path = "/private/var/folders/ab/xyz/T/AppTranslocation/6F1D2C3A-0000-4000-8000-000000000000/d/Skillcask.app"
        #expect(detect(path) == .translocated(original: nil))
        #expect(
            detect(path, original: "/Users/me/Downloads/Skillcask.app")
                == .translocated(original: URL(fileURLWithPath: "/Users/me/Downloads/Skillcask.app")))
        #expect(
            detect(
                "/Applications/Skillcask.app", exists: ["/opt/homebrew/Caskroom/skillcask-app"],
                links: ["/Applications/Skillcask.app": path])
                == .translocated(original: nil), "the resolved path is translocated")
    }

    /// The live resolver follows a real symlink.
    @Test func theLiveResolverFollowsSymlinks() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "skillcask-install-\(UUID().uuidString)")
        let app = dir.appending(path: "Real.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appending(path: "Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        #expect(InstallMethodDetector.resolvingSymlinks(link.path).hasSuffix("/Real.app"))
        #expect(
            InstallMethodDetector.onDisk(app.path) && !InstallMethodDetector.onDisk(dir.appending(path: "none").path))
        #expect(InstallMethodDetector(bundlePath: link.path).detect() == .direct)
    }
}
