<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: swift-cli

Every way the swift-cli functionalities of this package fail, as their refusals say it.

## `wisent_errors.swift_cli.arguments`

read the command, options and operands a person or a script gave wisent-errors-swift, the Swift package's command line

Started through: `wisent-errors-swift`. Uses: none.

<a id="wisent_errors-swift_cli-arguments-command-absent"></a>

### `wisent_errors.swift_cli.arguments.command-absent`

- **What failed:** reading the command of `{given}`
- **Cause:** it names no command, so nothing would run
- **Observed state shown:** its commands: {commands}
- **Fix:** add one of {commands}, as in `{example}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it`

<a id="wisent_errors-swift_cli-arguments-command-unknown"></a>

### `wisent_errors.swift_cli.arguments.command-unknown`

- **What failed:** reading the command of `{given}`
- **Cause:** {quoted_command} is not one of its commands
- **Observed state shown:** its commands: {commands}
- **Fix:** run one of {commands}, as in `{example}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it`

<a id="wisent_errors-swift_cli-arguments-option-unknown"></a>

### `wisent_errors.swift_cli.arguments.option-unknown`

- **What failed:** reading the options of `wisent-errors-swift {command}`
- **Cause:** {quoted_option} is not one of its options
- **Observed state shown:** its options: {options}
- **Fix:** drop {quoted_option}, or give one of {options}
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/program/RunOutputTests.swift::test_program_run_refuses_a_command_line_it_cannot_read`

<a id="wisent_errors-swift_cli-arguments-option-value-absent"></a>

### `wisent_errors.swift_cli.arguments.option-value-absent`

- **What failed:** reading the options of `wisent-errors-swift {command}`
- **Cause:** {option} takes a value, and it is the last argument
- **Observed state shown:** arguments: {arguments}
- **Fix:** give {option} its value, as in `{example}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/program/RunOutputTests.swift::test_program_run_refuses_a_command_line_it_cannot_read`

<a id="wisent_errors-swift_cli-arguments-option-repeated"></a>

### `wisent_errors.swift_cli.arguments.option-repeated`

- **What failed:** reading the options of `wisent-errors-swift {command}`
- **Cause:** {option} takes one value and was given {count} times, so which one is meant cannot be read
- **Observed state shown:** its values: {values}
- **Fix:** give {option} once, as in `{example}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/declaration/DeclarationRuleTests.swift::test_declaration_cause_holds_one_cause_to_every_declaration_rule`

<a id="wisent_errors-swift_cli-arguments-option-required"></a>

### `wisent_errors.swift_cli.arguments.option-required`

- **What failed:** reading the options of `wisent-errors-swift {command}`
- **Cause:** it needs {option}, and {option} was not given
- **Observed state shown:** options given: {given}
- **Fix:** add {option}, as in `{example}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it`

<a id="wisent_errors-swift_cli-arguments-operands-wrong"></a>

### `wisent_errors.swift_cli.arguments.operands-wrong`

- **What failed:** reading the operands of `wisent-errors-swift {command}`
- **Cause:** it takes {expected}, and {count} were given
- **Observed state shown:** operands: {operands}
- **Fix:** run it as `wisent-errors-swift {usage}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one`

<a id="wisent_errors-swift_cli-arguments-value-unknown"></a>

### `wisent_errors.swift_cli.arguments.value-unknown`

- **What failed:** reading {option} of `wisent-errors-swift {command}`
- **Cause:** {quoted_value} is not one of its values
- **Observed state shown:** its values: {values}
- **Fix:** give {option} one of {values}
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it`

<a id="wisent_errors-swift_cli-arguments-value-malformed"></a>

### `wisent_errors.swift_cli.arguments.value-malformed`

- **What failed:** reading {option} of `wisent-errors-swift {command}`
- **Cause:** {quoted_value} is not {shape}
- **Observed state shown:** {found}
- **Fix:** give {option} {shape}, as in `{example}`
- **Class:** `usage`, exit 2
- **Test:** Swift `tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed`

## `wisent_errors.swift_cli.input`

read one JSON document a command of wisent-errors-swift was named, and decode it into what the command reads

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent_errors-swift_cli-input-input-absent"></a>

### `wisent_errors.swift_cli.input.input-absent`

- **What failed:** reading {what} from {path}
- **Cause:** no file is at that path
- **Observed state shown:** {parent}; the operating system answered {error}
- **Fix:** name a file that exists, or write it first; a relative path is read from {cwd}
- **Class:** `not_found`, exit 1
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one`

<a id="wisent_errors-swift_cli-input-input-is-directory"></a>

### `wisent_errors.swift_cli.input.input-is-directory`

- **What failed:** reading {what} from {path}
- **Cause:** the path names a directory, not a file
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** name the JSON file inside {path}, not the directory
- **Class:** `not_found`, exit 1
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one`

<a id="wisent_errors-swift_cli-input-input-not-permitted"></a>

### `wisent_errors.swift_cli.input.input-not-permitted`

- **What failed:** reading {what} from {path}
- **Cause:** the operating system refused this process the read
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running wisent-errors-swift read it (chmod u+r {path}), or run it as the file's owner
- **Class:** `refused`, exit 1
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one`

<a id="wisent_errors-swift_cli-input-input-read-failed"></a>

### `wisent_errors.swift_cli.input.input-read-failed`

- **What failed:** reading {what} from {path}
- **Cause:** the file is there and may be read, but the operating system stopped the read before its bytes were in hand
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** run the command again once the disk or the network share holding {path} answers; `ls -l {path}` shows whether it is still there
- **Class:** `infra_down`, exit 69
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_an_interrupted_read_is_refused`

<a id="wisent_errors-swift_cli-input-input-not-json"></a>

### `wisent_errors.swift_cli.input.input-not-json`

- **What failed:** decoding {what} from {path}
- **Cause:** the file is not JSON
- **Observed state shown:** {bytes} bytes; the reader answered {error}
- **Fix:** write {path} as JSON; `jq . {path}` points at the place it stops parsing
- **Class:** `config`, exit 1
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one`

<a id="wisent_errors-swift_cli-input-input-wrong-shape"></a>

### `wisent_errors.swift_cli.input.input-wrong-shape`

- **What failed:** decoding {what} from {path}
- **Cause:** the file is JSON, but not {shape}
- **Observed state shown:** {bytes} bytes; the decoder answered {error}
- **Fix:** write {path} as {shape}, as in {example}
- **Class:** `config`, exit 1
- **Test:** Swift `tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one`

## `wisent_errors.swift_cli.envelope_build`

build one failure envelope from its options, strictly or with the fallback that never refuses, print it and, with --out, write it to a file

Started through: `wisent-errors-swift envelope build`. Uses: `wisent_errors.envelope.build`.

<a id="wisent_errors-swift_cli-envelope_build-envelope-unwritten"></a>

### `wisent_errors.swift_cli.envelope_build.envelope-unwritten`

- **What failed:** writing the envelope to {path}
- **Cause:** the operating system refused to write the file there
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** name with --out a file in a directory this user can write, or leave --out out to print the envelope only
- **Class:** `config`, exit 1
- **Test:** Swift `tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it`

## `wisent_errors.swift_cli.envelope_read`

read one failure envelope from a JSON file and print it for a person: its rendered line, then its chain of causes

Started through: `wisent-errors-swift envelope read`. Uses: `wisent_errors.swift_cli.input`, `wisent_errors.envelope.build`.

## `wisent_errors.swift_cli.declaration_cause`

hold one cause, given field by field, to the declaration rules every runtime holds a catalogue to, and show the refusal it says with the values given

Started through: `wisent-errors-swift declaration cause`. Uses: none.

<a id="wisent_errors-swift_cli-declaration_cause-cause-broken"></a>

### `wisent_errors.swift_cli.declaration_cause.cause-broken`

- **What failed:** checking the cause {id}
- **Cause:** it breaks {count} declaration rule(s)
- **Observed state shown:** each is a line on stdout; the first: {first}
- **Fix:** correct the fields as each line says, then check the cause again; catalogue/declaration.json states every rule
- **Class:** `refused`, exit 1
- **Test:** Swift `tests/declaration/DeclarationRuleTests.swift::test_declaration_cause_holds_one_cause_to_every_declaration_rule`

## `wisent_errors.swift_cli.declaration_check`

hold every functionality of a product's `errors list --json` listing, read from a file, to the declaration rules

Started through: `wisent-errors-swift declaration check`. Uses: `wisent_errors.swift_cli.input`.

<a id="wisent_errors-swift_cli-declaration_check-listing-broken"></a>

### `wisent_errors.swift_cli.declaration_check.listing-broken`

- **What failed:** checking the functionalities listed in {path}
- **Cause:** {count} of its declarations break the declaration rules
- **Observed state shown:** {operations} functionalities read; each problem is a line on stdout; the first: {first}
- **Fix:** correct each declaration in the product's catalogue as its line says, then list and check it again
- **Class:** `refused`, exit 1
- **Test:** Swift `tests/explained/DescribedTests.swift::test_declaration_check_reads_a_listing_or_says_where_it_stops_being_one`

## `wisent_errors.swift_cli.telemetry`

keep a product's telemetry from a terminal, as its app keeps it: its status, the user's answer, a failure to report, the events waiting exactly as they will go, and sending them

Started through: `wisent-errors-swift telemetry status`, `wisent-errors-swift telemetry set`, `wisent-errors-swift telemetry failure`, `wisent-errors-swift telemetry show`, `wisent-errors-swift telemetry flush`. Uses: `wisent-errors.telemetry.store`, `wisent-errors.telemetry.deliver`.

## `wisent_errors.swift_cli.settings_window`

open the telemetry section of a product's Settings, the one its app shows, in a window of its own

Started through: `wisent-errors-swift telemetry settings`. Uses: `wisent-errors.telemetry.store`.

<a id="wisent_errors-swift_cli-settings_window-window-session-absent"></a>

### `wisent_errors.swift_cli.settings_window.window-session-absent`

- **What failed:** opening the telemetry settings window of {product}
- **Cause:** this process runs outside a logged-in macOS session, so the window server shows it no window
- **Observed state shown:** the window server knows no session of user {user} for this process
- **Fix:** run it from a terminal inside the logged-in session of {user}, or set the level from here with `wisent-errors-swift telemetry set <off|errors|usage> --product {product} --app {app}`
- **Class:** `config`, exit 1
- **Test:** Swift `tests/telemetry/swift/SettingsWindowTests.swift::test_telemetry_settings_opens_the_section_the_app_shows_and_keeps_the_choice_made_in_it`

## `wisent_errors.swift_cli.support`

file a product's support report from a terminal, as its app's Report a Problem window files it, and read support's answer to every report it filed

Started through: `wisent-errors-swift support report`, `wisent-errors-swift support status`. Uses: `wisent-errors.support.report`, `wisent-errors.support.exchange`, `wisent-errors.telemetry.store`.

## `wisent_errors.swift_cli.program_run`

find a product's installed command line program, admit it only when its publisher signed it, run it with its output handed on as it comes, and stop its whole process group on SIGTERM or SIGINT

Started through: `wisent-errors-swift program run`. Uses: none.

<a id="wisent_errors-swift_cli-program_run-home-unset"></a>

### `wisent_errors.swift_cli.program_run.home-unset`

- **What failed:** finding the installed program {name}
- **Cause:** HOME is not set, so neither ~/.local/bin nor ~/.stado/bin can be named
- **Observed state shown:** HOME holds {quoted_home}
- **Fix:** run it with HOME set to the home directory {name} was installed under
- **Class:** `config`, exit 1
- **Test:** Swift `tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed`

<a id="wisent_errors-swift_cli-program_run-program-missing"></a>

### `wisent_errors.swift_cli.program_run.program-missing`

- **What failed:** finding the installed program {name}
- **Cause:** no executable file named {name} is in either place a release installer puts it
- **Observed state shown:** looked in {searched}
- **Fix:** install {name} with its release installer (stado://releases/{name}/<version>/<platform>/install.sh), which places it in {first}
- **Class:** `not_found`, exit 1
- **Test:** Swift `tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed`

<a id="wisent_errors-swift_cli-program_run-program-unverified"></a>

### `wisent_errors.swift_cli.program_run.program-unverified`

- **What failed:** admitting {path} as the program {identifier}
- **Cause:** its code signature does not show that the team {team} signed it as {identifier}, so it is not run
- **Observed state shown:** Security answered {reason}
- **Fix:** reinstall {name} with its release installer, which places the program its publisher signed, or remove {path}; a program another publisher signs is named with --identifier and --team
- **Class:** `refused`, exit 1
- **Test:** Swift `tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed`

<a id="wisent_errors-swift_cli-program_run-program-unstartable"></a>

### `wisent_errors.swift_cli.program_run.program-unstartable`

- **What failed:** starting {path}
- **Cause:** the program was found and admitted, but the system could not start it
- **Observed state shown:** {reason}
- **Fix:** correct what the reason names: a --set name must be non-empty and hold no '=', and a program the kernel cannot execute is reinstalled with its release installer
- **Class:** `config`, exit 1
- **Test:** Swift `tests/program/RunOutputTests.swift::test_program_run_hands_on_the_environment_it_sets_and_withholds`

<a id="wisent_errors-swift_cli-program_run-program-unfollowed"></a>

### `wisent_errors.swift_cli.program_run.program-unfollowed`

- **What failed:** following {path} to its end
- **Cause:** {step} failed, so whether and how the program ended cannot be told
- **Observed state shown:** {reason}
- **Fix:** run it again; `log show --predicate 'subsystem == "com.wisent.WisentProgram"'` shows what the run recorded of its admission
- **Class:** `infra_down`, exit 69
- **Test:** Swift `tests/program/RunOutputTests.swift::test_a_run_whose_end_cannot_be_followed_is_refused`

<a id="wisent_errors-swift_cli-program_run-stdin-unread"></a>

### `wisent_errors.swift_cli.program_run.stdin-unread`

- **What failed:** reading the standard input to hand to {name}
- **Cause:** the standard input could not be read to its end
- **Observed state shown:** the operating system answered {error}
- **Fix:** give --stdin an input that can be read to its end, such as a file (< file) or a pipe whose writer closes it
- **Class:** `infra_down`, exit 69
- **Test:** Swift `tests/program/RunOutputTests.swift::test_program_run_hands_on_its_standard_input_with_stdin`
