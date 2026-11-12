// Real tests of `failure()`'s refusals, each a declared cause of
// `wisent_errors.envelope.build`: what the refusal says, the cause it names,
// and that `failureOrFallback` records the same cause instead of refusing.
//
//   node --test tests/envelope/build.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DeclaredError, failure, failureOrFallback } from '../../js/index.mjs';

function refused(fields) {
  try {
    const built = failure({ failurePoint: 'stado.fleet.enroll', code: 'refused', service: 'stado', ...fields });
    return assert.fail(`accepted: ${JSON.stringify(built)}`);
  } catch (error) {
    assert.ok(error instanceof DeclaredError && error instanceof TypeError, String(error));
    assert.equal(error.operation, 'wisent_errors.envelope.build');
    return error;
  }
}

test('an_empty_point_is_refused', () => {
  const error = refused({ failurePoint: '   ' });
  assert.equal(error.cause, 'failure-point-absent');
  assert.equal(
    error.message,
    "building the failure envelope of service stado: the failure point is empty, so the envelope would not say where it broke; observed: failure_point \"   \", nothing once the whitespace around it is trimmed; fix: pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with failureOrFallback, which records the gap in context instead of refusing",
  );
});

test('an_empty_segment_is_refused', () => {
  const error = refused({ failurePoint: 'stado..enroll' });
  assert.equal(error.cause, 'failure-point-segment-empty');
  assert.match(error.message, /segment 2 of the failure point "stado\.\.enroll" is empty.*observed: segments \["stado","","enroll"\]/);
});

test('a_segment_starting_with_no_letter_is_refused', () => {
  const error = refused({ failurePoint: 'Brama.dispatch' });
  assert.equal(error.cause, 'failure-point-segment-start');
  assert.match(error.message, /"Brama", starts with "B".*as 'brama\.dispatch'/);
});

test('a_character_outside_the_grammar_is_refused', () => {
  const error = refused({ failurePoint: 'stado.fleet enroll' });
  assert.equal(error.cause, 'failure-point-character');
  assert.match(error.message, /"fleet enroll", holds " ".*as 'stado\.fleet-enroll'/);
});

test('a_dangling_separator_is_refused', () => {
  assert.equal(refused({ failurePoint: 'stado.fleet-' }).cause, 'failure-point-separator');
  const salvaged = failureOrFallback({ failurePoint: 'stado.fleet-', code: 'refused', service: 'stado' });
  assert.equal(salvaged.context['wisent_errors.failure_point_cause'], 'failure-point-separator');
});

test('an_empty_service_is_refused', () => {
  const error = refused({ service: ' ' });
  assert.equal(error.cause, 'service-absent');
  assert.match(error.message, /^building the failure envelope at stado\.fleet\.enroll: the service is empty.*observed: service " "/);
});

test('a_field_that_is_not_text_is_refused', () => {
  const error = refused({ detail: new Error('connection reset') });
  assert.equal(error.cause, 'field-not-text');
  assert.match(error.message, /detail is of type object, not text.*observed: detail Error: connection reset/);
});

test('an_off_catalogue_code_is_refused', () => {
  const error = refused({ code: 'panic' });
  assert.equal(error.cause, 'code-off-catalogue');
  assert.match(error.message, /the code "panic" is not one of the catalogue's.*codes are config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown.*read it with codeOrFallback/);
});

test('a_blank_detail_is_refused', () => {
  const error = refused({ detail: '  ' });
  assert.equal(error.cause, 'detail-blank');
  assert.match(error.message, /observed: detail "  "; fix: pass the reason the layer below gave/);
});
