// The files and directories this repository's commands are named, read
// through the declared layers `wisent_errors.lint.input` (one JSON or text
// file) and `wisent_errors.lint.paths` (a directory or a tree to walk), so
// every command refuses an absent, unreadable or malformed input with the
// same sentence and the state it found.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { refuse } from './refuse.mjs';

const INPUT = 'wisent_errors.lint.input';
const PATHS = 'wisent_errors.lint.paths';

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
 * read from the position V8 names (`at position N`) or the end for input cut
 * short; a decoder that names neither is said as such.
 */
export function stopOf(text, message) {
  const named = /position (\d+)/.exec(message);
  const at = named ? Number(named[1]) : /end of (JSON )?input/i.test(message) ? text.length : null;
  if (at === null) return 'a place the decoder did not name';
  const before = text.slice(0, at).split('\n');
  const line = before.length;
  const column = before[line - 1].length + 1;
  const shown = text.split('\n')[line - 1] ?? '';
  return `line ${line}, column ${column}: ${JSON.stringify(shown)}`;
}

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
    return refuse(INPUT, 'input-not-json', { what, path, expected, bytes: String(Buffer.byteLength(text)), stop: stopOf(text, error.message), quoted_start: JSON.stringify(text.slice(0, 40)), error: error.message });
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

/** The names in a directory a command walks, refused when it cannot be listed. */
export function listDirectory(path, what) {
  try {
    return readdirSync(path, { withFileTypes: true });
  } catch (error) {
    return refuse(PATHS, 'path-unreadable', { what, path, state: stateOf(path), error: error.message });
  }
}

/** One file of a tree a command walks, refused when it cannot be read. */
export function readTreeFile(path, what) {
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    return refuse(PATHS, 'path-unreadable', { what, path, state: stateOf(path), error: error.message });
  }
}
