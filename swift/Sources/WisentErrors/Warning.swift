// A functionality's warnings, for Swift products: the same declaration the
// Rust crate's `warning` module, `@wisent/errors`' warning.mjs and the Python
// `Warning` hold, with the same rules, the same sentences
// (catalogue/declaration.json) and the same JSON.
//
// A warning is what a functionality does when it goes right and its caller
// still loses something: an effect nothing undoes, access taken from someone,
// a secret let out, a change outside the product, money spent. Most
// functionalities declare none: a warning on an ordinary read teaches its
// reader to confirm without reading.

/// What kind of loss a warning announces.
public enum Hazard: String, CaseIterable, Sendable, Equatable {
    case irreversible
    case overwrites
    case cutsOffAccess = "cuts-off-access"
    case exposesSecret = "exposes-secret"
    case externalChange = "external-change"
    case costsMoney = "costs-money"

    /// What the hazard means, as the documentation page states it.
    public var meaning: String {
        switch self {
        case .irreversible: return "removes or rewrites something nothing in the product restores afterwards"
        case .overwrites: return "puts something else in place of the current state; what it replaces is kept only where the warning says"
        case .cutsOffAccess: return "a person or a program loses access it has now"
        case .exposesSecret: return "a secret value leaves the place that protects it: a plain-text file, a screen, another person or system"
        case .externalChange: return "changes a system outside the product, which the product cannot undo"
        case .costsMoney: return "spends money"
        }
    }
}

/// One thing a functionality does that its caller must know before it runs.
/// The four sentences are `{name}` templates the warning code fills.
public struct Warning: Sendable, Equatable {
    public let id: String
    public let hazard: Hazard
    /// What the functionality is about to do.
    public let effect: String
    /// What cannot be had back afterwards, and whom it reaches.
    public let consequence: String
    /// What keeps a way back, done before confirming.
    public let safeguard: String
    /// How the caller confirms: the flag, the phrase, the button.
    public let confirm: String
    /// The real test that shows this warning: `tests/<area>/<file>::<test name>`.
    public let test: String

    public init(id: String, hazard: Hazard, effect: String, consequence: String, safeguard: String, confirm: String, test: String) {
        (self.id, self.hazard, self.effect, self.consequence) = (id, hazard, effect, consequence)
        (self.safeguard, self.confirm, self.test) = (safeguard, confirm, test)
    }

    /// The effect and what it costs, as one sentence.
    public func sentence(_ values: [String: String]) -> String {
        "\(fill(effect, values)); \(fill(consequence, values))"
    }

    /// What keeps a way back, with the values filled in.
    public func safeguarding(_ values: [String: String]) -> String { fill(safeguard, values) }

    /// How to confirm, with the values filled in.
    public func confirmation(_ values: [String: String]) -> String { fill(confirm, values) }

    /// What a caller that has not confirmed reads: the warning, that nothing
    /// was done, what keeps a way back and how to go ahead. A functionality
    /// answers this only when it did nothing.
    public func unconfirmed(_ values: [String: String]) -> String {
        "\(sentence(values)); nothing was done. Before confirming: \(safeguarding(values)). To go ahead: \(confirmation(values))"
    }

    /// The anchor of this warning's entry on the warnings page.
    public func anchor(_ operation: Operation) -> String {
        "\(operation.id.replacingOccurrences(of: ".", with: "-"))-warning-\(id)"
    }

    /// Everything wrong with this declaration, each as one sentence.
    public func problems() -> [String] {
        var problems: [String] = []
        if !matches(Declaration.causeIdPattern, id) {
            problems.append(say("id-malformed", ["kind": "warning", "quoted_id": jsonQuote(id), "pattern": Declaration.causeIdPattern]))
        }
        problems += textProblems(kind: "warning", id: id, fields: [("effect", effect), ("consequence", consequence), ("safeguard", safeguard), ("confirm", confirm)])
        if !matches(Declaration.testPathPattern, test) {
            problems.append(say("test-malformed", ["kind": "warning", "id": id, "quoted_test": jsonQuote(test), "pattern": Declaration.testPathPattern]))
        }
        return problems
    }

    func json(_ operation: Operation, page: String) -> String {
        let fields = [("id", id), ("hazard", hazard.rawValue), ("effect", effect), ("consequence", consequence), ("safeguard", safeguard), ("confirm", confirm), ("test", test), ("doc", "\(page)#\(anchor(operation))")]
        return "{" + fields.map { "\(jsonQuote($0.0)):\(jsonQuote($0.1))" }.joined(separator: ",") + "}"
    }
}

extension Operation {
    /// The declared warning with this id.
    public func warning(_ id: String) -> Warning? { warnings.first { $0.id == id } }

    /// Each warning's own problems and a warning declared twice.
    func warningProblems() -> [String] {
        var problems: [String] = []
        for (index, warning) in warnings.enumerated() {
            if warnings[..<index].contains(where: { $0.id == warning.id }) {
                problems.append(say("declared-twice", ["operation": id, "kind": "warning", "id": warning.id]))
            }
            problems += warning.problems().map { "operation \(id): \($0)" }
        }
        return problems
    }

    /// The functionality's warnings as the JSON document every product prints
    /// from `warnings list|show --json`, each linked to its entry on `page`.
    public func warningsJSON(page: String) -> String {
        "{\"operation\":\(jsonQuote(id)),\"entries\":[\(entries.map(jsonQuote).joined(separator: ","))],\"summary\":\(jsonQuote(summary)),\"warnings\":[\(warnings.map { $0.json(self, page: page) }.joined(separator: ","))]}"
    }

    /// The functionality's section of the warnings page, one anchored entry
    /// per warning; empty for one that declares none, because the page lists
    /// only what warns.
    public func warningsMarkdown() -> String {
        guard !warnings.isEmpty else { return "" }
        let started = entries.isEmpty ? "run only by the functionalities that use it" : entries.map { "`\($0)`" }.joined(separator: ", ")
        var page = "## `\(id)`\n\n\(summary)\n\nStarted through: \(started). \(warnings.count) declared warning(s).\n"
        for warning in warnings {
            page += "\n<a id=\"\(warning.anchor(self))\"></a>\n\n### `\(id).\(warning.id)`\n\n"
                + "- **Kind:** `\(warning.hazard.rawValue)`: \(warning.hazard.meaning)\n"
                + "- **What it does:** \(warning.effect)\n"
                + "- **What cannot be had back:** \(warning.consequence)\n"
                + "- **Before confirming:** \(warning.safeguard)\n"
                + "- **To go ahead:** \(warning.confirm)\n"
                + "- **Test:** `\(warning.test)`\n"
        }
        return page
    }
}
