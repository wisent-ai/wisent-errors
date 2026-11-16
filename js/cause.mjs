// Why a caught value failed, as one line: the sentence every Wisent program
// writes into a refusal's observed state or a log when it catches something.

/**
 * Why a caught value failed: an Error's message followed by each `cause` under
 * it, said once, or the value itself as text (an object as its JSON). Node's
 * fetch throws "fetch failed" and keeps the refused connection or the
 * unresolved host in `cause`, and a PostgREST error is a plain object that
 * String() says as "[object Object]"; the message alone said only that. The
 * chain is read until it ends or comes back to a cause already said. An empty
 * message says nothing, so an Error whose chain says nothing is its name.
 */
export function causeOf(error) {
  if (!(error instanceof Error)) return valueText(error);
  const said = [];
  const say = (text) => {
    if (text && !said.some((sentence) => sentence.includes(text))) said.push(text);
  };
  say(error.message);
  let cause = error.cause;
  for (const seen = new Set(); cause !== undefined && cause !== null && !seen.has(cause) && seen.add(cause); ) {
    if (!(cause instanceof Error)) {
      say(valueText(cause));
      break;
    }
    say(cause.message);
    cause = cause.cause;
  }
  return said.length > 0 ? said.join(': ') : error.name;
}

/**
 * A thrown value that is not an Error, as text: an object as its JSON, a
 * bigint in it as its digits and an object that holds itself as
 * "[Circular]", which JSON.stringify would throw on, ending the caller's
 * catch with a failure of its own.
 */
function valueText(value) {
  if (value === null || typeof value !== 'object') return String(value);
  const ancestors = [];
  const text = JSON.stringify(value, function (_key, item) {
    if (typeof item === 'bigint') return item.toString();
    if (item === null || typeof item !== 'object') return item;
    while (ancestors.length > 0 && ancestors.at(-1) !== this) ancestors.pop();
    if (ancestors.includes(item)) return '[Circular]';
    ancestors.push(item);
    return item;
  });
  return text ?? String(value);
}
