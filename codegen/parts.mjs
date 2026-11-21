// This package's own failure catalogue, read from the parts under
// catalogue/failures/: JSON files at any depth (lint/commands.json,
// lint/layers.json), each `{ area, operations }`, read in the order of their
// paths below it. A JSON file has no include of its own, so the catalogue is
// a directory and this is the one loader that reads it, for the generator
// and for the commands that raise these failures. Subfolders keep each
// folder small; an area may span several parts.
//
// The loader declares its own causes here, in code, because they are what it
// says when the parts themselves cannot be read.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const FAILURES = join(dirname(fileURLToPath(import.meta.url)), '..', 'catalogue', 'failures');
const DOCS = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';

const cause = (id, failed, why, observed, remedy, test) => ({
  id, code: 'config', usage: false, exit: null, failed, cause: why, observed, remedy, test: `tests/tools/parts.mjs::${test}`,
});

/** The loader's own functionality and every way it fails. */
export const PARTS = Object.freeze({
  id: 'wisent_errors.catalogue.parts',
  entries: [],
  uses: [],
  summary: 'read the parts of this package\'s own failure catalogue in catalogue/failures/ and join them into one catalogue',
  docs: DOCS,
  warnings: [],
  causes: [
    cause('parts-unlisted', 'listing the failure catalogue parts in {directory}', 'the directory cannot be listed, so no part of the catalogue can be read', '{state}; the operating system answered {error}', 'restore it with `git checkout -- catalogue/failures`, or let the user running the command read it', 'an_unlisted_parts_directory_is_refused'),
    cause('parts-absent', 'reading the failure catalogue parts in {directory}', 'the directory holds no .json part, so this package would declare none of its own failures', 'it holds {listing}', 'restore the parts with `git checkout -- catalogue/failures`', 'a_parts_directory_with_no_part_is_refused'),
    cause('part-unreadable', 'reading the failure catalogue part {path}', 'the part is listed but cannot be read', '{state}; the operating system answered {error}', 'let the user running the command read it (chmod u+r {path}), or restore it with `git checkout -- {path}`', 'an_unreadable_part_is_refused'),
    cause('part-not-json', 'reading the failure catalogue part {path}', 'the part is not JSON', '{bytes} bytes; the decoder answered {error}', 'correct the JSON of {path}; `jq . {path}` points at the place it stops parsing', 'a_part_that_is_not_json_is_refused'),
    cause('part-wrong-shape', 'reading the failure catalogue part {path}', 'the part is JSON but not an object with an area and a list of operations, each with an id, runtimes, entries (one list, or one list per runtime) and causes carrying their tests', 'at {where} it holds {found}', 'write {path} as an object with "area" and "operations", the way the other parts are written', 'a_part_of_the_wrong_shape_is_refused'),
    cause('operation-declared-twice', 'reading the failure catalogue parts in {directory}', 'the operation {operation} is declared in both {first} and {second}', '{parts} part(s) read', 'keep {operation} in one part and delete it from the other', 'an_operation_declared_in_two_parts_is_refused'),
    cause('uses-undeclared', 'joining the failure catalogue parts in {directory}', 'the operation {operation} uses {used}, which no part declares', 'declared operations: {declared}', 'declare {used} in a part, or take it out of the uses of {operation}', 'a_use_no_part_declares_is_refused'),
    cause('raised-undeclared', 'raising {raised}', 'the command raises a cause that no part of catalogue/failures/ declares, so it has no sentence, code or test', '{declared}', 'declare {raised} in its part of catalogue/failures/, or raise the cause that is declared', 'a_raised_cause_no_part_declares_is_refused'),
  ],
});

/** A refusal of the loader, as an error the caller raises like any other. */
export class PartsError extends Error {
  constructor(causeId, values) {
    const declared = PARTS.causes.find((candidate) => candidate.id === causeId);
    super(causeId);
    this.operation = PARTS;
    this.declared = declared;
    this.values = values;
  }
}

const describe = (value) => (value === undefined ? 'nothing' : Array.isArray(value) ? `a list of ${value.length}` : value === null ? 'null' : typeof value === 'object' ? `an object with ${Object.keys(value).join(', ') || 'no key'}` : `${typeof value} ${JSON.stringify(value)}`);

function stateOf(path) {
  try {
    const entry = statSync(path);
    return `${path} is a ${entry.isDirectory() ? 'directory' : 'file'} of mode ${(entry.mode & 0o777).toString(8)}, owner uid ${entry.uid}`;
  } catch (error) {
    return `${path} cannot be examined: ${error.code ?? error.message}`;
  }
}

function shapeProblem(part) {
  if (part === null || typeof part !== 'object' || Array.isArray(part)) return ['the part', describe(part)];
  if (typeof part.area !== 'string' || !part.area) return ['area', describe(part.area)];
  if (!Array.isArray(part.operations)) return ['operations', describe(part.operations)];
  for (const [index, operation] of part.operations.entries()) {
    const where = `operations[${index}]`;
    if (typeof operation?.id !== 'string') return [`${where}.id`, describe(operation?.id)];
    if (!Array.isArray(operation.runtimes)) return [`${where}.runtimes`, describe(operation.runtimes)];
    const entries = operation.entries;
    if (!Array.isArray(entries)) {
      if (entries === null || typeof entries !== 'object') return [`${where}.entries`, describe(entries)];
      for (const [runtime, list] of Object.entries(entries)) {
        if (!Array.isArray(list)) return [`${where}.entries.${runtime}`, describe(list)];
      }
    }
    if (!Array.isArray(operation.causes)) return [`${where}.causes`, describe(operation.causes)];
    for (const [position, declared] of operation.causes.entries()) {
      const tests = declared?.tests;
      if (tests === null || typeof tests !== 'object' || Object.keys(tests).length === 0) return [`${where}.causes[${position}].tests`, describe(tests)];
    }
  }
  return null;
}

/** What `folder` holds, or the loader's refusal naming the folder that cannot be listed. */
function listed(folder) {
  try {
    return readdirSync(folder, { withFileTypes: true });
  } catch (error) {
    throw new PartsError('parts-unlisted', { directory: folder, state: stateOf(folder), error: error.message });
  }
}

/** The .json parts among `entries` of `below` (relative to `directory`) and every folder under it, as `/`-joined paths below `directory`. */
function partFiles(directory, below, entries) {
  const files = [];
  for (const entry of entries) {
    const relative = below === '' ? entry.name : `${below}/${entry.name}`;
    if (entry.isDirectory()) files.push(...partFiles(directory, relative, listed(join(directory, relative))));
    else if (entry.name.endsWith('.json')) files.push(relative);
  }
  return files;
}

/** Every part at any depth, in the order of their paths below `directory`, each `{ path, file, area, operations }` (`file` is the path below it). */
export function readParts(directory = FAILURES) {
  const names = listed(directory);
  const files = partFiles(directory, '', names).sort();
  if (files.length === 0) throw new PartsError('parts-absent', { directory, listing: names.length ? names.map((entry) => entry.name).join(', ') : 'nothing' });
  const parts = [];
  const seen = new Map();
  for (const file of files) {
    const path = join(directory, file);
    let text;
    try {
      text = readFileSync(path, 'utf8');
    } catch (error) {
      throw new PartsError('part-unreadable', { path, state: stateOf(path), error: error.message });
    }
    let part;
    try {
      part = JSON.parse(text);
    } catch (error) {
      throw new PartsError('part-not-json', { path, bytes: String(Buffer.byteLength(text)), error: error.message });
    }
    const wrong = shapeProblem(part);
    if (wrong !== null) {
      const [where, found] = wrong;
      throw new PartsError('part-wrong-shape', { path, where, found });
    }
    for (const operation of part.operations) {
      if (seen.has(operation.id)) {
        throw new PartsError('operation-declared-twice', { directory, operation: operation.id, first: seen.get(operation.id), second: path, parts: String(files.length) });
      }
      seen.set(operation.id, path);
    }
    parts.push({ path, file, area: part.area, operations: part.operations });
  }
  return parts;
}

/**
 * The operations one runtime declares, as the library's Operation shape: a
 * cause is kept when it names a test in that runtime (`node`, this
 * repository's own commands, is tested in JavaScript: `tests.js`), entries
 * are the operation's list or that runtime's own list when the part gives one
 * per runtime, `uses` hold the operations themselves, and `extra` operations
 * (the loader's own) are joined in so a part may use them.
 */
export function operationsFor(runtime, parts, extra = []) {
  const testKey = runtime === 'node' ? 'js' : runtime;
  // Copies: `uses` is resolved in place below, and the loader's own PARTS is frozen.
  const declared = extra.map((operation) => ({ ...operation, uses: [...operation.uses] }));
  for (const part of parts) {
    for (const operation of part.operations) {
      if (!operation.runtimes.includes(runtime)) continue;
      declared.push({
        id: operation.id,
        entries: Array.isArray(operation.entries) ? [...operation.entries] : [...(operation.entries[testKey] ?? [])],
        uses: [...operation.uses],
        summary: operation.summary,
        docs: operation.docs,
        warnings: [],
        causes: operation.causes
          .filter((candidate) => candidate.tests[testKey] !== undefined)
          .map(({ tests, ...rest }) => ({ ...rest, exit: rest.exit ?? null, test: tests[testKey] })),
      });
    }
  }
  const byId = new Map(declared.map((operation) => [operation.id, operation]));
  for (const operation of declared) {
    operation.uses = operation.uses.map((used) => {
      if (typeof used !== 'string') return used;
      const found = byId.get(used);
      if (found === undefined) {
        throw new PartsError('uses-undeclared', { directory: FAILURES, operation: operation.id, used, declared: [...byId.keys()].join(', ') });
      }
      return found;
    });
  }
  return declared;
}
