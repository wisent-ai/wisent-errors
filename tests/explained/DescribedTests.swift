// `wisent-errors-swift declaration check <file>`, the package's command line
// holding a product's `errors list --json` listing, read from a file, to the
// declaration rules, run as a process: the listing it passes, the problems
// it prints and refuses, and the described decoding every Wisent app reads
// JSON through -- where text stopped being JSON (`describedObject`), and
// the type, key and coding path a decoder stopped at (`decodeDescribed`).
//
//   swift test --filter DescribedTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195) -- and reads its exit
// status and both streams whole from its pipes. The flow `declaration check`
// exists for is a product's CI handing it the listing `errors list --json`
// printed and failing the build on what it says: the listings written under
// the case's directory are such files of an example product (rule 12), in
// both shapes a product prints -- the bare array, and the object Stado
// prints with the array under `operations` -- one per way a listing is
// refused and each shape it passes, so the refusals are the feature, not a
// stand-in for it; the second case reads the listing the fleet's real
// stado prints (WISENT_PROGRAM_TEST_STADO), and fails as blocked naming
// the variable without it. This file imports no module of the package;
// nothing of the library is called here.
// Rule 5: each step asserts the exit status, the whole of stdout (the
// problems, one a line) and of the refusal's three stderr lines, and reads
// each listing back after the command: it is left byte for byte as it was.
// Rule 9: every sentence, problem line and exit status below was copied
// from live runs of wisent-errors-swift built from this tree (`swift build
// --product wisent-errors-swift`, 2026-11-21): each listing written byte for
// byte as here under target/probe-swift/{described,listing} and checked by
// hand under `env -i` given only HOME, CFFIXED_USER_HOME, TMPDIR and XDG_*
// inside it, Foundation's words for the JSON it could not read as that run
// printed them. stado 0.23.71's own listing (`stado errors list --json` run
// the same way, 4398309 bytes, 671 operations) was refused live with 166
// problems of Stado's own declarations, the first `operation stado.store:
// cause swap-unconditioned: a declared cause is never `unknown`, …`; what
// Stado declares changes with each release, so that case compares the
// whole sentence with the count and first problem its run printed.

#if os(macOS)
import Foundation
import XCTest

final class DescribedTests: CommandCase {
    private let what = "the listing of a product's functionalities"
    private let shape = "what `errors list --json` prints: a JSON array of functionalities, or an object holding that array under operations (beside commands and undeclared), one object per functionality with operation, entries, uses, summary, docs and causes, each cause with id, code, usage, failed, cause, observed, remedy and test"
    private let example = #"[{"operation":"example.pairs.import","entries":["example pairs import"],"uses":[],"summary":"import a pairs file","docs":"https://example.com/docs/errors","causes":[]}]"#

    /// One functionality as `errors list --json` prints it, with `docs`, `uses` and its cause's `cause`, `observed` and `usage` as given.
    private func listing(docs: String, uses: String, cause: String, observed: String, usage: String = "false") -> Data {
        Data(#"[{"operation":"example.pairs.import","entries":["example pairs import"],"uses":\#(uses),"summary":"import a pairs file","docs":"\#(docs)","causes":[{"id":"pairs-unreadable","code":"config","usage":\#(usage),"failed":"reading the pairs file {path}","cause":"\#(cause)","observed":"\#(observed)","remedy":"write {path} as JSON","test":"tests/pairs/import.rs::a_damaged_file_is_refused"}]}]"#.utf8)
    }

    private func written(_ name: String, _ data: Data) throws -> URL {
        let file = root.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    func test_declaration_check_reads_a_listing_or_says_where_it_stops_being_one() throws {
        // Text that is not JSON: where Foundation's reader stopped.
        let brokenBytes = Data(#"[{"operation": "example.pairs.import",]"#.utf8)
        let broken = try written("broken.json", brokenBytes)
        XCTAssertEqual(try run(["declaration", "check", broken.path]), Ran(status: 1, stdout: "", stderr: refusal(
            "wisent_errors.swift_cli.input", "input-not-json", page: "swift-cli",
            "decoding \(what) from \(broken.path): the file is not JSON; observed: \(brokenBytes.count) bytes; the reader answered No string key for value in object around line 1, column 38.",
            fix: "write \(broken.path) as JSON; `jq . \(broken.path)` points at the place it stops parsing")))
        XCTAssertEqual(try Data(contentsOf: broken), brokenBytes)

        // JSON missing a key: the key and the functionality it is missing from.
        let keylessBytes = Data(#"[{"operation":"example.pairs.import","entries":[],"uses":[],"summary":"import a pairs file","docs":"https://example.com/docs/errors"}]"#.utf8)
        let keyless = try written("keyless.json", keylessBytes)
        XCTAssertEqual(try run(["declaration", "check", keyless.path]), Ran(status: 1, stdout: "", stderr: refusal(
            "wisent_errors.swift_cli.input", "input-wrong-shape", page: "swift-cli",
            "decoding \(what) from \(keyless.path): the file is JSON, but not \(shape); observed: \(keylessBytes.count) bytes; the decoder answered Listing could not be decoded: key \"causes\" is missing at 0",
            fix: "write \(keyless.path) as \(shape), as in \(example)")))
        XCTAssertEqual(try Data(contentsOf: keyless), keylessBytes)

        // A value of the wrong type: its coding path, and the decoder's own reason.
        let mistypedBytes = listing(docs: "https://example.com/docs/errors", uses: "[]", cause: "the file is not JSON", observed: "{bytes} bytes", usage: #""no""#)
        let mistyped = try written("mistyped.json", mistypedBytes)
        XCTAssertEqual(try run(["declaration", "check", mistyped.path]), Ran(status: 1, stdout: "", stderr: refusal(
            "wisent_errors.swift_cli.input", "input-wrong-shape", page: "swift-cli",
            "decoding \(what) from \(mistyped.path): the file is JSON, but not \(shape); observed: \(mistypedBytes.count) bytes; the decoder answered Listing could not be decoded: 0.causes.0.usage is not Bool: Expected to decode Bool but found a string instead.",
            fix: "write \(mistyped.path) as \(shape), as in \(example)")))
        XCTAssertEqual(try Data(contentsOf: mistyped), mistypedBytes)

        // A listing whose declarations break the rules: each problem a line, the first in the refusal.
        let brokenRulesBytes = listing(docs: "http://example.com/docs/errors", uses: #"["example.pairs.verify"]"#, cause: "{error}", observed: "{bytes} bytes")
        let brokenRules = try written("errors.json", brokenRulesBytes)
        let problems = [
            "operation example.pairs.import: docs \"http://example.com/docs/errors\" is not an https page; name the page that lists its causes",
            "operation example.pairs.import: cause pairs-unreadable: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
            "operation example.pairs.import: cause pairs-unreadable: `cause` is only \"{error}\", the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`",
            "operation example.pairs.import: it uses example.pairs.verify, which the catalogue does not list; list every functionality the product runs",
        ]
        XCTAssertEqual(try run(["declaration", "check", brokenRules.path]), Ran(
            status: 1, stdout: problems.joined(separator: "\n") + "\n",
            stderr: refusal(
                "wisent_errors.swift_cli.declaration_check", "listing-broken", page: "swift-cli",
                "checking the functionalities listed in \(brokenRules.path): 4 of its declarations break the declaration rules; observed: 1 functionalities read; each problem is a line on stdout; the first: \(problems[0])",
                fix: "correct each declaration in the product's catalogue as its line says, then list and check it again")))
        XCTAssertEqual(try Data(contentsOf: brokenRules), brokenRulesBytes)

        // The same listing corrected: every declaration keeps the rules.
        let keptBytes = listing(docs: "https://example.com/docs/errors", uses: "[]", cause: "the file is not JSON", observed: "{bytes} bytes; the decoder answered {error}")
        try keptBytes.write(to: brokenRules)
        XCTAssertEqual(
            try run(["declaration", "check", brokenRules.path]),
            Ran(status: 0, stdout: "1 functionalities, 1 causes: every declaration keeps the rules\n", stderr: ""))
        XCTAssertEqual(try Data(contentsOf: brokenRules), keptBytes)

        // The object Stado's `errors list --json` prints, the same functionality under operations: read as the array is.
        let objectBytes = Data(#"{"commands":1,"operations":"#.utf8) + keptBytes + Data(#","undeclared":[]}"#.utf8)
        let object = try written("object.json", objectBytes)
        XCTAssertEqual(
            try run(["declaration", "check", object.path]),
            Ran(status: 0, stdout: "1 functionalities, 1 causes: every declaration keeps the rules\n", stderr: ""))
        XCTAssertEqual(try Data(contentsOf: object), objectBytes)

        // An object with no operations, one whose operations are no list, and JSON that is neither shape.
        for (name, bytes, answered) in [
            ("unlisted.json", Data(#"{"commands":1,"undeclared":[]}"#.utf8), "key \"operations\" is missing at the top level"),
            ("keyed.json", Data(#"{"commands":1,"operations":{"example.pairs.import":{}},"undeclared":[]}"#.utf8),
             "operations is not Array<Any>: Expected to decode Array<Any> but found a dictionary instead."),
            ("text.json", Data(#""example.pairs.import""#.utf8), "the top level is not Array<Any>: Expected to decode Array<Any> but found a string instead."),
        ] {
            let file = try written(name, bytes)
            XCTAssertEqual(try run(["declaration", "check", file.path]), Ran(status: 1, stdout: "", stderr: refusal(
                "wisent_errors.swift_cli.input", "input-wrong-shape", page: "swift-cli",
                "decoding \(what) from \(file.path): the file is JSON, but not \(shape); observed: \(bytes.count) bytes; the decoder answered Listing could not be decoded: \(answered)",
                fix: "write \(file.path) as \(shape), as in \(example)")))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
        XCTAssertEqual(
            try tree(root),
            ["broken.json", "cache", "config", "data", "errors.json", "home", "keyed.json", "keyless.json", "mistyped.json", "object.json", "state", "text.json", "tmp", "unlisted.json"],
            "the command wrote nothing beside what it read")
    }

    /// The listing the fleet's real stado prints, `stado errors list --json`
    /// run by the copy WISENT_PROGRAM_TEST_STADO names, read whole: every
    /// functionality under its `operations`, each problem of Stado's own
    /// declarations a line. What Stado declares changes with each release,
    /// so the sentence is compared whole with the count and first problem
    /// this run printed and the number of operations the file holds.
    func test_declaration_check_reads_the_listing_stado_prints() throws {
        let named = (try required(
            "WISENT_PROGRAM_TEST_STADO", "the fleet's signed stado, which .wisent-release.json test_products installs (~/.local/bin/stado)") as NSString)
            .expandingTildeInPath
        let config = try written("stado-config.json", Data("{}".utf8))
        let listed = root.appendingPathComponent("stado-errors.json")
        let said = root.appendingPathComponent("stado-errors.err")
        for file in [listed, said] { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let stado = Process()
        stado.executableURL = URL(fileURLWithPath: named).resolvingSymlinksInPath()
        stado.arguments = ["errors", "list", "--json"]
        // stado's own backend overrides, so it reads and writes nothing of the operator's.
        stado.environment = environment.merging([
            "STADO_CONFIG": config.path, "WC_STORAGE_BACKEND": "local", "WC_LOCAL_STORAGE_PATH": root.appendingPathComponent("storage").path,
        ]) { $1 }
        stado.currentDirectoryURL = root
        stado.standardOutput = try FileHandle(forWritingTo: listed)
        stado.standardError = try FileHandle(forWritingTo: said)
        stado.standardInput = FileHandle.nullDevice
        try stado.run()
        stado.waitUntilExit()
        XCTAssertEqual(stado.terminationStatus, 0, try text(said))
        let listing = try Data(contentsOf: listed)
        let operations = try XCTUnwrap(try object(listing, listed.path)["operations"] as? [Any], "stado's listing holds its operations")

        let ran = try run(["declaration", "check", listed.path])
        XCTAssertEqual(try Data(contentsOf: listed), listing, "the listing is left as stado wrote it")
        guard ran.status == 1 else {
            // A Stado whose declarations all keep the rules: every operation read, nothing refused.
            XCTAssertEqual(ran.status, 0, "\(ran)")
            XCTAssertEqual(ran.stderr, "")
            return XCTAssertTrue(ran.stdout.hasPrefix("\(operations.count) functionalities, "), ran.stdout)
        }
        let problems = ran.stdout.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(ran, Ran(status: 1, stdout: ran.stdout, stderr: refusal(
            "wisent_errors.swift_cli.declaration_check", "listing-broken", page: "swift-cli",
            "checking the functionalities listed in \(listed.path): \(problems.count) of its declarations break the declaration rules; observed: \(operations.count) functionalities read; each problem is a line on stdout; the first: \(try XCTUnwrap(problems.first))",
            fix: "correct each declaration in the product's catalogue as its line says, then list and check it again")))
    }
}
#endif
