#!/usr/bin/env node
// Emit every golden case through the JavaScript runtime, one JSON per line.
//
// The three emitters exist so the conformance harness can compare languages
// against each other and against the golden field, rather than each runtime
// asserting its own behaviour and agreeing with nobody.
//
// With --table it dumps the whole derived vocabulary instead: every code's
// severity, retryability, outage, HTTP status and exit code, plus how each
// interesting upstream status classifies. Six envelopes prove the shape; this
// proves the table, which is where three copies of an HTTP status map and three
// copies of an exit rule used to live.

import { failure, failureOrFallback, trimDetail, trimDetailAtWordEdge, codeOrFallback } from '../js/index.mjs';
import { CODES, exitCode, fromUpstreamStatus, httpStatus, operatorSummary, outage, retryable, severity } from '../js/codes.mjs';
import { readCases, TABLE_STATUSES, TABLE_CHOSEN_EXIT, TABLE_TRIMS, TABLE_MEMBERS } from './cases.mjs';

if (process.argv.includes('--table')) {
  for (const code of CODES) {
    console.log(
      [
        `code=${code}`,
        `severity=${severity(code)}`,
        `retryable=${retryable(code)}`,
        `outage=${outage(code)}`,
        `http_status=${httpStatus(code)}`,
        `exit_code=${exitCode(code, TABLE_CHOSEN_EXIT)}`,
        `operator_summary=${operatorSummary(code)}`,
      ].join('\t'),
    );
  }
  for (const status of TABLE_STATUSES) {
    console.log(`status=${status}\tcode=${fromUpstreamStatus(status)}`);
  }
  for (const text of TABLE_MEMBERS) {
    console.log(`member=${text}\tcode=${codeOrFallback(text)}`);
  }
  for (const probe of TABLE_TRIMS) {
    const cut = probe.rule === 'word' ? trimDetailAtWordEdge(probe.text, probe.limit) : trimDetail(probe.text, probe.limit);
    console.log(`${probe.rule}=${probe.limit}\tresult=${cut}`);
  }
  process.exit(0);
}

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

  const build = fields.builder === 'or_fallback' ? failureOrFallback : failure;
  const envelope = build({
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
