// Why a caught value failed, as one line: the sentence every Wisent program
// writes into a refusal's observed state or a log when it catches something.

/**
 * Why a caught value failed: an Error's message followed by each `cause` under
 * it, said once, or the value itself as text (an object as its JSON). Node's
 * fetch throws "fetch failed" and keeps the refused connection or the
 * unresolved host in `cause`, and a PostgREST error is a plain object that
 * String() says as "[object Object]"; the message alone said only that. The
 * chain is read until it ends or comes back to a cause already said.
 */
export function causeOf(error) {
  if (!(error instanceof Error)) return valueText(error);
  const said = [error.message];
  let cause = error.cause;
  for (const seen = new Set(); cause !== undefined && cause !== null && !seen.has(cause) && seen.add(cause); ) {
    if (!(cause instanceof Error)) {
      said.push(valueText(cause));
      break;
    }
    const text = cause.message;
    if (text && !said.some((sentence) => sentence.includes(text))) said.push(text);
    cause = cause.cause;
  }
  return said.join(': ');
}

/** A thrown value that is not an Error, as text: an object as its JSON. */
function valueText(value) {
  if (value === null || typeof value !== 'object') return String(value);
  return JSON.stringify(value) ?? String(value);
}
