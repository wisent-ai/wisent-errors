//! The one line rule a product's lint scans its source with; the
//! JavaScript runtime's `genericSentencesIn` applies the same rule.

use crate::{GenericSentence, GENERIC_SENTENCES};

/// The generic sentences inside the string literals of one source line.
///
/// Comment lines are skipped: a comment that explains why a sentence is
/// generic is not an error message. `single_quoted` also reads `'...'` as a
/// literal, which is right for JavaScript and Python and wrong for Rust, where
/// a quote opens a lifetime or a character.
pub fn generic_sentences_in(line: &str, single_quoted: bool) -> Vec<&'static GenericSentence> {
    let trimmed = line.trim_start();
    if ["//", "/*", "*", "#", "--"]
        .iter()
        .any(|marker| trimmed.starts_with(marker))
    {
        return Vec::new();
    }
    let mut found = Vec::new();
    for literal in literals(line, single_quoted) {
        let lower = literal.to_lowercase();
        for sentence in GENERIC_SENTENCES {
            if lower.contains(sentence.text) && !found.contains(&sentence) {
                found.push(sentence);
            }
        }
    }
    found
}

/// The quoted segments of one line, escapes kept.
fn literals(line: &str, single_quoted: bool) -> Vec<&str> {
    let mut segments = Vec::new();
    let bytes = line.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        let quote = bytes[index];
        let opens = quote == b'"' || quote == b'`' || (single_quoted && quote == b'\'');
        if !opens {
            index += 1;
            continue;
        }
        let start = index + 1;
        let mut end = start;
        while end < bytes.len() && bytes[end] != quote {
            end += if bytes[end] == b'\\' { 2 } else { 1 };
        }
        let end = end.min(bytes.len());
        segments.push(&line[start..end]);
        index = end + 1;
    }
    segments
}
