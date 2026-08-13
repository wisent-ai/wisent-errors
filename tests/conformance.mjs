#!/usr/bin/env node
// Prove the three runtimes are one behaviour.
//
// Each emits every golden case; this compares all of them against the expected
// column and against each other. That comparison is the whole reason this
// package can exist as three implementations without becoming three dialects --
// and it is exactly the check whose absence let one product quietly lose the
// vocabulary while five kept it.
//
// Usage: node tests/conformance.mjs

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CASES_PATH, readCases } from './cases.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');

const expected = new Map();
const order = [];
for (const fields of readCases()) {
  expected.set(fields.name, fields.expected);
  order.push(fields.name);
}

function emitted(label, run) {
  let output;
  try {
    output = run();
  } catch (error) {
    console.log(`${label}: could not run -- ${String(error.message).split('\n')[0]}`);
    return null;
  }
  const rows = new Map();
  for (const line of output.split('\n')) {
    if (!line.trim()) continue;
    const separator = line.indexOf('\t');
    rows.set(line.slice(0, separator), line.slice(separator + 1));
  }
  return rows;
}

const runtimes = [
  {
    label: 'js',
    rows: emitted('js', () => execFileSync(process.execPath, [join(HERE, 'emit.mjs')], { encoding: 'utf8' })),
  },
  {
    label: 'python',
    rows: emitted('python', () => execFileSync('/usr/bin/env', ['python3', join(HERE, 'emit.py')], { encoding: 'utf8' })),
  },
  {
    label: 'rust',
    rows: emitted('rust', () =>
      execFileSync(join(ROOT, 'rust', 'target', 'debug', 'emit'), [], {
        encoding: 'utf8',
        input: readFileSync(CASES_PATH, "utf8"),
      }),
    ),
  },
];

let failures = 0;
const missing = runtimes.filter((runtime) => runtime.rows === null);
for (const runtime of missing) {
  failures += 1;
  console.log(`RUNTIME MISSING  ${runtime.label}`);
}

for (const name of order) {
  const golden = expected.get(name);
  const answers = runtimes
    .filter((runtime) => runtime.rows !== null)
    .map((runtime) => ({ label: runtime.label, json: runtime.rows.get(name) }));

  const wrong = answers.filter((answer) => answer.json !== golden);
  if (wrong.length === 0) {
    console.log(`ok    ${name}  (${answers.map((answer) => answer.label).join(', ')})`);
    continue;
  }
  failures += 1;
  console.log(`FAIL  ${name}`);
  console.log(`  expected  ${golden}`);
  for (const answer of wrong) {
    console.log(`  ${answer.label.padEnd(8)}  ${answer.json ?? '(no line emitted)'}`);
  }
}

console.log(`\n${order.length} case(s), ${failures} failing`);
process.exit(failures === 0 ? 0 : 1);
