# Integrating the Rust runtime

The crate is `wisent-errors`, in `rust/`, reachable as a git dependency
because the repository root is a Cargo workspace naming it — without that,
`wisent-errors = { git = "..." }` would fail to find a crate that sits in a
subdirectory, and the only way to consume it would be a vendored copy, which
is the thing this package exists to end. Edition 2021, zero dependencies, no
serde: `Failure::to_json()` hand-serializes in the schema's key order.

## Install

```toml
[dependencies]
wisent-errors = { git = "https://github.com/wisent-ai/wisent-errors", rev = "<sha>" }
```

A path dependency works the same (`{ path = "../wisent-errors/rust" }`) and
is how the run below was produced.

## A complete consumer, compiled and executed

`src/main.rs`:

```rust
use wisent_errors::{trim_detail_at_word_edge, Code, Failure, Invalid};

fn main() {
    let refused = Failure::new("toy.store.read", Code::InfraDown, "toy")
        .expect("a well-formed point")
        .detail("error sending request for url (http://127.0.0.1:8765/api/object)");

    let failure = Failure::new("toy.cli.registry-pull", Code::InfraDown, "toy")
        .expect("a well-formed point")
        .impact("the registry read this command needed")
        .caused_by(refused)
        .with_context("attempt", "2");

    println!("render: {}", failure.render());
    for row in failure.chain() {
        println!("  {row}");
    }

    match Failure::new("Not A Point", Code::Auth, "toy") {
        Err(error @ Invalid::FailurePoint(_)) => println!("strict refusal: {error}"),
        other => println!("unexpected: {other:?}"),
    }

    let salvaged = Failure::or_fallback("Not A Point", Code::Unknown, "");
    println!("salvaged: {}", salvaged.to_json());

    // A retryable failure decides the process exit code.
    std::process::exit(failure.code.exit_code(1));
}
```

`cargo run` output, verbatim (trimmed to the highlights; the full session
also exercises `from_upstream_status`, `http_status`, `parse`,
`or_fallback`, and the word-edge trim):

```
render: infrastructure we depend on is unreachable — our failure; retry later {"failure_point":"toy.cli.registry-pull","error_code":"infra_down","service":"toy","impact":"the registry read this command needed","severity":"critical","retryable":true,"outage":true,"detail":null,"cause":{"failure_point":"toy.store.read","error_code":"infra_down","service":"toy","impact":null,"severity":"critical","retryable":true,"outage":true,"detail":"error sending request for url (http://127.0.0.1:8765/api/object)"},"context":{"attempt":"2"}}
  toy.cli.registry-pull [infra_down] -
  toy.store.read [infra_down] error sending request for url (http://127.0.0.1:8765/api/object)
strict refusal: failure_point "Not A Point" is not a dotted lowercase path
strict refusal: service must not be empty
salvaged: {"failure_point":"Not A Point","error_code":"unknown","service":"unknown","impact":null,"severity":"error","retryable":false,"outage":false,"detail":null,"context":{"wisent_errors.failure_point":"malformed","wisent_errors.service":"absent"}}
```

and the process exit, checked from the shell: `$? = 69` — the retryable
remap, end to end. The scaffolding script that reproduces this run is
[examples/rust-consumer.sh](../examples/rust-consumer.sh).

## Rust-specific behaviour worth knowing

- **Strict construction is `Result`.** `Failure::new(point, code, service)
  -> Result<Failure, Invalid>` where `Invalid::FailurePoint(String)`
  displays `failure_point "<point>" is not a dotted lowercase path` and
  `Invalid::Empty("service")` displays `service must not be empty`. An
  off-catalogue code is unrepresentable: `Code` is an enum.
- **Builder methods consume and return `Self`** — `impact`, `detail`,
  `caused_by`, `with_context`. `detail` trims to `DETAIL_LIMIT` (2000
  characters, counted in `chars`, not bytes) and an all-whitespace value
  becomes `None`.
- **`Failure` implements `Display` and `std::error::Error`** — `Display`
  prints `render()`, so `?`-propagated failures print the full line. `Code`
  and `Severity` also implement `Display` (`as_str()`).
- **`context` is a `BTreeMap<String, String>`** so context keys serialize in
  sorted order and the bytes match the other runtimes.
- **Salvage cannot record an off-catalogue code.** `Failure::or_fallback`
  takes a `Code`; the golden case for that path deliberately has no Rust
  side, as the case file itself explains — the type system refuses the bad
  code before a note could be recorded.
- **The trims count characters, not bytes.** The first version compared a
  byte offset from `rfind` against a character limit and discarded two
  thirds of a non-ASCII detail; provider text in this fleet is not ASCII.

## Guard your tree

```bash
node ci/no-handrolled-envelope.mjs <your-source-tree>
```

Full API: [reference/rust](../reference/rust.md); adoption strategy:
[integration](../integration.md).
