// `wisent-errors-swift program run <name> [-- <arguments>]`, the package's
// command line running an admitted program the way a macOS app runs it
// (WisentProgram), run as a process: how the run ends when the command is
// asked to stop, as a terminal's Ctrl-C or a service manager's SIGTERM asks
// it. The first SIGTERM or SIGINT stops the program's whole process group
// with SIGTERM -- a process the program started goes with it -- and a second
// kills a program that ignores the first, or that stopped itself, with
// SIGKILL; the command exits with the program's status, or 128 + the signal
// that ended it. A program that exits leaving a process holding its output
// does not hold the run, and the command says so.
//
//   swift test --filter RunStopTests
//
// Rule 4: the case runs the built wisent-errors-swift (CommandCase.swift),
// which finds, admits and runs a real program: node, the Node.js-signed
// runtime product command lines run on, installed where its installer
// places it (ProgramCase.swift). The script `-e` hands node is what the
// program does -- wait, ignore SIGTERM, start /usr/bin/tail -- run by the
// real runtime; the signals are real, sent to the command's real process.
// Rule 5: each step asserts the command's exit status and both streams
// whole, and reads the kernel's process table: the process the program
// started is gone after the stop (kill(pid, 0) answers ESRCH), and a program
// that stopped itself is seen stopped (proc_pidinfo) before it is asked.
// Rule 6: stopping a run has no refusal an input can provoke: its one
// failure, a signal to the program's group the system refuses
// (program-unfollowed), comes only from a defect of WisentProgram, and
// tests/untested-causes.json says so; the command's refusals are
// RunOutputTests' and AdmissionTests'. A stop that arrives before the
// program started (exit 128 + the signal, nothing run) cannot be timed from
// outside the process, so it is not a step here.
// Rule 7: one test, one command: `program run` and how it ends when asked,
// step by step: each request is one signal to the command, the evidence it
// arrived read before the next. Its admission (AdmissionTests) and what it
// hands on (RunOutputTests) are the same command's other stories.

#if os(macOS)
import Darwin
import Foundation
import XCTest

final class RunStopTests: ProgramCase {
    func test_program_run_stops_the_programs_whole_group_when_asked_and_kills_it_when_asked_again() throws {
        try installNode()

        // SIGTERM to the command: the program ends on the SIGTERM it is sent, 128 + 15.
        let waiting = try start(node("console.log('ready'); setTimeout(() => {}, 30000)"))
        XCTAssertEqual(waiting.line(), "ready")
        waiting.signal(SIGTERM)
        XCTAssertEqual(waiting.finish(), Ran(status: 128 + SIGTERM, stdout: "ready\n", stderr: ""))

        // SIGINT, a terminal's Ctrl-C, is the same request: the program is sent SIGTERM.
        let interrupted = try start(node("console.log('ready'); setTimeout(() => {}, 30000)"))
        XCTAssertEqual(interrupted.line(), "ready")
        interrupted.signal(SIGINT)
        XCTAssertEqual(interrupted.finish(), Ran(status: 128 + SIGTERM, stdout: "ready\n", stderr: ""))

        // The whole group: the program starts `tail`, which never ends by
        // itself, ignores SIGTERM and exits only once `tail` has; the run
        // ending at all is the evidence the stop reached `tail` too.
        let grouped = try start(node(
            "const tail = require('child_process').spawn('/usr/bin/tail', ['-f', '/dev/null'], { stdio: ['ignore', 'inherit', 'inherit'] }); process.on('SIGTERM', () => {}); tail.on('exit', () => process.exit(0)); console.log(tail.pid)"))
        let line = try XCTUnwrap(grouped.line(), "the program says the pid of the process it started")
        let started = try XCTUnwrap(pid_t(line), line)
        grouped.signal(SIGTERM)
        XCTAssertEqual(grouped.finish(), Ran(status: 0, stdout: "\(started)\n", stderr: ""))
        XCTAssertTrue(isGone(started), "the process the program started is gone")

        // A program that ignores the first request ends on the second, with SIGKILL, 128 + 9.
        let stubborn = try start(node("process.on('SIGTERM', () => console.log('ignored SIGTERM')); console.log('ready'); setInterval(() => {}, 1000)"))
        XCTAssertEqual(stubborn.line(), "ready")
        stubborn.signal(SIGTERM)
        XCTAssertEqual(stubborn.line(), "ignored SIGTERM", "the first request reached the program")
        stubborn.signal(SIGINT)
        XCTAssertEqual(stubborn.finish(), Ran(status: 128 + SIGKILL, stdout: "ready\nignored SIGTERM\n", stderr: ""))

        // A program that stopped itself, ignoring SIGTERM: seen stopped in the
        // process table, two requests still end it.
        let stopped = try start(node(
            "process.on('SIGTERM', () => {}); process.stdout.write(process.pid + '\\n', () => process.kill(process.pid, 'SIGSTOP')); setInterval(() => {}, 1000)"))
        let pidLine = try XCTUnwrap(stopped.line(), "the program says its pid")
        let pid = try XCTUnwrap(pid_t(pidLine), pidLine)
        while !isStopped(pid) {
            guard !isGone(pid) else { return XCTFail("the program \(pid) ended before it was seen stopped") }
        }
        stopped.signal(SIGTERM)
        stopped.signal(SIGINT)
        XCTAssertEqual(stopped.finish(), Ran(status: 128 + SIGKILL, stdout: "\(pid)\n", stderr: ""))
        XCTAssertTrue(isGone(pid), "the stopped program is gone")

        // A program that exits leaving `tail` holding both its streams: the
        // run ends on the program's exit, and says both were still held.
        let left = try run(node(
            "const tail = require('child_process').spawn('/usr/bin/tail', ['-f', '/dev/null'], { stdio: ['ignore', 'inherit', 'inherit'] }); tail.unref(); console.log(tail.pid)"))
        let holder = try XCTUnwrap(pid_t(left.stdout.trimmingCharacters(in: .newlines)), left.stdout)
        defer { kill(holder, SIGKILL) }
        XCTAssertEqual(left, Ran(
            status: 0, stdout: "\(holder)\n",
            stderr: "note: a process node left running still held its stdout and stderr when node exited; what it writes there later is not shown\n"))
        XCTAssertFalse(isGone(holder), "the process the program left is still running, holding nothing of the run")
    }
}
#endif
