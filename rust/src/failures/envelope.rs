// Generated from catalogue/failures/envelope.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

//! This crate's own failures of the envelope functionalities.

use crate::{Cause, Code, Operation};

pub static ENVELOPE_BUILD_FAILURE_POINT_ABSENT: Cause = Cause {
    id: "failure-point-absent",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "building the failure envelope of service {service}",
    cause: "the failure point is empty, so the envelope would not say where it broke",
    observed: "failure_point {quoted_point}, nothing once the whitespace around it is trimmed",
    remedy: "pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with {fallback}, which records the gap in context instead of refusing",
    test: "tests/envelope/build.rs::an_empty_point_is_refused",
};

pub static ENVELOPE_BUILD_FAILURE_POINT_SEGMENT_EMPTY: Cause = Cause {
    id: "failure-point-segment-empty",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "building the failure envelope of service {service}",
    cause: "segment {position} of the failure point {quoted_point} is empty: two dots stand together, or a dot opens or ends it",
    observed: "segments {segments}",
    remedy: "drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with {fallback}",
    test: "tests/envelope/build.rs::an_empty_segment_is_refused",
};

pub static ENVELOPE_BUILD_FAILURE_POINT_SEGMENT_START: Cause = Cause {
    id: "failure-point-segment-start",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "building the failure envelope of service {service}",
    cause: "segment {position} of the failure point {quoted_point}, {quoted_segment}, starts with {quoted_character}, and a segment starts with a lowercase letter",
    observed: "segments {segments}",
    remedy: "start the segment with a lowercase letter, as {suggestion}; on an error path build it with {fallback}",
    test: "tests/envelope/build.rs::a_segment_starting_with_no_letter_is_refused",
};

pub static ENVELOPE_BUILD_FAILURE_POINT_CHARACTER: Cause = Cause {
    id: "failure-point-character",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "building the failure envelope of service {service}",
    cause: "segment {position} of the failure point {quoted_point}, {quoted_segment}, holds {quoted_character}, which is not a lowercase letter, a digit, '-' or '_'",
    observed: "segments {segments}",
    remedy: "write the point in lowercase letters, digits and single '-' or '_', as {suggestion}; on an error path build it with {fallback}",
    test: "tests/envelope/build.rs::a_character_outside_the_grammar_is_refused",
};

pub static ENVELOPE_BUILD_FAILURE_POINT_SEPARATOR: Cause = Cause {
    id: "failure-point-separator",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "building the failure envelope of service {service}",
    cause: "segment {position} of the failure point {quoted_point}, {quoted_segment}, ends with a separator or holds two together, and '-' and '_' only join two words",
    observed: "segments {segments}",
    remedy: "keep one '-' or '_' between two words of a segment, as {suggestion}; on an error path build it with {fallback}",
    test: "tests/envelope/build.rs::a_dangling_separator_is_refused",
};

pub static ENVELOPE_BUILD_SERVICE_ABSENT: Cause = Cause {
    id: "service-absent",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "building the failure envelope at {point}",
    cause: "the service is empty, so the envelope would not say which component failed",
    observed: "service {quoted_service}, nothing once the whitespace around it is trimmed",
    remedy: "pass the name of the component raising it, as in 'stado'; on an error path build it with {fallback}, which records the gap in context",
    test: "tests/envelope/build.rs::an_empty_service_is_refused",
};

pub static ENVELOPE_BUILD: Operation = Operation {
    id: "wisent_errors.envelope.build",
    entries: &["Rust: Failure::new", "JavaScript: failure, raise", "Python: failure, raise_failure", "Swift: Failure(failurePoint:code:service:)"],
    uses: &[],
    summary: "build one failure envelope strictly, refusing a point, a service, a code or a detail that would make it read like a report while it says nothing",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/envelope.md",
    causes: &[&ENVELOPE_BUILD_FAILURE_POINT_ABSENT, &ENVELOPE_BUILD_FAILURE_POINT_SEGMENT_EMPTY, &ENVELOPE_BUILD_FAILURE_POINT_SEGMENT_START, &ENVELOPE_BUILD_FAILURE_POINT_CHARACTER, &ENVELOPE_BUILD_FAILURE_POINT_SEPARATOR, &ENVELOPE_BUILD_SERVICE_ABSENT],
    warnings: &[],
};
