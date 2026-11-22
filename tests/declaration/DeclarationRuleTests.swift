// `wisent-errors-swift declaration cause`, the package's command line holding
// one cause, given field by field as its author writes it, to the declaration
// rules every runtime holds a catalogue to (catalogue/declaration.json), run
// as a process: a placeholder the renderer never fills, a cause that only
// wraps the raw text below it, an id or test path off its pattern, a usage
// refusal with a retryable code or an exit of its own beside the derived
// ones -- each a line on stdout and a refusal naming the first -- and, for a
// cause that keeps them, the refusal it says with the values given, the
// placeholders those leave unfilled and the status it exits with: the cases
// tests/declaration/placeholders.rs holds the Rust crate to.
//
//   swift test --filter DeclarationRuleTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195) -- and reads its exit
// status and both streams whole from its pipes. That is the command a
// product's author runs on a cause before adding it to the catalogue, so its
// whole flow is the run: arguments in, problems and refusal out. This file
// imports no module of the package; nothing of the library is called here.
// Rule 5: each step asserts the exit status and the whole of stdout and of
// stderr (the refusal's three lines), and that the command, which reads and
// writes no file, left the case's directory as it found it.
// Rule 7: one test, one command: `declaration cause` with its success and
// every refusal it can say, step by step.
// Rule 9: every sentence, problem line and exit status below was copied
// from live runs of wisent-errors-swift built from this tree (`swift build
// --product wisent-errors-swift`, 2026-11-21): each step run by hand with
// the same arguments under `env -i` given only HOME, CFFIXED_USER_HOME,
// TMPDIR and XDG_* inside target/probe-swift/declaration, as CommandCase
// gives them; the case's directory was listed after the runs, holding
// nothing new.

#if os(macOS)
import Foundation
import XCTest

final class DeclarationRuleTests: CommandCase {
    private let codes = "config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown"
    private let grammar = "a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec"

    /// `declaration cause` with every field of a cause that keeps the rules, each overridden by `fields`, then `more`.
    private func cause(_ fields: [String: String] = [:], _ more: [String] = []) throws -> Ran {
        let given = [
            "--id": "value-unsafe", "--code": "refused", "--failed": "checking the value {name}",
            "--cause": "the value holds a quote the engine would read as the end of the string",
            "--observed": "value {value}", "--remedy": "quote {name} before passing it",
            "--test": "tests/engine/values.rs::an_unsafe_value_is_refused",
        ].merging(fields) { $1 }
        let options = given.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }
        return try run(["declaration", "cause"] + options + more)
    }

    /// The refusal of a cause that breaks `problems.count` rules: each problem a line on stdout.
    private func broken(_ id: String, _ problems: [String]) -> Ran {
        Ran(status: 1, stdout: problems.joined(separator: "\n") + "\n", stderr: refusal(
            "wisent_errors.swift_cli.declaration_cause", "cause-broken", page: "swift-cli",
            "checking the cause \(id): it breaks \(problems.count) declaration rule(s); observed: each is a line on stdout; the first: \(problems[0])",
            fix: "correct the fields as each line says, then check the cause again; catalogue/declaration.json states every rule"))
    }

    func test_declaration_cause_holds_one_cause_to_every_declaration_rule() throws {
        let before = try tree(root)

        // A field it needs left out, a code that is none, an exit that is no number.
        let all = try cause()
        XCTAssertEqual(all.status, 0, "\(all)")
        XCTAssertEqual(
            try run(["declaration", "cause", "--id", "value-unsafe", "--code", "refused", "--failed", "checking the value {name}"]),
            usage(
                "option-required",
                "reading the options of `wisent-errors-swift declaration cause`: it needs --cause, and --cause was not given; observed: options given: --code, --failed, --id",
                fix: "add --cause, as in `--cause \"the file is not JSON\"`"))
        XCTAssertEqual(try cause(["--code": "sometimes"]), usage(
            "value-unknown",
            "reading --code of `wisent-errors-swift declaration cause`: \"sometimes\" is not one of its values; observed: its values: \(codes)",
            fix: "give --code one of \(codes)"))
        XCTAssertEqual(try cause(["--exit": "three"]), usage(
            "value-malformed",
            "reading --exit of `wisent-errors-swift declaration cause`: \"three\" is not a whole number, the status the command exits with; observed: it holds no whole number",
            fix: "give --exit a whole number, the status the command exits with, as in `--exit 3`"))

        // Placeholders the renderer never fills, one with a format spec.
        XCTAssertEqual(try cause(["--observed": "value {value:?}"]), broken("value-unsafe", [
            "cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is \(grammar); write {value} and have the raising site pass the value already formatted",
        ]))
        XCTAssertEqual(try cause(["--failed": "checking {Path} and {deal.title}", "--remedy": "quote {name before passing it"]), broken("value-unsafe", [
            "cause value-unsafe: `failed` holds the placeholder {Path}, which the renderer never fills: a placeholder is \(grammar); write {path} and have the raising site pass the value already formatted",
            "cause value-unsafe: `failed` holds the placeholder {deal.title}, which the renderer never fills: a placeholder is \(grammar); write {deal_title} and have the raising site pass the value already formatted",
            "cause value-unsafe: `remedy` opens a placeholder at \"{name before passing it\" that no '}' closes; close it as {name} or drop the '{'",
        ]))

        // A cause that only wraps the raw text of the layer below.
        XCTAssertEqual(try cause(["--cause": "{error}"]), broken("value-unsafe", [
            "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
            "cause value-unsafe: `cause` is only \"{error}\", the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`",
        ]))

        // An id and a test path off the patterns every runtime holds them to.
        XCTAssertEqual(try cause(["--id": "Fleet", "--test": "purge.sh"]), broken("Fleet", [
            "cause \"Fleet\": the id is not lowercase words joined by '-' (pattern ^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$); rename it, as in 'fleet-undeclared'",
            "cause Fleet: test \"purge.sh\" is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it",
        ]))

        // A usage refusal with a retryable code, and an exit beside the derived ones.
        XCTAssertEqual(try cause(["--code": "infra_down", "--exit": "2"], ["--usage"]), broken("value-unsafe", [
            "cause value-unsafe: a usage refusal cannot be `infra_down`, which is retryable; a usage refusal is refused for its own form, so give it a code retrying cannot help, or set usage to false",
            "cause value-unsafe: exit 2 is declared, but a usage refusal exits 2 and a retryable code 69; drop the exit, or make the cause neither",
            "cause value-unsafe: exit 2 is not a status of its own: 0 is success, 2 usage and 69 retry; declare the product's documented status, or none",
        ]))

        // A cause that keeps every rule: what it says with the values given, and what they leave unfilled.
        XCTAssertEqual(all, Ran(
            status: 0,
            stdout: "cause value-unsafe keeps every declaration rule; with the values given it says:\n"
                + "Error: checking the value {name}: the value holds a quote the engine would read as the end of the string; observed: value {value}\n"
                + "fix: quote {name} before passing it\nexit: 1\nunfilled: {name}, {value}\n",
            stderr: ""))
        XCTAssertEqual(try cause(["--exit": "3"], ["--value", "name=greeting", "--value", #"value="hello"#]), Ran(
            status: 0,
            stdout: "cause value-unsafe keeps every declaration rule; with the values given it says:\n"
                + "Error: checking the value greeting: the value holds a quote the engine would read as the end of the string; observed: value \"hello\n"
                + "fix: quote greeting before passing it\nexit: 3\n",
            stderr: ""))
        XCTAssertEqual(try cause([:], ["--usage", "--value", "name=greeting"]), Ran(
            status: 0,
            stdout: "cause value-unsafe keeps every declaration rule; with the values given it says:\n"
                + "Error: checking the value greeting: the value holds a quote the engine would read as the end of the string; observed: value {value}\n"
                + "fix: quote greeting before passing it\nexit: 2\nunfilled: {value}\n",
            stderr: ""))
        XCTAssertEqual(try cause([:], ["--value", "greeting"]), usage(
            "value-malformed",
            "reading --value of `wisent-errors-swift declaration cause`: \"greeting\" is not NAME=VALUE; observed: it holds no '='",
            fix: "give --value NAME=VALUE, as in `--value path=/srv/example-host/pairs.json`"))
        XCTAssertEqual(try tree(root), before, "the command wrote no file")
    }
}
#endif
