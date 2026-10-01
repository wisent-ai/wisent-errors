#!/usr/bin/env node
// What must hold before this package ships: the generated code matches the
// catalogue, and the schema states the same vocabulary as the catalogue, so
// there is one source of truth for every runtime.
//
// Usage: node ci/check.mjs

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
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

console.log(`\n${problems.length === 0 ? 'all checks passed' : `${problems.length} check(s) failed`}`);
process.exit(problems.length === 0 ? 0 : 1);
