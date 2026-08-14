// The failure envelope, for Swift components.
//
// Two things only: build an envelope whose derived fields cannot be wrong, and
// render it so a reader can find the source. Everything a caller decides -- where
// it broke, what the layer below said, which subject it concerns -- is an
// argument. Everything derivable from the code comes from the catalogue.
//
// This runtime exists because two native clients held their own copies:
// oko-desktop and wisent-ios. It is hand-written around the generated `Codes.swift`
// and produces byte-identical JSON to the Rust, Python and JavaScript runtimes,
// which the package's conformance harness checks rather than assumes.

import Foundation

/// This package's own bound. A product's bound is the product's to choose.
public let detailLimit = 2000

/// Trim a detail to a bound. A hard cut, which is what the fleet emits.
///
/// The limit is an argument because the width is a product's own decision --
/// stado and probierz keep 300, wisent-customer-support 400, wisent-tools 500 --
/// while the rule for how to cut is the thing that was written six times.
public func trimDetail(_ text: String?, limit: Int = detailLimit) -> String {
    let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count <= limit { return value }
    return String(value.prefix(limit))
}

/// The same, cut back to a word edge when one falls within `slack` of the bound.
///
/// Separate and opt-in, because it changes emitted bytes. The edge is measured in
/// characters: an earlier Rust version compared a byte offset against a character
/// limit and discarded two thirds of a non-ASCII detail.
public func trimDetailAtWordEdge(_ text: String?, limit: Int = detailLimit, slack: Int = 24) -> String {
    let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cut = trimDetail(value, limit: limit)
    if cut.count < limit { return cut }
    let characters = Array(value)
    if characters.count > limit, characters[limit].isWhitespace {
        return String(cut.reversed().drop { $0.isWhitespace }.reversed())
    }
    guard let edge = cut.lastIndex(of: " ") else {
        return String(cut.reversed().drop { $0.isWhitespace }.reversed())
    }
    let charactersBefore = cut.distance(from: cut.startIndex, to: edge)
    let kept = charactersBefore > limit - slack ? String(cut[cut.startIndex..<edge]) : cut
    return String(kept.reversed().drop { $0.isWhitespace }.reversed())
}

/// Why an envelope could not be built.
public enum Invalid: Error, Equatable, Sendable {
    case failurePoint(String)
    case empty(String)

    public var message: String {
        switch self {
        case .failurePoint(let point): "failure_point \"\(point)\" is not a dotted lowercase path"
        case .empty(let field): "\(field) must not be empty"
        }
    }
}

/// A dotted lowercase path: digits and single separators inside each segment.
///
/// The depth carries no meaning. This checked for exactly three segments until the
/// migrations reached real registries, and a rule that refuses what a product
/// already emits is the package being wrong.
public func isValidFailurePoint(_ point: String) -> Bool {
    if point.isEmpty { return false }
    for segment in point.split(separator: ".", omittingEmptySubsequences: false) {
        guard let first = segment.first, first.isASCII, first.isLowercase else { return false }
        for character in segment {
            let allowed = (character.isASCII && character.isLowercase)
                || (character.isASCII && character.isNumber)
                || character == "-" || character == "_"
            if !allowed { return false }
        }
        if segment.hasSuffix("-") || segment.hasSuffix("_") { return false }
        if segment.contains("--") || segment.contains("__") { return false }
    }
    return true
}

/// One failure, in the shape every Wisent component reports.
public struct Failure: Sendable, Equatable {
    public let failurePoint: String
    public let code: Code
    public let service: String
    public private(set) var impact: String?
    public private(set) var detail: String?
    public private(set) var cause: [Failure]
    public private(set) var context: [String: String]

    public var severity: Severity { code.severity }
    public var retryable: Bool { code.retryable }
    public var outage: Bool { code.outage }

    /// Build an envelope.
    ///
    /// `impact` and `detail` are optional and serialize as `null` when absent: a
    /// stable key set is what makes these lines queryable, three products in this
    /// fleet have no impact axis at all, and a call site that knows its code
    /// exactly may have no layer below to quote.
    ///
    /// Throws on anything malformed. Inside an error path, where throwing destroys
    /// the diagnosis being carried, use `Failure.orFallback`.
    public init(failurePoint: String, code: Code, service: String) throws {
        let point = failurePoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidFailurePoint(point) else { throw Invalid.failurePoint(point) }
        let service = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !service.isEmpty else { throw Invalid.empty("service") }
        self.failurePoint = point
        self.code = code
        self.service = service
        self.impact = nil
        self.detail = nil
        self.cause = []
        self.context = [:]
    }

    private init(point: String, code: Code, service: String, context: [String: String]) {
        self.failurePoint = point
        self.code = code
        self.service = service
        self.impact = nil
        self.detail = nil
        self.cause = []
        self.context = context
    }

    /// An envelope that is always produced, whatever it was handed.
    ///
    /// Reporting a failure must not itself fail: an error path that throws takes
    /// the diagnosis with it. An unparseable point is kept verbatim -- an operator
    /// still needs it -- and the violation is recorded in `context` under a
    /// `wisent_errors.` key, so the defect travels in the data.
    public static func orFallback(failurePoint: String?, code: Code, service: String?) -> Failure {
        var notes: [String: String] = [:]
        var point = (failurePoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if point.isEmpty {
            point = "unknown"
            notes["wisent_errors.failure_point"] = "absent"
        } else if !isValidFailurePoint(point) {
            notes["wisent_errors.failure_point"] = "malformed"
        }
        var resolved = (service ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if resolved.isEmpty {
            resolved = "unknown"
            notes["wisent_errors.service"] = "absent"
        }
        return Failure(point: point, code: code, service: resolved, context: notes)
    }

    /// What the caller loses. Absent where a product has no impact axis.
    public func impact(_ impact: String) -> Failure {
        var copy = self
        let value = impact.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.impact = value.isEmpty ? nil : value
        return copy
    }

    /// The reason the layer below gave, verbatim and bounded.
    public func detail(_ detail: String?) -> Failure {
        var copy = self
        let value = trimDetail(detail, limit: detailLimit)
        copy.detail = value.isEmpty ? nil : value
        return copy
    }

    /// The failure underneath this one.
    public func causedBy(_ cause: Failure) -> Failure {
        var copy = self
        copy.cause = [cause]
        return copy
    }

    public func withContext(_ key: String, _ value: String) -> Failure {
        var copy = self
        copy.context[key] = value
        return copy
    }

    /// The envelope as JSON, with keys in the schema's order so two runtimes
    /// produce the same bytes and a conformance test can compare them.
    public func toJSON() -> String {
        var out = "{"
        out += "\(escape("failure_point")):\(escape(failurePoint))"
        out += ",\(escape("error_code")):\(escape(code.rawValue))"
        out += ",\(escape("service")):\(escape(service))"
        out += ",\(escape("impact")):\(impact.map(escape) ?? "null")"
        out += ",\(escape("severity")):\(escape(severity.rawValue))"
        out += ",\(escape("retryable")):\(retryable)"
        out += ",\(escape("outage")):\(outage)"
        out += ",\(escape("detail")):\(detail.map(escape) ?? "null")"
        if let cause = cause.first {
            out += ",\(escape("cause")):\(cause.toJSON())"
        }
        if !context.isEmpty {
            let pairs = context.keys.sorted().map { "\(escape($0)):\(escape(context[$0] ?? ""))" }
            out += ",\(escape("context")):{\(pairs.joined(separator: ","))}"
        }
        out += "}"
        return out
    }

    /// One line for a human, and the envelope for everything else.
    public func render() -> String {
        let retry = retryable ? "; retry later" : "; retrying will not help"
        let whose = outage ? "our failure" : "the request or its credentials"
        return "\(code.operatorSummary) \u{2014} \(whose)\(retry) \(toJSON())"
    }

    /// Flatten the cause chain, outermost first, for a reader in a hurry.
    public func chain() -> [String] {
        var rows: [String] = []
        var node: Failure? = self
        while let current = node {
            rows.append("\(current.failurePoint) [\(current.code.rawValue)] \(current.detail ?? "-")")
            node = current.cause.first
        }
        return rows
    }
}

/// JSON string escaping, matching the other three runtimes exactly.
private func escape(_ value: String) -> String {
    var out = "\""
    for character in value.unicodeScalars {
        switch character {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if character.value < 0x20 {
                out += String(format: "\\u%04x", character.value)
            } else {
                out.unicodeScalars.append(character)
            }
        }
    }
    return out + "\""
}
