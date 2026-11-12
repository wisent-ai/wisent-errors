// Render this package's own failure catalogue (catalogue/failures/) as the
// declarations each runtime raises its own failures from: the same causes,
// the same sentences, in every runtime that can meet them.
//
// Rust and Swift get one module per part of the catalogue, every cause a
// named declaration its raising site refers to, so no generated file grows
// past what a reader holds as the catalogue grows. JavaScript and Python hold
// one frozen object per operation and stay one file each.

import { constant } from './declaration.mjs';

const json = (value) => JSON.stringify(value);
const rustCode = (code) => code.split('_').map((part) => part[0].toUpperCase() + part.slice(1)).join('');
const swiftCode = (code) => code.replace(/_([a-z])/g, (_, next) => next.toUpperCase());
// The package prefix is every operation's, so it names nothing:
// `wisent_errors.envelope.build` is ENVELOPE_BUILD, and
// `wisent-errors.telemetry.store` is TELEMETRY_STORE.
const bare = (id) => id.replace(/^wisent[-_]errors\./, '');
const short = (operation) => constant(bare(operation.id));
const camel = (text) => text.replace(/[._-]([a-z0-9])/g, (_, next) => next.toUpperCase());
const pascal = (text) => camel(text).replace(/^[a-z]/, (first) => first.toUpperCase());
const rustCause = (operation, cause) => `${short(operation)}_${constant(cause.id)}`;
const swiftOperation = (operation) => camel(bare(operation.id));
const swiftCause = (operation, cause) => `${swiftOperation(operation)}${pascal(cause.id)}`;

/** The Rust module of one part: `cli-output` is `cli_output`. */
export const rustModule = (area) => area.replace(/-/g, '_');

/** The Swift file of one part: `telemetry` is OwnFailuresTelemetry.swift. */
export const swiftFile = (area) => `OwnFailures${pascal(area)}.swift`;

/**
 * One runtime's operations grouped by the part declaring them, in the parts'
 * order, each `{ area, source, operations }`.
 */
export function byArea(operations, parts) {
  const declaring = new Map();
  for (const part of parts) {
    for (const operation of part.operations) declaring.set(operation.id, part);
  }
  const areas = new Map();
  for (const operation of operations) {
    const part = declaring.get(operation.id);
    const area = areas.get(part.area) ?? { area: part.area, source: `catalogue/failures/${part.path.split('/').pop()}`, operations: [] };
    area.operations.push(operation);
    areas.set(part.area, area);
  }
  return [...areas.values()];
}

export function failuresJs({ operations, banner }) {
  const body = operations.map((operation) => `export const ${short(operation)} = Object.freeze(${JSON.stringify(operation, null, 2)});`).join('\n\n');
  return `${banner('//', 'catalogue/failures/')}

${body}
`;
}

export function failuresPython({ operations, banner }) {
  const body = operations.map((operation) => `${short(operation)} = Operation.from_dict(json.loads(r"""${JSON.stringify(operation)}"""))`).join('\n\n');
  return `${banner('#', 'catalogue/failures/')}

import json

from .operation import Operation

${body}
`;
}

/** rust/src/failures/mod.rs: one module per part, every declaration re-exported. */
export function failuresRustModule(areas, banner) {
  const modules = areas.map(({ area }) => rustModule(area));
  return `${banner('//', 'catalogue/failures/')}

//! This crate's own failures, declared like any product's: one module per
//! part of catalogue/failures/, each declaration named here.

${modules.map((module) => `mod ${module};`).join('\n')}

${modules.map((module) => `pub use ${module}::*;`).join('\n')}
`;
}

/** rust/src/failures/<area>.rs: the causes and operations of one part. */
export function failuresRust({ area, source, operations }, banner) {
  const out = [];
  for (const operation of operations) {
    for (const cause of operation.causes) {
      out.push(`pub static ${rustCause(operation, cause)}: Cause = Cause {
    id: ${json(cause.id)},
    code: Code::${rustCode(cause.code)},
    usage: ${cause.usage},
    exit: ${cause.exit === null ? 'None' : `Some(${cause.exit})`},
    failed: ${json(cause.failed)},
    cause: ${json(cause.cause)},
    observed: ${json(cause.observed)},
    remedy: ${json(cause.remedy)},
    test: ${json(cause.test)},
};`);
    }
    out.push(`pub static ${short(operation)}: Operation = Operation {
    id: ${json(operation.id)},
    entries: &[${operation.entries.map(json).join(', ')}],
    uses: &[${operation.uses.map((used) => `&super::${short(used)}`).join(', ')}],
    summary: ${json(operation.summary)},
    docs: ${json(operation.docs)},
    causes: &[${operation.causes.map((cause) => `&${rustCause(operation, cause)}`).join(', ')}],
    warnings: &[],
};`);
  }
  return `${banner('//', source)}

//! This crate's own failures of the ${area} functionalities.

use crate::{Cause, Code, Operation};

${out.join('\n\n')}
`;
}

/** swift/Sources/WisentErrors/Own/OwnFailures.swift: the namespace each part's file extends. */
export function failuresSwiftNamespace(areas, banner) {
  return `${banner('//', 'catalogue/failures/')}

/// This package's own failures, declared like any product's: each part of
/// catalogue/failures/ extends it from its own file (${areas.map(({ area }) => swiftFile(area)).join(', ')}).
public enum OwnFailures {}
`;
}

/** swift/Sources/WisentErrors/Own/OwnFailures<Area>.swift: the causes and operations of one part. */
export function failuresSwift({ source, operations }, banner) {
  const out = [];
  for (const operation of operations) {
    for (const cause of operation.causes) {
      out.push(`    public static let ${swiftCause(operation, cause)} = Cause(
        id: ${json(cause.id)}, code: .${swiftCode(cause.code)}, usage: ${cause.usage}, exit: ${cause.exit === null ? 'nil' : cause.exit},
        failed: ${json(cause.failed)},
        cause: ${json(cause.cause)},
        observed: ${json(cause.observed)},
        remedy: ${json(cause.remedy)},
        test: ${json(cause.test)}
    )`);
    }
    out.push(`    public static let ${swiftOperation(operation)} = Operation(
        id: ${json(operation.id)},
        entries: ${json(operation.entries).replaceAll('","', '", "')},
        uses: [${operation.uses.map(swiftOperation).join(', ')}],
        summary: ${json(operation.summary)},
        docs: ${json(operation.docs)},
        causes: [${operation.causes.map((cause) => swiftCause(operation, cause)).join(', ')}]
    )`);
  }
  return `${banner('//', source)}

extension OwnFailures {
${out.join('\n\n')}
}
`;
}
