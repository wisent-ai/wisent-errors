// Real tests of how a desktop app finds and runs its product's installed CLI:
// the places are looked in the order the product's variable, PATH,
// ~/.local/bin and ~/.stado/bin give, a program the release installer placed
// in ~/.local/bin is found by an app whose PATH is launchd's, none executable
// is a refusal naming every place, a run hands back both streams whole with
// the exit status, and cancelling the caller stops the program with SIGTERM.
//
//   swift test --filter InstalledProgramTests

#if os(macOS)
import Foundation
import WisentProgram
import XCTest

final class InstalledProgramTests: XCTestCase {
    private let program = InstalledProgram(name: "para", variable: "PARA", leading: ["-c"])

    func testThePlacesAreTheVariableThenPathThenTheInstallerAndStadoBinDirectories() {
        let home = URL(fileURLWithPath: "/home/someone")
        let places = program.candidates(environment: ["PARA": "/opt/para", "PATH": "/usr/bin:/bin"], home: home)
        XCTAssertEqual(
            places.map(\.path),
            ["/opt/para", "/usr/bin/para", "/bin/para", "/home/someone/.local/bin/para", "/home/someone/.stado/bin/para"])
        XCTAssertEqual(
            program.candidates(environment: ["PARA": ""], home: home).map(\.path),
            ["/home/someone/.local/bin/para", "/home/someone/.stado/bin/para"],
            "an empty variable is unset, and no PATH searches nothing")
    }

    /// An app opened from Finder runs with launchd's PATH, which does not hold
    /// ~/.local/bin, where the release installer places the program.
    func testAProgramTheInstallerPlacedIsFoundUnderLaunchdsPath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let placed = bin.appendingPathComponent("para")
        try Data("#!/bin/sh\n".utf8).write(to: placed)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: placed.path)
        let found = try program.executable(environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], home: home)
        XCTAssertEqual(found.path, placed.path)
    }

    func testNoExecutableAnywhereIsRefusedNamingEveryPlace() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try program.executable(environment: ["PATH": home.path], home: home)) { error in
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .missing(searched: [
                    home.appendingPathComponent("para").path,
                    home.appendingPathComponent(".local/bin/para").path,
                    home.appendingPathComponent(".stado/bin/para").path,
                ]))
        }
    }

    func testARunHandsBackBothStreamsWholeAndItsStatus() async throws {
        let outcome = try await program.run(
            ["printf out; printf err >&2; exit 3"], executable: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 3, signalled: false, stdout: "out", stderr: "err"))
    }

    func testEachChunkIsHandedOnWithItsStreamAsItArrives() async throws {
        final class Chunks: @unchecked Sendable {
            private let lock = NSLock()
            private var held: [String] = []
            func add(_ text: String) { lock.withLock { held.append(text) } }
            var all: String { lock.withLock { held.joined() } }
        }
        let seen = Chunks()
        let outcome = try await program.run(["printf one; printf two >&2"], executable: URL(fileURLWithPath: "/bin/sh")) {
            stream, text in seen.add(stream == .stdout ? "out:\(text);" : "err:\(text);")
        }
        XCTAssertTrue(seen.all.contains("out:one;") && seen.all.contains("err:two;"), seen.all)
        XCTAssertEqual(outcome.stdout, "one")
    }

    /// `ł` (C5 82) written in two halves reaches the run in two reads; each
    /// read decoded on its own said it as two U+FFFD.
    func testACharacterTwoReadsSplitIsSaidWhole() async throws {
        let outcome = try await program.run(
            ["printf 'Rachuba \\305'; sleep 0.2; printf '\\202\\303\\263d'"], executable: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(outcome.stdout, "Rachuba łód")
    }

    func testCancellingTheCallerStopsTheProgram() async throws {
        let run = Task { try await program.run(["exec sleep 30"], executable: URL(fileURLWithPath: "/bin/sh")) }
        try await Task.sleep(nanoseconds: 200_000_000)
        run.cancel()
        let outcome = try await run.value
        XCTAssertTrue(outcome.signalled, "\(outcome)")
        XCTAssertEqual(outcome.status, SIGTERM)
    }
}
#endif
