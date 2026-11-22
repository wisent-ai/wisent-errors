// wisent-errors-swift: the Swift package's own command line, driving its
// libraries the way an app drives them. It builds an envelope or says why it
// cannot (`envelope build`), reads one back for a person (`envelope read`),
// holds causes to the declaration rules (`declaration cause|check`), keeps a
// product's telemetry and files its support reports from a terminal
// (`telemetry …`, `support …`), and runs a product's installed command line
// program only when its publisher signed it (`program run`). The commands
// are documented in docs/guides/swift-reporter.md.
//
// Every refusal is a declared cause, printed on stderr in three lines, and
// the command exits with the status the cause declares:
//
//   Error: <failed>: <cause>; observed: <observed>
//   fix: <remedy>
//   cause: <operation>.<cause id>; <page>#<anchor>

#if os(macOS)
import Foundation

let status = await Commands.run(Array(CommandLine.arguments.dropFirst()))
exit(status)
#endif
