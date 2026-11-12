//! The `{name}` templates a cause or a warning is written in: how the
//! renderer reads them, and what in them it would never fill. The
//! JavaScript, Python and Swift runtimes read a template the same way, so the
//! four fill and refuse alike.
//!
//! A template is read left to right. `{` opens a placeholder that the next
//! `}` closes, unless another `{` comes first: then the first `{` never
//! closes. What lies between the braces is a placeholder when it is a name
//! ([`crate::declaration::PLACEHOLDER_PATTERN`]); anything else there
//! (`{value:?}`, `{Path}`) is kept as written and never filled. A `}` no `{`
//! opened is kept as written.

use crate::declaration as rules;
use crate::render::escape;

/// One piece of a template, as the renderer reads it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part<'a> {
    Text(&'a str),
    /// `{name}`, filled from the value of that name.
    Placeholder(&'a str),
    /// `{...}` whose inside is not a name, braces included: never filled.
    Malformed(&'a str),
    /// A `{` and what follows it up to the next `{` or the end: no `}` closes it.
    Unclosed(&'a str),
    /// A `}` no `{` opened.
    Unopened,
}

/// Whether `name` is one the renderer fills.
pub fn is_placeholder_name(name: &str) -> bool {
    let mut characters = name.chars();
    matches!(characters.next(), Some('a'..='z'))
        && characters.all(|character| matches!(character, 'a'..='z' | '0'..='9' | '_'))
}

/// The template's parts, in order.
pub fn parts(template: &str) -> Vec<Part<'_>> {
    let mut found = Vec::new();
    let mut text_start = 0;
    let mut index = 0;
    while index < template.len() {
        let byte = template.as_bytes()[index];
        if byte != b'{' && byte != b'}' {
            index += 1;
            continue;
        }
        if text_start < index {
            found.push(Part::Text(&template[text_start..index]));
        }
        if byte == b'}' {
            found.push(Part::Unopened);
            index += 1;
        } else {
            let rest = &template[index + 1..];
            match (rest.find('}'), rest.find('{')) {
                (Some(close), reopen) if reopen.map_or(true, |reopen| close < reopen) => {
                    let inside = &rest[..close];
                    found.push(if is_placeholder_name(inside) {
                        Part::Placeholder(inside)
                    } else {
                        Part::Malformed(&template[index..index + close + 2])
                    });
                    index += close + 2;
                }
                (_, reopen) => {
                    let end = reopen.map_or(template.len(), |reopen| index + 1 + reopen);
                    found.push(Part::Unclosed(&template[index..end]));
                    index = end;
                }
            }
        }
        text_start = index;
    }
    if text_start < template.len() {
        found.push(Part::Text(&template[text_start..]));
    }
    found
}

/// `template` with each `{name}` replaced by its value.
///
/// A placeholder with no value stays as written, so a value the raising code
/// forgot is visible in the sentence instead of silently becoming nothing;
/// text the renderer does not read as a placeholder stays as written too.
pub fn fill(template: &str, values: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(template.len());
    for part in parts(template) {
        match part {
            Part::Placeholder(name) => match values.iter().find(|(key, _)| *key == name) {
                Some((_, value)) => out.push_str(value),
                None => {
                    out.push('{');
                    out.push_str(name);
                    out.push('}');
                }
            },
            Part::Text(text) | Part::Malformed(text) | Part::Unclosed(text) => out.push_str(text),
            Part::Unopened => out.push('}'),
        }
    }
    out
}

/// The names of the placeholders a template fills, in order of appearance.
pub fn placeholders(template: &str) -> Vec<&str> {
    parts(template)
        .into_iter()
        .filter_map(|part| match part {
            Part::Placeholder(name) => Some(name),
            _ => None,
        })
        .collect()
}

/// The placeholders of `templates` that `values` gives no value for, each once.
pub fn unfilled<'a>(templates: &[&'a str], values: &[(&str, &str)]) -> Vec<&'a str> {
    let mut missing: Vec<&'a str> = Vec::new();
    for template in templates {
        for name in placeholders(template) {
            if !values.iter().any(|(key, _)| *key == name) && !missing.contains(&name) {
                missing.push(name);
            }
        }
    }
    missing
}

/// The name a malformed placeholder most likely meant: what precedes a format
/// spec, lowercase, with '_' for anything else.
pub fn suggestion(malformed: &str) -> String {
    let inside = &malformed[1..malformed.len() - 1];
    let head = inside
        .find([':', '!'])
        .map_or(inside, |end| &inside[..end])
        .to_lowercase();
    let mapped: String = head
        .chars()
        .map(|character| match character {
            'a'..='z' | '0'..='9' | '_' => character,
            _ => '_',
        })
        .collect();
    let name = mapped.trim_start_matches(|character: char| !character.is_ascii_lowercase());
    format!("{{{}}}", if name.is_empty() { "value" } else { name })
}

/// `base` and `extra` as one list of values.
fn joined<'a>(base: &[(&'a str, &'a str)], extra: &[(&'a str, &'a str)]) -> Vec<(&'a str, &'a str)> {
    base.iter().chain(extra).copied().collect()
}

/// Everything in one field's template the renderer would never fill or a
/// reader would never be helped by, each as one sentence. `kind` is `cause`
/// or `warning`; the raw-message rule binds a cause's `failed`, `cause` and
/// `remedy`, which are the declaration's own words.
pub fn template_problems(kind: &str, id: &str, field: &str, template: &str) -> Vec<String> {
    let base = [("kind", kind), ("id", id), ("field", field)];
    let quoted = escape(template);
    let mut problems = Vec::new();
    let read = parts(template);
    for part in &read {
        match *part {
            Part::Malformed(text) => {
                let suggested = suggestion(text);
                let values = [
                    ("placeholder", text),
                    ("grammar", rules::PLACEHOLDER_GRAMMAR),
                    ("suggestion", suggested.as_str()),
                ];
                problems.push(fill(rules::PLACEHOLDER_MALFORMED, &joined(&base, &values)));
            }
            Part::Unclosed(text) => {
                let shown = escape(text);
                let values = [
                    ("quoted_text", shown.as_str()),
                    ("example", "{name}"),
                    ("open", "{"),
                    ("close", "}"),
                ];
                problems.push(fill(rules::PLACEHOLDER_UNCLOSED, &joined(&base, &values)));
            }
            Part::Unopened => {
                let values = [("quoted_text", quoted.as_str()), ("open", "{"), ("close", "}")];
                problems.push(fill(rules::PLACEHOLDER_UNOPENED, &joined(&base, &values)));
            }
            Part::Placeholder(name)
                if kind == "cause"
                    && field != "observed"
                    && rules::RAW_MESSAGE_NAMES.contains(&name) =>
            {
                let braced = format!("{{{name}}}");
                let values = [("placeholder", braced.as_str())];
                problems.push(fill(rules::PLACEHOLDER_RAW_MESSAGE, &joined(&base, &values)));
            }
            _ => {}
        }
    }
    if kind == "cause" && field == "cause" {
        let wraps = read.iter().any(|part| !matches!(part, Part::Text(_)));
        let words = read.iter().any(
            |part| matches!(part, Part::Text(text) if text.chars().any(char::is_alphabetic)),
        );
        if wraps && !words {
            let values = [("quoted_text", quoted.as_str())];
            problems.push(fill(rules::CAUSE_ONLY_WRAPPED, &joined(&base, &values)));
        }
    }
    problems
}
