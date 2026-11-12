#!/usr/bin/env node
// What must hold before this package ships: the generated code matches the
// catalogue, the schema states the same vocabulary as the catalogue, and this
// package's own failure catalogue holds to the rules it gives every product,
// its tests written or listed in tests/untested-causes.json and every
// placeholder passed by a raising site.
//
// Usage: node ci/check.mjs

import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { catalogue as listing } from '../js/index.mjs';
import { holding, listDirectory, readJsonInput } from './input.mjs';
import { guarded, ownOperations, refusalText } from './refuse.mjs';
import { operationsFor, readParts } from '../codegen/parts.mjs';
import { checkListing } from './standard/catalogue.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const catalogue = readJsonInput(join(ROOT, 'catalogue', 'codes.json'), 'the vocabulary', 'an object with codes, severities and failure_point', holding('codes', 'severities', 'failure_point'));
const schemaPath = join('schema', 'failure.schema.json');
const schema = readJsonInput(join(ROOT, schemaPath), 'the envelope schema', 'a JSON schema with properties error_code, severity and failure_point', holding('properties'));

const problems = [];
const report = (label, ok, detail) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${label}${ok || !detail ? '' : `\n        ${detail.split('\n').join('\n        ')}`}`);
  if (!ok) problems.push(label);
};

// 1. generated code matches the catalogue
const generated = spawnSync(process.execPath, [join(ROOT, 'codegen', 'generate.mjs'), '--check'], { encoding: 'utf8' });
report('generated code matches the catalogue', generated.status === 0, `${generated.stdout}${generated.stderr}`.trim());

// 2. the schema's vocabulary is the catalogue's
const differs = (what, catalogueSays, schemaSays) =>
  refusalText('wisent_errors.ship.check', 'vocabulary-differs', { what, schema: schemaPath, catalogue_says: catalogueSays, schema_says: schemaSays });
const catalogueCodes = catalogue.codes.map((entry) => entry.code).join(', ');
const schemaCodes = (schema.properties?.error_code?.enum ?? []).join(', ');
report('schema and catalogue name the same codes', catalogueCodes === schemaCodes, differs('codes', catalogueCodes, schemaCodes));
const catalogueSeverities = catalogue.severities.join(', ');
const schemaSeverities = (schema.properties?.severity?.enum ?? []).join(', ');
report('schema and catalogue name the same severities', catalogueSeverities === schemaSeverities, differs('severities', catalogueSeverities, schemaSeverities));
const schemaPattern = String(schema.properties?.failure_point?.pattern);
report('the failure point pattern is stated once', catalogue.failure_point.pattern === schemaPattern, differs('failure point pattern', catalogue.failure_point.pattern, schemaPattern));

// 3. this package's own failure catalogue holds, in every runtime it is generated into.
// Its raising sites are the runtimes, the commands under ci/ and codegen/, and
// tests/inventory.mjs, a command that lives under tests/ by the fleet's convention.
const SOURCES = ['js', 'rust/src', 'python/wisent_errors', 'swift/Sources', 'ci', 'codegen', 'tests/inventory.mjs'];
for (const runtime of ['node', 'js', 'rust', 'python', 'swift']) {
  const operations = guarded(() => (runtime === 'node' ? ownOperations() : operationsFor(runtime, readParts())));
  const own = guarded(() => checkListing(operations.map((operation) => listing(operation, 1)), ROOT, null, SOURCES));
  const refused = own.report.filter((entry) => entry.problems.length > 0);
  report(
    `this package's own ${runtime} failure catalogue holds (${own.report.length} functionalities)`,
    refused.length === 0,
    refused.map((entry) => `${entry.operation}:\n  ${entry.problems.join('\n  ')}`).join('\n'),
  );
}

// 4. the package's node tests pass: every tests/<area>/*.mjs, as `node --test`
// runs them. Nothing else runs them before a push to this repository, which
// is how six failing ones reached main unseen.
const testFiles = listDirectory(join(ROOT, 'tests'), 'the tests')
  .filter((area) => area.isDirectory())
  .flatMap((area) =>
    listDirectory(join(ROOT, 'tests', area.name), 'a test area')
      .filter((entry) => entry.isFile() && entry.name.endsWith('.mjs'))
      .map((entry) => join('tests', area.name, entry.name)),
  )
  .sort();
const tested = spawnSync(process.execPath, ['--test', ...testFiles], { cwd: ROOT, encoding: 'utf8' });
const failing = `${tested.stdout}${tested.stderr}`.split('\n').filter((line) => line.startsWith('✖ ') || line.startsWith('test at '));
report(
  `the node tests pass (${testFiles.length} files)`,
  tested.status === 0,
  failing.length ? [...new Set(failing)].join('\n') : `node --test exited with status ${tested.status}${tested.error ? `: ${tested.error.message}` : ''}`,
);

console.log(`\n${problems.length === 0 ? 'all checks passed' : `${problems.length} check(s) failed: ${problems.join('; ')}`}`);
process.exitCode = problems.length === 0 ? 0 : 1;
