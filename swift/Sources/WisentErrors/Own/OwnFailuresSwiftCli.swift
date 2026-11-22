// Generated from catalogue/failures/swift-cli.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

extension OwnFailures {
    public static let swiftCliArgumentsCommandAbsent = Cause(
        id: "command-absent", code: .refused, usage: true, exit: nil,
        failed: "reading the command of `{given}`",
        cause: "it names no command, so nothing would run",
        observed: "its commands: {commands}",
        remedy: "add one of {commands}, as in `{example}`",
        test: "tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it"
    )

    public static let swiftCliArgumentsCommandUnknown = Cause(
        id: "command-unknown", code: .refused, usage: true, exit: nil,
        failed: "reading the command of `{given}`",
        cause: "{quoted_command} is not one of its commands",
        observed: "its commands: {commands}",
        remedy: "run one of {commands}, as in `{example}`",
        test: "tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it"
    )

    public static let swiftCliArgumentsOptionUnknown = Cause(
        id: "option-unknown", code: .refused, usage: true, exit: nil,
        failed: "reading the options of `wisent-errors-swift {command}`",
        cause: "{quoted_option} is not one of its options",
        observed: "its options: {options}",
        remedy: "drop {quoted_option}, or give one of {options}",
        test: "tests/program/RunOutputTests.swift::test_program_run_hands_on_the_programs_streams_status_and_input"
    )

    public static let swiftCliArgumentsOptionValueAbsent = Cause(
        id: "option-value-absent", code: .refused, usage: true, exit: nil,
        failed: "reading the options of `wisent-errors-swift {command}`",
        cause: "{option} takes a value, and it is the last argument",
        observed: "arguments: {arguments}",
        remedy: "give {option} its value, as in `{example}`",
        test: "tests/program/RunOutputTests.swift::test_program_run_hands_on_the_programs_streams_status_and_input"
    )

    public static let swiftCliArgumentsOptionRepeated = Cause(
        id: "option-repeated", code: .refused, usage: true, exit: nil,
        failed: "reading the options of `wisent-errors-swift {command}`",
        cause: "{option} takes one value and was given {count} times, so which one is meant cannot be read",
        observed: "its values: {values}",
        remedy: "give {option} once, as in `{example}`",
        test: "tests/declaration/DeclarationRuleTests.swift::test_declaration_cause_holds_one_cause_to_every_declaration_rule"
    )

    public static let swiftCliArgumentsOptionRequired = Cause(
        id: "option-required", code: .refused, usage: true, exit: nil,
        failed: "reading the options of `wisent-errors-swift {command}`",
        cause: "it needs {option}, and {option} was not given",
        observed: "options given: {given}",
        remedy: "add {option}, as in `{example}`",
        test: "tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it"
    )

    public static let swiftCliArgumentsOperandsWrong = Cause(
        id: "operands-wrong", code: .refused, usage: true, exit: nil,
        failed: "reading the operands of `wisent-errors-swift {command}`",
        cause: "it takes {expected}, and {count} were given",
        observed: "operands: {operands}",
        remedy: "run it as `wisent-errors-swift {usage}`",
        test: "tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one"
    )

    public static let swiftCliArgumentsValueUnknown = Cause(
        id: "value-unknown", code: .refused, usage: true, exit: nil,
        failed: "reading {option} of `wisent-errors-swift {command}`",
        cause: "{quoted_value} is not one of its values",
        observed: "its values: {values}",
        remedy: "give {option} one of {values}",
        test: "tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it"
    )

    public static let swiftCliArgumentsValueMalformed = Cause(
        id: "value-malformed", code: .refused, usage: true, exit: nil,
        failed: "reading {option} of `wisent-errors-swift {command}`",
        cause: "{quoted_value} is not {shape}",
        observed: "{found}",
        remedy: "give {option} {shape}, as in `{example}`",
        test: "tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed"
    )

    public static let swiftCliArguments = Operation(
        id: "wisent_errors.swift_cli.arguments",
        entries: ["wisent-errors-swift"],
        uses: [],
        summary: "read the command, options and operands a person or a script gave wisent-errors-swift, the Swift package's command line",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliArgumentsCommandAbsent, swiftCliArgumentsCommandUnknown, swiftCliArgumentsOptionUnknown, swiftCliArgumentsOptionValueAbsent, swiftCliArgumentsOptionRepeated, swiftCliArgumentsOptionRequired, swiftCliArgumentsOperandsWrong, swiftCliArgumentsValueUnknown, swiftCliArgumentsValueMalformed]
    )

    public static let swiftCliInputInputAbsent = Cause(
        id: "input-absent", code: .notFound, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "no file is at that path",
        observed: "{parent}; the operating system answered {error}",
        remedy: "name a file that exists, or write it first; a relative path is read from {cwd}",
        test: "tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one"
    )

    public static let swiftCliInputInputIsDirectory = Cause(
        id: "input-is-directory", code: .notFound, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the path names a directory, not a file",
        observed: "{state}; the operating system answered {error}",
        remedy: "name the JSON file inside {path}, not the directory",
        test: "tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one"
    )

    public static let swiftCliInputInputNotPermitted = Cause(
        id: "input-not-permitted", code: .refused, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the operating system refused this process the read",
        observed: "{state}; the operating system answered {error}",
        remedy: "let the user running wisent-errors-swift read it (chmod u+r {path}), or run it as the file's owner",
        test: "tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one"
    )

    public static let swiftCliInputInputReadFailed = Cause(
        id: "input-read-failed", code: .infraDown, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the file is there and may be read, but the operating system stopped the read before its bytes were in hand",
        observed: "{state}; the operating system answered {error}",
        remedy: "run the command again once the disk or the network share holding {path} answers; `ls -l {path}` shows whether it is still there",
        test: "tests/explained/ExplainedTests.swift::test_an_interrupted_read_is_refused"
    )

    public static let swiftCliInputInputNotJson = Cause(
        id: "input-not-json", code: .config, usage: false, exit: nil,
        failed: "decoding {what} from {path}",
        cause: "the file is not JSON",
        observed: "{bytes} bytes; the reader answered {error}",
        remedy: "write {path} as JSON; `jq . {path}` points at the place it stops parsing",
        test: "tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one"
    )

    public static let swiftCliInputInputWrongShape = Cause(
        id: "input-wrong-shape", code: .config, usage: false, exit: nil,
        failed: "decoding {what} from {path}",
        cause: "the file is JSON, but not {shape}",
        observed: "{bytes} bytes; the decoder answered {error}",
        remedy: "write {path} as {shape}, as in {example}",
        test: "tests/explained/ExplainedTests.swift::test_envelope_read_says_the_envelope_or_why_the_file_is_not_one"
    )

    public static let swiftCliInput = Operation(
        id: "wisent_errors.swift_cli.input",
        entries: [],
        uses: [],
        summary: "read one JSON document a command of wisent-errors-swift was named, and decode it into what the command reads",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliInputInputAbsent, swiftCliInputInputIsDirectory, swiftCliInputInputNotPermitted, swiftCliInputInputReadFailed, swiftCliInputInputNotJson, swiftCliInputInputWrongShape]
    )

    public static let swiftCliEnvelopeBuildEnvelopeUnwritten = Cause(
        id: "envelope-unwritten", code: .config, usage: false, exit: nil,
        failed: "writing the envelope to {path}",
        cause: "the operating system refused to write the file there",
        observed: "{state}; the operating system answered {error}",
        remedy: "name with --out a file in a directory this user can write, or leave --out out to print the envelope only",
        test: "tests/envelope/EnvelopeBuildTests.swift::test_envelope_build_prints_the_envelope_or_refuses_naming_what_breaks_it"
    )

    public static let swiftCliEnvelopeBuild = Operation(
        id: "wisent_errors.swift_cli.envelope_build",
        entries: ["wisent-errors-swift envelope build"],
        uses: [envelopeBuild],
        summary: "build one failure envelope from its options, strictly or with the fallback that never refuses, print it and, with --out, write it to a file",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliEnvelopeBuildEnvelopeUnwritten]
    )

    public static let swiftCliEnvelopeRead = Operation(
        id: "wisent_errors.swift_cli.envelope_read",
        entries: ["wisent-errors-swift envelope read"],
        uses: [swiftCliInput, envelopeBuild],
        summary: "read one failure envelope from a JSON file and print it for a person: its rendered line, then its chain of causes",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: []
    )

    public static let swiftCliDeclarationCauseCauseBroken = Cause(
        id: "cause-broken", code: .refused, usage: false, exit: nil,
        failed: "checking the cause {id}",
        cause: "it breaks {count} declaration rule(s)",
        observed: "each is a line on stdout; the first: {first}",
        remedy: "correct the fields as each line says, then check the cause again; catalogue/declaration.json states every rule",
        test: "tests/declaration/DeclarationRuleTests.swift::test_declaration_cause_holds_one_cause_to_every_declaration_rule"
    )

    public static let swiftCliDeclarationCause = Operation(
        id: "wisent_errors.swift_cli.declaration_cause",
        entries: ["wisent-errors-swift declaration cause"],
        uses: [],
        summary: "hold one cause, given field by field, to the declaration rules every runtime holds a catalogue to, and show the refusal it says with the values given",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliDeclarationCauseCauseBroken]
    )

    public static let swiftCliDeclarationCheckListingBroken = Cause(
        id: "listing-broken", code: .refused, usage: false, exit: nil,
        failed: "checking the functionalities listed in {path}",
        cause: "{count} of its declarations break the declaration rules",
        observed: "{operations} functionalities read; each problem is a line on stdout; the first: {first}",
        remedy: "correct each declaration in the product's catalogue as its line says, then list and check it again",
        test: "tests/explained/DescribedTests.swift::test_declaration_check_reads_a_listing_or_says_where_it_stops_being_one"
    )

    public static let swiftCliDeclarationCheck = Operation(
        id: "wisent_errors.swift_cli.declaration_check",
        entries: ["wisent-errors-swift declaration check"],
        uses: [swiftCliInput],
        summary: "hold every functionality of a product's `errors list --json` listing, read from a file, to the declaration rules",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliDeclarationCheckListingBroken]
    )

    public static let swiftCliTelemetry = Operation(
        id: "wisent_errors.swift_cli.telemetry",
        entries: ["wisent-errors-swift telemetry status", "wisent-errors-swift telemetry set", "wisent-errors-swift telemetry failure", "wisent-errors-swift telemetry show", "wisent-errors-swift telemetry flush"],
        uses: [telemetryStore, telemetryDeliver],
        summary: "keep a product's telemetry from a terminal, as its app keeps it: its status, the user's answer, a failure to report, the events waiting exactly as they will go, and sending them",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: []
    )

    public static let swiftCliSettingsWindowWindowSessionAbsent = Cause(
        id: "window-session-absent", code: .config, usage: false, exit: nil,
        failed: "opening the telemetry settings window of {product}",
        cause: "this process runs outside a logged-in macOS session, so the window server shows it no window",
        observed: "the window server knows no session of user {user} for this process",
        remedy: "run it from a terminal inside the logged-in session of {user}, or set the level from here with `wisent-errors-swift telemetry set <off|errors|usage> --product {product} --app {app}`",
        test: "tests/telemetry/swift/SettingsWindowTests.swift::test_telemetry_settings_opens_the_section_the_app_shows_and_keeps_the_choice_made_in_it"
    )

    public static let swiftCliSettingsWindow = Operation(
        id: "wisent_errors.swift_cli.settings_window",
        entries: ["wisent-errors-swift telemetry settings"],
        uses: [telemetryStore],
        summary: "open the telemetry section of a product's Settings, the one its app shows, in a window of its own",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliSettingsWindowWindowSessionAbsent]
    )

    public static let swiftCliSupport = Operation(
        id: "wisent_errors.swift_cli.support",
        entries: ["wisent-errors-swift support report", "wisent-errors-swift support status"],
        uses: [supportReport, supportExchange, telemetryStore],
        summary: "file a product's support report from a terminal, as its app's Report a Problem window files it, and read support's answer to every report it filed",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: []
    )

    public static let swiftCliProgramRunHomeUnset = Cause(
        id: "home-unset", code: .config, usage: false, exit: nil,
        failed: "finding the installed program {name}",
        cause: "HOME is not set, so neither ~/.local/bin nor ~/.stado/bin can be named",
        observed: "HOME holds {quoted_home}",
        remedy: "run it with HOME set to the home directory {name} was installed under",
        test: "tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed"
    )

    public static let swiftCliProgramRunProgramMissing = Cause(
        id: "program-missing", code: .notFound, usage: false, exit: nil,
        failed: "finding the installed program {name}",
        cause: "no executable file named {name} is in either place a release installer puts it",
        observed: "looked in {searched}",
        remedy: "install {name} with its release installer (stado://releases/{name}/<version>/<platform>/install.sh), which places it in {first}",
        test: "tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed"
    )

    public static let swiftCliProgramRunProgramUnverified = Cause(
        id: "program-unverified", code: .refused, usage: false, exit: nil,
        failed: "admitting {path} as the program {identifier}",
        cause: "its code signature does not show that the team {team} signed it as {identifier}, so it is not run",
        observed: "Security answered {reason}",
        remedy: "reinstall {name} with its release installer, which places the program its publisher signed, or remove {path}; a program another publisher signs is named with --identifier and --team",
        test: "tests/program/AdmissionTests.swift::test_program_run_admits_only_the_program_its_publisher_signed"
    )

    public static let swiftCliProgramRunProgramUnstartable = Cause(
        id: "program-unstartable", code: .config, usage: false, exit: nil,
        failed: "starting {path}",
        cause: "the program was found and admitted, but the system could not start it",
        observed: "{reason}",
        remedy: "correct what the reason names: a --set name must be non-empty and hold no '=', and a program the kernel cannot execute is reinstalled with its release installer",
        test: "tests/program/RunOutputTests.swift::test_program_run_hands_on_the_programs_streams_status_and_input"
    )

    public static let swiftCliProgramRunProgramUnfollowed = Cause(
        id: "program-unfollowed", code: .infraDown, usage: false, exit: nil,
        failed: "following {path} to its end",
        cause: "{step} failed, so whether and how the program ended cannot be told",
        observed: "{reason}",
        remedy: "run it again; `log show --predicate 'subsystem == \"com.wisent.WisentProgram\"'` shows what the run recorded of its admission",
        test: "tests/program/RunOutputTests.swift::test_a_run_whose_end_cannot_be_followed_is_refused"
    )

    public static let swiftCliProgramRunStdinUnread = Cause(
        id: "stdin-unread", code: .infraDown, usage: false, exit: nil,
        failed: "reading the standard input to hand to {name}",
        cause: "the standard input could not be read to its end",
        observed: "the operating system answered {error}",
        remedy: "give --stdin an input that can be read to its end, such as a file (< file) or a pipe whose writer closes it",
        test: "tests/program/RunOutputTests.swift::test_program_run_hands_on_the_programs_streams_status_and_input"
    )

    public static let swiftCliProgramRun = Operation(
        id: "wisent_errors.swift_cli.program_run",
        entries: ["wisent-errors-swift program run"],
        uses: [],
        summary: "find a product's installed command line program, admit it only when its publisher signed it, run it with its output handed on as it comes, and stop its whole process group on SIGTERM or SIGINT",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/swift-cli.md",
        causes: [swiftCliProgramRunHomeUnset, swiftCliProgramRunProgramMissing, swiftCliProgramRunProgramUnverified, swiftCliProgramRunProgramUnstartable, swiftCliProgramRunProgramUnfollowed, swiftCliProgramRunStdinUnread]
    )
}
