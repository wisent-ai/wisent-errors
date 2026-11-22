// `wisent-errors-swift program run <name> [-- <arguments>]`, the package's
// command line running an admitted program the way a macOS app runs it
// (WisentProgram), run as a process: what the run hands on. Both streams
// whole on the streams they came on, with the program's exit status; a
// character two reads split said whole; --stdin, the command's own standard
// input read to its end, as the program's, and a program that closes it
// early told apart in a note; --set over the environment, --withhold and the
// prefixes withheld by default (the program's own, XDG_, DYLD_); and every
// refusal of its command line, its input and its start.
//
//   swift test --filter RunOutputTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195). That child finds, admits
// and runs a real program: node, the Node.js-signed runtime product command
// lines run on, a copy of the file WISENT_PROGRAM_TEST_NODE names installed
// where its installer places it (ProgramCase.swift). WisentProgram runs
// whatever program a product names; what `program run` promises is how it
// hands that program's streams, status, input and environment on, so the
// script `-e` gives node is the real program's behaviour each step needs (a
// split character, an early close of its input), run by the real runtime,
// not a fixture: nothing stands in for node, for the command or for the
// system.
// Rule 5: each run's evidence is node's own record, a file the script writes
// under the case's directory with what it read and wrote, read back from
// disk after the run and compared with what the command handed on (exit
// status, stdout, stderr); a refused run is shown never to have started node
// by the record being absent, and the home is read back at the end as node
// was installed.
// Rule 6: `program run`'s refusals of its output story, each asserted whole:
// an operand left out, an option it does not have, an option without its
// value, a --set with no '=', a variable name no environment holds (the
// program cannot start), and a standard input that cannot be read. Its
// admission refusals are AdmissionTests'; a run whose end cannot be followed
// is provoked only by a defect of WisentProgram, the command setting SIGCHLD
// back to its default first, and tests/untested-causes.json says so.
// Rule 7: one test, one command: `program run` and what it hands on, step by
// step. Its admission (AdmissionTests) and its stop (RunStopTests) are the
// same command's other stories, each in its own file.
// Rule 9: every sentence, record, stream and exit status below was copied
// from live runs of wisent-errors-swift built from this tree (`swift build
// --product wisent-errors-swift`, 2026-11-21): each step run by hand under
// `env -i` given only HOME, CFFIXED_USER_HOME, TMPDIR and XDG_* inside
// target/probe-swift/runoutput, with a copy of ~/.local/bin/node installed in
// that home and the same scripts, inputs and records; the operating system's
// words for the directory given as input are the ones that run printed.

#if os(macOS)
import Foundation
import XCTest

final class RunOutputTests: ProgramCase {
    private let options = "--identifier, --set, --stdin, --team, --withhold"

    /// The file node writes what it received and did into, read back from disk after each run.
    private var record: URL { root.appendingPathComponent("record.json") }

    /// `body` run by node with `record(facts)` at hand, which writes `facts` to the record file as JSON.
    private func recording(_ body: String) -> String {
        "const record = (facts) => require('fs').writeFileSync('\(record.path)', JSON.stringify(facts)); \(body)"
    }

    /// What node wrote to the record, read back from disk; the file is removed so the next step starts without one.
    private func recorded() throws -> NSDictionary {
        let facts = try object(record) as NSDictionary
        try FileManager.default.removeItem(at: record)
        return facts
    }

    private func unrecorded(_ why: String) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), why)
    }

    func test_program_run_hands_on_the_programs_streams_status_and_input() throws {
        let node = try installNode()

        // Its command line: an operand left out, an option it lacks, one without its value, a --set with no '='.
        XCTAssertEqual(try run(["program", "run"]), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift program run`: it takes <name>, and 0 were given; observed: operands: none",
            fix: "run it as `wisent-errors-swift program run <name> [-- <arguments>]`"))
        XCTAssertEqual(try run(["program", "run", "node", "--verbose"]), usage(
            "option-unknown",
            "reading the options of `wisent-errors-swift program run`: \"--verbose\" is not one of its options; observed: its options: \(options)",
            fix: "drop \"--verbose\", or give one of \(options)"))
        XCTAssertEqual(try run(["program", "run", "node", "--set"]), usage(
            "option-value-absent",
            "reading the options of `wisent-errors-swift program run`: --set takes a value, and it is the last argument; observed: arguments: [\"node\",\"--set\"]",
            fix: "give --set its value, as in `--set STADO_CONFIG=/srv/example-host/empty.json`"))
        XCTAssertEqual(try run(self.node(recording("record({ran: true})"), ["--set", "WISENT_PROGRAM_TEST"])), usage(
            "value-malformed",
            "reading --set of `wisent-errors-swift program run`: \"WISENT_PROGRAM_TEST\" is not NAME=VALUE; observed: it holds no '='",
            fix: "give --set NAME=VALUE, as in `--set STADO_CONFIG=/srv/example-host/empty.json`"))
        unrecorded("a refused command line never starts node")

        // Both streams whole, and the program's status as the command's: what node says it wrote and its exit code, read from its record.
        let streams = try run(self.node(recording(
            "process.stdout.write('out'); process.stderr.write('err'); process.exitCode = 3; record({stdout: 'out', stderr: 'err', exitCode: process.exitCode})")))
        XCTAssertEqual(try recorded(), ["stdout": "out", "stderr": "err", "exitCode": 3] as NSDictionary)
        XCTAssertEqual(streams, Ran(status: 3, stdout: "out", stderr: "err"))

        // `ł` (C5 82) written in two halves, 200 ms apart, reaches the run in two reads and is said whole.
        let split = try run(self.node(recording(
            "const halves = [Buffer.concat([Buffer.from('Rachuba '), Buffer.from([0xc5])]), Buffer.from([0x82, 0xc3, 0xb3, 0x64])]; process.stdout.write(halves[0]); setTimeout(() => { process.stdout.write(halves[1]); record({written: Buffer.concat(halves).toString('utf8'), writes: halves.length}) }, 200)")))
        XCTAssertEqual(try recorded(), ["written": "Rachuba łód", "writes": 2] as NSDictionary)
        XCTAssertEqual(split, Ran(status: 0, stdout: "Rachuba łód", stderr: ""))

        // --stdin: the command's standard input, then its end, is the program's: what node read, from its record.
        let echo = recording("let read = ''; process.stdin.setEncoding('utf8'); process.stdin.on('data', (chunk) => { read += chunk }); process.stdin.on('end', () => { record({read}); process.stdout.write(read); process.stderr.write('done') })")
        let handed = try run(self.node(echo, ["--stdin"]), input: .bytes(Data("one\ntwo\n".utf8)))
        XCTAssertEqual(try recorded(), ["read": "one\ntwo\n"] as NSDictionary)
        XCTAssertEqual(handed, Ran(status: 0, stdout: "one\ntwo\n", stderr: "done"))
        // Without --stdin the program's input is empty: the command's own is not handed on.
        let kept = try run(self.node(echo), input: .bytes(Data("one\ntwo\n".utf8)))
        XCTAssertEqual(try recorded(), ["read": ""] as NSDictionary)
        XCTAssertEqual(kept, Ran(status: 0, stdout: "", stderr: "done"))

        // A program that closes its input before all of it is written: more
        // than the largest buffer a macOS pipe holds (BIG_PIPE_SIZE,
        // https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/pipe.h).
        let closing = try run(
            self.node(recording("require('fs').closeSync(0); record({closed: true}); process.stdout.write('closed')"), ["--stdin"]),
            input: .bytes(Data(repeating: UInt8(ascii: "x"), count: 2 * 64 * 1024)))
        XCTAssertEqual(try recorded(), ["closed": true] as NSDictionary)
        XCTAssertEqual(closing, Ran(status: 0, stdout: "closed", stderr: "note: node closed its standard input or exited before all of it was written, so its answer may cover only part of the input\n"))

        // A standard input that cannot be read to its end: a directory, which read(2) refuses with EISDIR.
        XCTAssertEqual(try run(self.node(echo, ["--stdin"]), input: .file(home)), programRun(
            "stdin-unread", status: 69,
            "reading the standard input to hand to node: the standard input could not be read to its end; observed: the operating system answered The file couldn’t be opened. (NSCocoaErrorDomain 256): The operation couldn’t be completed. Is a directory (NSPOSIXErrorDomain 21)",
            fix: "give --stdin an input that can be read to its end, such as a file (< file) or a pipe whose writer closes it"))
        unrecorded("node is never started on an input the command could not read")

        // The environment: the command's own, with --set over it, less --withhold and the prefixes withheld by default, as node read it.
        let set = try run(self.node(
            recording("record({set: process.env.WISENT_PROGRAM_TEST, home: process.env.HOME}); process.stdout.write(process.env.WISENT_PROGRAM_TEST + '|' + process.env.HOME)"),
            ["--set", "WISENT_PROGRAM_TEST=set"]))
        XCTAssertEqual(try recorded(), ["set": "set", "home": home.path] as NSDictionary)
        XCTAssertEqual(set, Ran(status: 0, stdout: "set|\(home.path)", stderr: ""))
        // fallback: the program's own `??` says null (JSON) or "withheld" when node finds no HOME, the evidence of the step.
        let withheld = try run(self.node(recording("record({home: process.env.HOME ?? null}); process.stdout.write(process.env.HOME ?? 'withheld')"), ["--withhold", "HOME"]))
        XCTAssertEqual(try recorded(), ["home": NSNull()] as NSDictionary)
        XCTAssertEqual(withheld, Ran(status: 0, stdout: "withheld", stderr: ""))
        var crowded = environment
        for name in ["NODE_WISENT_PROGRAM_TEST", "XDG_WISENT_PROGRAM_TEST", "DYLD_WISENT_PROGRAM_TEST", "WISENT_PROGRAM_TEST_KEPT"] {
            crowded[name] = "the command's"
        }
        let prefixed = try run(
            self.node(recording(
                "const names = Object.keys(process.env).filter((name) => name.includes('WISENT_PROGRAM_TEST') || name.startsWith('XDG_')).sort(); record({names}); process.stdout.write(JSON.stringify(names))")),
            environment: crowded)
        XCTAssertEqual(try recorded(), ["names": ["WISENT_PROGRAM_TEST_KEPT"]] as NSDictionary)
        XCTAssertEqual(prefixed, Ran(status: 0, stdout: #"["WISENT_PROGRAM_TEST_KEPT"]"#, stderr: ""))

        // A name no environment entry can hold: the program is found and admitted, and cannot start.
        XCTAssertEqual(try run(self.node(recording("record({ran: true})"), ["--set", "=x"])), programRun(
            "program-unstartable", status: 1,
            "starting \(node.path): the program was found and admitted, but the system could not start it; observed: the environment variable name \"\" is empty or holds =, which ends a name in an environment entry",
            fix: "correct what the reason names: a --set name must be non-empty and hold no '=', and a program the kernel cannot execute is reinstalled with its release installer"))
        unrecorded("a program the system could not start wrote nothing")
        XCTAssertEqual(try tree(home), [".local", ".local/bin", ".local/bin/node"], "the runs left the home as node was installed")
    }
}
#endif
