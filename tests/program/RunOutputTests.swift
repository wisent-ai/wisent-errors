// Real tests, through WisentProgram's public API, of what one run of an
// admitted program hands back: both streams whole with the exit status, each
// chunk with its stream as it arrives and a character two reads split said
// whole, its input as its standard input and a program that closes it early
// told apart, its environment the app's with what is set over it, less what
// is withheld, a name holding = refused before it starts, a program that
// cannot start refused naming why, and a run whose exit cannot be waited for
// refused naming the wait. The program is the Node.js-signed node
// WISENT_PROGRAM_TEST_NODE names, copied into a home under .build and found
// there (ProgramCase.swift), admitted under its own requirement.
//
//   swift test --filter RunOutputTests

#if os(macOS)
import Darwin
import Foundation
import WisentProgram
import XCTest

final class RunOutputTests: ProgramCase {
    func test_a_run_hands_back_both_streams_whole_and_its_status() async throws {
        let outcome = try await node.run(
            ["process.stdout.write('out'); process.stderr.write('err'); process.exitCode = 3"], executable: try installedNode())
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 3, signalled: false, stdout: "out", stderr: "err"))
    }

    func test_each_chunk_is_handed_on_with_its_stream_as_it_arrives() async throws {
        final class Chunks: @unchecked Sendable {
            private let lock = NSLock()
            private var held: [InstalledProgram.Stream: String] = [:]
            func add(_ stream: InstalledProgram.Stream, _ text: String) { lock.withLock { held[stream, default: ""] += text } }
            var all: [InstalledProgram.Stream: String] { lock.withLock { held } }
        }
        let seen = Chunks()
        let outcome = try await node.run(
            ["process.stdout.write('one'); process.stderr.write('two')"], executable: try installedNode()
        ) { stream, text in seen.add(stream, text) }
        XCTAssertEqual(seen.all, [.stdout: "one", .stderr: "two"])
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 0, signalled: false, stdout: "one", stderr: "two"))
    }

    /// `ł` (C5 82) written in two halves reaches the run in two reads; each
    /// read decoded on its own said it as two U+FFFD.
    func test_a_character_two_reads_split_is_said_whole() async throws {
        let outcome = try await node.run(
            ["process.stdout.write(Buffer.concat([Buffer.from('Rachuba '), Buffer.from([0xc5])])); setTimeout(() => process.stdout.write(Buffer.from([0x82, 0xc3, 0xb3, 0x64])), 200)"],
            executable: try installedNode())
        XCTAssertEqual(outcome.stdout, "Rachuba łód")
    }

    func test_the_input_is_the_programs_standard_input_then_its_end() async throws {
        let outcome = try await node.run(
            ["let read = ''; process.stdin.setEncoding('utf8'); process.stdin.on('data', (chunk) => { read += chunk }); process.stdin.on('end', () => { process.stdout.write(read); process.stderr.write('done') })"],
            executable: try installedNode(), input: Data("one\ntwo\n".utf8))
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 0, signalled: false, stdout: "one\ntwo\n", stderr: "done"))
        XCTAssertTrue(outcome.inputDelivered)
    }

    func test_a_program_that_closes_its_input_early_is_told_apart_and_signals_nothing_here() async throws {
        // More than the largest buffer a macOS pipe holds (BIG_PIPE_SIZE,
        // https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/pipe.h),
        // so some of it is still unwritten when the program closes its input.
        let input = Data(repeating: UInt8(ascii: "x"), count: 2 * 64 * 1024)
        let outcome = try await node.run(
            ["require('fs').closeSync(0); process.stdout.write('closed')"], executable: try installedNode(), input: input)
        XCTAssertEqual(
            outcome, InstalledProgram.Outcome(status: 0, signalled: false, stdout: "closed", stderr: "", inputDelivered: false))
    }

    func test_the_environment_is_set_over_the_apps_own() async throws {
        let home = try XCTUnwrap(ProcessInfo.processInfo.environment["HOME"], "the test needs HOME set to inherit it")
        let outcome = try await node.run(
            ["process.stdout.write(process.env.WISENT_PROGRAM_TEST + '|' + process.env.HOME)"], executable: try installedNode(),
            environment: ["WISENT_PROGRAM_TEST": "set"])
        XCTAssertEqual(outcome.stdout, "set|\(home)", "HOME is the app's own, inherited")
    }

    func test_a_variable_the_run_withholds_does_not_reach_the_program() async throws {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["HOME"], "the test needs HOME set to withhold it")
        let outcome = try await node.run(
            ["process.stdout.write(process.env.HOME ?? 'withheld')"], executable: try installedNode(), withholding: ["HOME"])
        XCTAssertEqual(outcome.stdout, "withheld")
    }

    func test_the_programs_own_variables_and_the_loaders_are_withheld_by_default() async throws {
        XCTAssertEqual(node.withheld, ["NODE_", "XDG_", "DYLD_"])
        XCTAssertEqual(InstalledProgram(name: "trends-cli").withheld, ["TRENDS_CLI_", "XDG_", "DYLD_"])
        let set = ["NODE_WISENT_PROGRAM_TEST", "XDG_WISENT_PROGRAM_TEST", "DYLD_WISENT_PROGRAM_TEST", "WISENT_PROGRAM_TEST_KEPT"]
        for name in set { setenv(name, "the app's", 1) }
        defer { for name in set { unsetenv(name) } }
        let outcome = try await node.run(
            ["process.stdout.write(JSON.stringify(Object.keys(process.env).filter((name) => name.includes('WISENT_PROGRAM_TEST')).sort()))"],
            executable: try installedNode())
        XCTAssertEqual(outcome.stdout, #"["WISENT_PROGRAM_TEST_KEPT"]"#)
    }

    func test_an_environment_name_holding_an_equals_sign_is_refused_before_the_program_starts() async throws {
        let found = try installedNode()
        do {
            let outcome = try await node.run(["process.stdout.write('ran')"], executable: found, environment: ["A=B": "x"])
            XCTFail("a name holding = was run: \(outcome)")
        } catch {
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .failedToStart(
                    path: found.path,
                    reason: "the environment variable name \"A=B\" is empty or holds =, which ends a name in an environment entry"))
        }
    }

    func test_a_program_that_cannot_start_is_refused_naming_why() async throws {
        let missing = try caseHome().appendingPathComponent("no-such-program")
        do {
            let outcome = try await node.run([], executable: missing)
            XCTFail("the run is refused, not \(outcome)")
        } catch {
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .failedToStart(path: missing.path, reason: failed("posix_spawn", ENOENT)))
        }
    }

    /// With SIGCHLD ignored the system reaps every child itself, as in an app
    /// that sets it, so the program's exit cannot be waited for: the run is
    /// refused naming that wait, instead of standing forever.
    func test_a_program_something_else_reaped_is_refused_naming_the_wait() async throws {
        let found = try installedNode()
        let previous = signal(SIGCHLD, SIG_IGN)
        defer { signal(SIGCHLD, previous) }
        do {
            let outcome = try await node.run(["process.exitCode = 0"], executable: found)
            XCTFail("the run is refused, not \(outcome)")
        } catch {
            XCTAssertEqual(
                error as? InstalledProgram.Failure,
                .unfollowed(path: found.path, step: "waitid", reason: failed("waitid", ECHILD)))
        }
    }
}
#endif
