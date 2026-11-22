// `wisent-errors-swift program run <name>`, the package's command line
// running a product's installed program the way its macOS app runs it
// (WisentProgram), run as a process: which program it admits. It looks only
// where the release installer places the program, $HOME/.local/bin then
// $HOME/.stado/bin, never on PATH or in the product's old variable; a
// program there is admitted only when its code signature shows the fleet's
// team signed it as com.wisent.<name>; one refused is not passed over for
// the next place; and the fleet-signed stado is admitted and runs, saying
// what it says when the system runs the same file directly.
//
//   swift test --filter AdmissionTests
//
// Rule 4: every `run(...)` below, the usage refusals included, is
// CommandCase.run (tests/swift-cli/CommandCase.swift), which starts the
// executable `swift test` built from swift/Sources/wisent-errors-swift as a
// child process -- `process.executableURL = Self.executable`
// (CommandCase.swift:173), then `try process.run()` (CommandCase.swift:195)
// -- and reads its exit status and both streams whole from its pipes
// (Running.finish, CommandCase.swift:108). Inside that child, Security
// checks real files: a shell script (a real file no one signed), a copy of
// /bin/sh (a real program Apple signed, not the fleet) and a copy of the
// fleet-signed stado given another product's name (signed, but as
// com.wisent.stado). Nothing answers for Security; the last step runs the
// real stado through the command, and the same copy directly with Process.
// Rule 5: `usage(...)` and `programRun(...)` only build the expected Ran,
// the exit status and the three stderr lines; each is compared whole with
// the Ran the child's pipes gave. Each step also reads state back: a
// refused program never ran (the file each stand-in writes when run is not
// there), a refused command line left the home empty, and the admitted
// stado left the case's home as it was installed and its storage empty.
// Rule 7: one test, one command: `program run` and how it admits, with every
// refusal of finding and admitting. Its output and its input
// (RunOutputTests) and its stop (RunStopTests) are the same command's other
// stories, each in its own file.
// Rule 8: the command's environment is cleared and given only HOME,
// CFFIXED_USER_HOME, TMPDIR and XDG_* inside the case's directory under
// .build; stado is handed, with --set, its own backend overrides:
// WC_STORAGE_BACKEND=local, WC_LOCAL_STORAGE_PATH under the case's directory
// and STADO_CONFIG naming an empty configuration file of the case's own, so
// it reads and writes nothing of the operator's.
// Rule 9: every sentence and exit status below was copied from live runs of
// wisent-errors-swift built from this tree (`swift build --product
// wisent-errors-swift`, 2026-11-21): each step run by hand under `env -i`
// given only HOME, CFFIXED_USER_HOME, TMPDIR and XDG_* inside
// target/probe-swift/admission, on the same stand-ins, the same copy of
// /bin/sh and a copy of the fleet-signed stado WISENT_PROGRAM_TEST_STADO
// names, Security's words as that run printed them. stado's own answer to
// `--version` was the same run directly and through the command; it changes
// with each stado release, so it is compared here with what the same copy
// answers when this process runs it.
// Rule 10: `program run` is implemented in
// swift/Sources/wisent-errors-swift/ProgramCommands.swift. The fleet-signed
// stado is not described, it is installed: .wisent-release.json declares it
// in `test_products` ({"product": "stado", "surface": "cli"}), which installs
// Stado's signed command line into the gate run's home, and names it in
// `env` as WISENT_PROGRAM_TEST_STADO (~/.local/bin/stado). Without it, the
// last step fails as blocked naming the variable, never passes.

#if os(macOS)
import Foundation
import XCTest

final class AdmissionTests: ProgramCase {
    /// A shell script at `relative` under the home that writes `marker` when run: a real file no one signed.
    @discardableResult
    private func standIn(_ relative: String, marker: URL) throws -> URL {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf ran > '\(marker.path)'\n".utf8).write(to: file)
        // rwxr-xr-x: an executable the user's account can run.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// A copy of `source` at `relative` under the home.
    @discardableResult
    private func copy(_ source: URL, to relative: String) throws -> URL {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: file)
        return file
    }

    /// What Security answered the live run for a file no one signed, and for a signature that is not the fleet's.
    private let unsigned = "code object is not signed at all (OSStatus -67062)"
    private let notTheFleets = "code failed to satisfy specified code requirement(s) (OSStatus -67050)"

    private func unverified(_ path: URL, name: String, identifier: String, _ security: String) -> Ran {
        programRun(
            "program-unverified", status: 1,
            "admitting \(path.path) as the program \(identifier): its code signature does not show that the team LNTWB5B9DV signed it as \(identifier), so it is not run; observed: Security answered \(security)",
            fix: "reinstall \(name) with its release installer, which places the program its publisher signed, or remove \(path.path); a program another publisher signs is named with --identifier and --team")
    }

    func test_program_run_admits_only_the_program_its_publisher_signed() throws {
        let marker = root.appendingPathComponent("ran")
        let local = home.appendingPathComponent(".local/bin/para")
        let stado = home.appendingPathComponent(".stado/bin/para")

        // A name that is a path, a team and an identifier no publisher has.
        XCTAssertEqual(try run(["program", "run", "../para"]), usage(
            "value-malformed",
            "reading the program name of `wisent-errors-swift program run`: \"../para\" is not one file name, as the installer names the program; observed: it names a path, not one file name",
            fix: "give the program name one file name, as the installer names the program, as in `program run stado -- --version`"))
        XCTAssertEqual(try run(["program", "run", "para", "--team", "lntwb"]), usage(
            "value-malformed",
            "reading --team of `wisent-errors-swift program run`: \"lntwb\" is not an Apple developer team id: ten uppercase letters and digits; observed: it is 5 character(s), not ten uppercase letters and digits",
            fix: "give --team an Apple developer team id: ten uppercase letters and digits, as in `--team HX7739G8FX`"))
        XCTAssertEqual(try run(["program", "run", "para", "--identifier", "com.wisent.para\" or true"]), usage(
            "value-malformed",
            "reading --identifier of `wisent-errors-swift program run`: \"com.wisent.para\\\" or true\" is not a signing identifier: ASCII letters, digits, '.' and '-'; observed: it holds a character a signing identifier never holds",
            fix: "give --identifier a signing identifier: ASCII letters, digits, '.' and '-', as in `--identifier org.nodejs.node`"))

        // No HOME: neither place can be named.
        var homeless = environment
        homeless["HOME"] = nil
        XCTAssertEqual(try run(["program", "run", "para"], environment: homeless), programRun(
            "home-unset", status: 1,
            "finding the installed program para: HOME is not set, so neither ~/.local/bin nor ~/.stado/bin can be named; observed: HOME holds \"\"",
            fix: "run it with HOME set to the home directory para was installed under"))
        XCTAssertEqual(try tree(home), [], "a refused command line installed and ran nothing")

        // A stand-in on PATH and named by the product's old variable is never looked at.
        let elsewhere = try standIn("bin/para", marker: marker)
        var led = environment
        led["PATH"] = elsewhere.deletingLastPathComponent().path
        led["PARA"] = elsewhere.path
        XCTAssertEqual(try run(["program", "run", "para"], environment: led), programRun(
            "program-missing", status: 1,
            "finding the installed program para: no executable file named para is in either place a release installer puts it; observed: looked in \(local.path), \(stado.path)",
            fix: "install para with its release installer (stado://releases/para/<version>/<platform>/install.sh), which places it in \(local.path)"))

        // A stand-in script where the installer places the program: unsigned, refused, never run.
        try standIn(".local/bin/para", marker: marker)
        XCTAssertEqual(try run(["program", "run", "para"]), unverified(local, name: "para", identifier: "com.wisent.para", unsigned))

        // Refused there, it is not passed over for a program in the next place.
        try copy(URL(fileURLWithPath: "/bin/sh"), to: ".stado/bin/para")
        XCTAssertEqual(try run(["program", "run", "para"]), unverified(local, name: "para", identifier: "com.wisent.para", unsigned))

        // A copy of a program Apple signed, given the name: a valid signature, not the fleet's.
        try FileManager.default.removeItem(at: local)
        XCTAssertEqual(try run(["program", "run", "para", "--", "-c", "printf ran > '\(marker.path)'"]), unverified(
            stado, name: "para", identifier: "com.wisent.para", notTheFleets))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "no refused program ran")

        // The fleet-signed stado: given another product's name it is refused; under its own it runs.
        try FileManager.default.removeItem(at: stado)
        let installed = try install(
            from: "WISENT_PROGRAM_TEST_STADO", meaning: "the fleet's signed stado, which .wisent-release.json test_products installs (~/.local/bin/stado)",
            as: "stado")
        try FileManager.default.copyItem(at: installed, to: local)
        XCTAssertEqual(try run(["program", "run", "para"]), unverified(local, name: "para", identifier: "com.wisent.para", notTheFleets))
        try FileManager.default.removeItem(at: local)

        let config = root.appendingPathComponent("stado-config.json")
        try Data("{}".utf8).write(to: config)
        let storage = root.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let backends = ["WC_STORAGE_BACKEND": "local", "WC_LOCAL_STORAGE_PATH": storage.path, "STADO_CONFIG": config.path]
        let ran = try run(["program", "run", "stado"] + backends.sorted { $0.key < $1.key }.flatMap { ["--set", "\($0.key)=\($0.value)"] } + ["--", "--version"])

        let direct = Process()
        direct.executableURL = installed
        direct.arguments = ["--version"]
        // The environment `program run` hands stado: the command's, less XDG_* and STADO_* (withheld by default), with --set over it.
        direct.environment = environment.filter { !$0.key.hasPrefix("XDG_") }.merging(backends) { $1 }
        direct.currentDirectoryURL = root
        let (out, err) = (root.appendingPathComponent("direct.out"), root.appendingPathComponent("direct.err"))
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        direct.standardOutput = try FileHandle(forWritingTo: out)
        direct.standardError = try FileHandle(forWritingTo: err)
        direct.standardInput = FileHandle.nullDevice
        try direct.run()
        direct.waitUntilExit()
        XCTAssertEqual(direct.terminationStatus, 0, try text(err))
        XCTAssertFalse(try text(out).isEmpty, "stado says its version")
        XCTAssertEqual(ran, Ran(status: 0, stdout: try text(out), stderr: try text(err)))
        XCTAssertEqual(
            try tree(home), [".local", ".local/bin", ".local/bin/stado", ".stado", ".stado/bin", "bin", "bin/para"],
            "the admitted stado left the home as it was installed")
        XCTAssertEqual(try tree(storage), [], "stado wrote nothing to its storage")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "no refused program ran")
    }
}
#endif
