#!/usr/bin/env node
// Emit every golden case through the JavaScript runtime, one JSON per line.
//
// The three emitters exist so the conformance harness can compare languages
// against each other and against the golden field, rather than each runtime
// asserting its own behaviour and agreeing with nobody.

import { failure } from '../js/index.mjs';
import { readCases } from './cases.mjs';

for (const fields of readCases()) {
  const cause = fields.cause_failure_point
    ? failure({
        failurePoint: fields.cause_failure_point,
        code: fields.cause_code,
        service: fields.cause_service,
        impact: fields.cause_impact,
        detail: fields.cause_detail,
      })
    : undefined;

  let context;
  if (fields.context) {
    const at = fields.context.indexOf('=');
    context = { [fields.context.slice(0, at)]: fields.context.slice(at + 1) };
  }

  const envelope = failure({
    failurePoint: fields.failure_point,
    code: fields.code,
    service: fields.service,
    impact: fields.impact,
    detail: fields.detail,
    cause,
    context,
  });
  console.log(`${fields.name}\t${JSON.stringify(envelope)}`);
}
