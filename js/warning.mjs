// A functionality's warnings, for JavaScript products: the same declaration
// the Rust crate's `warning` module holds, with the same rules and the same
// JSON, so a product in either language prints one shape and is held to one
// standard.
//
// A warning is what a functionality does when it goes right and its caller
// still loses something: an effect nothing undoes, access taken from someone,
// a secret let out, a change outside the product, money spent. It is declared
// on the operation (`warnings`), each `{ id, hazard, effect, consequence,
// safeguard, confirm, test }`. Most functionalities declare none: a warning on
// an ordinary read teaches its reader to confirm without reading.

import { CAUSE_ID_PATTERN, SENTENCES, TEST_PATH_PATTERN } from './declaration.mjs';
import { CAUSE_ID, TEST_PATH, textProblems } from './operation.mjs';
import { fill } from './template.mjs';

const say = (key, values) => fill(SENTENCES[key], values);

/** Every hazard a warning can announce, with what it means. */
export const HAZARDS = Object.freeze({
  irreversible: 'removes or rewrites something nothing in the product restores afterwards',
  overwrites: 'puts something else in place of the current state; what it replaces is kept only where the warning says',
  'cuts-off-access': 'a person or a program loses access it has now',
  'exposes-secret': 'a secret value leaves the place that protects it: a plain-text file, a screen, another person or system',
  'external-change': 'changes a system outside the product, which the product cannot undo',
  'costs-money': 'spends money',
});

/** The effect and what it costs, as one sentence. */
export function warningSentence(warning, values = {}) {
  return `${fill(warning.effect, values)}; ${fill(warning.consequence, values)}`;
}

/**
 * What a caller that has not confirmed reads: the warning, that nothing was
 * done, what keeps a way back and how to go ahead. A functionality answers
 * this only when it did nothing.
 */
export function unconfirmed(warning, values = {}) {
  return `${warningSentence(warning, values)}; nothing was done. Before confirming: ${fill(warning.safeguard, values)}. To go ahead: ${fill(warning.confirm, values)}`;
}

/** The anchor of a warning's entry on the warnings page. */
export function warningAnchor(operation, warning) {
  return `${operation.id.replaceAll('.', '-')}-warning-${warning.id}`;
}

/** Everything wrong with one warning's declaration, each as one sentence. */
export function warningProblems(warning) {
  const problems = [];
  const id = warning.id;
  if (typeof id !== 'string' || !CAUSE_ID.test(id)) problems.push(say('id-malformed', { kind: 'warning', quoted_id: JSON.stringify(id), pattern: CAUSE_ID_PATTERN }));
  if (!Object.hasOwn(HAZARDS, warning.hazard)) {
    problems.push(say('hazard-unknown', { id, quoted_hazard: JSON.stringify(warning.hazard), hazards: Object.keys(HAZARDS).join(', ') }));
  }
  problems.push(...textProblems('warning', id, ['effect', 'consequence', 'safeguard', 'confirm'].map((field) => [field, warning[field]])));
  if (typeof warning.test !== 'string' || !TEST_PATH.test(warning.test)) {
    problems.push(say('test-malformed', { kind: 'warning', id, quoted_test: JSON.stringify(warning.test), pattern: TEST_PATH_PATTERN }));
  }
  return problems;
}

/** Everything wrong with the warnings one functionality declares. */
export function warningDeclarationProblems(operation) {
  const problems = [];
  const warnings = operation.warnings ?? [];
  warnings.forEach((warning, index) => {
    if (warnings.slice(0, index).some((earlier) => earlier.id === warning.id)) problems.push(say('declared-twice', { operation: operation.id, kind: 'warning', id: warning.id }));
    for (const problem of warningProblems(warning)) problems.push(`operation ${operation.id}: ${problem}`);
  });
  return problems;
}

/**
 * The functionality's warnings as the JSON document every product prints from
 * `warnings list|show --json`, each linked to its entry on `page`.
 */
export function warningsCatalogue(operation, page) {
  return {
    operation: operation.id,
    entries: [...(operation.entries ?? [])],
    summary: operation.summary,
    warnings: (operation.warnings ?? []).map((warning) => ({
      id: warning.id,
      hazard: warning.hazard,
      effect: warning.effect,
      consequence: warning.consequence,
      safeguard: warning.safeguard,
      confirm: warning.confirm,
      test: warning.test,
      doc: `${page}#${warningAnchor(operation, warning)}`,
    })),
  };
}

/**
 * The functionality's section of the warnings page, one anchored entry per
 * warning; empty for one that declares none, because the page lists only what
 * warns.
 */
export function warningsMarkdown(operation) {
  const warnings = operation.warnings ?? [];
  if (warnings.length === 0) return '';
  const entries = (operation.entries ?? []).length
    ? operation.entries.map((entry) => `\`${entry}\``).join(', ')
    : 'run only by the functionalities that use it';
  let page = `## \`${operation.id}\`\n\n${operation.summary}\n\nStarted through: ${entries}. ${warnings.length} declared warning(s).\n`;
  for (const warning of warnings) {
    page +=
      `\n<a id="${warningAnchor(operation, warning)}"></a>\n\n### \`${operation.id}.${warning.id}\`\n\n` +
      `- **Kind:** \`${warning.hazard}\`: ${HAZARDS[warning.hazard]}\n` +
      `- **What it does:** ${warning.effect}\n` +
      `- **What cannot be had back:** ${warning.consequence}\n` +
      `- **Before confirming:** ${warning.safeguard}\n` +
      `- **To go ahead:** ${warning.confirm}\n` +
      `- **Test:** \`${warning.test}\`\n`;
  }
  return page;
}
