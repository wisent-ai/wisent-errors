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

import { CASES_PATH, TABLE_PATH, readCases } from './cases.mjs';

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
      execFileSync(join(ROOT, 'target', 'debug', 'emit'), [], {
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

// The derived tables, compared the same way. The envelope cases prove the shape
// three ways; this proves the vocabulary itself -- every code's severity, exit
// code and HTTP status, and how each status classifies. Both mappings arrived
// here from three identical copies each, and nothing but this comparison would
// notice if one runtime's copy started to differ.
const tables = [
  ['js', () => execFileSync(process.execPath, [join(HERE, 'emit.mjs'), '--table'], { encoding: 'utf8' })],
  ['python', () => execFileSync('/usr/bin/env', ['python3', join(HERE, 'emit.py'), '--table'], { encoding: 'utf8' })],
  [
    'rust',
    () =>
      execFileSync(join(ROOT, 'target', 'debug', 'emit'), ['--table'], {
        encoding: 'utf8',
        input: readFileSync(TABLE_PATH, 'utf8'),
      }),
  ],
].map(([label, run]) => {
  try {
    return { label, lines: run().trim().split('\n') };
  } catch (error) {
    return { label, lines: null, why: String(error.message).split('\n')[0] };
  }
});

const reference = tables.find((table) => table.lines !== null);
let tableRows = 0;
if (!reference) {
  failures += 1;
  console.log('TABLE MISSING  no runtime dumped the vocabulary');
} else {
  tableRows = reference.lines.length;
  for (const table of tables) {
    if (table.lines === null) {
      failures += 1;
      console.log(`TABLE MISSING  ${table.label} -- ${table.why}`);
      continue;
    }
    const differing = table.lines
      .map((line, index) => [line, reference.lines[index]])
      .filter(([line, against]) => line !== against);
    if (differing.length === 0 || table.label === reference.label) continue;
    failures += 1;
    console.log(`TABLE DIFFERS  ${table.label} vs ${reference.label}`);
    for (const [line, against] of differing.slice(0, 5)) {
      console.log(`  ${table.label.padEnd(8)}  ${line}`);
      console.log(`  ${reference.label.padEnd(8)}  ${against ?? '(no such row)'}`);
    }
  }
  if (tables.every((table) => table.lines !== null)) {
    console.log(`ok    derived vocabulary  (${tableRows} rows, ${tables.map((table) => table.label).join(', ')})`);
  }
}

console.log(`\n${order.length} case(s) + ${tableRows} vocabulary row(s), ${failures} failing`);
process.exit(failures === 0 ? 0 : 1);
