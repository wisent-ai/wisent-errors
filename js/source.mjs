// The one line rule a product's lint scans its source with: the generic
// sentences inside the string literals of one line. The Rust crate's
// `operation::generic_sentences_in` applies the same rule.

import { GENERIC_SENTENCES } from './codes.mjs';

/**
 * The generic sentences inside the string literals of one source line.
 *
 * Comment lines are skipped: a comment explaining why a sentence is generic is
 * not an error message. `singleQuoted` also reads '...' as a literal, which is
 * right for JavaScript and Python and wrong for Rust and Swift.
 */
export function genericSentencesIn(line, singleQuoted) {
  const trimmed = line.trimStart();
  if (['//', '/*', '*', '#', '--'].some((marker) => trimmed.startsWith(marker))) return [];
  const found = [];
  for (const literal of literals(line, singleQuoted)) {
    const lower = literal.toLowerCase();
    for (const sentence of GENERIC_SENTENCES) {
      if (lower.includes(sentence.text) && !found.includes(sentence)) found.push(sentence);
    }
  }
  return found;
}

/** The quoted segments of one line, escapes kept. */
export function literals(line, singleQuoted) {
  const segments = [];
  let index = 0;
  while (index < line.length) {
    const quote = line[index];
    if (!(quote === '"' || quote === '`' || (singleQuoted && quote === "'"))) {
      index += 1;
      continue;
    }
    let end = index + 1;
    while (end < line.length && line[end] !== quote) end += line[end] === '\\' ? 2 : 1;
    end = Math.min(end, line.length);
    segments.push(line.slice(index + 1, end));
    index = end + 1;
  }
  return segments;
}
