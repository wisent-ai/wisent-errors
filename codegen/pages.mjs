// Render docs/errors/<area>.md: every failure this package declares of its
// own, one page per area of catalogue/failures/ (an area may span parts in a
// subfolder, as lint/commands.json and lint/layers.json), each cause anchored
// where its refusal's `cause:` line points.

const RUNTIMES = { rust: 'Rust', js: 'JavaScript', python: 'Python', swift: 'Swift' };

function section(operation) {
  // A part gives entries as one list, or as one list per runtime.
  const listed = Array.isArray(operation.entries)
    ? operation.entries.map((entry) => `\`${entry}\``)
    : Object.entries(operation.entries).flatMap(([runtime, entries]) => entries.map((entry) => `${RUNTIMES[runtime] ?? runtime} \`${entry}\``));
  const entries = listed.length ? listed.join(', ') : 'run only by the functionalities that use it';
  const uses = operation.uses.length ? operation.uses.map((used) => `\`${typeof used === 'string' ? used : used.id}\``).join(', ') : 'none';
  let text = `## \`${operation.id}\`\n\n${operation.summary}\n\nStarted through: ${entries}. Uses: ${uses}.\n`;
  for (const cause of operation.causes) {
    const tests = cause.tests
      ? Object.entries(cause.tests).map(([runtime, test]) => `${RUNTIMES[runtime] ?? runtime} \`${test}\``).join(', ')
      : `\`${cause.test}\``;
    // The exits rust/src/codes.rs declares: a usage refusal exits 2, as clap's usage errors do
    // (https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit); a retryable code exits
    // EX_UNAVAILABLE, 69 (https://man.freebsd.org/cgi/man.cgi?query=sysexits); anything else exits its
    // declared status or 1, a failure (https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html).
    const exit = cause.usage ? 2 : ['rate_limit', 'timeout', 'infra_down'].includes(cause.code) ? 69 : cause.exit ?? 1;
    // The class the refusal prints, as rust/src/operation/causes/class.rs's `Class::of` names it: a
    // usage cause is `usage`, whatever code it carries.
    const kind = cause.usage ? 'usage' : cause.code;
    text +=
      `\n<a id="${operation.id.replaceAll('.', '-')}-${cause.id}"></a>\n\n### \`${operation.id}.${cause.id}\`\n\n` +
      `- **What failed:** ${cause.failed}\n` +
      `- **Cause:** ${cause.cause}\n` +
      `- **Observed state shown:** ${cause.observed}\n` +
      `- **Fix:** ${cause.remedy}\n` +
      `- **Class:** \`${kind}\`, exit ${exit}\n` +
      `- **Test:** ${tests}\n`;
  }
  return text;
}

/** One page per area, `{ area, body }`; the parts loader's own causes go on the tools page. */
export function pages(parts, loader) {
  const areas = new Map();
  for (const part of parts) {
    const list = areas.get(part.area) ?? [];
    list.push(...part.operations);
    areas.set(part.area, list);
  }
  const tools = areas.get('tools') ?? [];
  tools.push(loader);
  areas.set('tools', tools);
  return [...areas.entries()].map(([area, operations]) => ({
    area,
    body:
      `<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->\n\n` +
      `# wisent-errors' own failures: ${area}\n\nEvery way the ${area} functionalities of this package fail, as their refusals say it.\n\n` +
      operations.map(section).join('\n'),
  }));
}
