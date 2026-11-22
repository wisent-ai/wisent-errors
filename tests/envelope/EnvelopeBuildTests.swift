// `wisent-errors-swift envelope build`, the package's command line building
// one failure envelope the way a Swift product builds one
// (`Failure(failurePoint:code:service:)`, or `Failure.orFallback` with
// --fallback), run as a process: the envelope it prints and writes with
// --out, every refusal of `wisent_errors.envelope.build` it says instead,
// its own argument refusals, and the file it cannot write -- the cases
// tests/envelope/build.rs holds the Rust crate to.
//
//   swift test --filter EnvelopeBuildTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195) -- and reads its exit
// status and both streams whole from its pipes; the envelope is then read
// from the file the child wrote. This file imports no module of the
// package: what it checks is what a person or a script running the command
// gets.
// Rule 5: each step asserts the exit status, the whole of stdout and of the
// refusal's three stderr lines, and reads the --out file back from disk: the
// envelope it holds after a build, and no file at all after a refusal.
// Rule 7: one test, one command: `envelope build` with its success, its
// --fallback, and every refusal it can say, step by step.
// Rule 9: every sentence, envelope and exit status below was copied from
// live runs of wisent-errors-swift built from this tree (`swift build
// --product wisent-errors-swift`, 2026-11-21): each step run by hand with
// the same arguments under `env -i` given only HOME, CFFIXED_USER_HOME,
// TMPDIR and XDG_* inside target/probe-swift/envelope, the --out file read
// back after each. The operating system's words for the directory that is
// not there are the ones that run printed, Foundation's in English, as the
// cleared environment gives the child no language of the operator's.

#if os(macOS)
import Foundation
import XCTest

final class EnvelopeBuildTests: CommandCase {
    private let codes = "config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown"
    private let example = "wisent-errors-swift envelope build --point stado.fleet.enroll --code refused --service stado"

    /// A refusal of `wisent_errors.envelope.build`, given as the one line `sentence; fix: remedy`: usage, so exit 2.
    private func invalid(_ cause: String, _ line: String) -> Ran {
        let parts = line.components(separatedBy: "; fix: ")
        return Ran(status: 2, stdout: "", stderr: refusal("wisent_errors.envelope.build", cause, page: "envelope", parts[0], fix: parts[1]))
    }

    func test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it() throws {
        let out = root.appendingPathComponent("failure.json")
        let build = { (point: String, service: String, more: [String]) throws -> Ran in
            try self.run(["envelope", "build", "--point", point, "--code", "refused", "--service", service, "--out", out.path] + more)
        }

        // A command line that names no command, or one it does not have.
        XCTAssertEqual(try run([]), usage(
            "command-absent",
            "reading the command of `wisent-errors-swift`: it names no command, so nothing would run; observed: its commands: envelope, declaration, telemetry, support, program",
            fix: "add one of envelope, declaration, telemetry, support, program, as in `\(example)`"))
        XCTAssertEqual(try run(["envelop"]), usage(
            "command-unknown",
            "reading the command of `wisent-errors-swift`: \"envelop\" is not one of its commands; observed: its commands: envelope, declaration, telemetry, support, program",
            fix: "run one of envelope, declaration, telemetry, support, program, as in `\(example)`"))
        XCTAssertEqual(try run(["envelope"]), usage(
            "command-absent",
            "reading the command of `wisent-errors-swift envelope`: it names no command, so nothing would run; observed: its commands: build, read",
            fix: "add one of build, read, as in `\(example)`"))
        XCTAssertEqual(try run(["envelope", "bild"]), usage(
            "command-unknown",
            "reading the command of `wisent-errors-swift envelope`: \"bild\" is not one of its commands; observed: its commands: build, read",
            fix: "run one of build, read, as in `\(example)`"))

        // An option it needs left out, a code that is none, a context without its '='.
        XCTAssertEqual(try run(["envelope", "build", "--point", "stado.fleet.enroll", "--code", "refused", "--out", out.path]), usage(
            "option-required",
            "reading the options of `wisent-errors-swift envelope build`: it needs --service, and --service was not given; observed: options given: --code, --out, --point",
            fix: "add --service, as in `--service stado`"))
        XCTAssertEqual(try run(["envelope", "build", "--point", "stado.fleet.enroll", "--code", "sometimes", "--service", "stado"]), usage(
            "value-unknown",
            "reading --code of `wisent-errors-swift envelope build`: \"sometimes\" is not one of its values; observed: its values: \(codes)",
            fix: "give --code one of \(codes)"))
        XCTAssertEqual(try build("stado.fleet.enroll", "stado", ["--context", "host"]), usage(
            "value-malformed",
            "reading --context of `wisent-errors-swift envelope build`: \"host\" is not NAME=VALUE; observed: it holds no '='",
            fix: "give --context NAME=VALUE, as in `--context host=example-host`"))
        XCTAssertEqual(try tree(root), ["cache", "config", "data", "home", "state", "tmp"], "no refusal wrote the envelope")

        // Each refusal of the builder, with the envelope never written.
        XCTAssertEqual(try build("   ", "stado", []), invalid(
            "failure-point-absent",
            "building the failure envelope of service stado: the failure point is empty, so the envelope would not say where it broke; observed: failure_point \"   \", nothing once the whitespace around it is trimmed; fix: pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with Failure.orFallback, which records the gap in context instead of refusing"))
        XCTAssertEqual(try build("stado..enroll", "stado", []), invalid(
            "failure-point-segment-empty",
            "building the failure envelope of service stado: segment 2 of the failure point \"stado..enroll\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"stado\",\"\",\"enroll\"]; fix: drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with Failure.orFallback"))
        XCTAssertEqual(try build("Brama.dispatch", "brama", []), invalid(
            "failure-point-segment-start",
            "building the failure envelope of service brama: segment 1 of the failure point \"Brama.dispatch\", \"Brama\", starts with \"B\", and a segment starts with a lowercase letter; observed: segments [\"Brama\",\"dispatch\"]; fix: start the segment with a lowercase letter, as 'brama.dispatch'; on an error path build it with Failure.orFallback"))
        XCTAssertEqual(try build("stado.fleet enroll", "stado", []), invalid(
            "failure-point-character",
            "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet enroll\", \"fleet enroll\", holds \" \", which is not a lowercase letter, a digit, '-' or '_'; observed: segments [\"stado\",\"fleet enroll\"]; fix: write the point in lowercase letters, digits and single '-' or '_', as 'stado.fleet-enroll'; on an error path build it with Failure.orFallback"))
        XCTAssertEqual(try build("stado.fleet-", "stado", []), invalid(
            "failure-point-separator",
            "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet-\", \"fleet-\", ends with a separator or holds two together, and '-' and '_' only join two words; observed: segments [\"stado\",\"fleet-\"]; fix: keep one '-' or '_' between two words of a segment, as 'stado.fleet'; on an error path build it with Failure.orFallback"))
        XCTAssertEqual(try build("stado.fleet.enroll", " ", []), invalid(
            "service-absent",
            "building the failure envelope at stado.fleet.enroll: the service is empty, so the envelope would not say which component failed; observed: service \" \", nothing once the whitespace around it is trimmed; fix: pass the name of the component raising it, as in 'stado'; on an error path build it with Failure.orFallback, which records the gap in context"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "no refused envelope was written")

        // The envelope, printed and written whole.
        let built = #"{"failure_point":"stado.fleet.enroll","error_code":"refused","service":"stado","impact":"one enrollment","severity":"warning","retryable":false,"outage":false,"detail":"the fleet answered 403","remedy":"enroll the host first","context":{"host":"example-host"}}"# + "\n"
        XCTAssertEqual(
            try build("stado.fleet.enroll", "stado", [
                "--impact", "one enrollment", "--detail", "the fleet answered 403", "--remedy", "enroll the host first",
                "--context", "host=example-host",
            ]),
            Ran(status: 0, stdout: built, stderr: ""))
        XCTAssertEqual(try text(out), built)

        // --fallback never refuses: the gap is recorded in the envelope's context.
        let absent = #"{"failure_point":"unknown","error_code":"refused","service":"stado","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":null,"remedy":null,"context":{"wisent_errors.failure_point":"absent"}}"# + "\n"
        XCTAssertEqual(try build("   ", "stado", ["--fallback"]), Ran(status: 0, stdout: absent, stderr: ""))
        XCTAssertEqual(try text(out), absent)
        let malformed = #"{"failure_point":"stado..enroll","error_code":"refused","service":"unknown","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":null,"remedy":null,"context":{"wisent_errors.failure_point":"malformed","wisent_errors.failure_point_cause":"failure-point-segment-empty","wisent_errors.service":"absent"}}"# + "\n"
        XCTAssertEqual(try build("stado..enroll", " ", ["--fallback"]), Ran(status: 0, stdout: malformed, stderr: ""))
        XCTAssertEqual(try text(out), malformed)

        // A file it cannot write: the directory --out names is not there.
        let nowhere = root.appendingPathComponent("missing").appendingPathComponent("failure.json")
        XCTAssertEqual(
            try run(["envelope", "build", "--point", "stado.fleet.enroll", "--code", "refused", "--service", "stado", "--out", nowhere.path]),
            Ran(status: 1, stdout: "", stderr: refusal(
                "wisent_errors.swift_cli.envelope_build", "envelope-unwritten", page: "swift-cli",
                "writing the envelope to \(nowhere.path): the operating system refused to write the file there; observed: \(nowhere.deletingLastPathComponent().path) cannot be examined: The file “missing” couldn’t be opened because there is no such file. (NSCocoaErrorDomain 260): The operation couldn’t be completed. No such file or directory (NSPOSIXErrorDomain 2); the operating system answered The folder “failure.json” doesn’t exist. (NSCocoaErrorDomain 4): The operation couldn’t be completed. No such file or directory (NSPOSIXErrorDomain 2)",
                fix: "name with --out a file in a directory this user can write, or leave --out out to print the envelope only")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nowhere.deletingLastPathComponent().path), "nothing was made for the refused file")
        XCTAssertEqual(try text(out), malformed, "the envelope written before is left as it was")
    }
}
#endif
