<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: command

Every way the command functionalities of this package fail, as their refusals say it.

## `wisent_errors.command.arguments`

read the words of a wisent-errors command line: the command it names, the operands it gives and the options it sets

Started through: `wisent-errors <command>`. Uses: none.

<a id="wisent_errors-command-arguments-command-absent"></a>

### `wisent_errors.command.arguments.command-absent`

- **What failed:** reading the command wisent-errors was asked to run
- **Cause:** the command line names no command, only options or nothing
- **Observed state shown:** the arguments were {quoted_arguments}; the commands are {commands}
- **Fix:** name one of the commands after the options, as in `wisent-errors --product <file> telemetry status`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read`

<a id="wisent_errors-command-arguments-command-unknown"></a>

### `wisent_errors.command.arguments.command-unknown`

- **What failed:** reading the command {quoted_command}
- **Cause:** wisent-errors has no command of that name
- **Observed state shown:** the commands are {commands}
- **Fix:** name one of {commands}
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read`

<a id="wisent_errors-command-arguments-operand-missing"></a>

### `wisent_errors.command.arguments.operand-missing`

- **What failed:** reading the operands of `wisent-errors {command}`
- **Cause:** the command takes {wanted} and was given {given}
- **Observed state shown:** its operands were {quoted_operands}
- **Fix:** give {wanted}, as in `{usage}`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events`

<a id="wisent_errors-command-arguments-operand-extra"></a>

### `wisent_errors.command.arguments.operand-extra`

- **What failed:** reading the operands of `wisent-errors {command}`
- **Cause:** the command takes {wanted}, and {quoted_extra} is more than it reads
- **Observed state shown:** its operands were {quoted_operands}
- **Fix:** drop {quoted_extra}, or quote an operand that holds spaces as one word, as in `{usage}`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/store.rs::telemetry_status_says_every_file_as_it_finds_it`

<a id="wisent_errors-command-arguments-option-unknown"></a>

### `wisent_errors.command.arguments.option-unknown`

- **What failed:** reading the options of `wisent-errors {command}`
- **Cause:** {quoted_option} is not an option the command takes
- **Observed state shown:** its options are {options}
- **Fix:** drop {quoted_option}, or write in its place an option the command takes, as in `{usage}`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read`

<a id="wisent_errors-command-arguments-option-value-missing"></a>

### `wisent_errors.command.arguments.option-value-missing`

- **What failed:** reading the option {option}
- **Cause:** the option takes a value and is the last word of the command line
- **Observed state shown:** the arguments were {quoted_arguments}
- **Fix:** give its value right after it, as in `{option} {placeholder}`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read`

<a id="wisent_errors-command-arguments-number-invalid"></a>

### `wisent_errors.command.arguments.number-invalid`

- **What failed:** reading {what} for `wisent-errors {command}`
- **Cause:** {quoted_value} is not a whole number
- **Observed state shown:** its operands were {quoted_operands}
- **Fix:** give {what} as a whole number, as in `{usage}`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/queued/signals.rs::telemetry_command_queues_usage_and_counts_a_usage_loop`

<a id="wisent_errors-command-arguments-code-unknown"></a>

### `wisent_errors.command.arguments.code-unknown`

- **What failed:** reading the code of the failure at {point}
- **Cause:** {quoted_code} is not a code of the fleet's vocabulary
- **Observed state shown:** the codes are {codes}
- **Fix:** name one of {codes}; catalogue/codes.json says what each one means
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/queued/signals.rs::telemetry_failure_queues_the_failure_and_counts_a_repeat_in_a_row`

## `wisent_errors.command.product`

read the product file that names which product a telemetry, support or doctor command speaks for: its id, its app id and its version

Started through: `wisent-errors --product <file> <command>`. Uses: `wisent_errors.cli_output.read_json`.

<a id="wisent_errors-command-product-product-unnamed"></a>

### `wisent_errors.command.product.product-unnamed`

- **What failed:** running `wisent-errors {command}`
- **Cause:** the command speaks for a product and no --product names the product's file
- **Observed state shown:** the arguments were {quoted_arguments}
- **Fix:** name the product's file before the command, as in `wisent-errors --product product.json {command}`: a JSON object with its id, app_id and version
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read`

<a id="wisent_errors-command-product-product-field-invalid"></a>

### `wisent_errors.command.product.product-field-invalid`

- **What failed:** reading the product file {path}
- **Cause:** its {field} is not {wanted}
- **Observed state shown:** {field} holds {found}
- **Fix:** write {field} in {path} as {wanted}, as in {example}
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/main.rs::the_command_line_says_which_word_it_cannot_read`

## `wisent_errors.command.check`

hold a product's doctor findings to the functionalities its failure catalogue declares, and its warnings to the declaration rules, as the product's CI runs them

Started through: `wisent-errors doctor check <errors-list.json> <doctor.json>`, `wisent-errors warnings check <warnings-list.json>`. Uses: `wisent_errors.cli_output.read_json`.

<a id="wisent_errors-command-check-input-shape-invalid"></a>

### `wisent_errors.command.check.input-shape-invalid`

- **What failed:** reading {what} {path}
- **Cause:** {place} is not {wanted}
- **Observed state shown:** {place} holds {found}
- **Fix:** name the file {source} printed, or print it again with {source}
- **Class:** `config`, exit 1
- **Test:** Rust `tests/diagnosis/main.rs::doctor_check_holds_the_findings_to_the_errors_list`

<a id="wisent_errors-command-check-doctor-incomplete"></a>

### `wisent_errors.command.check.doctor-incomplete`

- **What failed:** holding the doctor's findings in {doctor} to the functionalities {listing} declares
- **Cause:** {count} problem(s) keep the doctor from trying each functionality once: {problems}
- **Observed state shown:** {declared} functionality(ies) with an entry point declared, {findings} finding(s) reported
- **Fix:** give every functionality with an entry point one diagnosis check, a probe or a skip saying why, drop a second check and every check of a functionality the catalogue does not declare, then print the findings again with `<product> doctor --json`
- **Class:** `refused`, exit 1
- **Test:** Rust `tests/diagnosis/main.rs::doctor_check_holds_the_findings_to_the_errors_list`

<a id="wisent_errors-command-check-warnings-invalid"></a>

### `wisent_errors.command.check.warnings-invalid`

- **What failed:** holding the warnings {listing} declares to the declaration rules
- **Cause:** {count} problem(s) in the declarations: {problems}
- **Observed state shown:** {warnings} warning(s) of {operations} functionality(ies) read
- **Fix:** change each declaration as its problem says, in the product's code, then print the listing again with `<product> warnings list`
- **Class:** `refused`, exit 1
- **Test:** Rust `tests/warnings/declaration.rs::warnings_check_holds_each_warning_to_the_declaration_rules`
