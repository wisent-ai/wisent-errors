// Whether a repository holds the real test a declaration names, read the same
// way for a cause (ci/error-standard.mjs) and for a warning
// (ci/warning-standard.mjs).

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Why the test `declared` names (`tests/<area>/<file>::<test name>`) is not
// one `repository` holds, or null when the file exists and names the test. A
// file is read as text, so a test of any language counts by its name standing
// as a word in it.
export function absentTest(repository, declared) {
  const [file, name] = String(declared).split('::');
  if (!file || !name) return `${declared} names no file::test`;
  const path = join(repository, file);
  if (!existsSync(path)) return `${path} is absent`;
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (error) {
    return `${path} cannot be read: ${error.message}`;
  }
  return new RegExp(`\\b${name}\\b`).test(text) ? null : `${path} never names ${name}`;
}
