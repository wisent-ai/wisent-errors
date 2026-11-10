#!/bin/sh
# Scaffold a scratch SwiftPM consumer of WisentErrors, report one failure
# through its telemetry to a toy collector, and show what the collector
# received, as a companion to the website integration guide:
#
#   sh docs/examples/swift-consumer.sh
#
# A real consumer pins a version; this uses a path dependency on the checkout.
# Everything happens under the checkout's ignored .build directory: the
# consumer's telemetry state (consent, queue, installation id) and the toy
# collector, which listens on the loopback interface at a port the kernel
# assigns, publishes its address through a named pipe the script reads, answers
# the collector's {"ok": true} and exits after one event.
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

// An app declares its product in Info.plist and the user answers in its
// Settings; this command-line demo names the product and answers `errors`
// itself, keeping the state where WISENT_TELEMETRY_HOME says.
let telemetry = WisentTelemetry(product: TelemetryProduct(id: "toy", appID: "toy-desktop", version: "0.0.0"))
try telemetry.setLevel(.errors)
let reporter = WisentFailureReporter(telemetry: telemetry)

// The reporter queues the failure and sends the queue from a detached task; a
// process that exits immediately would take the attempt with it. A real app
// keeps running -- this demo awaits the attempt before it exits.
await withCheckedContinuation { (settled: CheckedContinuation<Void, Never>) in
    reporter.report(throttled) { settled.resume() }
}
print("telemetry status: \(telemetry.status())")
MAIN

cat > "$WORK/collector.mjs" <<'COLLECTOR'
import { createServer } from 'node:http';
import { writeFileSync } from 'node:fs';
import { networkInterfaces } from 'node:os';

const [, , addressFile] = process.argv;
const loopback = Object.values(networkInterfaces()).flat()
  .find((entry) => entry.internal && entry.family === 'IPv4');
if (!loopback) throw new Error('this machine has no IPv4 loopback interface for the toy collector to listen on');

const server = createServer((request, response) => {
  let body = '';
  request.on('data', (chunk) => { body += chunk; });
  request.on('end', () => {
    console.log(`collector: ${request.method} ${request.url}`);
    console.log(`collector: body: ${body}`);
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({ ok: true }));
    server.close();
  });
});
// Port 0 asks the kernel for a free one; Node requires it named.
server.listen({ host: loopback.address, port: 0 }, () => {
  const { address, port } = server.address();
  writeFileSync(addressFile, `http://${address}:${port}/api/analytics/mobile/collect\n`);
});
COLLECTOR

(cd "$WORK/consumer" && swift build 2>&1 | tail -n 1)

# The collector publishes its address through a named pipe: the shell's read
# returns exactly when the collector has bound, so the consumer never sends to
# an address that is not listening yet.
ADDRESS_PIPE="$WORK/collector-url"
mkfifo "$ADDRESS_PIPE"
node "$WORK/collector.mjs" "$ADDRESS_PIPE" &
COLLECTOR_PID=$!
# A consumer that fails to run sends nothing for the collector to answer, so
# the collector is stopped with it instead of outliving the script.
trap 'kill "$COLLECTOR_PID"' EXIT
read -r COLLECTOR_URL < "$ADDRESS_PIPE"

(
  cd "$WORK/consumer" &&
  WISENT_TELEMETRY_COLLECTOR_URL="$COLLECTOR_URL" WISENT_TELEMETRY_HOME="$WORK/telemetry" \
    swift run --skip-build consumer
)

trap - EXIT
wait "$COLLECTOR_PID"
