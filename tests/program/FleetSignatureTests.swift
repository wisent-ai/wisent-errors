// Real tests that a desktop app runs only the program the fleet signed: the
// places are only ~/.local/bin and ~/.stado/bin of the home, a stand-in named
// on PATH or by the product's old variable is never looked at, a stand-in
// script or a copy of another signed program given the product's name is
// refused as unverified, a refused program is not passed over for the next
// place, none executable is a refusal naming every place, a run of a
// process that is not the fleet's is killed before it runs or reads its
// input, naming the executable the kernel ran, an installed fleet program is
// admitted and runs, and a process that already ran is not taken for one
// started suspended and untouched.
//
//   swift test --filter FleetSignatureTests

#if os(macOS)
import Foundation
import Security
@testable import WisentProgram
import XCTest

final class FleetSignatureTests: XCTestCase {
    private let program = InstalledProgram(name: "para", leading: ["-c"])

    /// A home of the test's own, removed when the test ends.
    private func testHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    /// An executable file at `relative` under `home`: a shell script, or a
    /// copy of `copying`.
    @discardableResult
    private func placed(_ relative: String, in home: URL, copying: String? = nil) throws -> URL {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let copying {
            try FileManager.default.copyItem(atPath: copying, toPath: file.path)
        } else {
            try Data("#!/bin/sh\nprintf stand-in\n".utf8).write(to: file)
        }
        // rwxr-xr-x: an executable the user's account can run.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    func testTheRequirementIsTheFleetsDesignatedOne() {
        XCTAssertEqual(program.identifier, "com.wisent.para")
        XCTAssertEqual(
            FleetSignature.requirement(identifier: program.identifier),
            #"identifier "com.wisent.para" and anchor apple generic and certificate leaf[subject.OU] = "LNTWB5B9DV""#)
    }

    func testThePlacesAreOnlyTheInstallerAndStadoBinDirectories() {
        let home = URL(fileURLWithPath: "/home/someone")
        XCTAssertEqual(
            program.candidates(home: home).map(\.path),
            ["/home/someone/.local/bin/para", "/home/someone/.stado/bin/para"])
    }

    /// The forged caller of the audit (audit-rest-01.md row 39): a stand-in
    /// where a PATH entry or the product's old variable (PARA) would have led.
    /// Neither is read any more, so the places looked in are the two of the
    /// home, and a stand-in anywhere else is not found.
    func testAStandInOnPathOrNamedByTheOldVariableIsNeverLookedAt() throws {
        let home = try testHome()
        try placed("bin/para", in: home)
        XCTAssertThrowsError(try program.executable(home: home)) { error in
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .missing(searched: [
                    home.appendingPathComponent(".local/bin/para").path,
                    home.appendingPathComponent(".stado/bin/para").path,
                ]))
        }
    }

    func testAStandInScriptWhereTheInstallerPlacesTheProgramIsRefused() throws {
        let home = try testHome()
        let standIn = try placed(".local/bin/para", in: home)
        XCTAssertThrowsError(try program.executable(home: home)) { error in
            guard case .unverified(let path, let reason)? = error as? InstalledProgram.Failure else {
                return XCTFail("refused with \(error)")
            }
            XCTAssertEqual(path, standIn.path)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    /// A copy of a program Apple signed keeps a valid signature, but not the
    /// fleet's identifier and team, whatever name it is given: Security
    /// answers errSecCSReqFailed (-67050, `<Security/CSCommon.h>`), the
    /// requirement unmet, not a broken signature.
    func testACopyOfAnotherSignedProgramGivenTheNameIsRefused() throws {
        let home = try testHome()
        let copy = try placed(".stado/bin/para", in: home, copying: "/bin/sh")
        XCTAssertThrowsError(try program.executable(home: home)) { error in
            guard case .unverified(let path, let reason)? = error as? InstalledProgram.Failure else {
                return XCTFail("refused with \(error)")
            }
            XCTAssertEqual(path, copy.path)
            XCTAssertTrue(reason.contains("OSStatus \(errSecCSReqFailed)"), reason)
        }
    }

    func testARefusedProgramIsNotPassedOverForTheNextPlace() throws {
        let home = try testHome()
        let first = try placed(".local/bin/para", in: home)
        try placed(".stado/bin/para", in: home, copying: "/bin/sh")
        XCTAssertThrowsError(try program.executable(home: home)) { error in
            guard case .unverified(let path, _)? = error as? InstalledProgram.Failure else {
                return XCTFail("refused with \(error)")
            }
            XCTAssertEqual(path, first.path)
        }
    }

    func testNoExecutableAnywhereIsRefusedNamingEveryPlace() throws {
        let home = try testHome()
        XCTAssertThrowsError(try program.executable(home: home)) { error in
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .missing(searched: [
                    home.appendingPathComponent(".local/bin/para").path,
                    home.appendingPathComponent(".stado/bin/para").path,
                ]))
        }
    }

    /// Whatever path a caller hands `run`, the process the kernel started
    /// is checked before it runs: /bin/sh is Apple's, not the fleet's
    /// para, so it is killed suspended, writes nothing and is handed no input.
    func testAProcessThatIsNotTheFleetsIsKilledBeforeItRunsOrReadsItsInput() async throws {
        let home = try testHome()
        let marker = home.appendingPathComponent("ran")
        do {
            let outcome = try await program.run(
                ["cat > '\(marker.path)'"], executable: URL(fileURLWithPath: "/bin/sh"), input: Data("secret".utf8))
            XCTFail("a process the fleet did not sign was run: \(outcome)")
        } catch InstalledProgram.Failure.unverified(let path, let reason) {
            XCTAssertEqual(path, "/bin/sh", "the path is the one the kernel gives for the process")
            XCTAssertFalse(reason.isEmpty)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the refused process ran")
    }

    /// The path every app relies on: an installed fleet program found,
    /// started suspended, admitted by pid and run to its exit.
    func testAFleetSignedProgramIsAdmittedAndRuns() async throws {
        let stado = InstalledProgram(name: "stado")
        try XCTSkipUnless(
            stado.candidates().contains { FileManager.default.isExecutableFile(atPath: $0.path) },
            "no stado is installed in ~/.local/bin or ~/.stado/bin of this machine to admit")
        let found = try stado.executable()
        XCTAssertThrowsError(try FleetSignature.verify(file: found, identifier: "com.wisent.para"))
        let outcome = try await stado.run(["--version"], executable: found)
        XCTAssertEqual(outcome.status, 0, outcome.stderr)
        XCTAssertFalse(outcome.signalled)
    }

    /// A process that runs is not one started suspended and untouched.
    func testARunningProcessIsNotTakenForAnUnrunOne() throws {
        let running = Process()
        running.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        running.arguments = ["-f", "/dev/null"]
        try running.run()
        defer { running.terminate() }
        guard case .failure(let refusal) = FleetSignature.unrun(running.processIdentifier) else {
            return XCTFail("a running process was taken for one that ran nothing")
        }
        XCTAssertTrue(refusal.reason.contains("resumed"), refusal.reason)
    }
}
#endif
