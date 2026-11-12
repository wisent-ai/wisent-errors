// Every value name a repository's raising sites pass, read from its source,
// so a placeholder no site passes is refused at the declaration instead of
// reaching a reader as `{name}`.
//
// What counts as passing a name, per language: a Rust `("name", value)`
// pair, a JavaScript or TypeScript object key (`name: value`, `'name':
// value`, or the shorthand `{ name }`), a Python dict key or keyword
// (`"name": value`, `name=value`), a Swift dictionary key (`"name": value`).
// The reading is generous on purpose: a name any site passes counts, so a
// refusal is certain and a placeholder only one unrelated site passes goes
// unrefused. Tests and build output are not read: a value a test passes is
// not one the product passes.

import { extname, join } from 'node:path';
import { listDirectory, readTreeFile } from '../input.mjs';

const NAME = '([a-z][a-z0-9_]*)';
const PATTERNS = {
  rust: [new RegExp(`\\(\\s*"${NAME}"\\s*,`, 'g')],
  js: [new RegExp(`["']?\\b${NAME}["']?\\s*:(?!:)`, 'g'), new RegExp(`[{,]\\s*${NAME}\\s*(?=[,}])`, 'g')],
  python: [new RegExp(`["']${NAME}["']\\s*:`, 'g'), new RegExp(`\\b${NAME}\\s*=(?!=)`, 'g')],
  swift: [new RegExp(`"${NAME}"\\s*:`, 'g')],
};
const LANGUAGE = new Map([
  ['.rs', 'rust'], ['.mjs', 'js'], ['.js', 'js'], ['.cjs', 'js'], ['.ts', 'js'], ['.tsx', 'js'], ['.py', 'python'], ['.swift', 'swift'],
]);
const SKIPPED = new Set(['.git', '.build', '.venv', 'node_modules', 'target', 'dist', 'build', 'Pods', 'DerivedData', 'vendor', 'tests', 'test', '__tests__', 'Tests', 'fixtures']);

function* files(directory) {
  for (const entry of listDirectory(directory, 'a source directory of the repository')) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      if (!SKIPPED.has(entry.name)) yield* files(path);
    } else if (entry.isFile() && LANGUAGE.has(extname(entry.name))) {
      yield path;
    }
  }
}

/**
 * `{ names, files }`: every value name the repository's source passes, and how
 * many files were read. `sources` names the files and directories that raise,
 * relative to the repository, for a repository whose commands live where the
 * walk would skip them (a command under tests/); by default the whole
 * repository is read but its tests.
 */
export function passedNames(repository, sources = null) {
  const names = new Set();
  let read = 0;
  const paths = sources === null
    ? [...files(repository)]
    : sources.flatMap((source) => {
        const path = join(repository, source);
        return LANGUAGE.has(extname(path)) ? [path] : [...files(path)];
      });
  for (const path of paths) {
    read += 1;
    const text = readTreeFile(path, 'a source file of the repository');
    for (const pattern of PATTERNS[LANGUAGE.get(extname(path))]) {
      for (const found of text.matchAll(pattern)) names.add(found[1]);
    }
  }
  return { names, files: read };
}
