// Real tests of the declaration rules a Swift product's causes are held to:
// a placeholder the renderer never fills, a cause that only wraps the raw
// text below it, raw text outside `observed`, and the probes
// catalogue/declaration.json states for every runtime.
//
//   swift test --filter PlaceholderTests

import XCTest
@testable import WisentErrors

final class PlaceholderTests: XCTestCase {
    private func cause(failed: String = "checking the value {name}", cause: String = "the value holds a quote the engine would read as the end of the string", observed: String = "value {value}", remedy: String = "quote {name} before passing it", test: String = "tests/engine/values.rs::an_unsafe_value_is_refused") -> Cause {
        Cause(id: "value-unsafe", code: .refused, usage: false, exit: nil, failed: failed, cause: cause, observed: observed, remedy: remedy, test: test)
    }

    func test_a_format_spec_placeholder_is_refused_naming_the_cause_and_the_placeholder() {
        XCTAssertEqual(cause(observed: "value {value:?}").problems(), [
            "cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted",
        ])
        XCTAssertEqual(fill("value {value:?}", ["value": "x", "value:?": "y"]), "value {value:?}")
    }

    func test_every_placeholder_the_renderer_will_not_fill_is_refused() {
        let problems = cause(failed: "checking {Path} and {deal.title}", remedy: "quote {name before passing it").problems()
        XCTAssertEqual(problems.count, 3, problems.joined(separator: "\n"))
        XCTAssertTrue(problems[0].contains("write {path}"))
        XCTAssertTrue(problems[1].contains("write {deal_title}"))
        XCTAssertTrue(problems[2].contains("`remedy` opens a placeholder at \"{name before passing it\" that no '}' closes"))
    }

    func test_a_cause_whose_why_is_only_the_raw_message_is_refused() {
        let problems = cause(cause: "{error}").problems()
        XCTAssertTrue(problems.contains("cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`"), problems.joined(separator: "\n"))
        XCTAssertTrue(problems.contains { $0.hasPrefix("cause value-unsafe: `cause` is only \"{error}\", the text it wraps") })
        XCTAssertEqual(cause(observed: "the parser said {problem}").problems(), [])
    }

    func test_the_renderer_reads_a_template_as_every_runtime_does() {
        XCTAssertEqual(templateParts("a {x} {Y} {z"), [.text("a "), .placeholder("x"), .text(" "), .malformed("{Y}"), .text(" "), .unclosed("{z")])
        XCTAssertEqual(unfilled(["{a} {b}", "{b} {c}"], ["b": "1"]), ["a", "c"])
        let probes = Declaration.probes
        for name in probes["placeholder"]?.valid ?? [] { XCTAssertTrue(isPlaceholderName(name), name) }
        for name in probes["placeholder"]?.invalid ?? [] { XCTAssertFalse(isPlaceholderName(name), name) }
        for test in (probes["test_path"]?.valid ?? []) + (probes["test_path"]?.invalid ?? []) {
            let refused = cause(test: test).problems().contains { $0.contains("is not tests/<area>/<file>::<test name>") }
            XCTAssertEqual(refused, probes["test_path"]?.invalid.contains(test) ?? false, test)
        }
        XCTAssertEqual(probes.count, 3, "catalogue/declaration.json states probes for the placeholder, the cause id and the test path")
    }
}
