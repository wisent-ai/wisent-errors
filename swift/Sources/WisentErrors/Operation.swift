// A functionality's failure catalogue and warnings, for Swift products: the
// same declarations the Rust crate's `operation` and `warning` modules hold,
// held to the same rules with the same sentences (catalogue/declaration.json,
// generated into Declaration.swift).

import Foundation

func say(_ key: String, _ values: [String: String]) -> String {
    fill(Declaration.sentences[key] ?? key, values)
}

func matches(_ pattern: String, _ text: String) -> Bool {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(text.startIndex..., in: text)
    guard let found = expression.firstMatch(in: text, options: [.anchored], range: range) else { return false }
    return found.range == range && !text.hasSuffix("\n")
}

/// The problems of the texts every declaration kind shares: each field empty,
/// generic, or holding a placeholder the renderer never fills.
func textProblems(kind: String, id: String, fields: [(String, String)]) -> [String] {
    var problems: [String] = []
    for (field, text) in fields {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append(say("field-empty", ["kind": kind, "id": id, "field": field, "meaning": Declaration.fieldMeanings[field] ?? field]))
            continue
        }
        for generic in genericSentences where text.lowercased().contains(generic.text) {
            problems.append(say("field-generic", ["kind": kind, "id": id, "field": field, "quoted_text": jsonQuote(generic.text), "reason": generic.reason]))
        }
        problems += templateProblems(kind: kind, id: id, field: field, template: text)
    }
    return problems
}

/// One way an operation can fail; the four sentences are `{name}` templates.
public struct Cause: Sendable, Equatable {
    public let id: String
    public let code: Code
    public let usage: Bool
    public let exit: Int32?
    public let failed: String
    public let cause: String
    public let observed: String
    public let remedy: String
    public let test: String

    public init(id: String, code: Code, usage: Bool, exit: Int32?, failed: String, cause: String, observed: String, remedy: String, test: String) {
        (self.id, self.code, self.usage, self.exit) = (id, code, usage, exit)
        (self.failed, self.cause, self.observed, self.remedy, self.test) = (failed, cause, observed, remedy, test)
    }

    public func sentence(_ values: [String: String]) -> String {
        "\(fill(failed, values)): \(fill(cause, values)); observed: \(fill(observed, values))"
    }

    public func fix(_ values: [String: String]) -> String { fill(remedy, values) }

    /// The sentence and the fix as one line: what a refusal of this package says.
    public func refusal(_ values: [String: String]) -> String { "\(sentence(values)); fix: \(fix(values))" }

    public func unfilledPlaceholders(_ values: [String: String]) -> [String] {
        unfilled([failed, cause, observed, remedy], values)
    }

    public func exitCode(failureExit: Int32) -> Int32 {
        if usage { return Code.usageExit }
        if let exit { return exit }
        return code.exitCode(chosen: failureExit)
    }

    public func problems() -> [String] {
        var problems: [String] = []
        if !matches(Declaration.causeIdPattern, id) {
            problems.append(say("id-malformed", ["kind": "cause", "quoted_id": jsonQuote(id), "pattern": Declaration.causeIdPattern]))
        }
        problems += textProblems(kind: "cause", id: id, fields: [("failed", failed), ("cause", cause), ("observed", observed), ("remedy", remedy)])
        let codes = Code.allCases.filter { $0 != .unknown }.map(\.rawValue).joined(separator: ", ")
        if code == .unknown {
            problems.append(say("code-unknown", ["id": id, "codes": codes]))
        } else if usage && code.retryable {
            problems.append(say("usage-retryable", ["id": id, "code": code.rawValue]))
        }
        if let exit {
            let limits = ["id": id, "exit": String(exit), "usage_exit": String(Code.usageExit), "retry_exit": String(Code.retryExit)]
            if usage || code.retryable { problems.append(say("exit-beside-derived", limits)) }
            if [0, Code.usageExit, Code.retryExit].contains(exit) { problems.append(say("exit-not-own", limits)) }
        }
        if !matches(Declaration.testPathPattern, test) {
            problems.append(say("test-malformed", ["kind": "cause", "id": id, "quoted_test": jsonQuote(test), "pattern": Declaration.testPathPattern]))
        }
        return problems
    }
}

/// One functionality, named by its failure point, every cause of its own
/// steps and every warning its caller reads before it runs (Warning.swift).
public struct Operation: Sendable {
    public let id: String
    public let entries: [String]
    public let uses: [Operation]
    public let summary: String
    public let docs: String
    public let causes: [Cause]
    public let warnings: [Warning]

    public init(id: String, entries: [String], uses: [Operation], summary: String, docs: String, causes: [Cause], warnings: [Warning] = []) {
        (self.id, self.entries, self.uses, self.summary, self.docs) = (id, entries, uses, summary, docs)
        (self.causes, self.warnings) = (causes, warnings)
    }

    public func cause(_ id: String) -> Cause? { causes.first { $0.id == id } }

    public func anchor(_ cause: Cause) -> String { "\(id.replacingOccurrences(of: ".", with: "-"))-\(cause.id)" }

    public func problems() -> [String] {
        let named = ["operation": id]
        var problems: [String] = []
        if !isValidFailurePoint(id) {
            problems.append(say("operation-id-malformed", ["quoted_id": jsonQuote(id), "pattern": failurePointPattern]))
        }
        for (index, entry) in entries.enumerated() where entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append(say("entry-empty", named.merging(["position": String(index + 1), "count": String(entries.count)]) { $1 }))
        }
        if uses.contains(where: { $0.id == id }) { problems.append(say("uses-itself", named)) }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append(say("summary-empty", named)) }
        if !docs.hasPrefix("https://") { problems.append(say("docs-not-https", named.merging(["quoted_docs": jsonQuote(docs)]) { $1 })) }
        if causes.isEmpty && uses.isEmpty { problems.append(say("no-cause", named)) }
        for (index, cause) in causes.enumerated() {
            if causes[..<index].contains(where: { $0.id == cause.id }) {
                problems.append(say("declared-twice", named.merging(["kind": "cause", "id": cause.id]) { $1 }))
            }
            problems += cause.problems().map { "operation \(id): \($0)" }
        }
        return problems + warningProblems()
    }

    /// The catalogue as the JSON every product prints from `errors list|show --json`.
    public func catalogueJSON(failureExit: Int32) -> String {
        let causes = causes.map { cause in
            "{\"id\":\(jsonQuote(cause.id)),\"code\":\(jsonQuote(cause.code.rawValue)),\"exit\":\(cause.exitCode(failureExit: failureExit)),\"retryable\":\(cause.code.retryable),\"usage\":\(cause.usage),\"failed\":\(jsonQuote(cause.failed)),\"cause\":\(jsonQuote(cause.cause)),\"observed\":\(jsonQuote(cause.observed)),\"remedy\":\(jsonQuote(cause.remedy)),\"test\":\(jsonQuote(cause.test)),\"doc\":\(jsonQuote("\(docs)#\(anchor(cause))"))}"
        }
        return "{\"operation\":\(jsonQuote(id)),\"entries\":[\(entries.map(jsonQuote).joined(separator: ","))],\"uses\":[\(uses.map { jsonQuote($0.id) }.joined(separator: ","))],\"summary\":\(jsonQuote(summary)),\"docs\":\(jsonQuote(docs)),\"causes\":[\(causes.joined(separator: ","))]}"
    }
}

/// What only a product's whole catalogue shows: one declared twice, one using an unlisted one, one nothing starts.
public func catalogueProblems(_ operations: [Operation]) -> [String] {
    var problems: [String] = []
    for (index, operation) in operations.enumerated() {
        let named = ["operation": operation.id]
        if operations[..<index].contains(where: { $0.id == operation.id }) { problems.append(say("operation-twice", named)) }
        for used in operation.uses where !operations.contains(where: { $0.id == used.id }) {
            problems.append(say("uses-unlisted", named.merging(["used": used.id]) { $1 }))
        }
        let usedByAnother = operations.contains { other in other.uses.contains { $0.id == operation.id } }
        if operation.entries.isEmpty && !usedByAnother { problems.append(say("nothing-starts", named)) }
    }
    return problems
}
