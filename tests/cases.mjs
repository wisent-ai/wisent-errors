// Reading the golden case file, shared by the emitter and the harness.
//
// Kept separate so the harness can parse cases without importing the emitter,
// whose whole job is to print them: importing a module for one function and
// getting its output as well is how a test harness starts reporting noise.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));

export const CASES_PATH = join(HERE, 'conformance', 'cases.tsv');

/** Tab separated `key=value`; the first `=` separates, so values may contain more. */
export function parseCase(line) {
  const fields = {};
  for (const pair of line.split('\t')) {
    if (!pair) continue;
    const at = pair.indexOf('=');
    if (at < 0) continue;
    fields[pair.slice(0, at)] = pair.slice(at + 1);
  }
  return fields;
}

/** Every case in file order, comments and blank lines dropped. */
export function readCases(path = CASES_PATH) {
  return readFileSync(path, 'utf8')
    .split('\n')
    .filter((line) => line.trim() && !line.startsWith('#'))
    .map(parseCase);
}
