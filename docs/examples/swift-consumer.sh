#!/bin/sh
# Scaffold a scratch SwiftPM consumer of WisentErrors, run it against a toy
# Probierz intake, and show what the intake received as a companion to the
# website integration guide:
#
#   sh docs/examples/swift-consumer.sh
#
# A real consumer pins a git revision; this uses a path dependency on the
# checkout. Everything happens under the checkout's ignored .build directory;
# the toy intake listens on the loopback interface at a port the kernel
# assigns, publishes its address through a file the consumer reads, and exits
# after one request.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORK="$ROOT/.build/swift-consumer"
rm -rf "$WORK"
mkdir -p "$WORK/consumer/Sources/consumer"

# The consumer's manifest declares the same tools version as this package's
# own Package.swift, whose first line is that declaration: the floor a
# consumer of it needs.
read -r TOOLS_VERSION < "$ROOT/Package.swift"
cat > "$WORK/consumer/Package.swift" <<MANIFEST
$TOOLS_VERSION
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

// The reporter hands the POST to a detached task and returns at once; a
// process that exits immediately would take the report with it. A real app
// keeps running -- this demo awaits the intake's answer before it exits.
await withCheckedContinuation { (settled: CheckedContinuation<Void, Never>) in
    WisentFailureReporter.shared.report(throttled) { settled.resume() }
}
MAIN

cat > "$WORK/intake.mjs" <<'INTAKE'
import { createServer } from 'node:http';
import { writeFileSync } from 'node:fs';
import { networkInterfaces } from 'node:os';

const [, , addressFile] = process.argv;
const loopback = Object.values(networkInterfaces()).flat()
  .find((entry) => entry.internal && entry.family === 'IPv4');
if (!loopback) throw new Error('this machine has no IPv4 loopback interface for the toy intake to listen on');

const server = createServer((request, response) => {
  let body = '';
  request.on('data', (chunk) => { body += chunk; });
  request.on('end', () => {
    console.log(`intake: ${request.method} ${request.url}`);
    console.log(`intake: authorization: ${request.headers.authorization}`);
    console.log(`intake: body: ${body}`);
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({ accepted: true }));
    server.close();
  });
});
// With no port named, the kernel assigns a free one.
server.listen({ host: loopback.address }, () => {
  const { address, port } = server.address();
  writeFileSync(addressFile, `http://${address}:${port}\n`);
});
INTAKE

(cd "$WORK/consumer" && swift build 2>&1 | tail -n 1)

# The intake publishes its address through a named pipe: the shell's read
# returns exactly when the intake has bound, so the consumer never runs
# against an address that is not listening yet.
ADDRESS_PIPE="$WORK/intake-url"
mkfifo "$ADDRESS_PIPE"
node "$WORK/intake.mjs" "$ADDRESS_PIPE" &
INTAKE_PID=$!
# A consumer that fails to run leaves no request for the intake to answer, so
# the intake is stopped with it instead of outliving the script.
trap 'kill "$INTAKE_PID"' EXIT
read -r INTAKE_URL < "$ADDRESS_PIPE"

(
  cd "$WORK/consumer" &&
  PROBIERZ_INTAKE_URL="$INTAKE_URL" PROBIERZ_INTAKE_TOKEN=toy-token \
    swift run --skip-build consumer
)

trap - EXIT
wait "$INTAKE_PID"
