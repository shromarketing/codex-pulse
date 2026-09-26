import Foundation
import Testing
@testable import CodexPulse

@Suite("Codex CLI discovery")
struct ExecutableLocatorTests {
    @Test("Manifest entrypoint wins over direct, legacy, and PATH locations")
    func manifestPriority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = fixture.applicationRoot + "/ChatGPT.app/Contents/Resources/codex-cli"
        let entry = try fixture.executable(package + "/new/codex")
        try fixture.json(package + "/codex-package.json", ["layoutVersion": 1, "entrypoint": "new/codex"])
        _ = try fixture.executable(package + "/bin/codex")
        _ = try fixture.executable(fixture.applicationRoot + "/ChatGPT.app/Contents/Resources/codex")
        _ = try fixture.executable(fixture.pathRoot + "/codex")

        #expect(ExecutableLocator.locate("codex", environment: ["PATH": fixture.pathRoot], homeDirectory: fixture.home, applicationDirectories: [fixture.applicationRoot]) == entry)
    }

    @Test("Explicit override is authoritative, including an invalid path")
    func overridePriority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundled = try fixture.executable(fixture.applicationRoot + "/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        let override = try fixture.executable(fixture.root + "/custom-codex")
        let environment = ["PATH": fixture.pathRoot, "CODEX_PULSE_CODEX_PATH": override]

        #expect(ExecutableLocator.locate("codex", environment: environment, homeDirectory: fixture.home, applicationDirectories: [fixture.applicationRoot]) == override)
        #expect(ExecutableLocator.locate("codex", environment: ["PATH": fixture.pathRoot, "CODEX_PULSE_CODEX_PATH": fixture.root + "/missing"], homeDirectory: fixture.home, applicationDirectories: [fixture.applicationRoot]) == nil)
        #expect(ExecutableLocator.missingCodexMessage(language: .russian, environment: ["CODEX_PULSE_CODEX_PATH": fixture.root + "/missing"]).contains("не ведёт"))
        #expect(bundled != override)
    }

    @Test("Direct path survives a missing or unusable manifest")
    func directFallback() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = fixture.applicationRoot + "/ChatGPT.app/Contents/Resources/codex-cli"
        try fixture.json(package + "/codex-package.json", ["entrypoint": "../outside/codex"])
        let direct = try fixture.executable(package + "/bin/codex")

        #expect(ExecutableLocator.locate("codex", environment: ["PATH": ""], homeDirectory: fixture.home, applicationDirectories: [fixture.applicationRoot]) == direct)
    }

    @Test("Legacy and process PATH remain available")
    func legacyAndPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy = try fixture.executable(fixture.applicationRoot + "/Codex.app/Contents/MacOS/codex")
        let path = try fixture.executable(fixture.pathRoot + "/codex")
        let environment = ["PATH": fixture.pathRoot]

        #expect(ExecutableLocator.locate("codex", environment: environment, homeDirectory: fixture.home, applicationDirectories: [fixture.applicationRoot]) == legacy)
        try FileManager.default.removeItem(atPath: legacy)
        #expect(ExecutableLocator.locate("codex", environment: environment, homeDirectory: fixture.home, applicationDirectories: [fixture.applicationRoot]) == path)
        #expect(ExecutableLocator.missingCodexMessage(language: .english).contains("CODEX_PULSE_CODEX_PATH"))
    }

    @Test("Missing CLI guidance follows the selected UI language")
    func localizedGuidance() {
        let snapshot = ProviderSnapshot.unavailable(
            .codex,
            message: ExecutableLocator.missingCodexMessage(language: .english)
        )

        #expect(providerMessage(snapshot, language: .russian)?.contains("Проверены") == true)
        #expect(providerMessage(snapshot, language: .english)?.contains("Checked") == true)
    }
}

private struct Fixture {
    let root: String
    var applicationRoot: String { root + "/Applications" }
    var pathRoot: String { root + "/path" }
    var home: String { root + "/home" }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-locator-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    func executable(_ path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func json(_ path: String, _ object: [String: Any]) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: URL(fileURLWithPath: path))
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}
