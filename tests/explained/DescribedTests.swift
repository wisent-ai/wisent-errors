// `wisent-errors-swift declaration check <file>`, the package's command line
// holding a product's `errors list --json` listing, read from a file, to the
// declaration rules, run as a process: the listing it passes, the problems
// it prints and refuses, and the described decoding every Wisent app reads
// JSON through -- where text stopped being JSON (`describedObject`), and
// the type, key and coding path a decoder stopped at (`decodeDescribed`).
//
//   swift test --filter DescribedTests
//
// Rule 4: the case runs the built wisent-errors-swift (CommandCase.swift) on
// listings written under the case's directory, as a product's CI runs it on
// the listing its `errors list --json` printed; nothing of the library is
// called here.
// Rule 5: each step asserts the exit status, the whole of stdout (the
// problems, one a line) and of the refusal's three stderr lines, and reads
// each listing back after the command: it is left byte for byte as it was.
// Rule 9: the command cannot be built here, so no sentence was probed: each
// expected refusal is the cause's template in catalogue/failures/swift-cli.json,
// and each problem the rule's sentence in catalogue/declaration.json,
// rendered whole with the values the step gives; Foundation's own words for
// JSON it cannot read are asked of it the same way in this process.

#if os(macOS)
import Foundation
import XCTest

final class DescribedTests: CommandCase {
    private let what = "the listing of a product's functionalities"
    private let shape = "the JSON array `errors list --json` prints: one object per functionality with operation, entries, uses, summary, docs and causes, each cause with id, code, usage, failed, cause, observed, remedy and test"
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

    /// The listing's shape as Foundation's decoder reads it, to ask it its own words.
    private struct Listed: Decodable {
        struct Declared: Decodable {
            let id: String
            let usage: Bool
        }

        let operation: String
        let causes: [Declared]
    }

    func test_declaration_check_reads_a_listing_or_says_where_it_stops_being_one() throws {
        // Text that is not JSON: where Foundation's reader stopped.
        let brokenBytes = Data(#"[{"operation": "example.pairs.import",]"#.utf8)
        let broken = try written("broken.json", brokenBytes)
        var reader = "no failure"
        do {
            _ = try JSONSerialization.jsonObject(with: brokenBytes, options: [.fragmentsAllowed])
        } catch {
            // fallback: Foundation's reader gives its reason under NSDebugDescriptionErrorKey; without one the command says the error whole, as here.
            reader = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? explained(error)
        }
        XCTAssertEqual(try run(["declaration", "check", broken.path]), Ran(status: 1, stdout: "", stderr: refusal(
            "wisent_errors.swift_cli.input", "input-not-json", page: "swift-cli",
            "decoding \(what) from \(broken.path): the file is not JSON; observed: \(brokenBytes.count) bytes; the reader answered \(reader)",
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
        var decoder = "no failure"
        do {
            _ = try JSONDecoder().decode([Listed].self, from: mistypedBytes)
        } catch DecodingError.typeMismatch(_, let context) {
            decoder = context.debugDescription
        } catch {
            decoder = "another failure: \(explained(error))"
        }
        XCTAssertEqual(try run(["declaration", "check", mistyped.path]), Ran(status: 1, stdout: "", stderr: refusal(
            "wisent_errors.swift_cli.input", "input-wrong-shape", page: "swift-cli",
            "decoding \(what) from \(mistyped.path): the file is JSON, but not \(shape); observed: \(mistypedBytes.count) bytes; the decoder answered Listing could not be decoded: 0.causes.0.usage is not Bool: \(decoder)",
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
        XCTAssertEqual(
            try tree(root), ["broken.json", "cache", "config", "data", "errors.json", "home", "keyless.json", "mistyped.json", "state", "tmp"],
            "the command wrote nothing beside what it read")
    }
}
#endif
