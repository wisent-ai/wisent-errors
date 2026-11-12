<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: envelope

Every way the envelope functionalities of this package fail, as their refusals say it.

## `wisent_errors.envelope.build`

build one failure envelope strictly, refusing a point, a service, a code or a detail that would make it read like a report while it says nothing

Started through: `Rust: Failure::new`, `JavaScript: failure, raise`, `Python: failure, raise_failure`, `Swift: Failure(failurePoint:code:service:)`. Uses: none.

<a id="wisent_errors-envelope-build-failure-point-absent"></a>

### `wisent_errors.envelope.build.failure-point-absent`

- **What failed:** building the failure envelope of service {service}
- **Cause:** the failure point is empty, so the envelope would not say where it broke
- **Observed state shown:** failure_point {quoted_point}, nothing once the whitespace around it is trimmed
- **Fix:** pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with {fallback}, which records the gap in context instead of refusing
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/envelope/build.rs::an_empty_point_is_refused`, JavaScript `tests/envelope/build.mjs::an_empty_point_is_refused`, Python `tests/envelope/build.py::test_an_empty_point_is_refused`, Swift `tests/envelope/BuildTests.swift::test_an_empty_point_is_refused`

<a id="wisent_errors-envelope-build-failure-point-segment-empty"></a>

### `wisent_errors.envelope.build.failure-point-segment-empty`

- **What failed:** building the failure envelope of service {service}
- **Cause:** segment {position} of the failure point {quoted_point} is empty: two dots stand together, or a dot opens or ends it
- **Observed state shown:** segments {segments}
- **Fix:** drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with {fallback}
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/envelope/build.rs::an_empty_segment_is_refused`, JavaScript `tests/envelope/build.mjs::an_empty_segment_is_refused`, Python `tests/envelope/build.py::test_an_empty_segment_is_refused`, Swift `tests/envelope/BuildTests.swift::test_an_empty_segment_is_refused`

<a id="wisent_errors-envelope-build-failure-point-segment-start"></a>

### `wisent_errors.envelope.build.failure-point-segment-start`

- **What failed:** building the failure envelope of service {service}
- **Cause:** segment {position} of the failure point {quoted_point}, {quoted_segment}, starts with {quoted_character}, and a segment starts with a lowercase letter
- **Observed state shown:** segments {segments}
- **Fix:** start the segment with a lowercase letter, as {suggestion}; on an error path build it with {fallback}
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/envelope/build.rs::a_segment_starting_with_no_letter_is_refused`, JavaScript `tests/envelope/build.mjs::a_segment_starting_with_no_letter_is_refused`, Python `tests/envelope/build.py::test_a_segment_starting_with_no_letter_is_refused`, Swift `tests/envelope/BuildTests.swift::test_a_segment_starting_with_no_letter_is_refused`

<a id="wisent_errors-envelope-build-failure-point-character"></a>

### `wisent_errors.envelope.build.failure-point-character`

- **What failed:** building the failure envelope of service {service}
- **Cause:** segment {position} of the failure point {quoted_point}, {quoted_segment}, holds {quoted_character}, which is not a lowercase letter, a digit, '-' or '_'
- **Observed state shown:** segments {segments}
- **Fix:** write the point in lowercase letters, digits and single '-' or '_', as {suggestion}; on an error path build it with {fallback}
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/envelope/build.rs::a_character_outside_the_grammar_is_refused`, JavaScript `tests/envelope/build.mjs::a_character_outside_the_grammar_is_refused`, Python `tests/envelope/build.py::test_a_character_outside_the_grammar_is_refused`, Swift `tests/envelope/BuildTests.swift::test_a_character_outside_the_grammar_is_refused`

<a id="wisent_errors-envelope-build-failure-point-separator"></a>

### `wisent_errors.envelope.build.failure-point-separator`

- **What failed:** building the failure envelope of service {service}
- **Cause:** segment {position} of the failure point {quoted_point}, {quoted_segment}, ends with a separator or holds two together, and '-' and '_' only join two words
- **Observed state shown:** segments {segments}
- **Fix:** keep one '-' or '_' between two words of a segment, as {suggestion}; on an error path build it with {fallback}
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/envelope/build.rs::a_dangling_separator_is_refused`, JavaScript `tests/envelope/build.mjs::a_dangling_separator_is_refused`, Python `tests/envelope/build.py::test_a_dangling_separator_is_refused`, Swift `tests/envelope/BuildTests.swift::test_a_dangling_separator_is_refused`

<a id="wisent_errors-envelope-build-service-absent"></a>

### `wisent_errors.envelope.build.service-absent`

- **What failed:** building the failure envelope at {point}
- **Cause:** the service is empty, so the envelope would not say which component failed
- **Observed state shown:** service {quoted_service}, nothing once the whitespace around it is trimmed
- **Fix:** pass the name of the component raising it, as in 'stado'; on an error path build it with {fallback}, which records the gap in context
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/envelope/build.rs::an_empty_service_is_refused`, JavaScript `tests/envelope/build.mjs::an_empty_service_is_refused`, Python `tests/envelope/build.py::test_an_empty_service_is_refused`, Swift `tests/envelope/BuildTests.swift::test_an_empty_service_is_refused`

<a id="wisent_errors-envelope-build-field-not-text"></a>

### `wisent_errors.envelope.build.field-not-text`

- **What failed:** building the failure envelope at {point}
- **Cause:** {field} is {kind}, not text, so the envelope could not carry it as written
- **Observed state shown:** {field} {shown}
- **Fix:** pass {field} as a string; an error from the layer below goes in as its message, as in String(error.message)
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/envelope/build.mjs::a_field_that_is_not_text_is_refused`, Python `tests/envelope/build.py::test_a_field_that_is_not_text_is_refused`

<a id="wisent_errors-envelope-build-code-off-catalogue"></a>

### `wisent_errors.envelope.build.code-off-catalogue`

- **What failed:** building the failure envelope at {point}
- **Cause:** the code {quoted_code} is not one of the catalogue's, so nothing could derive its severity, retryability or exit status
- **Observed state shown:** the catalogue's codes are {codes}
- **Fix:** pass one of the catalogue's codes; on a wire boundary read it with {coerce}, which keeps an unknown code as the fallback
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/envelope/build.mjs::an_off_catalogue_code_is_refused`, Python `tests/envelope/build.py::test_an_off_catalogue_code_is_refused`

<a id="wisent_errors-envelope-build-detail-blank"></a>

### `wisent_errors.envelope.build.detail-blank`

- **What failed:** building the failure envelope at {point}
- **Cause:** a detail was given but holds only whitespace, so it would read as a reason while saying none
- **Observed state shown:** detail {quoted_detail}
- **Fix:** pass the reason the layer below gave, or leave detail out, which writes null
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/envelope/build.mjs::a_blank_detail_is_refused`, Python `tests/envelope/build.py::test_a_blank_detail_is_refused`
