// Generated from catalogue/failures/ by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

export const ENVELOPE_BUILD = Object.freeze({
  "id": "wisent_errors.envelope.build",
  "entries": [
    "Rust: Failure::new",
    "JavaScript: failure, raise",
    "Python: failure, raise_failure",
    "Swift: Failure(failurePoint:code:service:)"
  ],
  "uses": [],
  "summary": "build one failure envelope strictly, refusing a point, a service, a code or a detail that would make it read like a report while it says nothing",
  "docs": "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/envelope.md",
  "warnings": [],
  "causes": [
    {
      "id": "failure-point-absent",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope of service {service}",
      "cause": "the failure point is empty, so the envelope would not say where it broke",
      "observed": "failure_point {quoted_point}, nothing once the whitespace around it is trimmed",
      "remedy": "pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with {fallback}, which records the gap in context instead of refusing",
      "exit": null,
      "test": "tests/envelope/build.mjs::an_empty_point_is_refused"
    },
    {
      "id": "failure-point-segment-empty",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope of service {service}",
      "cause": "segment {position} of the failure point {quoted_point} is empty: two dots stand together, or a dot opens or ends it",
      "observed": "segments {segments}",
      "remedy": "drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with {fallback}",
      "exit": null,
      "test": "tests/envelope/build.mjs::an_empty_segment_is_refused"
    },
    {
      "id": "failure-point-segment-start",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope of service {service}",
      "cause": "segment {position} of the failure point {quoted_point}, {quoted_segment}, starts with {quoted_character}, and a segment starts with a lowercase letter",
      "observed": "segments {segments}",
      "remedy": "start the segment with a lowercase letter, as {suggestion}; on an error path build it with {fallback}",
      "exit": null,
      "test": "tests/envelope/build.mjs::a_segment_starting_with_no_letter_is_refused"
    },
    {
      "id": "failure-point-character",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope of service {service}",
      "cause": "segment {position} of the failure point {quoted_point}, {quoted_segment}, holds {quoted_character}, which is not a lowercase letter, a digit, '-' or '_'",
      "observed": "segments {segments}",
      "remedy": "write the point in lowercase letters, digits and single '-' or '_', as {suggestion}; on an error path build it with {fallback}",
      "exit": null,
      "test": "tests/envelope/build.mjs::a_character_outside_the_grammar_is_refused"
    },
    {
      "id": "failure-point-separator",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope of service {service}",
      "cause": "segment {position} of the failure point {quoted_point}, {quoted_segment}, ends with a separator or holds two together, and '-' and '_' only join two words",
      "observed": "segments {segments}",
      "remedy": "keep one '-' or '_' between two words of a segment, as {suggestion}; on an error path build it with {fallback}",
      "exit": null,
      "test": "tests/envelope/build.mjs::a_dangling_separator_is_refused"
    },
    {
      "id": "service-absent",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope at {point}",
      "cause": "the service is empty, so the envelope would not say which component failed",
      "observed": "service {quoted_service}, nothing once the whitespace around it is trimmed",
      "remedy": "pass the name of the component raising it, as in 'stado'; on an error path build it with {fallback}, which records the gap in context",
      "exit": null,
      "test": "tests/envelope/build.mjs::an_empty_service_is_refused"
    },
    {
      "id": "field-not-text",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope at {point}",
      "cause": "{field} is {kind}, not text, so the envelope could not carry it as written",
      "observed": "{field} {shown}",
      "remedy": "pass {field} as a string; an error from the layer below goes in as its message, as in String(error.message)",
      "exit": null,
      "test": "tests/envelope/build.mjs::a_field_that_is_not_text_is_refused"
    },
    {
      "id": "code-off-catalogue",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope at {point}",
      "cause": "the code {quoted_code} is not one of the catalogue's, so nothing could derive its severity, retryability or exit status",
      "observed": "the catalogue's codes are {codes}",
      "remedy": "pass one of the catalogue's codes; on a wire boundary read it with {coerce}, which keeps an unknown code as the fallback",
      "exit": null,
      "test": "tests/envelope/build.mjs::an_off_catalogue_code_is_refused"
    },
    {
      "id": "detail-blank",
      "code": "refused",
      "usage": true,
      "failed": "building the failure envelope at {point}",
      "cause": "a detail was given but holds only whitespace, so it would read as a reason while saying none",
      "observed": "detail {quoted_detail}",
      "remedy": "pass the reason the layer below gave, or leave detail out, which writes null",
      "exit": null,
      "test": "tests/envelope/build.mjs::a_blank_detail_is_refused"
    }
  ]
});
