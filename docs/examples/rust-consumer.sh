#!/bin/sh
# Scaffold a temporary Cargo consumer of the wisent-errors crate, run it, and
# show the exit code — the run behind docs/integrate/rust.md:
#
#   sh docs/examples/rust-consumer.sh
#
# A real consumer pins a git revision (see docs/quick-start.md); this uses a
# path dependency on the checkout. Everything happens in a temp directory.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wisent-errors-rust-consumer.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/consumer/src"
cat > "$WORK/consumer/Cargo.toml" <<MANIFEST
[package]
name = "consumer"
version = "0.0.0"
edition = "2021"

[dependencies]
wisent-errors = { path = "$ROOT/rust" }
MANIFEST

cat > "$WORK/consumer/src/main.rs" <<'MAIN'
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

    println!("from_upstream_status(503): {}", Code::from_upstream_status(503));
    println!("http_status(rate_limit): {}", Code::RateLimit.http_status());
    println!("parse(\"panic\"): {:?}", Code::parse("panic"));
    println!("or_fallback(\"panic\"): {}", Code::or_fallback("panic"));
    println!(
        "word-edge trim: {:?}",
        trim_detail_at_word_edge("one detail that runs past its bound", 22, 8)
    );

    match Failure::new("Not A Point", Code::Auth, "toy") {
        Err(error @ Invalid::FailurePoint(_)) => println!("strict refusal: {error}"),
        other => println!("unexpected: {other:?}"),
    }
    match Failure::new("toy.cli", Code::Auth, "   ") {
        Err(error) => println!("strict refusal: {error}"),
        Ok(_) => println!("unexpected: a blank service was accepted"),
    }

    let salvaged = Failure::or_fallback("Not A Point", Code::Unknown, "");
    println!("salvaged: {}", salvaged.to_json());

    // A retryable failure decides the process exit code.
    std::process::exit(failure.code.exit_code(1));
}
MAIN

status=0
(cd "$WORK/consumer" && cargo run --quiet) || status=$?
echo "\$? = $status"
