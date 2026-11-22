// The files and directories this repository's commands are named, read
// through the declared layers `wisent_errors.lint.input` (one JSON or text
// file) and `wisent_errors.lint.paths` (a directory or a tree to walk), so
// every command refuses an absent, unreadable or malformed input with the
// same sentence and the state it found.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { refuse } from './refuse.mjs';

const INPUT = 'wisent_errors.lint.input';
const PATHS = 'wisent_errors.lint.paths';

const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
// What a build or a test writes under the package is not its source: a guard
// that skipped these could not be run on the trees its own tests make.
const SCRATCH = ['target', '.build'].map((name) => join(PACKAGE_ROOT, name) + sep);

/**
 * Whether `path` is this package's own source, which the guards a consuming
 * repository runs never report: matched by resolved path, not by a name in
 * it, so a relative invocation from the package is recognised too, and a
 * sibling whose name only begins like the package's is not.
 */
export function packageSource(path) {
  const at = resolve(path);
  const inside = at === PACKAGE_ROOT || at.startsWith(PACKAGE_ROOT + sep);
  return inside && !SCRATCH.some((scratch) => at.startsWith(scratch));
}

/** What is at `path`: its kind, mode and owner, or why it cannot be examined. */
export function stateOf(path) {
  try {
    const entry = statSync(path);
    const kind = entry.isDirectory() ? 'a directory' : entry.isFile() ? `a file of ${entry.size} bytes` : 'neither a file nor a directory';
    return `${path} is ${kind}, mode ${(entry.mode & 0o777).toString(8)}, owner uid ${entry.uid}`;
  } catch (error) {
    return `${path} cannot be examined: ${error.code ?? error.message}`;
  }
}

/** What PATH is, for the refusal of a program that could not be started: unset, or what it holds, quoted so an empty one reads as empty. */
export const pathVariable = () => (process.env.PATH === undefined ? 'is unset' : `holds ${JSON.stringify(process.env.PATH)}`);

/** What the directory meant to hold `path` holds, for a refusal of an absent path. */
export function parentOf(path) {
  const parent = dirname(resolve(path));
  try {
    const names = readdirSync(parent);
    return `${parent} exists and holds ${names.length} entr${names.length === 1 ? 'y' : 'ies'}${names.length ? `: ${names.join(', ')}` : ''}`;
  } catch (error) {
    return `${parent} cannot be listed either: ${error.code ?? error.message}`;
  }
}

/** The text of one input file, refused as the lint.input layer declares. */
export function readTextInput(path, what) {
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return refuse(INPUT, 'input-absent', { what, path, parent: parentOf(path), cwd: process.cwd() });
    if (error.code === 'EISDIR') return refuse(INPUT, 'input-is-directory', { what, path, state: stateOf(path) });
    return refuse(INPUT, 'input-not-permitted', { what, path, state: stateOf(path), error: error.message });
  }
}

/** A short, readable description of what a JSON value is. */
export function describe(value) {
  if (Array.isArray(value)) return `a list of ${value.length}`;
  if (value === null) return 'null';
  if (typeof value === 'object') return `an object with ${Object.keys(value).slice(0, 8).join(', ') || 'no key'}`;
  return `${typeof value} ${JSON.stringify(value)}`;
}

/**
 * Where the decoder stopped in `text`, as `line L, column C: <that line>`,
 * read from the position V8 names (`at position N`), the end for input cut
 * short, or the text V8 quotes around an unexpected token (tokenAt); a
 * decoder that names none of these is said as such.
 */
export function stopOf(text, message) {
  const named = /position (?<position>\d+)/.exec(message);
  const at = named ? Number(named.groups.position) : /end of (JSON )?input/i.test(message) ? text.length : tokenAt(text, message);
  if (at === null) return 'a place the decoder did not name';
  const before = text.slice(0, at).split('\n');
  const line = before.length;
  const column = before[line - 1].length + 1;
  const shown = text.split('\n')[line - 1] ?? '';
  return `line ${line}, column ${column}: ${JSON.stringify(shown)}`;
}

/**
 * Where an unexpected token stands in `text`. V8 names no position for one; it
 * quotes the whole text when it is shorter than 21 characters, else up to 10
 * characters each side of the token, `...` marking a cut
 * (https://github.com/v8/v8/blob/main/src/json/json-parser.cc,
 * ReportUnexpectedToken). The token is the 11th character of a quote cut on
 * the left and the 10th from the end of one cut only on the right; in a whole
 * quote it is where a prefix of the text first stops being JSON cut short.
 * Null when the message is no such quote.
 */
function tokenAt(text, message) {
  const quoted = /^Unexpected token '[\s\S]', (?<left>\.\.\.)?"(?<context>[\s\S]*)"(?<right>\.\.\.)? is not valid JSON$/.exec(message);
  if (quoted === null) return null;
  const { left, context, right } = quoted.groups;
  if (left !== undefined) {
    const start = text.indexOf(context);
    return start < 0 ? null : start + 10;
  }
  if (right !== undefined) return context.length - 10;
  for (let end = 1; end <= text.length; end += 1) {
    try {
      JSON.parse(text.slice(0, end));
    } catch (error) {
      // discarded: a prefix cut short fails too; only the first unexpected token is where the text stops
      if (error.message.startsWith('Unexpected token ')) return end - 1;
    }
  }
  return null;
}

/** A decoder's answer on one line: V8 quotes the text it stopped in, line breaks and all, which would break a refusal's three lines. */
export const oneLine = (answer) => answer.replaceAll('\n', '\\n');

/**
 * One JSON input file. `accept(value)` answers what the value holds that is
 * not `expected` (a sentence), or null when it is that.
 */
export function readJsonInput(path, what, expected, accept = () => null) {
  const text = readTextInput(path, what);
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    // The start shown is the file's first line, where a reader looks first,
    // not a chosen number of characters.
    return refuse(INPUT, 'input-not-json', { what, path, expected, bytes: String(Buffer.byteLength(text)), stop: stopOf(text, error.message), quoted_start: JSON.stringify(text.split('\n')[0]), error: oneLine(error.message) });
  }
  const found = accept(value);
  if (found !== null) refuse(INPUT, 'input-wrong-shape', { what, path, expected, found });
  return value;
}

/** An `accept` for readJsonInput: an object holding every one of `keys`, or which of them it lacks. */
export const holding = (...keys) => (value) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return describe(value);
  const missing = keys.filter((key) => value[key] === undefined || value[key] === null);
  return missing.length === 0 ? null : `${describe(value)}, lacking ${missing.join(', ')}`;
};

/** A directory a command reads, refused as the lint.paths layer declares. */
export function openDirectory(path, what) {
  let entry;
  try {
    entry = statSync(path);
  } catch (error) {
    if (error.code === 'ENOENT') return refuse(PATHS, 'path-absent', { what, path, parent: parentOf(path), cwd: process.cwd() });
    return refuse(PATHS, 'path-unreadable', { what, path, state: stateOf(path), error: error.message });
  }
  if (!entry.isDirectory()) refuse(PATHS, 'path-not-directory', { what, path, state: stateOf(path), directory: dirname(resolve(path)) });
  return entry;
}

/**
 * The names in a directory a command walks, refused when it cannot be listed.
 * Nothing at the path is refused as absent, not as a listing the operating
 * system refused: a path `--sources` names that does not exist is a typo, and
 * `chmod` cannot fix it.
 */
export function listDirectory(path, what) {
  try {
    return readdirSync(path, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return refuse(PATHS, 'path-absent', { what, path, parent: parentOf(path), cwd: process.cwd() });
    return refuse(PATHS, 'path-unreadable', { what, path, state: stateOf(path), error: error.message });
  }
}

/** One file of a tree a command walks, refused when it cannot be read, or as absent when nothing is at the path. */
export function readTreeFile(path, what) {
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return refuse(PATHS, 'path-absent', { what, path, parent: parentOf(path), cwd: process.cwd() });
    return refuse(PATHS, 'path-unreadable', { what, path, state: stateOf(path), error: error.message });
  }
}
