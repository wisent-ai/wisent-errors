# Runbook

What red looks like, captured for real. Every failure below was produced
by breaking a scratch copy of this repository and running the gate —
nothing here is imagined output. Make such a copy the same way when you
need to reproduce one:

```bash
SCRATCH=$(mktemp -d)
git archive HEAD | tar -x -C "$SCRATCH"
cd "$SCRATCH"
```

The gate is one command, `node ci/check.mjs`; the healthy run is in
[walkthrough-conformance](walkthrough-conformance.md). Each section:
symptom, meaning, action.

## A runtime drifted from the catalogue

The scratch copy's `js/codes.mjs` was edited by hand — `rate_limit`'s
severity changed from `warning` to `error`, the exact class of defect five
of six hand-kept copies developed in the wild. The gate, in full:

```
$ node ci/check.mjs
FAIL  generated code matches the catalogue
        unchanged  rust/src/codes.rs
unchanged  python/wisent_errors/codes.py
DRIFTED    js/codes.mjs
unchanged  swift/Sources/WisentErrors/Codes.swift

generated code does not match the catalogue; run codegen/generate.mjs
ok    schema and catalogue name the same codes
ok    schema and catalogue name the same severities
ok    the failure point pattern is stated once
ok    every golden envelope obeys the schema
FAIL  runtimes agree
        ok    credential-refused  (js, python, rust, swift)
FAIL  throttled
  expected  {"failure_point":"brama.dispatch.bounded-rotation","error_code":"rate_limit","service":"brama","impact":"one model request","severity":"warning","retryable":true,"outage":false,"detail":"all bounded 'codex' credentials unavailable for agent"}
  js        {"failure_point":"brama.dispatch.bounded-rotation","error_code":"rate_limit","service":"brama","impact":"one model request","severity":"error","retryable":true,"outage":false,"detail":"all bounded 'codex' credentials unavailable for agent"}
ok    store-unreachable  (js, python, rust, swift)
FAIL  nested-refusal
  expected  {"failure_point":"brama.dispatch.bounded-rotation","error_code":"rate_limit","service":"brama","impact":"one model request","severity":"warning","retryable":true,"outage":false,"detail":"all bounded 'claude-code' credentials unavailable for agent","cause":{"failure_point":"brama.gateway.oauth-refresh","error_code":"auth","service":"brama","impact":"one credential refresh","severity":"warning","retryable":false,"outage":false,"detail":"invalid_grant -- Refresh token not found or invalid"}}
  js        {"failure_point":"brama.dispatch.bounded-rotation","error_code":"rate_limit","service":"brama","impact":"one model request","severity":"error","retryable":true,"outage":false,"detail":"all bounded 'claude-code' credentials unavailable for agent","cause":{"failure_point":"brama.gateway.oauth-refresh","error_code":"auth","service":"brama","impact":"one credential refresh","severity":"warning","retryable":false,"outage":false,"detail":"invalid_grant -- Refresh token not found or invalid"}}
ok    silent-skip  (js, python, rust, swift)
ok    unattributed  (js, python, rust, swift)
ok    quiet-refusal  (js, python, rust, swift)
ok    single-segment  (js, python, rust, swift)
ok    deep-segment  (js, python, rust, swift)
ok    salvaged-malformed  (js, python, rust, swift)
ok    salvaged-absent  (js, python, rust, swift)
TABLE DIFFERS  python vs js
  python    code=rate_limit	severity=warning	retryable=true	outage=false	http_status=429	exit_code=69	operator_summary=an upstream is throttling us
  js        code=rate_limit	severity=error	retryable=true	outage=false	http_status=429	exit_code=69	operator_summary=an upstream is throttling us
TABLE DIFFERS  rust vs js
  rust      code=rate_limit	severity=warning	retryable=true	outage=false	http_status=429	exit_code=69	operator_summary=an upstream is throttling us
  js        code=rate_limit	severity=error	retryable=true	outage=false	http_status=429	exit_code=69	operator_summary=an upstream is throttling us
TABLE DIFFERS  swift vs js
  swift     code=rate_limit	severity=warning	retryable=true	outage=false	http_status=429	exit_code=69	operator_summary=an upstream is throttling us
  js        code=rate_limit	severity=error	retryable=true	outage=false	http_status=429	exit_code=69	operator_summary=an upstream is throttling us
ok    derived vocabulary  (45 rows, js, python, rust, swift)

11 case(s) + 45 vocabulary row(s), 5 failing

2 check(s) failed
$ echo $?
1
```

Reading it: `DRIFTED js/codes.mjs` names the file whose bytes are no
longer what the catalogue derives; the `FAIL <case>` pairs show exactly
which bytes differ and in which runtime (only the golden cases carrying a
`rate_limit` envelope fail — `severity":"error"` where the column says
`"warning"`); the `TABLE DIFFERS` triplets show the drifted vocabulary row
against every other runtime. One caveat: the trailing
`ok    derived vocabulary` line records only that all four runtimes dumped
a table — the `TABLE DIFFERS` lines above it are the verdict, and they are
counted in `5 failing`.

**Action.** A generated file is never edited by hand. If the drift was an
accidental edit, `git checkout -- <file>`. If you meant to change the
vocabulary, change `catalogue/codes.json`, run
`node codegen/generate.mjs` (all four targets print `written`), update the
golden column in `tests/conformance/cases.tsv` for affected cases, and
rerun the gate.

## The gate says DRIFTED, everything else is green

Same first check as above with the harness still passing — the drift is in
a spot no golden case exercises (a comment, an operator summary). The
meaning and the action are the same: the generator is the only writer of
those files.

## Schema and catalogue disagree

The scratch copy's `schema/failure.schema.json` gained a fourth severity:

```
$ node ci/check.mjs
ok    generated code matches the catalogue
ok    schema and catalogue name the same codes
FAIL  schema and catalogue name the same severities
        catalogue warning,error,critical vs schema warning,error,critical,fatal
ok    the failure point pattern is stated once
ok    every golden envelope obeys the schema
ok    runtimes agree (11 case(s) + 45 vocabulary row(s), 0 failing)

1 check(s) failed
```

A schema that disagrees with the table it validates is a second source of
truth. The same check compares the code enums and the failure-point
pattern (`the failure point pattern is stated once`).

**Action.** The catalogue is the source of truth; make the schema match
it, never the reverse — unless the vocabulary change is intentional, in
which case both files change in one commit and the golden cases with them.

## RUNTIME MISSING

On a machine without the Rust and Swift toolchains (captured with a
stripped `PATH` on a fresh scratch copy — no `target/`, no `.build/`):

```
$ node tests/conformance.mjs
could not build the Rust emitter -- the Rust runtime will be reported missing:
  spawnSync cargo ENOENT
could not build the Swift emitter -- the Swift runtime will be reported missing:
  error: command Applying debug entitlements to ./.build/arm64-apple-macosx/debug/emit failed: unable to spawn process 'codesign' (No such file or directory)
rust: could not run -- spawnSync /private/tmp/wisent-errors-scratch.9eLB/target/debug/emit ENOENT
swift: could not run -- spawnSync /private/tmp/wisent-errors-scratch.9eLB/.build/debug/emit ENOENT
RUNTIME MISSING  rust
RUNTIME MISSING  swift
ok    credential-refused  (js, python)
ok    throttled  (js, python)
ok    store-unreachable  (js, python)
ok    nested-refusal  (js, python)
ok    silent-skip  (js, python)
ok    unattributed  (js, python)
ok    quiet-refusal  (js, python)
ok    single-segment  (js, python)
ok    deep-segment  (js, python)
ok    salvaged-malformed  (js, python)
ok    salvaged-absent  (js, python)
TABLE MISSING  rust -- spawnSync /private/tmp/wisent-errors-scratch.9eLB/target/debug/emit ENOENT
TABLE MISSING  swift -- spawnSync /private/tmp/wisent-errors-scratch.9eLB/.build/debug/emit ENOENT

11 case(s) + 45 vocabulary row(s), 4 failing
```

A missing runtime is a failure, not a skip — deliberately. The `could not
build` preamble says which fact about the machine is wrong (`spawnSync
cargo ENOENT`: cargo is not installed or not on `PATH`; a `codesign` or
SDK error: the Swift toolchain is broken); the `ok` lines still prove the
runtimes that could run agree with the golden column, so a partial machine
still gives partial evidence.

**Action.** Install the missing toolchain (`node`, `python3`, `cargo`,
`swift` are the full set) and rerun. Never conclude anything from a run
with MISSING lines except that those runtimes were not checked.

## The guard reports sites in a consumer tree

```
$ node ci/no-handrolled-envelope.mjs /tmp/toy-shelf
2 site(s) name an envelope key outside the package:
  /tmp/toy-shelf/serve.mjs:14  failure_point: 'shelf.store.read',
  /tmp/toy-shelf/serve.mjs:15  error_code: 'store_down',
...
```

Sites, not verdicts. Read each line: a hand-built envelope gets migrated
([walkthrough-adoption](walkthrough-adoption.md)); a field declaration, a
parsed operator-visible log line, or another vendor's own `error_code`
(Azure has one) is a legitimate answer and stays. The full contract is in
[reference/tools](reference/tools.md).

## A strict builder throws in production

`TypeError: failurePoint "..." is not a dotted lowercase path` (or the
Python/Rust/Swift equivalent — the per-runtime references list every exact
sentence) surfacing from an error path means a strict builder is running
where only the salvage builder is safe. That is the one place the fix is
in the consumer, not the data: use `failureOrFallback` /
`failure_or_fallback` / `Failure::or_fallback` / `Failure.orFallback`
there, and the violation will travel as a `wisent_errors.*` context note
instead of an exception thrown mid-diagnosis
([integration](integration.md), step 4).

## An envelope arrives with `wisent_errors.*` context keys

Not an error in the envelope — the envelope working as designed: some call
site fed the salvage builder a malformed point, an off-catalogue code, or
an empty service, and the violation traveled in the data. The keys name
the defect (`wisent_errors.failure_point: malformed`,
`wisent_errors.error_code: "off-catalogue: panic"`,
`wisent_errors.service: absent`); the `failure_point` is kept verbatim so
you can find the call site. Fix the call site; the envelopes it already
emitted stay honest.

## Where the reporter's silence is the symptom

Swift desktop components report through `WisentFailureReporter`, which
never fails the caller — so a missing report has exactly three causes: the
intake pair unset and the token file unreadable (the no-op path), the
intake unreachable within its five-second timeout, or the intake refusing
the POST. All three are invisible to the app by design. Check the
configuration resolution order in [configuration](configuration.md), then
the intake's own logs — a toy intake capture for comparison is in
[integrate/swift](integrate/swift.md).
