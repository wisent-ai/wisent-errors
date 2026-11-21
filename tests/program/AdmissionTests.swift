// Real tests, through WisentProgram's public API, that a desktop app runs
// only the program the fleet signed: the places are only ~/.local/bin and
// ~/.stado/bin of the home, a stand-in named on PATH or by the product's old
// variable is never looked at, a stand-in script or a copy of another signed
// program given the product's name is refused as unverified with Security's
// answer, a refused program is not passed over for the next place, none
// executable is a refusal naming every place, a process that is not the
// fleet's is killed before it runs or reads its input, naming the executable
// the kernel ran, and a fleet program (the stado WISENT_PROGRAM_TEST_STADO
// names, copied into a home under .build) is admitted and runs.
//
//   swift test --filter AdmissionTests

#if os(macOS)
import Foundation
import Security
import WisentProgram
import XCTest

final class AdmissionTests: ProgramCase {
    private let para = InstalledProgram(name: "para", leading: ["-c"])

    /// An executable file at `relative` under `home`: a shell script, or a copy of `copying`.
    @discardableResult
    private func placed(_ relative: String, in home: URL, copying: String? = nil) throws -> URL {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let copying {
            try FileManager.default.copyItem(atPath: copying, toPath: file.path)
        } else {
            try Data("#!/bin/sh\nprintf stand-in\n".utf8).write(to: file)
        }
        // rwxr-xr-x: an executable the user's account can run.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func places(_ home: URL) -> [String] {
        [home.appendingPathComponent(".local/bin/para").path, home.appendingPathComponent(".stado/bin/para").path]
    }

    private func refusal(_ attempt: () throws -> URL) -> InstalledProgram.Failure? {
        do {
            let found = try attempt()
            XCTFail("\(found.path) was admitted")
            return nil
        } catch {
            return error as? InstalledProgram.Failure
        }
    }

    func test_the_requirement_is_the_fleets_designated_one() {
        XCTAssertEqual(para.identifier, "com.wisent.para")
        XCTAssertEqual(FleetSignature.team, "LNTWB5B9DV")
        XCTAssertEqual(
            FleetSignature.requirement(identifier: para.identifier),
            #"identifier "com.wisent.para" and anchor apple generic and certificate leaf[subject.OU] = "LNTWB5B9DV""#)
    }

    func test_the_places_are_only_the_installer_and_stado_bin_directories() {
        XCTAssertEqual(
            para.candidates(home: URL(fileURLWithPath: "/home/example-user")).map(\.path),
            ["/home/example-user/.local/bin/para", "/home/example-user/.stado/bin/para"])
    }

    /// The forged caller of the audit: a stand-in where a PATH entry or the
    /// product's old variable (PARA) would have led. Neither is read, so the
    /// places looked in are the two of the home.
    func test_a_stand_in_on_path_or_named_by_the_old_variable_is_never_looked_at() throws {
        let home = try caseHome()
        let standIn = try placed("bin/para", in: home)
        setenv("PARA", standIn.path, 1)
        defer { unsetenv("PARA") }
        XCTAssertEqual(refusal { try para.executable(home: home) }, .missing(searched: places(home)))
    }

    func test_a_stand_in_script_where_the_installer_places_the_program_is_refused() throws {
        let home = try caseHome()
        let standIn = try placed(".local/bin/para", in: home)
        XCTAssertEqual(
            refusal { try para.executable(home: home) },
            .unverified(path: standIn.path, reason: security(errSecCSUnsigned)))
    }

    /// A copy of a program Apple signed keeps a valid signature, but not the
    /// fleet's identifier and team, whatever name it is given: Security
    /// answers errSecCSReqFailed, the requirement unmet, not a broken signature.
    func test_a_copy_of_another_signed_program_given_the_name_is_refused() throws {
        let home = try caseHome()
        let copy = try placed(".stado/bin/para", in: home, copying: "/bin/sh")
        XCTAssertEqual(
            refusal { try para.executable(home: home) },
            .unverified(path: copy.path, reason: security(errSecCSReqFailed)))
    }

    func test_a_refused_program_is_not_passed_over_for_the_next_place() throws {
        let home = try caseHome()
        let first = try placed(".local/bin/para", in: home)
        try placed(".stado/bin/para", in: home, copying: "/bin/sh")
        XCTAssertEqual(
            refusal { try para.executable(home: home) },
            .unverified(path: first.path, reason: security(errSecCSUnsigned)))
    }

    func test_no_executable_anywhere_is_refused_naming_every_place() throws {
        let home = try caseHome()
        XCTAssertEqual(refusal { try para.executable(home: home) }, .missing(searched: places(home)))
    }

    /// Whatever path a caller hands `run`, the process the kernel started is
    /// checked before it runs: /bin/sh is Apple's, not the fleet's para, so
    /// it is killed suspended, writes nothing and is handed no input.
    func test_a_process_that_is_not_the_fleets_is_killed_before_it_runs_or_reads_its_input() async throws {
        let marker = try caseHome().appendingPathComponent("ran")
        do {
            let outcome = try await para.run(
                ["cat > '\(marker.path)'"], executable: URL(fileURLWithPath: "/bin/sh"), input: Data("secret".utf8))
            XCTFail("a process the fleet did not sign was run: \(outcome)")
        } catch {
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .unverified(path: "/bin/sh", reason: security(errSecCSReqFailed)),
                "the path is the one the kernel gives for the process")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the refused process ran")
    }

    /// The path every app relies on: the fleet program found in the home's
    /// ~/.local/bin, started suspended, admitted by pid and run to its exit,
    /// saying what it says when the system runs it directly.
    func test_a_fleet_signed_program_is_admitted_and_runs() async throws {
        let stado = InstalledProgram(name: "stado")
        let found = try installed(stado, from: "WISENT_PROGRAM_TEST_STADO", meaning: "the fleet's signed stado (~/.stado/bin/stado)")
        XCTAssertThrowsError(try FleetSignature.verify(file: found, identifier: "com.wisent.para")) { error in
            XCTAssertEqual(error as? FleetSignature.Refusal, FleetSignature.Refusal(path: found.path, reason: security(errSecCSReqFailed)))
        }
        let outcome = try await stado.run(["--version"], executable: found)
        let direct = Process()
        direct.executableURL = found
        direct.arguments = ["--version"]
        let said = Pipe()
        direct.standardOutput = said
        try direct.run()
        let printed = String(decoding: said.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        direct.waitUntilExit()
        XCTAssertEqual(direct.terminationStatus, 0)
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 0, signalled: false, stdout: printed, stderr: ""))
    }
}
#endif
