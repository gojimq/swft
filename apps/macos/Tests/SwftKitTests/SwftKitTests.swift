import Foundation
import Testing
@testable import SwftKit

@Test func packageBuilds() { _ = SwftKit.self }

/// Opened from inside an agent run, Swft inherits that run's private TMPDIR; once the run's folder is deleted every
/// temp file the server or a provider creates fails (Antigravity sign-in could not create its setup workspace).
@Test func serverEnvironmentUsesTheUsersOwnTempFolder() {
    let env = ServerProcess.childEnvironment(
        inherited: ["TMPDIR": "/Users/someone/.t3/userdata/antigravity-tmp/ac0a3dfd6ddd/run-gone", "T3CODE_PORT": "1", "PATH": "/usr/bin"],
        extra: ["SWFT_EXTRA": "1"]
    )
    #expect(env["TMPDIR"] != nil)
    #expect(env["TMPDIR"]?.contains("antigravity-tmp") == false)
    #expect(FileManager.default.fileExists(atPath: env["TMPDIR"] ?? ""))
    #expect(env["T3CODE_PORT"] == nil)
    #expect(env["PATH"] == "/usr/bin")
    #expect(env["SWFT_EXTRA"] == "1")
}
