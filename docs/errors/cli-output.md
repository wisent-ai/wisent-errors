<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: cli-output

Every way the cli-output functionalities of this package fail, as their refusals say it.

## `wisent_errors.cli_output.read_json`

read one JSON input file a command was named and decode it into the type the command reads

Started through: `Rust: cli_output::read_json`. Uses: none.

<a id="wisent_errors-cli_output-read_json-input-absent"></a>

### `wisent_errors.cli_output.read_json.input-absent`

- **What failed:** reading the JSON input {path}
- **Cause:** no file is at that path
- **Observed state shown:** {parent}; the operating system answered {error}
- **Fix:** name a file that exists, or write it first; a relative path is read from {cwd}
- **Code:** `not_found`, exit 2
- **Test:** Rust `tests/cli-output/read_json.rs::an_absent_input_is_refused`

<a id="wisent_errors-cli_output-read_json-input-not-permitted"></a>

### `wisent_errors.cli_output.read_json.input-not-permitted`

- **What failed:** reading the JSON input {path}
- **Cause:** the file exists but this process may not read it
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running the command read it (chmod u+r {path}), or run the command as its owner
- **Code:** `refused`, exit 1
- **Test:** Rust `tests/cli-output/read_json.rs::an_unreadable_input_is_refused`

<a id="wisent_errors-cli_output-read_json-input-is-directory"></a>

### `wisent_errors.cli_output.read_json.input-is-directory`

- **What failed:** reading the JSON input {path}
- **Cause:** the path names a directory, not a file
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** name the JSON file inside it, not the directory
- **Code:** `not_found`, exit 2
- **Test:** Rust `tests/cli-output/read_json.rs::a_directory_input_is_refused`

<a id="wisent_errors-cli_output-read_json-input-read-interrupted"></a>

### `wisent_errors.cli_output.read_json.input-read-interrupted`

- **What failed:** reading the JSON input {path}
- **Cause:** the file opened but the operating system stopped the read part way, so the bytes in hand are not the whole file
- **Observed state shown:** {state}; the read ended with {kind}: {error}
- **Fix:** run the command again once the disk or the network share holding {path} answers; `ls -l {path}` shows whether it is still there
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/cli-output/read_json.rs::an_interrupted_read_is_refused`

<a id="wisent_errors-cli_output-read_json-input-not-json"></a>

### `wisent_errors.cli_output.read_json.input-not-json`

- **What failed:** decoding the JSON input {path}
- **Cause:** the file is not JSON: at line {line}, column {column} it holds a character JSON does not allow there
- **Observed state shown:** {bytes} bytes, line {line} reads {quoted_line}; the decoder answered {error}
- **Fix:** write valid JSON at line {line} of {path}, or name the file the command expects; `jq . {path}` shows the same place
- **Code:** `config`, exit 1
- **Test:** Rust `tests/cli-output/read_json.rs::an_input_that_is_not_json_is_refused`

<a id="wisent_errors-cli_output-read_json-input-truncated"></a>

### `wisent_errors.cli_output.read_json.input-truncated`

- **What failed:** decoding the JSON input {path}
- **Cause:** the JSON ends before its last value closes, so the file is cut short or still being written
- **Observed state shown:** {bytes} bytes, ending at line {line}, column {column}; the decoder answered {error}
- **Fix:** finish writing {path}, or write it again whole, before running the command
- **Code:** `config`, exit 1
- **Test:** Rust `tests/cli-output/read_json.rs::a_truncated_input_is_refused`

<a id="wisent_errors-cli_output-read_json-input-wrong-shape"></a>

### `wisent_errors.cli_output.read_json.input-wrong-shape`

- **What failed:** decoding the JSON input {path} as {expected}
- **Cause:** the file is JSON but not the document the command reads: a field is missing, extra, or of another type
- **Observed state shown:** at line {line}, column {column}; the decoder answered {error}
- **Fix:** give the document the fields {expected} declares, or name the file meant for this command
- **Code:** `config`, exit 1
- **Test:** Rust `tests/cli-output/read_json.rs::an_input_of_the_wrong_shape_is_refused`

## `wisent_errors.cli_output.print`

print a command's result as pretty JSON, or with --text as one path: value line per field, from the same document

Started through: `Rust: cli_output::output`. Uses: none.

<a id="wisent_errors-cli_output-print-document-unrepresentable"></a>

### `wisent_errors.cli_output.print.document-unrepresentable`

- **What failed:** turning the result of type {type} into JSON
- **Cause:** the result holds a value JSON has no form for, such as a map whose keys are not text
- **Observed state shown:** the encoder answered {error}
- **Fix:** give {type} keys that serialize as strings, or a Serialize form that writes them as text
- **Code:** `config`, exit 1
- **Test:** Rust `tests/cli-output/print.rs::a_result_json_cannot_hold_is_refused`

<a id="wisent_errors-cli_output-print-output-closed"></a>

### `wisent_errors.cli_output.print.output-closed`

- **What failed:** writing {bytes} bytes of the result to standard output
- **Cause:** whatever read standard output closed it before the result was written
- **Observed state shown:** the write ended with {kind}: {error}
- **Fix:** keep the reading end open until the command ends, as in `command | jq .` rather than a reader that stops early
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/cli-output/print.rs::a_closed_standard_output_is_refused`

<a id="wisent_errors-cli_output-print-output-unwritable"></a>

### `wisent_errors.cli_output.print.output-unwritable`

- **What failed:** writing {bytes} bytes of the result to standard output
- **Cause:** the operating system refused the write for a reason other than a closed reader: a full disk behind a redirect, or a device gone
- **Observed state shown:** the write ended with {kind}: {error}
- **Fix:** free space on the disk standard output is redirected to, or redirect it elsewhere, and run the command again
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/cli-output/print.rs::an_unwritable_standard_output_is_refused`
