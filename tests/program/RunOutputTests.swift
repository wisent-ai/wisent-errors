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
// Rule 4: the case runs the built wisent-errors-swift (CommandCase.swift),
// which finds, admits and runs a real program: node, the Node.js-signed
// runtime product command lines run on, installed where its installer
// places it (ProgramCase.swift). The script `-e` hands node is the program's
// behaviour the step needs, run by the real runtime; nothing stands in for
// node, for the command or for the system.
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
// Rule 9: the command cannot be built here, so no sentence was probed: each
// expected refusal is the cause's template in catalogue/failures/swift-cli.json
// rendered whole with the values the step gives; what the operating system
// answers a read of a directory is asked of it the same way in this process.

#if os(macOS)
import Foundation
import XCTest

final class RunOutputTests: ProgramCase {
    private let options = "--identifier, --set, --stdin, --team, --withhold"

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
        XCTAssertEqual(try run(self.node("process.stdout.write('ran')", ["--set", "WISENT_PROGRAM_TEST"])), usage(
            "value-malformed",
            "reading --set of `wisent-errors-swift program run`: \"WISENT_PROGRAM_TEST\" is not NAME=VALUE; observed: it holds no '='",
            fix: "give --set NAME=VALUE, as in `--set STADO_CONFIG=/srv/example-host/empty.json`"))

        // Both streams whole, and the program's status as the command's.
        XCTAssertEqual(
            try run(self.node("process.stdout.write('out'); process.stderr.write('err'); process.exitCode = 3")),
            Ran(status: 3, stdout: "out", stderr: "err"))

        // `ł` (C5 82) written in two halves, 200 ms apart, reaches the run in two reads and is said whole.
        XCTAssertEqual(
            try run(self.node("process.stdout.write(Buffer.concat([Buffer.from('Rachuba '), Buffer.from([0xc5])])); setTimeout(() => process.stdout.write(Buffer.from([0x82, 0xc3, 0xb3, 0x64])), 200)")),
            Ran(status: 0, stdout: "Rachuba łód", stderr: ""))

        // --stdin: the command's standard input, then its end, is the program's.
        let echo = "let read = ''; process.stdin.setEncoding('utf8'); process.stdin.on('data', (chunk) => { read += chunk }); process.stdin.on('end', () => { process.stdout.write(read); process.stderr.write('done') })"
        XCTAssertEqual(
            try run(self.node(echo, ["--stdin"]), input: .bytes(Data("one\ntwo\n".utf8))),
            Ran(status: 0, stdout: "one\ntwo\n", stderr: "done"))
        // Without --stdin the program's input is empty: the command's own is not handed on.
        XCTAssertEqual(try run(self.node(echo), input: .bytes(Data("one\ntwo\n".utf8))), Ran(status: 0, stdout: "", stderr: "done"))

        // A program that closes its input before all of it is written: more
        // than the largest buffer a macOS pipe holds (BIG_PIPE_SIZE,
        // https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/pipe.h).
        XCTAssertEqual(
            try run(
                self.node("require('fs').closeSync(0); process.stdout.write('closed')", ["--stdin"]),
                input: .bytes(Data(repeating: UInt8(ascii: "x"), count: 2 * 64 * 1024))),
            Ran(status: 0, stdout: "closed", stderr: "note: node closed its standard input or exited before all of it was written, so its answer may cover only part of the input\n"))

        // A standard input that cannot be read to its end: a directory, which read(2) refuses with EISDIR.
        let unread = answer { _ = try FileHandle(forReadingFrom: home).readToEnd() }
        XCTAssertEqual(try run(self.node(echo, ["--stdin"]), input: .file(home)), programRun(
            "stdin-unread", status: 69,
            "reading the standard input to hand to node: the standard input could not be read to its end; observed: the operating system answered \(unread)",
            fix: "give --stdin an input that can be read to its end, such as a file (< file) or a pipe whose writer closes it"))

        // The environment: the command's own, with --set over it, less --withhold and the prefixes withheld by default.
        XCTAssertEqual(
            try run(self.node("process.stdout.write(process.env.WISENT_PROGRAM_TEST + '|' + process.env.HOME)", ["--set", "WISENT_PROGRAM_TEST=set"])),
            Ran(status: 0, stdout: "set|\(home.path)", stderr: ""))
        // fallback: the program's own `??` says "withheld" when node finds no HOME, the evidence of the step.
        XCTAssertEqual(
            try run(self.node("process.stdout.write(process.env.HOME ?? 'withheld')", ["--withhold", "HOME"])),
            Ran(status: 0, stdout: "withheld", stderr: ""))
        var crowded = environment
        for name in ["NODE_WISENT_PROGRAM_TEST", "XDG_WISENT_PROGRAM_TEST", "DYLD_WISENT_PROGRAM_TEST", "WISENT_PROGRAM_TEST_KEPT"] {
            crowded[name] = "the command's"
        }
        XCTAssertEqual(
            try run(
                self.node("process.stdout.write(JSON.stringify(Object.keys(process.env).filter((name) => name.includes('WISENT_PROGRAM_TEST') || name.startsWith('XDG_')).sort()))"),
                environment: crowded),
            Ran(status: 0, stdout: #"["WISENT_PROGRAM_TEST_KEPT"]"#, stderr: ""))

        // A name no environment entry can hold: the program is found and admitted, and cannot start.
        XCTAssertEqual(try run(self.node("process.stdout.write('ran')", ["--set", "=x"])), programRun(
            "program-unstartable", status: 1,
            "starting \(node.path): the program was found and admitted, but the system could not start it; observed: the environment variable name \"\" is empty or holds =, which ends a name in an environment entry",
            fix: "correct what the reason names: a --set name must be non-empty and hold no '=', and a program the kernel cannot execute is reinstalled with its release installer"))
        XCTAssertEqual(try tree(home), [".local", ".local/bin", ".local/bin/node"], "the runs left the home as node was installed")
    }
}
#endif
