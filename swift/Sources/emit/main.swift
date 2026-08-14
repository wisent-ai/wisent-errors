// Emit every golden case through the Swift runtime, one JSON per line.
//
// The four emitters exist so the conformance harness can compare languages
// against each other and against the golden field, rather than each runtime
// asserting its own behaviour and agreeing with nobody.
//
// With --table it reads the probe file on stdin and dumps the whole derived
// vocabulary instead: every code's severity, retryability, outage, HTTP status and
// exit code, how each interesting upstream status classifies, and both trim rules.

import Foundation
import WisentErrors

/// Tab separated `key=value`; the first `=` separates, so a value may contain more.
func parseCase(_ line: String) -> [String: String] {
    var fields: [String: String] = [:]
    for pair in line.split(separator: "\t", omittingEmptySubsequences: false) {
        guard let at = pair.firstIndex(of: "=") else { continue }
        let key = String(pair[pair.startIndex..<at])
        let value = String(pair[pair.index(after: at)...])
        fields[key] = value
    }
    return fields
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func codeOrExit(_ text: String, _ name: String) -> Code {
    guard let code = Code(rawValue: text) else { fail("\(name): unknown code \"\(text)\"") }
    return code
}

var input = ""
while let line = readLine(strippingNewline: false) { input += line }

let wantsTable = CommandLine.arguments.contains("--table")

if wantsTable {
    var statuses: [Int] = []
    var chosen: Int32 = 0
    var trims: [(String, Int, String)] = []
    for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
        let text = String(line)
        if text.trimmingCharacters(in: .whitespaces).isEmpty || text.hasPrefix("#") { continue }
        let fields = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let kind = fields.first else { continue }
        switch kind {
        case "statuses":
            statuses = fields.dropFirst().compactMap { Int($0) }
        case "chosen_exit":
            chosen = fields.count > 1 ? (Int32(fields[1]) ?? 0) : 0
        case "trim", "word":
            if fields.count > 2, let limit = Int(fields[1]) {
                trims.append((kind, limit, fields[2]))
            }
        default:
            continue
        }
    }

    for code in Code.allCases {
        print(
            [
                "code=\(code.rawValue)",
                "severity=\(code.severity.rawValue)",
                "retryable=\(code.retryable)",
                "outage=\(code.outage)",
                "http_status=\(code.httpStatus)",
                "exit_code=\(code.exitCode(chosen: chosen))",
                "operator_summary=\(code.operatorSummary)",
            ].joined(separator: "\t")
        )
    }
    for status in statuses {
        print("status=\(status)\tcode=\(Code.fromUpstream(status: status).rawValue)")
    }
    for (rule, limit, text) in trims {
        let cut = rule == "word" ? trimDetailAtWordEdge(text, limit: limit) : trimDetail(text, limit: limit)
        print("\(rule)=\(limit)\tresult=\(cut)")
    }
    exit(0)
}

for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
    let text = String(line)
    if text.trimmingCharacters(in: .whitespaces).isEmpty || text.hasPrefix("#") { continue }
    let fields = parseCase(text)
    guard let name = fields["name"] else { fail("case: case is missing name") }

    var envelope: Failure
    if fields["builder"] == "or_fallback" {
        envelope = Failure.orFallback(
            failurePoint: fields["failure_point"],
            code: codeOrExit(fields["code"] ?? "", name),
            service: fields["service"]
        )
    } else {
        guard let point = fields["failure_point"], let service = fields["service"] else {
            fail("\(name): case is missing failure_point or service")
        }
        do {
            envelope = try Failure(
                failurePoint: point,
                code: codeOrExit(fields["code"] ?? "", name),
                service: service
            )
        } catch let error as Invalid {
            fail("\(name): \(error.message)")
        }
    }

    if let impact = fields["impact"] { envelope = envelope.impact(impact) }
    if let detail = fields["detail"] { envelope = envelope.detail(detail) }

    if let causePoint = fields["cause_failure_point"] {
        do {
            var cause = try Failure(
                failurePoint: causePoint,
                code: codeOrExit(fields["cause_code"] ?? "", name),
                service: fields["cause_service"] ?? ""
            )
            if let impact = fields["cause_impact"] { cause = cause.impact(impact) }
            if let detail = fields["cause_detail"] { cause = cause.detail(detail) }
            envelope = envelope.causedBy(cause)
        } catch let error as Invalid {
            fail("\(name): cause \(error.message)")
        }
    }

    if let context = fields["context"], let at = context.firstIndex(of: "=") {
        envelope = envelope.withContext(
            String(context[context.startIndex..<at]),
            String(context[context.index(after: at)...])
        )
    }

    print("\(name)\t\(envelope.toJSON())")
}
