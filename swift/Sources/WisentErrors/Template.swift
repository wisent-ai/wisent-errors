// The `{name}` templates a cause or a warning is written in: how the renderer
// reads them, and what in them it would never fill, read the same way as the
// Rust, JavaScript and Python runtimes read them. `{` opens a placeholder the
// next `}` closes unless another `{` comes first; what lies between is a
// placeholder when it is a name (Declaration.placeholderPattern) and is kept
// as written otherwise; a `}` no `{` opened is kept as written.

/// One piece of a template, as the renderer reads it.
public enum TemplatePart: Equatable, Sendable {
    case text(String)
    case placeholder(String)
    case malformed(String)
    case unclosed(String)
    case unopened
}

/// Whether `name` is one the renderer fills.
public func isPlaceholderName(_ name: String) -> Bool {
    let scalars = Array(name.unicodeScalars)
    guard let first = scalars.first, ("a"..."z").contains(first) else { return false }
    return scalars.dropFirst().allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
}

/// The template's parts, in order.
public func templateParts(_ template: String) -> [TemplatePart] {
    let scalars = Array(template.unicodeScalars)
    var found: [TemplatePart] = []
    var text = String.UnicodeScalarView()
    var index = 0
    func flush() {
        if !text.isEmpty { found.append(.text(String(text))) }
        text = String.UnicodeScalarView()
    }
    func slice(_ from: Int, _ to: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[from..<to])
        return String(view)
    }
    while index < scalars.count {
        let scalar = scalars[index]
        if scalar == "}" {
            flush()
            found.append(.unopened)
            index += 1
        } else if scalar == "{" {
            flush()
            let close = scalars[(index + 1)...].firstIndex(of: "}")
            let reopen = scalars[(index + 1)...].firstIndex(of: "{")
            if let close, reopen.map({ close < $0 }) ?? true {
                let inside = slice(index + 1, close)
                found.append(isPlaceholderName(inside) ? .placeholder(inside) : .malformed(slice(index, close + 1)))
                index = close + 1
            } else {
                let end = reopen ?? scalars.count
                found.append(.unclosed(slice(index, end)))
                index = end
            }
        } else {
            text.append(scalar)
            index += 1
        }
    }
    flush()
    return found
}

/// `template` with each `{name}` replaced by its value; one with no value stays as written.
public func fill(_ template: String, _ values: [String: String]) -> String {
    templateParts(template).map { part in
        switch part {
        case .text(let text), .malformed(let text), .unclosed(let text): return text
        case .unopened: return "}"
        case .placeholder(let name): return values[name] ?? "{\(name)}"
        }
    }.joined()
}

/// The names of the placeholders a template fills, in order of appearance.
public func placeholders(_ template: String) -> [String] {
    templateParts(template).compactMap { if case .placeholder(let name) = $0 { return name } else { return nil } }
}

/// The placeholders of `templates` that `values` gives no value for, each once.
public func unfilled(_ templates: [String], _ values: [String: String]) -> [String] {
    var missing: [String] = []
    for name in templates.flatMap(placeholders) where values[name] == nil && !missing.contains(name) {
        missing.append(name)
    }
    return missing
}

func placeholderSuggestion(_ malformed: String) -> String {
    let inside = String(malformed.unicodeScalars.dropFirst().dropLast())
    let head = inside.split(whereSeparator: { $0 == ":" || $0 == "!" }, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let mapped = String(String.UnicodeScalarView(head.lowercased().unicodeScalars.map { scalar in
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" ? scalar : "_"
    }))
    let name = String(mapped.drop { !("a"..."z").contains($0.unicodeScalars.first ?? " ") })
    return "{\(name.isEmpty ? "value" : name)}"
}

/// Everything in one field's template the renderer would never fill or a reader would never be helped by.
public func templateProblems(kind: String, id: String, field: String, template: String) -> [String] {
    let base = ["kind": kind, "id": id, "field": field]
    let say = { (key: String, extra: [String: String]) in
        fill(Declaration.sentences[key] ?? key, base.merging(extra) { $1 })
    }
    var problems: [String] = []
    let read = templateParts(template)
    for part in read {
        switch part {
        case .malformed(let text):
            problems.append(say("placeholder-malformed", ["placeholder": text, "grammar": Declaration.placeholderGrammar, "suggestion": placeholderSuggestion(text)]))
        case .unclosed(let text):
            problems.append(say("placeholder-unclosed", ["quoted_text": jsonQuote(text), "example": "{name}", "open": "{", "close": "}"]))
        case .unopened:
            problems.append(say("placeholder-unopened", ["quoted_text": jsonQuote(template), "open": "{", "close": "}"]))
        case .placeholder(let name) where kind == "cause" && field != "observed" && Declaration.rawMessageNames.contains(name):
            problems.append(say("placeholder-raw-message", ["placeholder": "{\(name)}"]))
        default:
            break
        }
    }
    if kind == "cause" && field == "cause" {
        let wraps = read.contains { if case .text = $0 { return false } else { return true } }
        let words = read.contains { if case .text(let text) = $0 { return text.contains { $0.isLetter } } else { return false } }
        if wraps && !words { problems.append(say("cause-only-wrapped", ["quoted_text": jsonQuote(template)])) }
    }
    return problems
}
