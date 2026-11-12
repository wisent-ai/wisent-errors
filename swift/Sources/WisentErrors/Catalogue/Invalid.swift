// Why an envelope could not be built, as the declared causes of
// `wisent_errors.envelope.build` say it (OwnFailures.envelopeBuild, generated
// into OwnFailuresEnvelope.swift from catalogue/failures/ and raised by
// tests/envelope/BuildTests.swift): which segment of the point broke the
// grammar, the character found, a point that would pass, and the fallback
// that never refuses.

import Foundation

/// Why an envelope could not be built, with what the builder was handed.
public enum Invalid: Error, Equatable, Sendable {
    case failurePoint(String, service: String)
    case empty(String, given: String, failurePoint: String)

    /// The declared cause this refusal is.
    public var cause: Cause {
        switch self {
        case .failurePoint(let given, _):
            let point = given.trimmingCharacters(in: .whitespacesAndNewlines)
            return pointFlaw(point)?.cause ?? OwnFailures.envelopeBuildFailurePointAbsent
        case .empty:
            return OwnFailures.envelopeBuildServiceAbsent
        }
    }

    /// The values the cause's sentences name, as the builder knew them.
    public var values: [String: String] {
        let fallback = "Failure.orFallback"
        switch self {
        case .failurePoint(let given, let service):
            let point = given.trimmingCharacters(in: .whitespacesAndNewlines)
            var values = pointValues(point).merging(["service": service, "quoted_point": jsonQuote(given), "fallback": fallback]) { $1 }
            if let flaw = pointFlaw(point) { values.merge(flaw.values) { $1 } }
            return values
        case .empty(_, let given, let failurePoint):
            return ["point": failurePoint, "quoted_service": jsonQuote(given), "fallback": fallback]
        }
    }

    /// What failed, why, what was found and what fixes it, as one line.
    public var message: String { cause.refusal(values) }
}

private func pointValues(_ point: String) -> [String: String] {
    let segments = point.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    return ["segments": "[\(segments.map(jsonQuote).joined(separator: ","))]", "suggestion": pointSuggestion(point)]
}

private func isLower(_ scalar: Unicode.Scalar) -> Bool { ("a"..."z").contains(scalar) }
private func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
    isLower(scalar) || ("0"..."9").contains(scalar) || scalar == "-" || scalar == "_"
}

/// The point a malformed one most likely meant: lowercase words joined by '-', segments by '.'.
func pointSuggestion(_ point: String) -> String {
    let segments: [String] = point.split(separator: ".", omittingEmptySubsequences: false).compactMap { segment in
        var word = String.UnicodeScalarView()
        for scalar in segment.lowercased().unicodeScalars {
            if isLower(scalar) || ("0"..."9").contains(scalar) {
                word.append(scalar)
            } else if word.last != "-" {
                word.append("-")
            }
        }
        var text = String(word)
        while let first = text.unicodeScalars.first, !isLower(first) { text.removeFirst() }
        while text.hasSuffix("-") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
    return "'\(segments.isEmpty ? "stado.fleet.enroll" : segments.joined(separator: "."))'"
}

/// Why `point` is not a failure point, as its declared cause and the values it names; nil for a good one.
func pointFlaw(_ point: String) -> (cause: Cause, values: [String: String])? {
    if point.isEmpty { return (OwnFailures.envelopeBuildFailurePointAbsent, [:]) }
    for (index, segment) in point.split(separator: ".", omittingEmptySubsequences: false).enumerated() {
        let at = ["position": String(index + 1), "quoted_segment": jsonQuote(String(segment))]
        let scalars = Array(segment.unicodeScalars)
        guard let first = scalars.first else { return (OwnFailures.envelopeBuildFailurePointSegmentEmpty, at) }
        if !isLower(first) {
            return (OwnFailures.envelopeBuildFailurePointSegmentStart, at.merging(["quoted_character": jsonQuote(String(Character(first)))]) { $1 })
        }
        if let outside = scalars.first(where: { !isAllowed($0) }) {
            return (OwnFailures.envelopeBuildFailurePointCharacter, at.merging(["quoted_character": jsonQuote(String(Character(outside)))]) { $1 })
        }
        let separator = { (scalar: Unicode.Scalar) in scalar == "-" || scalar == "_" }
        let doubled = zip(scalars, scalars.dropFirst()).contains { separator($0) && separator($1) }
        if separator(scalars[scalars.count - 1]) || doubled { return (OwnFailures.envelopeBuildFailurePointSeparator, at) }
    }
    return nil
}

/// A dotted lowercase path: digits and single separators inside each segment.
///
/// The depth carries no meaning. This checked for exactly three segments until the
/// migrations reached real registries, and a rule that refuses what a product
/// already emits is the package being wrong.
public func isValidFailurePoint(_ point: String) -> Bool {
    pointFlaw(point) == nil
}
