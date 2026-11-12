//! Real tests of the declaration rules a Rust product's causes are held to:
//! a placeholder the renderer never fills, a cause that only wraps the raw
//! text below it, raw text outside `observed`, the probes
//! catalogue/declaration.json states for every runtime, and the gap a
//! raising site leaves recorded in the envelope.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --test declaration

use wisent_errors::declaration as rules;
use wisent_errors::operation::{fill, parts, unfilled, Part};
use wisent_errors::{Cause, Code};

const CAUSE: Cause = Cause {
    id: "value-unsafe",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "checking the value {name}",
    cause: "the value holds a quote the engine would read as the end of the string",
    observed: "value {value}",
    remedy: "quote {name} before passing it",
    test: "tests/engine/values.rs::an_unsafe_value_is_refused",
};

#[test]
fn a_format_spec_placeholder_is_refused_naming_the_cause_and_the_placeholder() {
    let spec = Cause { observed: "value {value:?}", ..CAUSE };
    assert_eq!(
        spec.problems(),
        vec!["cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted".to_owned()]
    );
    assert_eq!(fill("value {value:?}", &[("value", "x"), ("value:?", "y")]), "value {value:?}");
}

#[test]
fn every_placeholder_the_renderer_will_not_fill_is_refused() {
    let broken = Cause {
        failed: "checking {Path} and {deal.title}",
        remedy: "quote {name before passing it",
        ..CAUSE
    };
    let problems = broken.problems();
    assert_eq!(problems.len(), 3, "{problems:#?}");
    assert!(problems[0].contains("`failed` holds the placeholder {Path},") && problems[0].contains("write {path}"));
    assert!(problems[1].contains("`failed` holds the placeholder {deal.title},") && problems[1].contains("write {deal_title}"));
    assert!(problems[2].contains("`remedy` opens a placeholder at \"{name before passing it\" that no '}' closes; close it as {name} or drop the '{'"));
    let unopened = Cause { failed: "checking a} value", ..CAUSE };
    assert!(unopened.problems()[0].contains("`failed` holds a '}' at \"checking a} value\" that no '{' opened"));
}

#[test]
fn a_cause_whose_why_is_only_the_raw_message_is_refused() {
    let wrapped = Cause { cause: "{error}", ..CAUSE };
    let problems = wrapped.problems();
    assert!(problems.contains(&"cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`".to_owned()), "{problems:#?}");
    assert!(problems.iter().any(|problem| problem.starts_with("cause value-unsafe: `cause` is only \"{error}\", the text it wraps, so it says nothing of why")));
    let pair = Cause { cause: "{code}: {reason}", ..CAUSE };
    assert!(pair.problems().iter().any(|problem| problem.contains("`cause` is only \"{code}: {reason}\"")));
    let observed = Cause { observed: "the parser said {problem}", ..CAUSE };
    assert_eq!(observed.problems(), Vec::<String>::new());
}

#[test]
fn a_raising_site_that_leaves_a_placeholder_unfilled_is_recorded_in_the_envelope() {
    let failure = CAUSE.failure("engine.value.check", "engine", &[("name", "title")]);
    assert_eq!(failure.context.get("wisent_errors.unfilled").map(String::as_str), Some("value"));
    assert_eq!(unfilled(&["{a} {b}", "{b} {c}"], &[("b", "1")]), vec!["a", "c"]);
}

#[test]
fn the_renderer_reads_a_template_as_every_runtime_does() {
    assert_eq!(
        parts("a {x} {Y} {z"),
        vec![Part::Text("a "), Part::Placeholder("x"), Part::Text(" "), Part::Malformed("{Y}"), Part::Text(" "), Part::Unclosed("{z")]
    );
    for name in rules::PLACEHOLDER_VALID {
        assert_eq!(parts(&format!("{{{name}}}")), vec![Part::Placeholder(*name)], "{name}");
    }
    for name in rules::PLACEHOLDER_INVALID {
        assert!(!matches!(parts(&format!("{{{name}}}"))[..], [Part::Placeholder(_)]), "{name}");
    }
    for id in rules::CAUSE_ID_VALID.iter().chain(rules::CAUSE_ID_INVALID) {
        let valid = rules::CAUSE_ID_VALID.contains(id);
        let problems = Cause { id: *id, ..CAUSE }.problems();
        assert_eq!(problems.iter().any(|problem| problem.contains("the id is not lowercase words")), !valid, "{id}");
    }
    for test in rules::TEST_PATH_VALID.iter().chain(rules::TEST_PATH_INVALID) {
        let valid = rules::TEST_PATH_VALID.contains(test);
        let problems = Cause { test: *test, ..CAUSE }.problems();
        assert_eq!(problems.iter().any(|problem| problem.contains("is not tests/<area>/<file>::<test name>")), !valid, "{test}");
    }
}
