// Generated from catalogue/declaration.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

//! What a declared cause or warning must be, and the sentence each refusal
//! of a declaration says.

pub const PLACEHOLDER_PATTERN: &str = "^[a-z][a-z0-9_]*$";
pub const PLACEHOLDER_GRAMMAR: &str = "a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec";
pub const RAW_MESSAGE_NAMES: &[&str] = &["error","err","e","problem","message","body","stderr","stdout","output","raw","response","detail"];
pub const CAUSE_ID_PATTERN: &str = "^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$";
pub const TEST_PATH_PATTERN: &str = "^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$";

/// What a declaration field holds, as a refusal of an empty one says.
pub fn field_meaning(field: &str) -> &'static str {
    match field {
        "failed" => "the step that failed, as its reader would name it",
        "cause" => "why it failed, in words of its own",
        "observed" => "the state the refusal shows: the path read, the values that do exist, what the layer below answered",
        "remedy" => "what fixes it: the command to run, the declaration to change",
        "effect" => "what the functionality is about to do",
        "consequence" => "what cannot be had back afterwards, and whom it reaches",
        "safeguard" => "what keeps a way back, done before confirming",
        "confirm" => "how the caller confirms: the flag, the phrase, the button",
        _ => "the text the declaration states",
    }
}

pub const ID_MALFORMED: &str = "{kind} {quoted_id}: the id is not lowercase words joined by '-' (pattern {pattern}); rename it, as in 'fleet-undeclared'";
pub const FIELD_EMPTY: &str = "{kind} {id}: `{field}` is empty; write {meaning}";
pub const FIELD_GENERIC: &str = "{kind} {id}: `{field}` says {quoted_text}, which {reason}; name the step, the cause and the fix instead";
pub const PLACEHOLDER_MALFORMED: &str = "{kind} {id}: `{field}` holds the placeholder {placeholder}, which the renderer never fills: a placeholder is {grammar}; write {suggestion} and have the raising site pass the value already formatted";
pub const PLACEHOLDER_UNCLOSED: &str = "{kind} {id}: `{field}` opens a placeholder at {quoted_text} that no '{close}' closes; close it as {example} or drop the '{open}'";
pub const PLACEHOLDER_UNOPENED: &str = "{kind} {id}: `{field}` holds a '{close}' at {quoted_text} that no '{open}' opened; drop it, or open the placeholder it ends";
pub const PLACEHOLDER_RAW_MESSAGE: &str = "{kind} {id}: `{field}` names {placeholder}, the raw text of the layer below; `{field}` is the declaration's own words, so say it in words and move {placeholder} into `observed`";
pub const CAUSE_ONLY_WRAPPED: &str = "{kind} {id}: `cause` is only {quoted_text}, the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`";
pub const CODE_UNKNOWN: &str = "cause {id}: a declared cause is never `unknown`, the catch-all a declaration replaces; give it the code that names who must act: {codes}";
pub const CODE_OFF_CATALOGUE: &str = "cause {id}: code {quoted_code} is not in the catalogue; use one of {codes}";
pub const USAGE_RETRYABLE: &str = "cause {id}: a usage refusal cannot be `{code}`, which is retryable; a usage refusal is refused for its own form, so give it a code retrying cannot help, or set usage to false";
pub const EXIT_BESIDE_DERIVED: &str = "cause {id}: exit {exit} is declared, but a usage refusal exits {usage_exit} and a retryable code {retry_exit}; drop the exit, or make the cause neither";
pub const EXIT_NOT_OWN: &str = "cause {id}: exit {exit} is not a status of its own: 0 is success, {usage_exit} usage and {retry_exit} retry; declare the product's documented status, or none";
pub const TEST_MALFORMED: &str = "{kind} {id}: test {quoted_test} is not tests/<area>/<file>::<test name> (pattern {pattern}); name the real test that provokes it";
pub const HAZARD_UNKNOWN: &str = "warning {id}: hazard {quoted_hazard} is not one of {hazards}; pick the loss the caller cannot take back";
pub const DECLARED_TWICE: &str = "operation {operation}: {kind} {id} is declared twice; keep one declaration per id";
pub const OPERATION_ID_MALFORMED: &str = "operation {quoted_id}: the id is not a dotted lowercase path (pattern {pattern}); name the functionality by its failure point, as in 'stado.registry.read'";
pub const ENTRY_EMPTY: &str = "operation {operation}: entry {position} of {count} is empty; name the command, route, screen or routine that starts it, or drop the entry";
pub const USES_ITSELF: &str = "operation {operation}: it lists itself in `uses`; list only the functionalities it runs";
pub const SUMMARY_EMPTY: &str = "operation {operation}: `summary` is empty; say in one line what the functionality does";
pub const DOCS_NOT_HTTPS: &str = "operation {operation}: docs {quoted_docs} is not an https page; name the page that lists its causes";
pub const NO_CAUSE: &str = "operation {operation}: declares no cause and uses no functionality that declares one; declare every way its own steps fail, or list in `uses` the functionalities it runs";
pub const OPERATION_TWICE: &str = "operation {operation} is declared twice in the catalogue; keep one declaration per id";
pub const USES_UNLISTED: &str = "operation {operation}: it uses {used}, which the catalogue does not list; list every functionality the product runs";
pub const NOTHING_STARTS: &str = "operation {operation}: nothing starts it: it names no entry and no functionality of the catalogue uses it; name the entry that starts it, or drop it";
pub const LISTING_USAGE_EXIT: &str = "operation {operation}: cause {id} is a usage refusal, which exits {usage_exit}, but the listing says exit {exit}; print the exit the cause leaves";
pub const LISTING_RETRY_EXIT: &str = "operation {operation}: cause {id} has the retryable code {code}, which exits {retry_exit}, but the listing says exit {exit}; print the exit the cause leaves";
pub const LISTING_EXIT_NOT_FAILURE: &str = "operation {operation}: cause {id} lists exit {exit}, which is not a failure status (an integer other than 0); print the status the cause leaves a command with";
pub const LISTING_DOC_OFF_PAGE: &str = "operation {operation}: cause {id} links doc {quoted_doc}, which is not an anchor on the operation's page {docs}; print {docs}#{anchor}";
pub const ENTRIES_NOT_LIST: &str = "operation {operation}: `entries` is {found}, not a list; print every way the functionality is started";
pub const USES_NOT_LIST: &str = "operation {operation}: `uses` is {found}, not a list; print the ids of the functionalities it runs";
pub const ENTRY_UNINVENTORIED: &str = "operation {operation}: it names the entry {quoted_entry}, which the {count} entries of {entries} do not hold; add it there, or drop it from the entries";
pub const WARNINGS_NOT_LIST: &str = "operation {operation}: `warnings` is {found}, not a list; print the functionality's warnings, or an empty list";
pub const WARNING_DOC_NOT_ANCHOR: &str = "operation {operation}: warning {id} links doc {quoted_doc}, which is not an anchor on an https warnings page; print {page}#{anchor}, as the runtime's warnings listing writes it";
pub const WARNING_TEST_ABSENT: &str = "{operation}.{id} names the test {test}, which the repository does not hold: {why}; write that test, or name the one that shows this warning (repository {repository})";
pub const WARNING_UNCONFIRMED: &str = "operation {operation}: it declares {count} warning(s), but none of its entries ({entries}) asks for a confirmation in {confirmations}, so the warning is never read before it runs; ask for one, or drop a warning nothing needs (warnings {warnings}; {confirmations} lists {listed})";

pub const PLACEHOLDER_VALID: &[&str] = &["path","fleet","exit_status","a1"];
pub const PLACEHOLDER_INVALID: &[&str] = &["value:?","error:#","Path","1st","host-name","deal.title",""," name"];
pub const CAUSE_ID_VALID: &[&str] = &["fleet-undeclared","input-absent","exit2"];
pub const CAUSE_ID_INVALID: &[&str] = &["","Fleet","fleet_undeclared","fleet--undeclared","-fleet","2fleet"];
pub const TEST_PATH_VALID: &[&str] = &["tests/fleet/enroll.rs::enroll_refuses","tests/a/b/c.mjs::x_1"];
pub const TEST_PATH_INVALID: &[&str] = &["purge.sh","tests/x.rs::t","tests/a//b.rs::t","tests/a/b.rs::","tests/a/b.rs::Bad","src/a/b.rs::t"];
