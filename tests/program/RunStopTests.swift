// Real tests, through WisentProgram's public API, of how a run of an admitted
// program ends when asked to: cancelling the caller stops the program's whole
// process group with SIGTERM and a second request kills one that ignores it
// with SIGKILL, even one that stopped itself; a stop before the run refuses
// it; a stop that arrives after the group exited keeps the run's outcome; and
// a process the program left holding its output does not hold the run. The
// program is the Node.js-signed node WISENT_PROGRAM_TEST_NODE names, copied
// into a home under .build and found there (ProgramCase.swift).
//
//   swift test --filter RunStopTests

#if os(macOS)
import Darwin
import Foundation
import WisentProgram
import XCTest

final class RunStopTests: ProgramCase {
    func test_cancelling_the_caller_stops_the_program() async throws {
        let found = try installedNode()
        let first = FirstLine()
        let run = Task {
            try await node.run(["console.log('ready'); setTimeout(() => {}, 30000)"], executable: found) { stream, text in
                if stream == .stdout { first.add(text) }
            }
        }
        let ready = await first.next()
        XCTAssertEqual(ready, "ready")
        run.cancel()
        let outcome = try await run.value
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: SIGTERM, signalled: true, stdout: "ready\n", stderr: ""))
    }

    /// The program starts `tail`, which never ends by itself, handing it both
    /// its streams, and ignores SIGTERM, exiting only once `tail` has: the
    /// run ending at all is the evidence the stop reached `tail` too, which
    /// signalling the program alone never did.
    func test_cancelling_the_caller_stops_every_process_of_the_programs_group() async throws {
        let found = try installedNode()
        let first = FirstLine()
        let run = Task {
            try await node.run(
                ["const tail = require('child_process').spawn('/usr/bin/tail', ['-f', '/dev/null'], { stdio: ['ignore', 'inherit', 'inherit'] }); process.on('SIGTERM', () => {}); tail.on('exit', () => process.exit(0)); console.log(tail.pid)"],
                executable: found
            ) { stream, text in
                if stream == .stdout { first.add(text) }
            }
        }
        let line = await first.next()
        let started = try XCTUnwrap(pid_t(line), "the pid of the process the program started: \(line)")
        run.cancel()
        let outcome = try await run.value
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 0, signalled: false, stdout: "\(started)\n", stderr: ""))
        let alive = kill(started, 0)
        let code = errno
        XCTAssertEqual(alive, -1, "the process the program started is gone")
        XCTAssertEqual(code, ESRCH)
    }

    /// A program that ignores SIGTERM ends on the second request, with
    /// SIGKILL, and no wait is guessed between the two.
    func test_a_second_request_kills_a_program_that_ignores_the_first() async throws {
        let found = try installedNode()
        let stop = InstalledProgram.Stop()
        let first = FirstLine()
        let run = Task {
            try await node.run(
                ["process.on('SIGTERM', () => {}); console.log('ready'); setInterval(() => {}, 1000)"], executable: found, stop: stop
            ) { stream, text in
                if stream == .stdout { first.add(text) }
            }
        }
        let ready = await first.next()
        XCTAssertEqual(ready, "ready")
        stop.request()
        stop.request()
        let outcome = try await run.value
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: SIGKILL, signalled: true, stdout: "ready\n", stderr: ""))
    }

    /// The program stops itself after it was admitted, ignoring SIGTERM:
    /// macOS answers the run's wait for its exit with its stop
    /// (CLD_STOPPED), and a run that took that for the exit sat in waitpid,
    /// where no request to stop reached it. Seen stopped, two requests end it.
    func test_a_program_that_stops_itself_is_still_stopped_on_request() async throws {
        let found = try installedNode()
        let stop = InstalledProgram.Stop()
        let first = FirstLine()
        let run = Task {
            try await node.run(
                ["process.on('SIGTERM', () => {}); process.stdout.write(process.pid + '\\n', () => process.kill(process.pid, 'SIGSTOP')); setInterval(() => {}, 1000)"],
                executable: found, stop: stop
            ) { stream, text in
                if stream == .stdout { first.add(text) }
            }
        }
        let line = await first.next()
        let pid = try XCTUnwrap(pid_t(line), "the program's pid: \(line)")
        while !isStopped(pid) { await Task.yield() }
        stop.request()
        stop.request()
        let outcome = try await run.value
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: SIGKILL, signalled: true, stdout: "\(pid)\n", stderr: ""))
    }

    func test_a_stop_requested_before_the_run_refuses_it() async throws {
        let found = try installedNode()
        let stop = InstalledProgram.Stop()
        stop.request()
        do {
            let outcome = try await node.run(["process.stdout.write('ran')"], executable: found, stop: stop)
            XCTFail("the run is refused, not \(outcome)")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// A stop that reaches the run after the program's whole group exited,
    /// but before its exit is reaped, keeps the run's outcome. The output
    /// callback runs on the run's queue, so while it holds that queue it
    /// requests a stop (queued behind it, ahead of the exit), ends the
    /// program with SIGTERM itself and waits, without reaping, until it has
    /// exited. The stop then signals a group whose only member is a zombie,
    /// which killpg on macOS skips, answering ESRCH, or EPERM in POSIX mode
    /// (XNU bsd/kern/kern_sig.c, killpg1), and the run ends with the
    /// program's own SIGTERM.
    func test_a_stop_after_the_group_exited_keeps_the_runs_outcome() async throws {
        let found = try installedNode()
        let stop = InstalledProgram.Stop()
        let first = FirstLine()
        let outcome = try await node.run(
            ["console.log(process.pid); setInterval(() => {}, 1000)"], executable: found, stop: stop
        ) { stream, text in
            guard stream == .stdout, let line = first.add(text), let pid = pid_t(line) else { return }
            stop.request()
            XCTAssertEqual(kill(pid, SIGTERM), 0, String(cString: strerror(errno)))
            var info = siginfo_t()
            var waited: Int32
            repeat { waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) } while waited == -1 && errno == EINTR
            XCTAssertEqual(waited, 0, String(cString: strerror(errno)))
        }
        let pid = await first.next()
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: SIGTERM, signalled: true, stdout: "\(pid)\n", stderr: ""))
    }

    /// The program leaves `tail` running with both its streams: the run ends
    /// when the program exits, with what it wrote, and says both streams were
    /// still held, where it used to stand until `tail` ended.
    func test_a_process_the_program_left_holding_its_output_does_not_hold_the_run() async throws {
        let outcome = try await node.run(
            ["const tail = require('child_process').spawn('/usr/bin/tail', ['-f', '/dev/null'], { stdio: ['ignore', 'inherit', 'inherit'] }); tail.unref(); console.log(tail.pid)"],
            executable: try installedNode())
        let left = try XCTUnwrap(pid_t(outcome.stdout.trimmingCharacters(in: .newlines)), outcome.stdout)
        defer { kill(left, SIGKILL) }
        XCTAssertEqual(
            outcome,
            InstalledProgram.Outcome(status: 0, signalled: false, stdout: "\(left)\n", stderr: "", heldOpen: [.stdout, .stderr]))
    }
}
#endif
