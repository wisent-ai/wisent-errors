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
// Rule 4: the case runs the built wisent-errors-swift (CommandCase.swift)
// on real files under the case's directory; the library's `explained` is
// what the command says, never called here.
// Rule 5: each step asserts the exit status, the whole of stdout and of the
// refusal's three stderr lines, and reads the file back after the command:
// the envelope it read is left byte for byte as it was.
// Rule 7: one test, one command: `envelope read` with its success and every
// refusal an input can provoke, step by step. A read the operating system
// stops part way (input-read-failed) needs a device that fails under the
// file; tests/untested-causes.json lists it.
// Rule 9: the command cannot be built here, so no sentence was probed: each
// expected refusal is the cause's template in catalogue/failures/swift-cli.json
// rendered whole with the values the step gives, and what the operating
// system or Foundation's reader answers is asked of them the same way in
// this process.

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

        // The wrong number of operands.
        XCTAssertEqual(try run(["envelope", "read"]), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift envelope read`: it takes <file>, and 0 were given; observed: operands: none",
            fix: "run it as `wisent-errors-swift envelope read <file>`"))
        XCTAssertEqual(try run(["envelope", "read", "a.json", "b.json"]), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift envelope read`: it takes <file>, and 2 were given; observed: operands: [\"a.json\",\"b.json\"]",
            fix: "run it as `wisent-errors-swift envelope read <file>`"))

        // No file at the path, named relative to the directory it runs in.
        let absent = root.appendingPathComponent("absent.json")
        XCTAssertEqual(try run(["envelope", "read", "absent.json"]), input(
            "input-absent", status: 1,
            "reading the envelope from \(absent.path): no file is at that path; observed: its directory \(cwd) holds cache, config, data, home, state, tmp; the operating system answered \(answer { _ = try Data(contentsOf: absent) })",
            fix: "name a file that exists, or write it first; a relative path is read from \(cwd)"))

        // A directory where the file belongs.
        XCTAssertEqual(try run(["envelope", "read", home.path]), input(
            "input-is-directory", status: 1,
            "reading the envelope from \(home.path): the path names a directory, not a file; observed: \(home.path) is a directory of mode \(try mode(home)); the operating system answered \(answer { _ = try Data(contentsOf: home) })",
            fix: "name the JSON file inside \(home.path), not the directory"))

        // A file this user may not read: no permission for anyone.
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        let locked = root.appendingPathComponent("locked.json")
        let lockedBytes = Data(example.utf8)
        try lockedBytes.write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let refusedRead = answer { _ = try Data(contentsOf: locked) }
        let ranLocked = try run(["envelope", "read", locked.path])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path)
        XCTAssertEqual(ranLocked, input(
            "input-not-permitted", status: 1,
            "reading the envelope from \(locked.path): the operating system refused this process the read; observed: \(locked.path) is a file of \(lockedBytes.count) bytes, mode 0; the operating system answered \(refusedRead)",
            fix: "let the user running wisent-errors-swift read it (chmod u+r \(locked.path)), or run it as the file's owner"))
        XCTAssertEqual(try Data(contentsOf: locked), lockedBytes, "the refused file is left as it was")

        // Text that is not JSON: where Foundation's reader stopped, in its words.
        let broken = root.appendingPathComponent("broken.json")
        let brokenBytes = Data(#"{"failure_point": tru}"#.utf8)
        try brokenBytes.write(to: broken)
        var reader = "no failure"
        do {
            _ = try JSONSerialization.jsonObject(with: brokenBytes, options: [.fragmentsAllowed])
        } catch {
            // fallback: Foundation's reader gives its reason under NSDebugDescriptionErrorKey; without one the command says the error whole, as here.
            reader = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? explained(error)
        }
        XCTAssertEqual(try run(["envelope", "read", broken.path]), input(
            "input-not-json", status: 1,
            "decoding the envelope from \(broken.path): the file is not JSON; observed: \(brokenBytes.count) bytes; the reader answered \(reader)",
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
