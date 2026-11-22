// `wisent-errors-swift envelope read <file>`, the package's command line
// reading one failure envelope a service answered or a log kept and printing
// it for a person, run as a process: the envelope's rendered line and its
// chain of causes, and every way the file is not one, each said through
// `Error.explained` -- the operating system's own words with their domain
// and code and every underlying error (a file absent, a directory, a file
// this user may not read), where text stopped being JSON, and the coding
// path a decoder stopped at.
//
//   swift test --filter ExplainedTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195) -- and reads its exit
// status and both streams whole from its pipes, on real files, a real
// directory and a file of mode 0 under the case's directory. That is the
// whole flow of `envelope read`: a person handing it a file a service
// answered or a log kept. The library's `explained` is what the command
// says, never called here; this file imports no module of the package.
// Rule 5: each step asserts the exit status, the whole of stdout and of the
// refusal's three stderr lines, and reads the disk back after the command:
// each file it was handed left byte for byte as it was, the absent file
// still absent, the directory still empty, and at the end the case's
// directory holding only what the case wrote.
// Rule 7: one test, one command: `envelope read` with its success and every
// refusal an input can provoke, step by step. A read the operating system
// stops part way (input-read-failed) needs a device that fails under the
// file; tests/untested-causes.json lists it.
// Rule 9: every sentence, line and exit status below was copied from live
// runs of wisent-errors-swift built from this tree (`swift build --product
// wisent-errors-swift`, 2026-11-21): each file written byte for byte as here
// (the locked one chmod 000) under target/probe-swift/explained and read by
// hand from that directory under `env -i` given only HOME,
// CFFIXED_USER_HOME, TMPDIR and XDG_* inside it. The operating system's and
// Foundation's words are the ones that run printed, in English, as the
// cleared environment gives the child no language of the operator's.

#if os(macOS)
import Foundation
import XCTest

final class ExplainedTests: CommandCase {
    private let shape = "a failure envelope: an object with failure_point, error_code and service, and impact, detail, remedy, cause and context where it has them"
    private let example = #"{"failure_point":"stado.fleet.enroll","error_code":"refused","service":"stado"}"#

    private func input(_ cause: String, status: Int32, _ sentence: String, fix: String) -> Ran {
        Ran(status: status, stdout: "", stderr: refusal("wisent_errors.swift_cli.input", cause, page: "swift-cli", sentence, fix: fix))
    }

    /// The mode of `url` as the command says it: octal, no leading zero.
    private func mode(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return String(try XCTUnwrap(attributes[.posixPermissions] as? Int), radix: 8)
    }

    func test_envelope_read_says_the_envelope_or_why_the_file_is_not_one() throws {
        let cwd = root.path
        let made = try tree(root)

        // The wrong number of operands.
        XCTAssertEqual(try run(["envelope", "read"]), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift envelope read`: it takes <file>, and 0 were given; observed: operands: none",
            fix: "run it as `wisent-errors-swift envelope read <file>`"))
        XCTAssertEqual(try run(["envelope", "read", "a.json", "b.json"]), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift envelope read`: it takes <file>, and 2 were given; observed: operands: [\"a.json\",\"b.json\"]",
            fix: "run it as `wisent-errors-swift envelope read <file>`"))
        XCTAssertEqual(try tree(root), made, "a refused command line read and wrote nothing")

        // No file at the path, named relative to the directory it runs in.
        let absent = root.appendingPathComponent("absent.json")
        XCTAssertEqual(try run(["envelope", "read", "absent.json"]), input(
            "input-absent", status: 1,
            "reading the envelope from \(absent.path): no file is at that path; observed: its directory \(cwd) holds cache, config, data, home, state, tmp; the operating system answered The file “absent.json” couldn’t be opened because there is no such file. (NSCocoaErrorDomain 260): The operation couldn’t be completed. No such file or directory (NSPOSIXErrorDomain 2)",
            fix: "name a file that exists, or write it first; a relative path is read from \(cwd)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path), "nothing was made at the absent path")

        // A directory where the file belongs.
        XCTAssertEqual(try run(["envelope", "read", home.path]), input(
            "input-is-directory", status: 1,
            "reading the envelope from \(home.path): the path names a directory, not a file; observed: \(home.path) is a directory of mode \(try mode(home)); the operating system answered The file “home” couldn’t be opened. (NSCocoaErrorDomain 256): The operation couldn’t be completed. Is a directory (NSPOSIXErrorDomain 21)",
            fix: "name the JSON file inside \(home.path), not the directory"))
        XCTAssertEqual(try tree(home), [], "the directory is left as it was")

        // A file this user may not read: no permission for anyone.
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        let locked = root.appendingPathComponent("locked.json")
        let lockedBytes = Data(example.utf8)
        try lockedBytes.write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let ranLocked = try run(["envelope", "read", locked.path])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path)
        XCTAssertEqual(ranLocked, input(
            "input-not-permitted", status: 1,
            "reading the envelope from \(locked.path): the operating system refused this process the read; observed: \(locked.path) is a file of \(lockedBytes.count) bytes, mode 0; the operating system answered The file “locked.json” couldn’t be opened because you don’t have permission to view it. (NSCocoaErrorDomain 257): The operation couldn’t be completed. Permission denied (NSPOSIXErrorDomain 13)",
            fix: "let the user running wisent-errors-swift read it (chmod u+r \(locked.path)), or run it as the file's owner"))
        XCTAssertEqual(try Data(contentsOf: locked), lockedBytes, "the refused file is left as it was")

        // Text that is not JSON: where Foundation's reader stopped, in its words.
        let broken = root.appendingPathComponent("broken.json")
        let brokenBytes = Data(#"{"failure_point": tru}"#.utf8)
        try brokenBytes.write(to: broken)
        XCTAssertEqual(try run(["envelope", "read", broken.path]), input(
            "input-not-json", status: 1,
            "decoding the envelope from \(broken.path): the file is not JSON; observed: \(brokenBytes.count) bytes; the reader answered Something looked like a 'true' but wasn't around line 1, column 18.",
            fix: "write \(broken.path) as JSON; `jq . \(broken.path)` points at the place it stops parsing"))
        XCTAssertEqual(try Data(contentsOf: broken), brokenBytes)

        // JSON that is not an envelope: the key it lacks and where.
        let shapeless = root.appendingPathComponent("shapeless.json")
        let shapelessBytes = Data(#"{"error_code":"refused","service":"stado"}"#.utf8)
        try shapelessBytes.write(to: shapeless)
        XCTAssertEqual(try run(["envelope", "read", shapeless.path]), input(
            "input-wrong-shape", status: 1,
            "decoding the envelope from \(shapeless.path): the file is JSON, but not \(shape); observed: \(shapelessBytes.count) bytes; the decoder answered Envelope could not be decoded: key \"failure_point\" is missing at the top level",
            fix: "write \(shapeless.path) as \(shape), as in \(example)"))
        XCTAssertEqual(try Data(contentsOf: shapeless), shapelessBytes)

        // An envelope no runtime would build: the builder's own refusal.
        let unbuilt = root.appendingPathComponent("unbuilt.json")
        let unbuiltBytes = Data(#"{"failure_point":"stado..enroll","error_code":"refused","service":"stado"}"#.utf8)
        try unbuiltBytes.write(to: unbuilt)
        XCTAssertEqual(try run(["envelope", "read", unbuilt.path]), Ran(status: 2, stdout: "", stderr: refusal(
            "wisent_errors.envelope.build", "failure-point-segment-empty", page: "envelope",
            "building the failure envelope of service stado: segment 2 of the failure point \"stado..enroll\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"stado\",\"\",\"enroll\"]",
            fix: "drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with Failure.orFallback")))
        XCTAssertEqual(try Data(contentsOf: unbuilt), unbuiltBytes, "the refused envelope is left as it was")

        // An envelope with its cause: the line a person reads, then the chain.
        let envelope = root.appendingPathComponent("failure.json")
        let envelopeBytes = Data(#"{"failure_point":"stado.fleet.enroll","error_code":"refused","service":"stado","detail":"the fleet answered 403","cause":{"failure_point":"brama.dispatch","error_code":"not_found","service":"brama","detail":"no host example-host"},"context":{"host":"example-host"}}"#.utf8)
        try envelopeBytes.write(to: envelope)
        let json = #"{"failure_point":"stado.fleet.enroll","error_code":"refused","service":"stado","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":"the fleet answered 403","remedy":null,"cause":{"failure_point":"brama.dispatch","error_code":"not_found","service":"brama","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":"no host example-host","remedy":null},"context":{"host":"example-host"}}"#
        XCTAssertEqual(try run(["envelope", "read", envelope.path]), Ran(
            status: 0,
            stdout: "an explicit policy refused this command \u{2014} a rule we wrote, not the request's credentials; retrying will not help \(json)\n"
                + "stado.fleet.enroll [refused] the fleet answered 403\nbrama.dispatch [not_found] no host example-host\n",
            stderr: ""))
        XCTAssertEqual(try Data(contentsOf: envelope), envelopeBytes, "reading the envelope left it as it was")
        XCTAssertEqual(
            try tree(root),
            ["broken.json", "cache", "config", "data", "failure.json", "home", "locked.json", "shapeless.json", "state", "tmp", "unbuilt.json"],
            "the command wrote nothing beside what it read")
    }
}
#endif
