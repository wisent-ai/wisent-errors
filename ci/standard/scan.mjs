// `scan`: an error message in a product's source that holds one of the
// catalogue's generic sentences, against a baseline that only shrinks.

import { extname, join, relative } from 'node:path';
import { genericSentencesIn } from '../../js/index.mjs';
import { describe, listDirectory, openDirectory, readJsonInput, readTreeFile } from '../input.mjs';

const SOURCE = new Map([
  ['.rs', false], ['.swift', false], ['.go', false], ['.ts', true], ['.tsx', true], ['.js', true], ['.mjs', true], ['.cjs', true], ['.py', true],
]);
const SKIPPED_DIRECTORIES = new Set([
  '.git', '.build', '.venv', 'node_modules', 'target', 'dist', 'build', 'Pods', 'DerivedData', 'vendor', 'tests', 'test', '__tests__', 'Tests', 'fixtures',
]);
const TEST_FILE = /(\.test\.|\.spec\.|_test\.|Tests?\.swift$)/;

function* sourceFiles(directory) {
  for (const entry of listDirectory(directory, 'a source directory')) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRECTORIES.has(entry.name)) yield* sourceFiles(path);
    } else if (entry.isFile() && SOURCE.has(extname(entry.name)) && !TEST_FILE.test(entry.name)) {
      yield path;
    }
  }
}

const isBaseline = (value) =>
  value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.values(value).every((sentences) => sentences !== null && typeof sentences === 'object' && Object.values(sentences).every(Number.isInteger));

/** `{ files, findings, refused, stale }` for the directories, held to `baselinePath` when given. */
export function scanSources(directories, baselinePath) {
  const findings = [];
  let files = 0;
  for (const directory of directories) {
    openDirectory(directory, 'the source directory');
    for (const path of sourceFiles(directory)) {
      files += 1;
      const singleQuoted = SOURCE.get(extname(path));
      readTreeFile(path, 'a source file')
        .split('\n')
        .forEach((line, index) => {
          for (const sentence of genericSentencesIn(line, singleQuoted)) {
            findings.push({ path: relative(process.cwd(), path), line: index + 1, sentence: sentence.text, reason: sentence.reason, text: line.trim() });
          }
        });
    }
  }
  const baseline = baselinePath === null
    ? {}
    : readJsonInput(baselinePath, 'the baseline', '{"<path>": {"<sentence>": <count>}}', (value) => (isBaseline(value) ? null : describe(value)));
  const counts = {};
  for (const finding of findings) {
    counts[finding.path] ??= {};
    counts[finding.path][finding.sentence] = (counts[finding.path][finding.sentence] ?? 0) + 1;
  }
  const refused = [];
  for (const finding of findings) {
    const allowed = baseline[finding.path]?.[finding.sentence] ?? 0;
    const held = counts[finding.path][finding.sentence];
    if (held > allowed) refused.push({ ...finding, allowed, held });
  }
  const stale = [];
  for (const [path, sentences] of Object.entries(baseline)) {
    for (const [sentence, allowed] of Object.entries(sentences)) {
      const held = counts[path]?.[sentence] ?? 0;
      if (held < allowed) stale.push({ path, sentence, allowed, held });
    }
  }
  return { files, findings, refused, stale };
}
