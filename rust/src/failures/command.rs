// Generated from catalogue/failures/command.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

//! This crate's own failures of the command functionalities.

use crate::{Cause, Code, Operation};

pub static COMMAND_ARGUMENTS_COMMAND_ABSENT: Cause = Cause {
    id: "command-absent",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the command wisent-errors was asked to run",
    cause: "the command line names no command, only options or nothing",
    observed: "the arguments were {quoted_arguments}; the commands are {commands}",
    remedy: "name one of the commands after the options, as in `wisent-errors --product <file> telemetry status`",
    test: "tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read",
};

pub static COMMAND_ARGUMENTS_COMMAND_UNKNOWN: Cause = Cause {
    id: "command-unknown",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the command {quoted_command}",
    cause: "wisent-errors has no command of that name",
    observed: "the commands are {commands}",
    remedy: "name one of {commands}",
    test: "tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read",
};

pub static COMMAND_ARGUMENTS_OPERAND_MISSING: Cause = Cause {
    id: "operand-missing",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the operands of `wisent-errors {command}`",
    cause: "the command takes {wanted} and was given {given}",
    observed: "its operands were {quoted_operands}",
    remedy: "give {wanted}, as in `{usage}`",
    test: "tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events",
};

pub static COMMAND_ARGUMENTS_OPERAND_EXTRA: Cause = Cause {
    id: "operand-extra",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the operands of `wisent-errors {command}`",
    cause: "the command takes {wanted}, and {quoted_extra} is more than it reads",
    observed: "its operands were {quoted_operands}",
    remedy: "drop {quoted_extra}, or quote an operand that holds spaces as one word, as in `{usage}`",
    test: "tests/telemetry/store.rs::telemetry_status_says_every_file_as_it_finds_it",
};

pub static COMMAND_ARGUMENTS_OPTION_UNKNOWN: Cause = Cause {
    id: "option-unknown",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the options of `wisent-errors {command}`",
    cause: "{quoted_option} is not an option the command takes",
    observed: "its options are {options}",
    remedy: "drop {quoted_option}, or write in its place an option the command takes, as in `{usage}`",
    test: "tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read",
};

pub static COMMAND_ARGUMENTS_OPTION_VALUE_MISSING: Cause = Cause {
    id: "option-value-missing",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the option {option}",
    cause: "the option takes a value and is the last word of the command line",
    observed: "the arguments were {quoted_arguments}",
    remedy: "give its value right after it, as in `{option} {placeholder}`",
    test: "tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read",
};

pub static COMMAND_ARGUMENTS_NUMBER_INVALID: Cause = Cause {
    id: "number-invalid",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading {what} for `wisent-errors {command}`",
    cause: "{quoted_value} is not a whole number",
    observed: "its operands were {quoted_operands}",
    remedy: "give {what} as a whole number, as in `{usage}`",
    test: "tests/telemetry/queued/signals.rs::telemetry_command_queues_usage_and_counts_a_usage_loop",
};

pub static COMMAND_ARGUMENTS_CODE_UNKNOWN: Cause = Cause {
    id: "code-unknown",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "reading the code of the failure at {point}",
    cause: "{quoted_code} is not a code of the fleet's vocabulary",
    observed: "the codes are {codes}",
    remedy: "name one of {codes}; catalogue/codes.json says what each one means",
    test: "tests/telemetry/queued/signals.rs::telemetry_failure_queues_the_failure_and_counts_a_repeat_in_a_row",
};

pub static COMMAND_ARGUMENTS: Operation = Operation {
    id: "wisent_errors.command.arguments",
    entries: &["wisent-errors <command>"],
    uses: &[],
    summary: "read the words of a wisent-errors command line: the command it names, the operands it gives and the options it sets",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/command.md",
    causes: &[&COMMAND_ARGUMENTS_COMMAND_ABSENT, &COMMAND_ARGUMENTS_COMMAND_UNKNOWN, &COMMAND_ARGUMENTS_OPERAND_MISSING, &COMMAND_ARGUMENTS_OPERAND_EXTRA, &COMMAND_ARGUMENTS_OPTION_UNKNOWN, &COMMAND_ARGUMENTS_OPTION_VALUE_MISSING, &COMMAND_ARGUMENTS_NUMBER_INVALID, &COMMAND_ARGUMENTS_CODE_UNKNOWN],
    warnings: &[],
};

pub static COMMAND_PRODUCT_PRODUCT_UNNAMED: Cause = Cause {
    id: "product-unnamed",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "running `wisent-errors {command}`",
    cause: "the command speaks for a product and no --product names the product's file",
    observed: "the arguments were {quoted_arguments}",
    remedy: "name the product's file before the command, as in `wisent-errors --product product.json {command}`: a JSON object with its id, app_id and version",
    test: "tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read",
};

pub static COMMAND_PRODUCT_PRODUCT_FIELD_INVALID: Cause = Cause {
    id: "product-field-invalid",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading the product file {path}",
    cause: "its {field} is not {wanted}",
    observed: "{field} holds {found}",
    remedy: "write {field} in {path} as {wanted}, as in {example}",
    test: "tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read",
};

pub static COMMAND_PRODUCT: Operation = Operation {
    id: "wisent_errors.command.product",
    entries: &["wisent-errors --product <file> <command>"],
    uses: &[&super::CLI_OUTPUT_READ_JSON],
    summary: "read the product file that names which product a telemetry, support or doctor command speaks for: its id, its app id and its version",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/command.md",
    causes: &[&COMMAND_PRODUCT_PRODUCT_UNNAMED, &COMMAND_PRODUCT_PRODUCT_FIELD_INVALID],
    warnings: &[],
};

pub static COMMAND_CHECK_INPUT_SHAPE_INVALID: Cause = Cause {
    id: "input-shape-invalid",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading {what} {path}",
    cause: "{place} is not {wanted}",
    observed: "{place} holds {found}",
    remedy: "name the file {source} printed, or print it again with {source}",
    test: "tests/diagnosis/main.rs::doctor_check_holds_the_findings_to_the_errors_list",
};

pub static COMMAND_CHECK_DOCTOR_INCOMPLETE: Cause = Cause {
    id: "doctor-incomplete",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "holding the doctor's findings in {doctor} to the functionalities {listing} declares",
    cause: "{count} problem(s) keep the doctor from trying each functionality once: {problems}",
    observed: "{declared} functionality(ies) with an entry point declared, {findings} finding(s) reported",
    remedy: "give every functionality with an entry point one diagnosis check, a probe or a skip saying why, drop a second check and every check of a functionality the catalogue does not declare, then print the findings again with `<product> doctor --json`",
    test: "tests/diagnosis/main.rs::doctor_check_holds_the_findings_to_the_errors_list",
};

pub static COMMAND_CHECK_WARNINGS_INVALID: Cause = Cause {
    id: "warnings-invalid",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "holding the warnings {listing} declares to the declaration rules",
    cause: "{count} problem(s) in the declarations: {problems}",
    observed: "{warnings} warning(s) of {operations} functionality(ies) read",
    remedy: "change each declaration as its problem says, in the product's code, then print the listing again with `<product> warnings list`",
    test: "tests/warnings/declaration.rs::warnings_check_holds_each_warning_to_the_declaration_rules",
};

pub static COMMAND_CHECK: Operation = Operation {
    id: "wisent_errors.command.check",
    entries: &["wisent-errors doctor check <errors-list.json> <doctor.json>", "wisent-errors warnings check <warnings-list.json>"],
    uses: &[&super::CLI_OUTPUT_READ_JSON],
    summary: "hold a product's doctor findings to the functionalities its failure catalogue declares, and its warnings to the declaration rules, as the product's CI runs them",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/command.md",
    causes: &[&COMMAND_CHECK_INPUT_SHAPE_INVALID, &COMMAND_CHECK_DOCTOR_INCOMPLETE, &COMMAND_CHECK_WARNINGS_INVALID],
    warnings: &[],
};
