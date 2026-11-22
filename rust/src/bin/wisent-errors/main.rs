//! `wisent-errors`: the command line of this crate. It carries the telemetry
//! and support commands every product CLI carries from the crate
//! (`telemetry status|level|on|off|failure|command|help|show|events|export|flush`,
//! `support report|status`), run for the product a product file names, so a
//! product written in any language reports through it; a `doctor` over its
//! own functionalities and its failure catalogue (`errors list`); its
//! declared warnings (`warnings list|page`); and the checks a product's CI
//! runs on what its own `errors list`, `doctor --json` and `warnings list`
//! print (`doctor check`, `warnings check`). docs/command-line.md is its page.
//!
//!   wisent-errors [--product <file>] [--text] <command> [operands] [options]
//!
//! A result is printed through `cli_output::output`; a refusal is the three
//! lines every command of this package prints, the cause a declared one of
//! catalogue/failures/, and the process exits with the status it declares.

mod arguments;
mod check;
mod commands;
mod doctor;
mod product;
mod say;

use std::process::ExitCode;

fn main() -> ExitCode {
    // A word that is not UTF-8 is read with its stray bytes replaced, as a
    // refusal quotes it; every operand this command reads is text.
    let words: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|word| word.to_string_lossy().into_owned())
        .collect();
    let line = match arguments::read(words) {
        Ok(line) => line,
        Err(status) => return status,
    };
    if !line.spec.product {
        return match line.spec.words {
            ["telemetry", "events"] => commands::events(line.text),
            ["errors", "list"] => commands::errors_list(line.text),
            ["errors", "page"] => commands::errors_page(),
            ["warnings", "list"] => commands::warnings_list(line.text),
            ["warnings", "page"] => commands::warnings_page(),
            ["doctor", "check"] => check::doctor(&line.operands[0], &line.operands[1], line.text),
            _ => check::warnings(&line.operands[0], line.text),
        };
    }
    let named = match product::read(&line) {
        Ok(named) => named,
        Err(status) => return status,
    };
    match line.spec.words {
        ["doctor"] => doctor::run(named.product, named.path, line.flag("--json"), line.text),
        _ => commands::run(&line, &named),
    }
}
