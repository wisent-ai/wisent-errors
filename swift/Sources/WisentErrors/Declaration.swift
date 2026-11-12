// Generated from catalogue/declaration.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

/// What a declared cause or warning must be, and the sentence each refusal
/// of a declaration says.
public enum Declaration {
    public static let placeholderPattern = "^[a-z][a-z0-9_]*$"
    public static let placeholderGrammar = "a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec"
    public static let rawMessageNames: [String] = ["error", "err", "e", "problem", "message", "body", "stderr", "stdout", "output", "raw", "response", "detail"]
    public static let causeIdPattern = "^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$"
    public static let testPathPattern = "^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$"
    public static let fieldMeanings: [String: String] = [
        "failed": "the step that failed, as its reader would name it",
        "cause": "why it failed, in words of its own",
        "observed": "the state the refusal shows: the path read, the values that do exist, what the layer below answered",
        "remedy": "what fixes it: the command to run, the declaration to change",
        "effect": "what the functionality is about to do",
        "consequence": "what cannot be had back afterwards, and whom it reaches",
        "safeguard": "what keeps a way back, done before confirming",
        "confirm": "how the caller confirms: the flag, the phrase, the button",
    ]
    public static let sentences: [String: String] = [
        "id-malformed": "{kind} {quoted_id}: the id is not lowercase words joined by '-' (pattern {pattern}); rename it, as in 'fleet-undeclared'",
        "field-empty": "{kind} {id}: `{field}` is empty; write {meaning}",
        "field-generic": "{kind} {id}: `{field}` says {quoted_text}, which {reason}; name the step, the cause and the fix instead",
        "placeholder-malformed": "{kind} {id}: `{field}` holds the placeholder {placeholder}, which the renderer never fills: a placeholder is {grammar}; write {suggestion} and have the raising site pass the value already formatted",
        "placeholder-unclosed": "{kind} {id}: `{field}` opens a placeholder at {quoted_text} that no '{close}' closes; close it as {example} or drop the '{open}'",
        "placeholder-unopened": "{kind} {id}: `{field}` holds a '{close}' at {quoted_text} that no '{open}' opened; drop it, or open the placeholder it ends",
        "placeholder-raw-message": "{kind} {id}: `{field}` names {placeholder}, the raw text of the layer below; `{field}` is the declaration's own words, so say it in words and move {placeholder} into `observed`",
        "cause-only-wrapped": "{kind} {id}: `cause` is only {quoted_text}, the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`",
        "code-unknown": "cause {id}: a declared cause is never `unknown`, the catch-all a declaration replaces; give it the code that names who must act: {codes}",
        "code-off-catalogue": "cause {id}: code {quoted_code} is not in the catalogue; use one of {codes}",
        "usage-retryable": "cause {id}: a usage refusal cannot be `{code}`, which is retryable; a usage refusal is refused for its own form, so give it a code retrying cannot help, or set usage to false",
        "exit-beside-derived": "cause {id}: exit {exit} is declared, but a usage refusal exits {usage_exit} and a retryable code {retry_exit}; drop the exit, or make the cause neither",
        "exit-not-own": "cause {id}: exit {exit} is not a status of its own: 0 is success, {usage_exit} usage and {retry_exit} retry; declare the product's documented status, or none",
        "test-malformed": "{kind} {id}: test {quoted_test} is not tests/<area>/<file>::<test name> (pattern {pattern}); name the real test that provokes it",
        "hazard-unknown": "warning {id}: hazard {quoted_hazard} is not one of {hazards}; pick the loss the caller cannot take back",
        "declared-twice": "operation {operation}: {kind} {id} is declared twice; keep one declaration per id",
        "operation-id-malformed": "operation {quoted_id}: the id is not a dotted lowercase path (pattern {pattern}); name the functionality by its failure point, as in 'stado.registry.read'",
        "entry-empty": "operation {operation}: entry {position} of {count} is empty; name the command, route, screen or routine that starts it, or drop the entry",
        "uses-itself": "operation {operation}: it lists itself in `uses`; list only the functionalities it runs",
        "summary-empty": "operation {operation}: `summary` is empty; say in one line what the functionality does",
        "docs-not-https": "operation {operation}: docs {quoted_docs} is not an https page; name the page that lists its causes",
        "no-cause": "operation {operation}: declares no cause and uses no functionality that declares one; declare every way its own steps fail, or list in `uses` the functionalities it runs",
        "operation-twice": "operation {operation} is declared twice in the catalogue; keep one declaration per id",
        "uses-unlisted": "operation {operation}: it uses {used}, which the catalogue does not list; list every functionality the product runs",
        "nothing-starts": "operation {operation}: nothing starts it: it names no entry and no functionality of the catalogue uses it; name the entry that starts it, or drop it",
        "listing-usage-exit": "operation {operation}: cause {id} is a usage refusal, which exits {usage_exit}, but the listing says exit {exit}; print the exit the cause leaves",
        "listing-retry-exit": "operation {operation}: cause {id} has the retryable code {code}, which exits {retry_exit}, but the listing says exit {exit}; print the exit the cause leaves",
        "listing-exit-not-failure": "operation {operation}: cause {id} lists exit {exit}, which is not a failure status (an integer other than 0); print the status the cause leaves a command with",
        "listing-doc-off-page": "operation {operation}: cause {id} links doc {quoted_doc}, which is not an anchor on the operation's page {docs}; print {docs}#{anchor}",
        "entries-not-list": "operation {operation}: `entries` is {found}, not a list; print every way the functionality is started",
        "uses-not-list": "operation {operation}: `uses` is {found}, not a list; print the ids of the functionalities it runs",
        "entry-uninventoried": "operation {operation}: it names the entry {quoted_entry}, which the {count} entries of {entries} do not hold; add it there, or drop it from the entries",
        "warnings-not-list": "operation {operation}: `warnings` is {found}, not a list; print the functionality's warnings, or an empty list",
        "warning-doc-not-anchor": "operation {operation}: warning {id} links doc {quoted_doc}, which is not an anchor on an https warnings page; print {page}#{anchor}, as the runtime's warnings listing writes it",
        "warning-test-absent": "{operation}.{id} names the test {test}, which the repository does not hold: {why}; write that test, or name the one that shows this warning (repository {repository})",
        "warning-unconfirmed": "operation {operation}: it declares {count} warning(s), but none of its entries ({entries}) asks for a confirmation in {confirmations}, so the warning is never read before it runs; ask for one, or drop a warning nothing needs (warnings {warnings}; {confirmations} lists {listed})",
    ]
    public static let probes: [String: (valid: [String], invalid: [String])] = [
        "placeholder": (valid: ["path", "fleet", "exit_status", "a1"], invalid: ["value:?", "error:#", "Path", "1st", "host-name", "deal.title", "", " name"]),
        "cause_id": (valid: ["fleet-undeclared", "input-absent", "exit2"], invalid: ["", "Fleet", "fleet_undeclared", "fleet--undeclared", "-fleet", "2fleet"]),
        "test_path": (valid: ["tests/fleet/enroll.rs::enroll_refuses", "tests/a/b/c.mjs::x_1"], invalid: ["purge.sh", "tests/x.rs::t", "tests/a//b.rs::t", "tests/a/b.rs::", "tests/a/b.rs::Bad", "src/a/b.rs::t"]),
    ]
}
