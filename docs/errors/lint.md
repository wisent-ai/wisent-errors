<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: lint

Every way the lint functionalities of this package fail, as their refusals say it.

## `wisent_errors.lint.scan`

refuse an error message in a product's source that says a failure happened without saying which, against a baseline that only shrinks

Started through: `node ci/error-standard.mjs scan`. Uses: `wisent_errors.lint.arguments`, `wisent_errors.lint.input`, `wisent_errors.lint.paths`.

<a id="wisent_errors-lint-scan-generic-sentence-held"></a>

### `wisent_errors.lint.scan.generic-sentence-held`

- **What failed:** holding {path} to the error standard
- **Cause:** line {line} says {quoted_sentence}, which {reason}, and the baseline allows {allowed} of it in this file while it holds {held}
- **Observed state shown:** {text}
- **Fix:** declare the cause and raise it, saying what failed, why, the state observed and what fixes it, in place of the sentence
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/scan.mjs::a_generic_sentence_beyond_the_baseline_is_refused`

<a id="wisent_errors-lint-scan-baseline-stale"></a>

### `wisent_errors.lint.scan.baseline-stale`

- **What failed:** holding {path} to the baseline {baseline}
- **Cause:** the baseline allows {allowed} of {quoted_sentence} in the file while it holds {held}, and a baseline only shrinks
- **Observed state shown:** {held} held, {allowed} allowed
- **Fix:** lower the entry for {path} in {baseline} to {held}
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/scan.mjs::a_baseline_above_what_a_file_holds_is_refused`

## `wisent_errors.lint.catalogue`

hold the failure catalogue a product prints to the declaration rules, its tests, the values its raising sites pass and the entries it has

Started through: `node ci/error-standard.mjs catalogue`, `node ci/error-standard.mjs errors`. Uses: `wisent_errors.lint.arguments`, `wisent_errors.lint.input`, `wisent_errors.lint.paths`.

<a id="wisent_errors-lint-catalogue-declaration-refused"></a>

### `wisent_errors.lint.catalogue.declaration-refused`

- **What failed:** holding {operation} to the declaration rules
- **Cause:** {count} of its declarations break a rule, each named on its own line below
- **Observed state shown:** {problems}
- **Fix:** change each declaration as its line says, then run the check again
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/catalogue.mjs::a_cause_with_an_unfilled_placeholder_is_refused`

<a id="wisent_errors-lint-catalogue-placeholder-unpassed"></a>

### `wisent_errors.lint.catalogue.placeholder-unpassed`

- **What failed:** holding {operation}.{cause_id} to the values its raising sites pass
- **Cause:** `{field}` names {placeholder}, and no raising site in {repository} passes a value of that name, so every reader would see {placeholder} as written
- **Observed state shown:** {sites} source file(s) read; value names passed: {passed}
- **Fix:** pass {name} where the cause is raised, or take {placeholder} out of `{field}`
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/catalogue.mjs::a_placeholder_no_raising_site_passes_is_refused`

<a id="wisent_errors-lint-catalogue-test-absent"></a>

### `wisent_errors.lint.catalogue.test-absent`

- **What failed:** reading the test {operation}.{cause_id} names
- **Cause:** {why}, and {untested} does not list it with the reason it cannot be provoked locally
- **Observed state shown:** {test}
- **Fix:** write that test, name the one that provokes the cause, or list {test} in {untested} with why no local state can provoke it
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/catalogue.mjs::a_cause_whose_test_is_absent_is_refused`

<a id="wisent_errors-lint-catalogue-untested-listing-malformed"></a>

### `wisent_errors.lint.catalogue.untested-listing-malformed`

- **What failed:** reading the untested causes {untested}
- **Cause:** entry {position} is not a test path with a reason: it holds {found}
- **Observed state shown:** {count} entries
- **Fix:** write each entry as {example}
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/lint/catalogue.mjs::a_malformed_untested_listing_is_refused`

<a id="wisent_errors-lint-catalogue-entry-unstarted"></a>

### `wisent_errors.lint.catalogue.entry-unstarted`

- **What failed:** matching the entries in {entries} to the declared functionalities
- **Cause:** the entry {quoted_entry} starts no declared functionality, so whoever meets its failures has no declaration to read
- **Observed state shown:** {count} entries listed, {functionalities} functionalities declared
- **Fix:** declare every functionality it runs and name {quoted_entry} in their entries
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/catalogue.mjs::an_entry_no_functionality_names_is_refused`

## `wisent_errors.lint.warnings`

hold the warnings a product prints to the declaration rules, their tests and one warning for every confirmation

Started through: `node ci/warning-standard.mjs`. Uses: `wisent_errors.lint.arguments`, `wisent_errors.lint.input`, `wisent_errors.lint.paths`.

<a id="wisent_errors-lint-warnings-warning-refused"></a>

### `wisent_errors.lint.warnings.warning-refused`

- **What failed:** holding {operation} to the warning rules
- **Cause:** {count} of its warning declarations break a rule, each named on its own line
- **Observed state shown:** {problems}
- **Fix:** change each declaration as its line says, then run the check again
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/warnings/standard.mjs::a_warning_with_an_empty_safeguard_is_refused`

<a id="wisent_errors-lint-warnings-confirmation-unwarned"></a>

### `wisent_errors.lint.warnings.confirmation-unwarned`

- **What failed:** matching the confirmations in {confirmations} to the declared warnings
- **Cause:** the entry {quoted_entry} asks for a confirmation, but no functionality it starts declares what the confirmation is for
- **Observed state shown:** functionalities it starts: {starts}
- **Fix:** declare the warning, or stop asking for a confirmation nothing needs
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/warnings/standard.mjs::a_confirmation_no_warning_explains_is_refused`

## `wisent_errors.lint.handrolled`

list every line of a consuming tree that writes an envelope key by hand instead of building the envelope with this package

Started through: `node ci/no-handrolled-envelope.mjs`. Uses: `wisent_errors.lint.arguments`, `wisent_errors.lint.paths`.

<a id="wisent_errors-lint-handrolled-envelope-key-written"></a>

### `wisent_errors.lint.handrolled.envelope-key-written`

- **What failed:** reading {files} source file(s) under {roots} for hand-built envelopes
- **Cause:** {count} line(s) write failure_point or error_code outside the package, so their derived fields can drift from the catalogue
- **Observed state shown:** {sites}
- **Fix:** build each envelope with wisent-errors; a log line already parsed, a field declaration or another API's own error_code is a reason to keep the line, and reading it decides which
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/handrolled.mjs::a_hand_built_envelope_is_listed`

## `wisent_errors.lint.arguments`

read the words a command of this repository was started with: its command, its options and its operands

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent_errors-lint-arguments-command-absent"></a>

### `wisent_errors.lint.arguments.command-absent`

- **What failed:** starting {program}
- **Cause:** no command was named, and {program} does nothing without one
- **Observed state shown:** commands: {commands}
- **Fix:** name one of them: {usage}
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/arguments.mjs::no_command_is_refused`

<a id="wisent_errors-lint-arguments-command-unknown"></a>

### `wisent_errors.lint.arguments.command-unknown`

- **What failed:** starting {program}
- **Cause:** {quoted_command} is not one of its commands
- **Observed state shown:** commands: {commands}
- **Fix:** name one of them: {usage}
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/arguments.mjs::an_unknown_command_is_refused`

<a id="wisent_errors-lint-arguments-option-without-value"></a>

### `wisent_errors.lint.arguments.option-without-value`

- **What failed:** reading the options of {program}
- **Cause:** {option} is the last word, or the word after it is another option, so it names nothing
- **Observed state shown:** the words given: {words}
- **Fix:** give {option} its value: {usage}
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/arguments.mjs::an_option_without_its_value_is_refused`

<a id="wisent_errors-lint-arguments-option-unknown"></a>

### `wisent_errors.lint.arguments.option-unknown`

- **What failed:** reading the options of {program}
- **Cause:** {option} is not one of its options, and nothing it does reads it
- **Observed state shown:** the words given: {words}
- **Fix:** drop {option} or spell it as one of its options: {usage}
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/arguments.mjs::an_unknown_option_is_refused`

<a id="wisent_errors-lint-arguments-operands-miscounted"></a>

### `wisent_errors.lint.arguments.operands-miscounted`

- **What failed:** reading the operands of {program}
- **Cause:** it takes {expected} and was given {count}
- **Observed state shown:** operands given: {operands}
- **Fix:** name exactly {expected}: {usage}
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/arguments.mjs::a_wrong_number_of_operands_is_refused`

## `wisent_errors.lint.input`

read one JSON file a command of this repository was named: a catalogue, a baseline, an entry list, a list of untested causes

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent_errors-lint-input-input-absent"></a>

### `wisent_errors.lint.input.input-absent`

- **What failed:** reading {what} {path}
- **Cause:** no file is at that path
- **Observed state shown:** {parent}
- **Fix:** name the file that holds {what}, or write it first; a relative path is read from {cwd}
- **Code:** `not_found`, exit 2
- **Test:** JavaScript `tests/lint/input.mjs::an_absent_input_is_refused`

<a id="wisent_errors-lint-input-input-is-directory"></a>

### `wisent_errors.lint.input.input-is-directory`

- **What failed:** reading {what} {path}
- **Cause:** the path names a directory, and {what} is one file
- **Observed state shown:** {state}
- **Fix:** name the JSON file inside it, not the directory
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/input.mjs::a_directory_input_is_refused`

<a id="wisent_errors-lint-input-input-not-permitted"></a>

### `wisent_errors.lint.input.input-not-permitted`

- **What failed:** reading {what} {path}
- **Cause:** the file exists but its permissions refuse this process the read
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running the command read it (chmod u+r {path}), or run the command as its owner
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/input.mjs::an_input_the_process_may_not_read_is_refused`

<a id="wisent_errors-lint-input-input-not-json"></a>

### `wisent_errors.lint.input.input-not-json`

- **What failed:** reading {what} {path}
- **Cause:** the file is not JSON
- **Observed state shown:** {bytes} bytes, starting {quoted_start}; the decoder answered {error}, stopping at {stop}
- **Fix:** write {what} as JSON ({expected}), correcting {path} at {stop}
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/lint/input.mjs::an_input_that_is_not_json_is_refused`

<a id="wisent_errors-lint-input-input-wrong-shape"></a>

### `wisent_errors.lint.input.input-wrong-shape`

- **What failed:** reading {what} {path}
- **Cause:** the file is JSON but not {expected}
- **Observed state shown:** it holds {found}
- **Fix:** write {what} as {expected}
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/lint/input.mjs::an_input_of_the_wrong_shape_is_refused`

## `wisent_errors.lint.paths`

open a directory or a file a command of this repository was named to read: a source tree, a repository, a root to search

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent_errors-lint-paths-path-absent"></a>

### `wisent_errors.lint.paths.path-absent`

- **What failed:** opening {what} {path}
- **Cause:** nothing is at that path, so there is nothing to read and nothing could be found clean
- **Observed state shown:** {parent}
- **Fix:** name {what} as it exists; a relative path is read from {cwd}
- **Code:** `not_found`, exit 2
- **Test:** JavaScript `tests/lint/paths.mjs::an_absent_path_is_refused`

<a id="wisent_errors-lint-paths-path-not-directory"></a>

### `wisent_errors.lint.paths.path-not-directory`

- **What failed:** opening {what} {path}
- **Cause:** the path is a file, and {what} is read as a directory
- **Observed state shown:** {state}
- **Fix:** name the directory that holds it: {directory}
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/lint/paths.mjs::a_file_named_as_a_directory_is_refused`

<a id="wisent_errors-lint-paths-path-unreadable"></a>

### `wisent_errors.lint.paths.path-unreadable`

- **What failed:** reading {what} {path}
- **Cause:** the operating system refused to list or read it, so what it holds was never looked at
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running the command read it (chmod u+rx {path}), or leave it out of the paths named
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/lint/paths.mjs::an_unreadable_path_is_refused`
