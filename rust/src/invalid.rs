//! Why an envelope could not be built, as the declared causes of
//! `wisent_errors.envelope.build` say it ([`crate::failures::ENVELOPE_BUILD`]).
//!
//! Rejecting it is the point: an envelope with an unparseable failure point or
//! an empty service is worse than none, because it looks like a report. The
//! refusal names which segment of the point broke the grammar, the character
//! it found, a point that would pass and the fallback that never refuses.

use std::fmt;

use crate::failures as own;
use crate::render::escape;
use crate::Cause;

const FALLBACK: &str = "Failure::or_fallback";

/// Why an envelope could not be built, with what the builder was handed.
#[derive(Debug, PartialEq, Eq)]
pub enum Invalid {
    /// The failure point, as given, is not a dotted lowercase path.
    FailurePoint { given: String, service: String },
    /// A field that names something is empty once trimmed.
    Empty {
        field: &'static str,
        given: String,
        failure_point: String,
    },
}

/// Where a failure point breaks the grammar: the declared cause it is, the
/// segment (from 1) and, for a wrong character, the character.
pub(crate) struct Flaw {
    pub cause: &'static Cause,
    pub position: usize,
    pub segment: String,
    pub character: Option<char>,
}

/// Why `point` is not a failure point, or `None` when it is one.
pub(crate) fn point_flaw(point: &str) -> Option<Flaw> {
    if point.is_empty() {
        return Some(Flaw {
            cause: &own::ENVELOPE_BUILD_FAILURE_POINT_ABSENT,
            position: 0,
            segment: String::new(),
            character: None,
        });
    }
    for (index, segment) in point.split('.').enumerate() {
        let flaw = |cause, character| Flaw {
            cause,
            position: index + 1,
            segment: segment.to_owned(),
            character,
        };
        let Some(first) = segment.chars().next() else {
            return Some(flaw(&own::ENVELOPE_BUILD_FAILURE_POINT_SEGMENT_EMPTY, None));
        };
        if !first.is_ascii_lowercase() {
            return Some(flaw(&own::ENVELOPE_BUILD_FAILURE_POINT_SEGMENT_START, Some(first)));
        }
        let allowed = |c: char| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_';
        if let Some(outside) = segment.chars().find(|c| !allowed(*c)) {
            return Some(flaw(&own::ENVELOPE_BUILD_FAILURE_POINT_CHARACTER, Some(outside)));
        }
        let separator = |c: char| c == '-' || c == '_';
        let doubled = segment
            .chars()
            .zip(segment.chars().skip(1))
            .any(|(left, right)| separator(left) && separator(right));
        if segment.ends_with(separator) || doubled {
            return Some(flaw(&own::ENVELOPE_BUILD_FAILURE_POINT_SEPARATOR, None));
        }
    }
    None
}

/// The point a malformed one most likely meant, quoted: lowercase words
/// joined by '-', segments by '.'.
pub(crate) fn suggestion(point: &str) -> String {
    let segments: Vec<String> = point
        .split('.')
        .map(|segment| {
            let mut word = String::new();
            for character in segment.to_lowercase().chars() {
                if character.is_ascii_lowercase() || character.is_ascii_digit() {
                    word.push(character);
                } else if !word.ends_with('-') {
                    word.push('-');
                }
            }
            word.trim_start_matches(|c: char| !c.is_ascii_lowercase())
                .trim_end_matches('-')
                .to_owned()
        })
        .filter(|segment| !segment.is_empty())
        .collect();
    if segments.is_empty() {
        "'stado.fleet.enroll'".to_owned()
    } else {
        format!("'{}'", segments.join("."))
    }
}

impl Invalid {
    /// The declared cause this refusal is.
    pub fn cause(&self) -> &'static Cause {
        match self {
            Self::FailurePoint { given, .. } => point_flaw(given.trim())
                .map_or(&own::ENVELOPE_BUILD_FAILURE_POINT_ABSENT, |flaw| flaw.cause),
            Self::Empty { .. } => &own::ENVELOPE_BUILD_SERVICE_ABSENT,
        }
    }

    /// The values the cause's sentences name, as the builder knew them.
    pub fn values(&self) -> Vec<(&'static str, String)> {
        match self {
            Self::FailurePoint { given, service } => {
                let point = given.trim();
                let segments: Vec<String> = point.split('.').map(escape).collect();
                let mut values = vec![
                    ("service", service.clone()),
                    ("quoted_point", escape(given)),
                    ("segments", format!("[{}]", segments.join(","))),
                    ("suggestion", suggestion(point)),
                    ("fallback", FALLBACK.to_owned()),
                ];
                if let Some(flaw) = point_flaw(point) {
                    values.push(("position", flaw.position.to_string()));
                    values.push(("quoted_segment", escape(&flaw.segment)));
                    if let Some(character) = flaw.character {
                        values.push(("quoted_character", escape(&character.to_string())));
                    }
                }
                values
            }
            Self::Empty {
                given,
                failure_point,
                ..
            } => vec![
                ("point", failure_point.clone()),
                ("quoted_service", escape(given)),
                ("fallback", FALLBACK.to_owned()),
            ],
        }
    }
}

impl fmt::Display for Invalid {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let values = self.values();
        let borrowed: Vec<(&str, &str)> = values.iter().map(|(key, value)| (*key, value.as_str())).collect();
        formatter.write_str(&self.cause().refusal(&borrowed))
    }
}

impl std::error::Error for Invalid {}
