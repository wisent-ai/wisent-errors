#!/bin/sh
# Scaffold a temporary SwiftPM consumer of WisentErrors, run it against a toy
# Probierz intake, and show what the intake received as a companion to the
# website integration guide:
#
#   sh docs/examples/swift-consumer.sh
#
# A real consumer pins a git revision; this uses a path dependency on the
# checkout. Everything happens in a temporary directory; the toy intake listens
# on 127.0.0.1:19790 and exits after one request.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wisent-errors-swift-consumer.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/consumer/Sources/consumer"
cat > "$WORK/consumer/Package.swift" <<MANIFEST
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "consumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "$ROOT")],
    targets: [
        .executableTarget(
            name: "consumer",
            dependencies: [.product(name: "WisentErrors", package: "wisent-errors")]
        )
    ]
)
MANIFEST

cat > "$WORK/consumer/Sources/consumer/main.swift" <<'MAIN'
import Foundation
import WisentErrors

let refused = try Failure(failurePoint: "toy.gateway.oauth-refresh", code: .auth, service: "toy")
    .impact("one credential refresh")
    .detail("invalid_grant -- Refresh token not found or invalid")

let throttled = try Failure(failurePoint: "toy.dispatch.bounded-rotation", code: .rateLimit, service: "toy")
    .impact("one model request")
    .detail("all bounded 'claude-code' credentials unavailable for agent")
    .causedBy(refused)

print("render: \(throttled.render())")
for row in throttled.chain() { print("  \(row)") }

do { _ = try Failure(failurePoint: "Not A Point", code: .auth, service: "toy") }
catch let error as Invalid { print("strict refusal: \(error.message)") }

let salvaged = Failure.orFallback(failurePoint: nil, code: .unknown, service: nil)
print("salvaged: \(salvaged.toJSON())")

WisentFailureReporter.shared.report(throttled)
// The reporter hands the POST to a detached task and returns at once; a
// process that exits immediately would take the report with it. A real app
// keeps running — this demo waits instead.
Thread.sleep(forTimeInterval: 2)
MAIN

cat > "$WORK/intake.mjs" <<'INTAKE'
import { createServer } from 'node:http';

const server = createServer((request, response) => {
  let body = '';
  request.on('data', (chunk) => { body += chunk; });
  request.on('end', () => {
    console.log(`intake: ${request.method} ${request.url}`);
    console.log(`intake: authorization: ${request.headers.authorization}`);
    console.log(`intake: body: ${body}`);
    response.end();
    server.close();
  });
});
server.listen(19790, '127.0.0.1');
setTimeout(() => server.close(), 15000).unref();
INTAKE

node "$WORK/intake.mjs" &
INTAKE_PID=$!

(
  cd "$WORK/consumer" &&
  swift build 2>&1 | tail -n 1 &&
  PROBIERZ_INTAKE_URL=http://127.0.0.1:19790 PROBIERZ_INTAKE_TOKEN=toy-token \
    swift run --skip-build consumer
)

wait "$INTAKE_PID"
