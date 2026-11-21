// Real tests, through the package's public API, of the declaration rules a
// Swift product's causes are held to: a placeholder the renderer never fills,
// a cause that only wraps the raw text below it, raw text outside `observed`,
// and the probes catalogue/declaration.json states for every runtime -- the
// cases tests/declaration/placeholders.rs holds the Rust crate to.
//
//   swift test --filter DeclarationRuleTests

import XCTest
import WisentErrors

final class DeclarationRuleTests: XCTestCase {
    private func cause(
        id: String = "value-unsafe",
        failed: String = "checking the value {name}",
        cause: String = "the value holds a quote the engine would read as the end of the string",
        observed: String = "value {value}",
        remedy: String = "quote {name} before passing it",
        test: String = "tests/engine/values.rs::an_unsafe_value_is_refused"
    ) -> Cause {
        Cause(id: id, code: .refused, usage: false, exit: nil, failed: failed, cause: cause, observed: observed, remedy: remedy, test: test)
    }

    func test_a_format_spec_placeholder_is_refused_naming_the_cause_and_the_placeholder() {
        XCTAssertEqual(cause().problems(), [])
        XCTAssertEqual(cause(observed: "value {value:?}").problems(), [
            "cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted",
        ])
        XCTAssertEqual(fill("value {value:?}", ["value": "x", "value:?": "y"]), "value {value:?}")
    }

    func test_every_placeholder_the_renderer_will_not_fill_is_refused() {
        XCTAssertEqual(cause(failed: "checking {Path} and {deal.title}", remedy: "quote {name before passing it").problems(), [
            "cause value-unsafe: `failed` holds the placeholder {Path}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {path} and have the raising site pass the value already formatted",
            "cause value-unsafe: `failed` holds the placeholder {deal.title}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {deal_title} and have the raising site pass the value already formatted",
            "cause value-unsafe: `remedy` opens a placeholder at \"{name before passing it\" that no '}' closes; close it as {name} or drop the '{'",
        ])
    }

    func test_a_cause_whose_why_is_only_the_raw_message_is_refused() {
        XCTAssertEqual(cause(cause: "{error}").problems(), [
            "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
            "cause value-unsafe: `cause` is only \"{error}\", the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`",
        ])
        XCTAssertEqual(cause(observed: "the parser said {problem}").problems(), [])
    }

    func test_the_renderer_reads_a_template_as_every_runtime_does() {
        XCTAssertEqual(templateParts("a {x} {Y} {z"), [.text("a "), .placeholder("x"), .text(" "), .malformed("{Y}"), .text(" "), .unclosed("{z")])
        XCTAssertEqual(unfilled(["{a} {b}", "{b} {c}"], ["b": "1"]), ["a", "c"])
        XCTAssertEqual(Set(Declaration.probes.keys), ["placeholder", "cause_id", "test_path"])
        let names = Declaration.probes["placeholder"] ?? (valid: [], invalid: [])
        XCTAssertEqual(names.valid, ["path", "fleet", "exit_status", "a1"])
        for name in names.valid {
            XCTAssertTrue(isPlaceholderName(name), name)
            XCTAssertEqual(fill("<{\(name)}>", [name: "filled"]), "<filled>", name)
        }
        XCTAssertEqual(names.invalid, ["value:?", "error:#", "Path", "1st", "host-name", "deal.title", "", " name"])
        for name in names.invalid {
            XCTAssertFalse(isPlaceholderName(name), name)
            XCTAssertEqual(fill("<{\(name)}>", [name: "filled"]), "<{\(name)}>", name)
        }
    }

    func test_a_cause_id_is_held_to_the_probes_every_runtime_states() {
        let ids = Declaration.probes["cause_id"] ?? (valid: [], invalid: [])
        XCTAssertEqual(ids.valid, ["fleet-undeclared", "input-absent", "exit2"])
        for id in ids.valid { XCTAssertEqual(cause(id: id).problems(), [], id) }
        XCTAssertEqual(ids.invalid, ["", "Fleet", "fleet_undeclared", "fleet--undeclared", "-fleet", "2fleet"])
        for id in ids.invalid {
            XCTAssertEqual(cause(id: id).problems(), [
                "cause \"\(id)\": the id is not lowercase words joined by '-' (pattern ^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$); rename it, as in 'fleet-undeclared'",
            ], id)
        }
    }

    func test_a_test_path_is_held_to_the_probes_every_runtime_states() {
        let tests = Declaration.probes["test_path"] ?? (valid: [], invalid: [])
        XCTAssertEqual(tests.valid, ["tests/fleet/enroll.rs::enroll_refuses", "tests/a/b/c.mjs::x_1"])
        for test in tests.valid { XCTAssertEqual(cause(test: test).problems(), [], test) }
        XCTAssertEqual(tests.invalid, ["purge.sh", "tests/x.rs::t", "tests/a//b.rs::t", "tests/a/b.rs::", "tests/a/b.rs::Bad", "src/a/b.rs::t"])
        for test in tests.invalid {
            XCTAssertEqual(cause(test: test).problems(), [
                "cause value-unsafe: test \"\(test)\" is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it",
            ], test)
        }
    }
}
