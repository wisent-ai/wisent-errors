#!/usr/bin/env node
// Everything that must hold before this package ships.
//
// Four checks, each earned by a specific way the fleet's error handling failed:
//
//   1. generated code matches the catalogue -- because six hand-kept copies
//      drifted, and one lost the vocabulary entirely;
//   2. the schema's code list matches the catalogue -- because a schema that
//      disagrees with the table it validates is a second source of truth;
//   3. every golden envelope satisfies the schema's rules, including derived
//      fields -- because `severity` chosen at a call site is how the same code
//      came to mean different things in different products;
//   4. the three runtimes agree byte for byte -- the one check whose absence
//      allowed all of the above.
//
// The schema check is deliberately hand-rolled over the fields this schema
// actually uses rather than pulling a validator in: a package every product
// must adopt has to be cheap to adopt, and that includes its own CI.
//
// Usage: node ci/check.mjs

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { readCases } from '../tests/cases.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const catalogue = JSON.parse(readFileSync(join(ROOT, 'catalogue', 'codes.json'), 'utf8'));
const schema = JSON.parse(readFileSync(join(ROOT, 'schema', 'failure.schema.json'), 'utf8'));

const problems = [];
const report = (label, ok, detail) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${label}${ok || !detail ? '' : `\n        ${detail}`}`);
  if (!ok) problems.push(label);
};

// 1. generated code matches the catalogue
try {
  execFileSync(process.execPath, [join(ROOT, 'codegen', 'generate.mjs'), '--check'], { encoding: 'utf8' });
  report('generated code matches the catalogue', true);
} catch (error) {
  report('generated code matches the catalogue', false, String(error.stdout ?? error.message).trim());
}

// 2. the schema's vocabulary is the catalogue's
const catalogueCodes = catalogue.codes.map((entry) => entry.code);
const schemaCodes = schema.properties.error_code.enum;
report(
  'schema and catalogue name the same codes',
  JSON.stringify(catalogueCodes) === JSON.stringify(schemaCodes),
  `catalogue ${catalogueCodes.join(',')} vs schema ${schemaCodes.join(',')}`,
);
report(
  'schema and catalogue name the same severities',
  JSON.stringify(catalogue.severities) === JSON.stringify(schema.properties.severity.enum),
  `catalogue ${catalogue.severities.join(',')} vs schema ${schema.properties.severity.enum.join(',')}`,
);
report(
  'the failure point pattern is stated once',
  catalogue.failure_point.pattern === schema.properties.failure_point.pattern,
  'catalogue and schema disagree on the failure point pattern',
);

// 3. every golden envelope obeys the schema, derived fields included
const meaning = new Map(catalogue.codes.map((entry) => [entry.code, entry]));
const failurePoint = new RegExp(catalogue.failure_point.pattern);
const required = schema.required;

function validate(envelope, path) {
  const found = [];
  for (const field of required) {
    if (envelope[field] === undefined) found.push(`${path}.${field} is missing`);
  }
  for (const field of Object.keys(envelope)) {
    if (!(field in schema.properties)) found.push(`${path}.${field} is not in the schema`);
  }
  if (typeof envelope.failure_point === 'string' && !failurePoint.test(envelope.failure_point)) {
    found.push(`${path}.failure_point ${envelope.failure_point} is not <service>.<surface>.<operation>`);
  }
  const entry = meaning.get(envelope.error_code);
  if (!entry) {
    found.push(`${path}.error_code ${envelope.error_code} is not in the catalogue`);
  } else {
    if (envelope.severity !== entry.severity) found.push(`${path}.severity is ${envelope.severity}, catalogue says ${entry.severity}`);
    if (envelope.retryable !== entry.retryable) found.push(`${path}.retryable is ${envelope.retryable}, catalogue says ${entry.retryable}`);
    if (envelope.outage !== entry.outage) found.push(`${path}.outage is ${envelope.outage}, catalogue says ${entry.outage}`);
  }
  for (const field of ['service', 'impact', 'detail']) {
    if (typeof envelope[field] === 'string' && !envelope[field].trim()) found.push(`${path}.${field} is empty`);
  }
  if (envelope.cause !== undefined) found.push(...validate(envelope.cause, `${path}.cause`));
  return found;
}

const goldenProblems = [];
for (const fields of readCases()) {
  if (!fields.expected) {
    goldenProblems.push(`${fields.name} has no expected envelope`);
    continue;
  }
  goldenProblems.push(...validate(JSON.parse(fields.expected), fields.name));
}
report('every golden envelope obeys the schema', goldenProblems.length === 0, goldenProblems.join('\n        '));

// 4. the runtimes are one behaviour
try {
  const output = execFileSync(process.execPath, [join(ROOT, 'tests', 'conformance.mjs')], { encoding: 'utf8' });
  const summary = output.trim().split('\n').pop();
  report(`runtimes agree (${summary})`, true);
} catch (error) {
  report('runtimes agree', false, String(error.stdout ?? error.message).trim());
}

console.log(`\n${problems.length === 0 ? 'all checks passed' : `${problems.length} check(s) failed`}`);
process.exit(problems.length === 0 ? 0 : 1);
