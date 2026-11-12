// The `{name}` templates a cause or a warning is written in: how the renderer
// reads them, and what in them it would never fill. The Rust crate's
// `operation::template`, Python's `template` and Swift's `Template.swift`
// read a template the same way, so the four runtimes fill and refuse alike.
//
// A template is read left to right. `{` opens a placeholder that the next
// `}` closes, unless another `{` comes first: then the first `{` never
// closes. What lies between the braces is a placeholder when it is a name
// (PLACEHOLDER_PATTERN); anything else there (`{value:?}`, `{Path}`) is kept
// as written and never filled. A `}` no `{` opened is kept as written.

import { PLACEHOLDER_GRAMMAR, PLACEHOLDER_PATTERN, RAW_MESSAGE_NAMES, SENTENCES } from './declaration.mjs';

const NAME = new RegExp(PLACEHOLDER_PATTERN);

/** Whether `name` is one the renderer fills. */
export const isPlaceholderName = (name) => NAME.test(name);

/** The template's parts: `{ text }`, `{ placeholder }`, `{ malformed }`, `{ unclosed }` or `{ unopened }`, in order. */
export function parts(template) {
  const found = [];
  let text = '';
  let index = 0;
  const flush = () => {
    if (text) found.push({ text });
    text = '';
  };
  while (index < template.length) {
    const character = template[index];
    if (character === '}') {
      flush();
      found.push({ unopened: '}' });
      index += 1;
    } else if (character === '{') {
      flush();
      const close = template.indexOf('}', index + 1);
      const reopen = template.indexOf('{', index + 1);
      if (close >= 0 && (reopen < 0 || close < reopen)) {
        const inside = template.slice(index + 1, close);
        found.push(isPlaceholderName(inside) ? { placeholder: inside } : { malformed: template.slice(index, close + 1) });
        index = close + 1;
      } else {
        const end = reopen < 0 ? template.length : reopen;
        found.push({ unclosed: template.slice(index, end) });
        index = end;
      }
    } else {
      text += character;
      index += 1;
    }
  }
  flush();
  return found;
}

const has = (values, name) => Object.prototype.hasOwnProperty.call(values, name);

/**
 * `template` with each `{name}` replaced by `values[name]`. A placeholder with
 * no value stays as written, so a value the raising code forgot is visible
 * in the sentence instead of silently becoming nothing; text the renderer
 * does not read as a placeholder stays as written too.
 */
export function fill(template, values = {}) {
  return parts(template)
    .map((part) => {
      if (part.placeholder === undefined) return part.text ?? part.malformed ?? part.unclosed ?? part.unopened;
      return has(values, part.placeholder) ? String(values[part.placeholder]) : `{${part.placeholder}}`;
    })
    .join('');
}

/** The names of the placeholders a template fills, in order of appearance. */
export const placeholders = (template) => parts(template).flatMap((part) => (part.placeholder === undefined ? [] : [part.placeholder]));

/** The placeholders of `templates` that `values` gives no value for, each once. */
export function unfilled(templates, values = {}) {
  const missing = [];
  for (const template of templates) {
    for (const name of placeholders(template)) if (!has(values, name) && !missing.includes(name)) missing.push(name);
  }
  return missing;
}

/** The name a malformed placeholder most likely meant: what precedes a format spec, lowercase, with '_' for anything else. */
export function suggestion(malformed) {
  const inside = malformed.slice(1, -1).split(/[:!]/)[0].toLowerCase().replace(/[^a-z0-9_]/g, '_').replace(/^[^a-z]+/, '');
  return `{${inside || 'value'}}`;
}

const say = (key, values) => fill(SENTENCES[key], values);

/**
 * Everything in one field's template the renderer would never fill or a
 * reader would never be helped by, each as one sentence. `kind` is `cause`
 * or `warning`; the raw-message rule binds a cause's `failed`, `cause` and
 * `remedy`, which are the declaration's own words.
 */
export function templateProblems(kind, id, field, template) {
  const problems = [];
  const base = { kind, id, field };
  const read = parts(template);
  for (const part of read) {
    if (part.malformed !== undefined) {
      problems.push(say('placeholder-malformed', { ...base, placeholder: part.malformed, grammar: PLACEHOLDER_GRAMMAR, suggestion: suggestion(part.malformed) }));
    } else if (part.unclosed !== undefined) {
      problems.push(say('placeholder-unclosed', { ...base, quoted_text: JSON.stringify(part.unclosed), example: '{name}', open: '{', close: '}' }));
    } else if (part.unopened !== undefined) {
      problems.push(say('placeholder-unopened', { ...base, quoted_text: JSON.stringify(template), open: '{', close: '}' }));
    } else if (part.placeholder !== undefined && kind === 'cause' && field !== 'observed' && RAW_MESSAGE_NAMES.includes(part.placeholder)) {
      problems.push(say('placeholder-raw-message', { ...base, placeholder: `{${part.placeholder}}` }));
    }
  }
  if (kind === 'cause' && field === 'cause') {
    const wraps = read.some((part) => part.text === undefined);
    const words = read.some((part) => part.text !== undefined && /\p{L}/u.test(part.text));
    if (wraps && !words) problems.push(say('cause-only-wrapped', { ...base, quoted_text: JSON.stringify(template) }));
  }
  return problems;
}
