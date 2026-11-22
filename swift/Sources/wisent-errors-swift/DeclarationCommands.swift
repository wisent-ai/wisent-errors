// `declaration cause`: one cause, given field by field, held to the
// declaration rules every runtime holds a catalogue to (`Cause.problems`,
// whose sentences catalogue/declaration.json states), and, when it keeps
// them, the refusal it says with the values given and the status it exits
// with.
//
// `declaration check`: every functionality of a product's `errors list
// --json` listing, read from a file (Input.swift), held to the same rules and
// to those only a whole catalogue shows (`Operation.problems`,
// `catalogueProblems`). The listing is the bare array of functionalities, or
// the object Stado's `errors list --json` prints, which holds that array
// under `operations` beside `commands` and `undeclared`; only `operations`
// is read, as the Rust checker reads it (rust/src/bin/wisent-errors/check.rs).
//
// Each problem is one line on stdout; a cause or listing that has any is
// refused, naming how many and the first.

#if os(macOS)
import Foundation
import WisentErrors

enum DeclarationCommands {
    static let all: [Command] = [
        Command(
            words: "declaration cause",
            values: [
                ("--id", "pairs-unreadable"), ("--code", "config"), ("--exit", "3"),
                ("--failed", "\"reading the pairs file {path}\""), ("--cause", "\"the file is not JSON\""),
                ("--observed", "\"{bytes} bytes; the decoder answered {error}\""),
                ("--remedy", "\"write {path} as JSON\""), ("--test", "tests/pairs/import.rs::a_damaged_file_is_refused"),
            ],
            lists: [("--value", "path=/srv/example-host/pairs.json")],
            flags: ["--usage"],
            operands: [],
            rest: false,
            example: "declaration cause --id pairs-unreadable --code config --failed \"reading the pairs file {path}\" --cause \"the file is not JSON\" --observed \"{bytes} bytes\" --remedy \"write {path} as JSON\" --test tests/pairs/import.rs::a_damaged_file_is_refused",
            perform: DeclarationCommands.cause
        ),
        Command(
            words: "declaration check",
            values: [],
            lists: [],
            flags: [],
            operands: ["<file>"],
            rest: false,
            example: "declaration check errors.json",
            perform: DeclarationCommands.check
        ),
    ]

    static func cause(_ given: Given) async throws -> Int32 {
        let id = try given.required("--id")
        let code = try given.choice("--code", try given.required("--code"), EnvelopeCommands.codes)
        var exit: Int32?
        if let text = given.optional("--exit") {
            guard let number = Int32(text) else {
                throw given.malformed(
                    "--exit", text, shape: "a whole number, the status the command exits with",
                    found: "it holds no whole number", example: "--exit 3")
            }
            exit = number
        }
        let declared = Cause(
            id: id, code: code, usage: given.flags.contains("--usage"), exit: exit,
            failed: try given.required("--failed"), cause: try given.required("--cause"),
            observed: try given.required("--observed"), remedy: try given.required("--remedy"),
            test: try given.required("--test"))
        var values: [String: String] = [:]
        for entry in given.all("--value") {
            let (name, value) = try given.pair("--value", entry, example: "--value path=/srv/example-host/pairs.json")
            values[name] = value
        }
        let problems = declared.problems()
        if let first = problems.first {
            say(problems.joined(separator: "\n") + "\n")
            throw OwnFailures.swiftCliDeclarationCause.refusal(OwnFailures.swiftCliDeclarationCauseCauseBroken, [
                "id": id, "count": String(problems.count), "first": first,
            ])
        }
        var lines = "cause \(id) keeps every declaration rule; with the values given it says:\n"
            + "Error: \(declared.sentence(values))\nfix: \(declared.fix(values))\n"
            + "exit: \(declared.exitCode(failureExit: EXIT_FAILURE))\n"
        let unfilled = declared.unfilledPlaceholders(values)
        if !unfilled.isEmpty {
            lines += "unfilled: \(unfilled.map { "{\($0)}" }.joined(separator: ", "))\n"
        }
        say(lines)
        return EXIT_SUCCESS
    }

    /// One functionality as `errors list --json` prints it.
    struct Listed: Decodable {
        let operation: String
        let entries: [String]
        let uses: [String]
        let summary: String
        let docs: String
        let causes: [ListedCause]
    }

    /// One cause as the listing prints it. Its `exit` is the status it
    /// leaves, derived from its code where it declares none, so it is not
    /// read as a declared one.
    struct ListedCause: Decodable {
        let id: String
        let code: Code
        let usage: Bool
        let failed: String
        let cause: String
        let observed: String
        let remedy: String
        let test: String
    }

    /// The whole listing: a JSON array of functionalities, or an object holding it under `operations`.
    struct Listing: Decodable {
        let functionalities: [Listed]

        private enum Keys: String, CodingKey {
            case operations
        }

        init(from decoder: Decoder) throws {
            do {
                let object = try decoder.container(keyedBy: Keys.self)
                functionalities = try object.decode([Listed].self, forKey: .operations)
            } catch DecodingError.typeMismatch(_, let context) where context.codingPath.isEmpty {
                // discarded: the top level is no object, so it is read as the bare array, whose own failure is the one said.
                functionalities = try decoder.singleValueContainer().decode([Listed].self)
            }
        }
    }

    static let document = Document<Listing>(
        what: "the listing of a product's functionalities",
        shape: "what `errors list --json` prints: a JSON array of functionalities, or an object holding that array under operations (beside commands and undeclared), one object per functionality with operation, entries, uses, summary, docs and causes, each cause with id, code, usage, failed, cause, observed, remedy and test",
        example: #"[{"operation":"example.pairs.import","entries":["example pairs import"],"uses":[],"summary":"import a pairs file","docs":"https://example.com/docs/errors","causes":[]}]"#
    )

    static func check(_ given: Given) async throws -> Int32 {
        let path = given.operands[0]
        let listed = try document.read(path).functionalities
        let causes = listed.map { entry in
            entry.causes.map { cause in
                Cause(
                    id: cause.id, code: cause.code, usage: cause.usage, exit: nil, failed: cause.failed,
                    cause: cause.cause, observed: cause.observed, remedy: cause.remedy, test: cause.test)
            }
        }
        let alone = listed.indices.map { index in
            WisentErrors.Operation(
                id: listed[index].operation, entries: listed[index].entries, uses: [],
                summary: listed[index].summary, docs: listed[index].docs, causes: causes[index])
        }
        let operations = listed.indices.map { index in
            WisentErrors.Operation(
                id: listed[index].operation, entries: listed[index].entries,
                uses: listed[index].uses.map { used in
                    // fallback: a functionality the listing does not hold is named by its id alone, which catalogueProblems refuses as unlisted.
                    alone.first { $0.id == used } ?? WisentErrors.Operation(id: used, entries: [], uses: [], summary: "", docs: "", causes: [])
                },
                summary: listed[index].summary, docs: listed[index].docs, causes: causes[index])
        }
        let problems = operations.flatMap { $0.problems() } + catalogueProblems(operations)
        if let first = problems.first {
            say(problems.joined(separator: "\n") + "\n")
            throw OwnFailures.swiftCliDeclarationCheck.refusal(OwnFailures.swiftCliDeclarationCheckListingBroken, [
                "path": URL(fileURLWithPath: path).path, "count": String(problems.count),
                "operations": String(operations.count), "first": first,
            ])
        }
        say("\(operations.count) functionalities, \(causes.joined().count) causes: every declaration keeps the rules\n")
        return EXIT_SUCCESS
    }
}
#endif
