// Generated from catalogue/failures/cli-output.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

//! This crate's own failures of the cli-output functionalities.

use crate::{Cause, Code, Operation};

pub static CLI_OUTPUT_READ_JSON_INPUT_ABSENT: Cause = Cause {
    id: "input-absent",
    code: Code::NotFound,
    usage: true,
    exit: None,
    failed: "reading the JSON input {path}",
    cause: "no file is at that path",
    observed: "{parent}; the operating system answered {error}",
    remedy: "name a file that exists, or write it first; a relative path is read from {cwd}",
    test: "tests/cli-output/read_json.rs::an_absent_input_is_refused",
};

pub static CLI_OUTPUT_READ_JSON_INPUT_NOT_PERMITTED: Cause = Cause {
    id: "input-not-permitted",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "reading the JSON input {path}",
    cause: "the file exists but this process may not read it",
    observed: "{state}; the operating system answered {error}",
    remedy: "let the user running the command read it (chmod u+r {path}), or run the command as its owner",
    test: "tests/cli-output/read_json.rs::an_unreadable_input_is_refused",
};

pub static CLI_OUTPUT_READ_JSON_INPUT_IS_DIRECTORY: Cause = Cause {
    id: "input-is-directory",
    code: Code::NotFound,
    usage: true,
    exit: None,
    failed: "reading the JSON input {path}",
    cause: "the path names a directory, not a file",
    observed: "{state}; the operating system answered {error}",
    remedy: "name the JSON file inside it, not the directory",
    test: "tests/cli-output/read_json.rs::a_directory_input_is_refused",
};

pub static CLI_OUTPUT_READ_JSON_INPUT_READ_INTERRUPTED: Cause = Cause {
    id: "input-read-interrupted",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "reading the JSON input {path}",
    cause: "the file opened but the operating system stopped the read part way, so the bytes in hand are not the whole file",
    observed: "{state}; the read ended with {kind}: {error}",
    remedy: "run the command again once the disk or the network share holding {path} answers; `ls -l {path}` shows whether it is still there",
    test: "tests/cli-output/read_json.rs::an_interrupted_read_is_refused",
};

pub static CLI_OUTPUT_READ_JSON_INPUT_NOT_JSON: Cause = Cause {
    id: "input-not-json",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "decoding the JSON input {path}",
    cause: "the file is not JSON: at line {line}, column {column} it holds a character JSON does not allow there",
    observed: "{bytes} bytes, line {line} reads {quoted_line}; the decoder answered {error}",
    remedy: "write valid JSON at line {line} of {path}, or name the file the command expects; `jq . {path}` shows the same place",
    test: "tests/cli-output/read_json.rs::an_input_that_is_not_json_is_refused",
};

pub static CLI_OUTPUT_READ_JSON_INPUT_TRUNCATED: Cause = Cause {
    id: "input-truncated",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "decoding the JSON input {path}",
    cause: "the JSON ends before its last value closes, so the file is cut short or still being written",
    observed: "{bytes} bytes, ending at line {line}, column {column}; the decoder answered {error}",
    remedy: "finish writing {path}, or write it again whole, before running the command",
    test: "tests/cli-output/read_json.rs::a_truncated_input_is_refused",
};

pub static CLI_OUTPUT_READ_JSON_INPUT_WRONG_SHAPE: Cause = Cause {
    id: "input-wrong-shape",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "decoding the JSON input {path} as {expected}",
    cause: "the file is JSON but not the document the command reads: a field is missing, extra, or of another type",
    observed: "at line {line}, column {column}; the decoder answered {error}",
    remedy: "give the document the fields {expected} declares, or name the file meant for this command",
    test: "tests/cli-output/read_json.rs::an_input_of_the_wrong_shape_is_refused",
};

pub static CLI_OUTPUT_READ_JSON: Operation = Operation {
    id: "wisent_errors.cli_output.read_json",
    entries: &["Rust: cli_output::read_json"],
    uses: &[],
    summary: "read one JSON input file a command was named and decode it into the type the command reads",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/cli-output.md",
    causes: &[&CLI_OUTPUT_READ_JSON_INPUT_ABSENT, &CLI_OUTPUT_READ_JSON_INPUT_NOT_PERMITTED, &CLI_OUTPUT_READ_JSON_INPUT_IS_DIRECTORY, &CLI_OUTPUT_READ_JSON_INPUT_READ_INTERRUPTED, &CLI_OUTPUT_READ_JSON_INPUT_NOT_JSON, &CLI_OUTPUT_READ_JSON_INPUT_TRUNCATED, &CLI_OUTPUT_READ_JSON_INPUT_WRONG_SHAPE],
    warnings: &[],
};

pub static CLI_OUTPUT_PRINT_DOCUMENT_UNREPRESENTABLE: Cause = Cause {
    id: "document-unrepresentable",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "turning the result of type {type} into JSON",
    cause: "the result holds a value JSON has no form for, such as a map whose keys are not text",
    observed: "the encoder answered {error}",
    remedy: "give {type} keys that serialize as strings, or a Serialize form that writes them as text",
    test: "tests/cli-output/print.rs::a_result_json_cannot_hold_is_refused",
};

pub static CLI_OUTPUT_PRINT_OUTPUT_CLOSED: Cause = Cause {
    id: "output-closed",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "writing {bytes} bytes of the result to standard output",
    cause: "whatever read standard output closed it before the result was written",
    observed: "the write ended with {kind}: {error}",
    remedy: "keep the reading end open until the command ends, as in `command | jq .` rather than a reader that stops early",
    test: "tests/cli-output/print.rs::a_closed_standard_output_is_refused",
};

pub static CLI_OUTPUT_PRINT_OUTPUT_UNWRITABLE: Cause = Cause {
    id: "output-unwritable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "writing {bytes} bytes of the result to standard output",
    cause: "the operating system refused the write for a reason other than a closed reader: a full disk behind a redirect, or a device gone",
    observed: "the write ended with {kind}: {error}",
    remedy: "free space on the disk standard output is redirected to, or redirect it elsewhere, and run the command again",
    test: "tests/cli-output/print.rs::an_unwritable_standard_output_is_refused",
};

pub static CLI_OUTPUT_PRINT: Operation = Operation {
    id: "wisent_errors.cli_output.print",
    entries: &["Rust: cli_output::output"],
    uses: &[],
    summary: "print a command's result as pretty JSON, or with --text as one path: value line per field, from the same document",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/cli-output.md",
    causes: &[&CLI_OUTPUT_PRINT_DOCUMENT_UNREPRESENTABLE, &CLI_OUTPUT_PRINT_OUTPUT_CLOSED, &CLI_OUTPUT_PRINT_OUTPUT_UNWRITABLE],
    warnings: &[],
};
