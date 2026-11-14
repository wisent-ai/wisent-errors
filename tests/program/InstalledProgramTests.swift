// Real tests of how a desktop app finds and runs its product's installed CLI:
// the places are looked in the order the product's variable, PATH and
// ~/.stado/bin give, none executable is a refusal naming every place, a run
// hands back both streams whole with the exit status, and cancelling the
// caller stops the program with SIGTERM.
//
//   swift test --filter InstalledProgramTests

#if os(macOS)
import Foundation
import WisentProgram
import XCTest

final class InstalledProgramTests: XCTestCase {
    private let program = InstalledProgram(name: "para", variable: "PARA", leading: ["-c"])

    func testThePlacesAreTheVariableThenPathThenTheStadoBinDirectory() {
        let home = URL(fileURLWithPath: "/home/someone")
        let places = program.candidates(environment: ["PARA": "/opt/para", "PATH": "/usr/bin:/bin"], home: home)
        XCTAssertEqual(
            places.map(\.path), ["/opt/para", "/usr/bin/para", "/bin/para", "/home/someone/.stado/bin/para"])
        XCTAssertEqual(
            program.candidates(environment: ["PARA": ""], home: home).map(\.path),
            ["/home/someone/.stado/bin/para"], "an empty variable is unset, and no PATH searches nothing")
    }

    func testNoExecutableAnywhereIsRefusedNamingEveryPlace() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try program.executable(environment: ["PATH": home.path], home: home)) { error in
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .missing(searched: [home.appendingPathComponent("para").path, home.appendingPathComponent(".stado/bin/para").path]))
        }
    }

    func testARunHandsBackBothStreamsWholeAndItsStatus() async throws {
        let outcome = try await program.run(
            ["printf out; printf err >&2; exit 3"], executable: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 3, signalled: false, stdout: "out", stderr: "err"))
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
