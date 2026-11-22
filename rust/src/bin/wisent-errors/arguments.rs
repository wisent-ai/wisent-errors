//! The words of a command line: the options every command takes
//! (`--product <file>`, `--text`), the command they name, its operands and
//! its own options. Each word it cannot read is a declared cause of
//! `wisent_errors.command.arguments` (catalogue/failures/command.json).

use std::process::ExitCode;

use wisent_errors::failures as own;

use crate::say;

/// One command: the words that name it, what it reads and how it is written.
pub struct Spec {
    pub words: &'static [&'static str],
    /// How many operands it reads, all of them required.
    pub operands: usize,
    /// What its operands are, as a refusal names them.
    pub wanted: &'static str,
    /// Its own options, each with whether it takes a value.
    pub options: &'static [(&'static str, bool)],
    /// Whether it speaks for a product, named with `--product <file>`.
    pub product: bool,
    pub usage: &'static str,
}

const NONE: &str = "no operand";

/// Every command, in the order the commands are listed.
pub const COMMANDS: &[Spec] = &[
    Spec { words: &["telemetry", "status"], operands: 0, wanted: NONE, options: &[], product: true, usage: "wisent-errors --product <file> telemetry status" },
    Spec { words: &["telemetry", "level"], operands: 1, wanted: "one level: off, errors or usage", options: &[("--yes", false)], product: true, usage: "wisent-errors --product <file> telemetry level <off|errors|usage> [--yes]" },
    Spec { words: &["telemetry", "on"], operands: 0, wanted: NONE, options: &[], product: true, usage: "wisent-errors --product <file> telemetry on" },
    Spec { words: &["telemetry", "off"], operands: 0, wanted: NONE, options: &[("--yes", false)], product: true, usage: "wisent-errors --product <file> telemetry off [--yes]" },
    Spec {
        words: &["telemetry", "failure"],
        operands: 2,
        wanted: "a failure point and a code",
        options: &[("--detail", true), ("--remedy", true), ("--impact", true), ("--cause-id", true)],
        product: true,
        usage: "wisent-errors --product <file> telemetry failure <failure-point> <code> [--detail <text>] [--remedy <text>] [--impact <text>] [--cause-id <id>]",
    },
    Spec {
        words: &["telemetry", "command"],
        operands: 3,
        wanted: "the command's name, its exit status and its duration in milliseconds",
        options: &[],
        product: true,
        usage: "wisent-errors --product <file> telemetry command <name> <exit-status> <duration-ms>",
    },
    Spec { words: &["telemetry", "help"], operands: 1, wanted: "the command help was asked about", options: &[], product: true, usage: "wisent-errors --product <file> telemetry help <command>" },
    Spec { words: &["telemetry", "show"], operands: 0, wanted: NONE, options: &[], product: true, usage: "wisent-errors --product <file> telemetry show" },
    Spec { words: &["telemetry", "events"], operands: 0, wanted: NONE, options: &[], product: false, usage: "wisent-errors telemetry events" },
    Spec { words: &["telemetry", "export"], operands: 1, wanted: "the file to write the events to", options: &[], product: true, usage: "wisent-errors --product <file> telemetry export <file>" },
    Spec { words: &["telemetry", "flush"], operands: 0, wanted: NONE, options: &[], product: true, usage: "wisent-errors --product <file> telemetry flush" },
    Spec {
        words: &["support", "report"],
        operands: 0,
        wanted: NONE,
        options: &[("--description", true), ("--subject", true), ("--email", true), ("--with-failure", false)],
        product: true,
        usage: "wisent-errors --product <file> support report --description <text> [--subject <text>] [--email <address>] [--with-failure]",
    },
    Spec { words: &["support", "status"], operands: 0, wanted: NONE, options: &[], product: true, usage: "wisent-errors --product <file> support status" },
    Spec { words: &["doctor"], operands: 0, wanted: NONE, options: &[("--json", false)], product: true, usage: "wisent-errors --product <file> doctor [--json]" },
    Spec {
        words: &["doctor", "check"],
        operands: 2,
        wanted: "the failure catalogue `<product> errors list --json` printed and the findings `<product> doctor --json` printed",
        options: &[],
        product: false,
        usage: "wisent-errors doctor check <errors-list.json> <doctor.json>",
    },
    Spec { words: &["errors", "list"], operands: 0, wanted: NONE, options: &[], product: false, usage: "wisent-errors errors list" },
    Spec { words: &["errors", "page"], operands: 0, wanted: NONE, options: &[], product: false, usage: "wisent-errors errors page" },
    Spec { words: &["warnings", "list"], operands: 0, wanted: NONE, options: &[], product: false, usage: "wisent-errors warnings list" },
    Spec { words: &["warnings", "page"], operands: 0, wanted: NONE, options: &[], product: false, usage: "wisent-errors warnings page" },
    Spec {
        words: &["warnings", "check"],
        operands: 1,
        wanted: "the listing `<product> warnings list` printed",
        options: &[],
        product: false,
        usage: "wisent-errors warnings check <warnings-list.json>",
    },
];

/// A command line read whole.
pub struct Line {
    pub spec: &'static Spec,
    pub operands: Vec<String>,
    /// The command's own options that were set, with their values.
    options: Vec<(&'static str, Option<String>)>,
    /// The file `--product` names.
    pub product: Option<String>,
    /// `--text`: print one `path: value` line per field instead of JSON.
    pub text: bool,
    /// Every word, as the command line gave them, for a refusal to show.
    pub arguments: Vec<String>,
}

impl Line {
    /// The command, as its words name it: `telemetry level`.
    pub fn command(&self) -> String {
        self.spec.words.join(" ")
    }

    /// Whether the flag `name` was given.
    pub fn flag(&self, name: &str) -> bool {
        self.options.iter().any(|(option, _)| *option == name)
    }

    /// The value of the option `name`, the last one when it was given twice.
    pub fn value(&self, name: &str) -> Option<&str> {
        self.options
            .iter()
            .rev()
            .find(|(option, _)| *option == name)
            .and_then(|(_, value)| value.as_deref())
    }
}

/// The text a refusal quotes a word or a list of words as: JSON's.
pub fn quoted<T: serde::Serialize + ?Sized>(words: &T) -> String {
    // fallback: a string or a list of strings always has a JSON form; an empty quote stands in for none.
    serde_json::to_string(words).unwrap_or_default()
}

/// Every command, as the refusals list them.
fn commands() -> String {
    COMMANDS
        .iter()
        .map(|spec| spec.words.join(" "))
        .collect::<Vec<_>>()
        .join(", ")
}

/// Read `arguments`, or say the declared refusal of the word that cannot be
/// read and answer the status to exit with.
pub fn read(arguments: Vec<String>) -> Result<Line, ExitCode> {
    let quoted_arguments = quoted(&arguments);
    let mut product = None;
    let mut text = false;
    let mut rest: Vec<&str> = Vec::new();
    let mut words = arguments.iter();
    while let Some(word) = words.next() {
        match word.as_str() {
            "--product" => match words.next() {
                Some(file) => product = Some(file.clone()),
                None => {
                    return Err(say::refuse(
                        &own::COMMAND_ARGUMENTS,
                        &own::COMMAND_ARGUMENTS_OPTION_VALUE_MISSING,
                        &[("option", "--product"), ("quoted_arguments", &quoted_arguments), ("placeholder", "<file>")],
                    ))
                }
            },
            "--text" => text = true,
            other => rest.push(other),
        }
    }
    let named: Vec<&str> = rest.iter().take_while(|word| !word.starts_with("--")).copied().collect();
    // The command whose words the line starts with, the longest when one
    // command's words begin another's (`doctor`, `doctor check`).
    let Some(spec) = COMMANDS
        .iter()
        .filter(|spec| named.len() >= spec.words.len() && named[..spec.words.len()] == *spec.words)
        .max_by_key(|spec| spec.words.len())
    else {
        let commands = commands();
        let Some(first) = named.first() else {
            return Err(say::refuse(
                &own::COMMAND_ARGUMENTS,
                &own::COMMAND_ARGUMENTS_COMMAND_ABSENT,
                &[("quoted_arguments", &quoted_arguments), ("commands", &commands)],
            ));
        };
        // A group's word and the one after it, when that is what was meant.
        let tried: Vec<&str> = match COMMANDS.iter().any(|spec| spec.words.len() > 1 && spec.words[0] == *first) {
            true => named.iter().take(2).copied().collect(),
            false => vec![*first],
        };
        return Err(say::refuse(
            &own::COMMAND_ARGUMENTS,
            &own::COMMAND_ARGUMENTS_COMMAND_UNKNOWN,
            &[("quoted_command", &quoted(&tried.join(" "))), ("commands", &commands)],
        ));
    };
    let command = spec.words.join(" ");
    let mut operands = Vec::new();
    let mut options = Vec::new();
    let mut after = rest[spec.words.len()..].iter();
    while let Some(word) = after.next() {
        if !word.starts_with("--") {
            operands.push((*word).to_owned());
            continue;
        }
        let Some(&(option, takes)) = spec.options.iter().find(|(option, _)| option == word) else {
            let listed: Vec<&str> = spec.options.iter().map(|(option, _)| *option).collect();
            let options = match listed.is_empty() {
                true => "none".to_owned(),
                false => listed.join(", "),
            };
            return Err(say::refuse(
                &own::COMMAND_ARGUMENTS,
                &own::COMMAND_ARGUMENTS_OPTION_UNKNOWN,
                &[("command", &command), ("quoted_option", &quoted(*word)), ("options", &options), ("usage", spec.usage)],
            ));
        };
        if !takes {
            options.push((option, None));
            continue;
        }
        match after.next() {
            Some(value) => options.push((option, Some((*value).to_owned()))),
            None => {
                return Err(say::refuse(
                    &own::COMMAND_ARGUMENTS,
                    &own::COMMAND_ARGUMENTS_OPTION_VALUE_MISSING,
                    &[("option", option), ("quoted_arguments", &quoted_arguments), ("placeholder", "<text>")],
                ))
            }
        }
    }
    let quoted_operands = quoted(&operands);
    if operands.len() < spec.operands {
        let given = match operands.len() {
            0 => "none".to_owned(),
            count => count.to_string(),
        };
        return Err(say::refuse(
            &own::COMMAND_ARGUMENTS,
            &own::COMMAND_ARGUMENTS_OPERAND_MISSING,
            &[("command", &command), ("wanted", spec.wanted), ("given", &given), ("quoted_operands", &quoted_operands), ("usage", spec.usage)],
        ));
    }
    if let Some(extra) = operands.get(spec.operands) {
        return Err(say::refuse(
            &own::COMMAND_ARGUMENTS,
            &own::COMMAND_ARGUMENTS_OPERAND_EXTRA,
            &[("command", &command), ("wanted", spec.wanted), ("quoted_extra", &quoted(extra)), ("quoted_operands", &quoted_operands), ("usage", spec.usage)],
        ));
    }
    Ok(Line { spec, operands, options, product, text, arguments })
}
