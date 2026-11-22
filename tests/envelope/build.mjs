// Real tests of `failure()`: an envelope built whole with every field the
// catalogue derives, rendered and chained, thrown by `raise`, and salvaged by
// `failureOrFallback`; and its refusals, each a declared cause of
// `wisent_errors.envelope.build`: what the refusal says, the cause it names,
// and that `failureOrFallback` records the same cause instead of refusing.
//
//   node --test tests/envelope/build.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DeclaredError, FailureError, chain, failure, failureOrFallback, raise, render } from '../../js/index.mjs';

test('an_envelope_is_built_with_the_fields_the_catalogue_derives', () => {
  const below = failure({ failurePoint: 'registry.read', code: 'not_found', service: 'registry', detail: 'no key fleet/example-host' });
  const built = failure({
    failurePoint: ' stado.fleet.enroll ',
    code: 'infra_down',
    service: ' stado ',
    impact: '  ',
    detail: ' connect ECONNREFUSED 127.0.0.1:9 ',
    remedy: 'start the registry on example-host',
    cause: new FailureError(below),
    context: { host: 'example-host' },
  });
  assert.deepEqual(built, {
    failure_point: 'stado.fleet.enroll',
    error_code: 'infra_down',
    service: 'stado',
    impact: null,
    severity: 'critical',
    retryable: true,
    outage: true,
    detail: 'connect ECONNREFUSED 127.0.0.1:9',
    remedy: 'start the registry on example-host',
    cause: {
      failure_point: 'registry.read',
      error_code: 'not_found',
      service: 'registry',
      impact: null,
      severity: 'warning',
      retryable: false,
      outage: false,
      detail: 'no key fleet/example-host',
      remedy: null,
    },
    context: { host: 'example-host' },
  });
  assert.equal(render(built), `infrastructure we depend on is unreachable — our failure; retry later ${JSON.stringify(built)}`);
  assert.deepEqual(chain(built), ['stado.fleet.enroll [infra_down] connect ECONNREFUSED 127.0.0.1:9', 'registry.read [not_found] no key fleet/example-host']);
  assert.throws(
    () => raise({ failurePoint: 'stado.fleet.enroll', code: 'refused', service: 'stado' }),
    (error) => error instanceof FailureError && error.message === 'stado.fleet.enroll: an explicit policy refused this command' && error.envelope.detail === null,
  );
});

test('a_malformed_envelope_on_an_error_path_is_salvaged_with_its_gaps_recorded', () => {
  assert.deepEqual(failureOrFallback({ code: 'panic', detail: 'disk full' }), {
    failure_point: 'unknown',
    error_code: 'unknown',
    service: 'unknown',
    impact: null,
    severity: 'error',
    retryable: false,
    outage: false,
    detail: 'disk full',
    remedy: null,
    context: {
      'wisent_errors.failure_point': 'absent',
      'wisent_errors.error_code': 'off-catalogue: panic',
      'wisent_errors.service': 'absent',
    },
  });
});

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
  assert.equal(error.message, "building the failure envelope of service stado: segment 2 of the failure point \"stado..enroll\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"stado\",\"\",\"enroll\"]; fix: drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with failureOrFallback");
});

test('a_segment_starting_with_no_letter_is_refused', () => {
  const error = refused({ failurePoint: 'Brama.dispatch' });
  assert.equal(error.cause, 'failure-point-segment-start');
  assert.equal(error.message, "building the failure envelope of service stado: segment 1 of the failure point \"Brama.dispatch\", \"Brama\", starts with \"B\", and a segment starts with a lowercase letter; observed: segments [\"Brama\",\"dispatch\"]; fix: start the segment with a lowercase letter, as 'brama.dispatch'; on an error path build it with failureOrFallback");
});

test('a_character_outside_the_grammar_is_refused', () => {
  const error = refused({ failurePoint: 'stado.fleet enroll' });
  assert.equal(error.cause, 'failure-point-character');
  assert.equal(error.message, "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet enroll\", \"fleet enroll\", holds \" \", which is not a lowercase letter, a digit, '-' or '_'; observed: segments [\"stado\",\"fleet enroll\"]; fix: write the point in lowercase letters, digits and single '-' or '_', as 'stado.fleet-enroll'; on an error path build it with failureOrFallback");
});

test('a_dangling_separator_is_refused', () => {
  const error = refused({ failurePoint: 'stado.fleet-' });
  assert.equal(error.cause, 'failure-point-separator');
  assert.equal(error.message, "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet-\", \"fleet-\", ends with a separator or holds two together, and '-' and '_' only join two words; observed: segments [\"stado\",\"fleet-\"]; fix: keep one '-' or '_' between two words of a segment, as 'stado.fleet'; on an error path build it with failureOrFallback");
  const salvaged = failureOrFallback({ failurePoint: 'stado.fleet-', code: 'refused', service: 'stado' });
  assert.equal(salvaged.context['wisent_errors.failure_point_cause'], 'failure-point-separator');
});

test('an_empty_service_is_refused', () => {
  const error = refused({ service: ' ' });
  assert.equal(error.cause, 'service-absent');
  assert.equal(error.message, "building the failure envelope at stado.fleet.enroll: the service is empty, so the envelope would not say which component failed; observed: service \" \", nothing once the whitespace around it is trimmed; fix: pass the name of the component raising it, as in 'stado'; on an error path build it with failureOrFallback, which records the gap in context");
});

test('a_field_that_is_not_text_is_refused', () => {
  const error = refused({ detail: new Error('connection reset') });
  assert.equal(error.cause, 'field-not-text');
  assert.equal(error.message, 'building the failure envelope at stado.fleet.enroll: detail is of type object, not text, so the envelope could not carry it as written; observed: detail Error: connection reset; fix: pass detail as a string; an error from the layer below goes in as its message, as in String(error.message)');
});

test('an_off_catalogue_code_is_refused', () => {
  const error = refused({ code: 'panic' });
  assert.equal(error.cause, 'code-off-catalogue');
  assert.equal(error.message, "building the failure envelope at stado.fleet.enroll: the code \"panic\" is not one of the catalogue's, so nothing could derive its severity, retryability or exit status; observed: the catalogue's codes are config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown; fix: pass one of the catalogue's codes; on a wire boundary read it with codeOrFallback, which keeps an unknown code as the fallback");
});

test('a_blank_detail_is_refused', () => {
  const error = refused({ detail: '  ' });
  assert.equal(error.cause, 'detail-blank');
  assert.equal(error.message, 'building the failure envelope at stado.fleet.enroll: a detail was given but holds only whitespace, so it would read as a reason while saying none; observed: detail "  "; fix: pass the reason the layer below gave, or leave detail out, which writes null');
});
