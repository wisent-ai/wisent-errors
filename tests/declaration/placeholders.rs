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
    let malformed = |placeholder: &str, suggestion: &str| {
        format!("cause value-unsafe: `failed` holds the placeholder {placeholder}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {suggestion} and have the raising site pass the value already formatted")
    };
    assert_eq!(
        broken.problems(),
        vec![
            malformed("{Path}", "{path}"),
            malformed("{deal.title}", "{deal_title}"),
            "cause value-unsafe: `remedy` opens a placeholder at \"{name before passing it\" that no '}' closes; close it as {name} or drop the '{'".to_owned(),
        ]
    );
    let unopened = Cause { failed: "checking a} value", ..CAUSE };
    assert_eq!(
        unopened.problems(),
        vec!["cause value-unsafe: `failed` holds a '}' at \"checking a} value\" that no '{' opened; drop it, or open the placeholder it ends".to_owned()]
    );
}

#[test]
fn a_cause_whose_why_is_only_the_raw_message_is_refused() {
    let wraps = |quoted: &str| {
        format!("cause value-unsafe: `cause` is only {quoted}, the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`")
    };
    let wrapped = Cause { cause: "{error}", ..CAUSE };
    assert_eq!(
        wrapped.problems(),
        vec![
            "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`".to_owned(),
            wraps("\"{error}\""),
        ]
    );
    let pair = Cause { cause: "{code}: {reason}", ..CAUSE };
    assert_eq!(pair.problems(), vec![wraps("\"{code}: {reason}\"")]);
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
    for id in rules::CAUSE_ID_VALID {
        assert_eq!(Cause { id: *id, ..CAUSE }.problems(), Vec::<String>::new(), "{id}");
    }
    for id in rules::CAUSE_ID_INVALID {
        let quoted = serde_json::to_string(id).expect("an id is a JSON string");
        assert_eq!(
            Cause { id: *id, ..CAUSE }.problems(),
            vec![format!("cause {quoted}: the id is not lowercase words joined by '-' (pattern ^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$); rename it, as in 'fleet-undeclared'")],
            "{id}"
        );
    }
    for test in rules::TEST_PATH_VALID {
        assert_eq!(Cause { test: *test, ..CAUSE }.problems(), Vec::<String>::new(), "{test}");
    }
    for test in rules::TEST_PATH_INVALID {
        let quoted = serde_json::to_string(test).expect("a test path is a JSON string");
        assert_eq!(
            Cause { test: *test, ..CAUSE }.problems(),
            vec![format!("cause value-unsafe: test {quoted} is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it")],
            "{test}"
        );
    }
}
