// The commands of wisent-errors-swift, the options each takes, and reading a
// command line against them. A command line that names no command, an
// unknown command or option, an option without its value, a required option
// left out, the wrong number of operands, and a value that is not one of the
// option's are each a declared cause of `wisent_errors.swift_cli.arguments`.

#if os(macOS)
import Foundation
import WisentErrors

/// One command: its words, what it takes, and how it runs.
struct Command {
    /// The words after `wisent-errors-swift` that name it: `envelope build`.
    let words: String
    /// The options that take a value, each with an example value.
    let values: [(option: String, example: String)]
    /// The options that take a value and may be given again.
    let lists: [(option: String, example: String)]
    /// The options that take no value.
    let flags: [String]
    /// The operands it takes, as a person names them: `<file>`.
    let operands: [String]
    /// Whether it takes `-- <arguments>` after its operands, handed on as they are.
    let rest: Bool
    /// A whole command line of it, as a refusal shows it.
    let example: String
    let perform: (Given) async throws -> Int32

    var options: [String] { (values.map(\.option) + lists.map(\.option) + flags).sorted() }

    /// The usage line: the words, the operands and the arguments handed on.
    var usage: String {
        ([words] + operands + (rest ? ["[-- <arguments>]"] : [])).joined(separator: " ")
    }

    func exampleValue(_ option: String) -> String? {
        (values + lists).first { $0.option == option }?.example
    }
}

/// A command line read against its command.
struct Given {
    let command: Command
    var values: [String: String] = [:]
    var lists: [String: [String]] = [:]
    var flags: Set<String> = []
    var operands: [String] = []
    var rest: [String] = []

    /// The value of `option`, refused naming it when it was not given.
    func required(_ option: String) throws -> String {
        if let value = values[option] { return value }
        let given = (Array(values.keys) + Array(lists.keys) + Array(flags)).sorted()
        throw Arguments.refusal(OwnFailures.swiftCliArgumentsOptionRequired, [
            "command": command.words, "option": option,
            "given": given.isEmpty ? "none" : given.joined(separator: ", "),
            // fallback: every required option is declared with an example value.
            "example": "\(option) \(command.exampleValue(option) ?? "<value>")",
        ])
    }

    func optional(_ option: String) -> String? { values[option] }

    /// Every value `option` was given, in order.
    func all(_ option: String) -> [String] {
        // fallback: an option given no time holds no value.
        lists[option] ?? []
    }

    /// `value` of `option` as one of `choices`, refused naming them all.
    func choice<T>(_ option: String, _ value: String, _ choices: [(String, T)]) throws -> T {
        if let found = choices.first(where: { $0.0 == value }) { return found.1 }
        throw Arguments.refusal(OwnFailures.swiftCliArgumentsValueUnknown, [
            "command": command.words, "option": option, "quoted_value": quoted(value),
            "values": choices.map(\.0).joined(separator: ", "),
        ])
    }

    /// `value` of `option` refused as not having the shape it must have.
    func malformed(_ option: String, _ value: String, shape: String, found: String, example: String) -> DeclaredRefusal {
        Arguments.refusal(OwnFailures.swiftCliArgumentsValueMalformed, [
            "command": command.words, "option": option, "quoted_value": quoted(value),
            "shape": shape, "found": found, "example": example,
        ])
    }

    /// `value` of `option` as `name=value`, split at its first `=`.
    func pair(_ option: String, _ value: String, example: String) throws -> (String, String) {
        guard let equals = value.firstIndex(of: "=") else {
            throw malformed(option, value, shape: "NAME=VALUE", found: "it holds no '='", example: example)
        }
        return (String(value[..<equals]), String(value[value.index(after: equals)...]))
    }
}

enum Arguments {
    static func refusal(_ cause: Cause, _ values: [String: String]) -> DeclaredRefusal {
        OwnFailures.swiftCliArguments.refusal(cause, values)
    }

    /// `arguments` read against `command`.
    static func read(_ arguments: [String], for command: Command) throws -> Given {
        var given = Given(command: command)
        var index = 0
        var handedOn = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if handedOn {
                if command.rest { given.rest.append(argument) } else { given.operands.append(argument) }
                continue
            }
            if argument == "--" {
                handedOn = true
                continue
            }
            guard argument.hasPrefix("--") else {
                given.operands.append(argument)
                continue
            }
            if command.flags.contains(argument) {
                given.flags.insert(argument)
                continue
            }
            let single = command.values.contains { $0.option == argument }
            let repeated = command.lists.contains { $0.option == argument }
            guard single || repeated else {
                throw refusal(OwnFailures.swiftCliArgumentsOptionUnknown, [
                    "command": command.words, "quoted_option": quoted(argument),
                    "options": command.options.joined(separator: ", "),
                ])
            }
            guard index < arguments.count else {
                throw refusal(OwnFailures.swiftCliArgumentsOptionValueAbsent, [
                    "command": command.words, "option": argument,
                    "arguments": "[\(arguments.map(quoted).joined(separator: ","))]",
                    // fallback: every option that takes a value is declared with an example value.
                    "example": "\(argument) \(command.exampleValue(argument) ?? "<value>")",
                ])
            }
            let value = arguments[index]
            index += 1
            if repeated {
                given.lists[argument, default: []].append(value)
            } else {
                given.values[argument] = value
            }
        }
        guard given.operands.count == command.operands.count else {
            throw refusal(OwnFailures.swiftCliArgumentsOperandsWrong, [
                "command": command.words,
                "expected": command.operands.isEmpty ? "no operand" : command.operands.joined(separator: " "),
                "count": String(given.operands.count),
                "operands": given.operands.isEmpty ? "none" : "[\(given.operands.map(quoted).joined(separator: ","))]",
                "usage": command.usage,
            ])
        }
        return given
    }
}

/// `text` as a JSON string, the way every refusal of this package quotes what it was given.
func quoted(_ text: String) -> String { jsonQuote(text) }

/// Write `text` to stdout now, unbuffered, so a line is there before the next step.
func say(_ text: String) {
    emit(text, to: FileHandle.standardOutput)
}

/// Write `text` to stderr now.
func tell(_ text: String) {
    emit(text, to: FileHandle.standardError)
}

private func emit(_ text: String, to handle: FileHandle) {
    do {
        try handle.write(contentsOf: Data(text.utf8))
    } catch {
        // discarded: a closed stdout or stderr leaves nothing to say it on; the exit status still says how the command ended.
    }
}

/// A JSON document as the commands print it: keys sorted, indented, slashes as written.
func printed(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self) + "\n"
}

enum Commands {
    static let all: [Command] = EnvelopeCommands.all + DeclarationCommands.all + TelemetryCommands.all
        + SupportCommands.all + ProgramCommands.all

    /// The first words of every command, in the order listed.
    static var groups: [String] {
        var seen: [String] = []
        for command in all {
            // fallback: a command's words are never empty, so the first word is always there.
            let group = String(command.words.split(separator: " ").first ?? "")
            if !seen.contains(group) { seen.append(group) }
        }
        return seen
    }

    /// Run the command `arguments` name, and answer its exit status.
    static func run(_ arguments: [String]) async -> Int32 {
        do {
            let command = try find(arguments)
            let given = try Arguments.read(Array(arguments.dropFirst(2)), for: command)
            return try await command.perform(given)
        } catch let refusal as DeclaredRefusal {
            tell(refusal.lines + "\n")
            return refusal.exitCode(failureExit: EXIT_FAILURE)
        } catch {
            // Every command throws its declared refusal; anything else is a defect of this program, said whole.
            tell("Error: \(error.explained)\n")
            return EXIT_FAILURE
        }
    }

    private static func find(_ arguments: [String]) throws -> Command {
        let example = "wisent-errors-swift envelope build --point stado.fleet.enroll --code refused --service stado"
        guard let group = arguments.first else {
            throw Arguments.refusal(OwnFailures.swiftCliArgumentsCommandAbsent, [
                "given": "wisent-errors-swift", "commands": groups.joined(separator: ", "), "example": example,
            ])
        }
        let inGroup = all.filter { $0.words.hasPrefix("\(group) ") }
        guard let first = inGroup.first else {
            throw Arguments.refusal(OwnFailures.swiftCliArgumentsCommandUnknown, [
                "given": "wisent-errors-swift", "quoted_command": quoted(group),
                "commands": groups.joined(separator: ", "), "example": example,
            ])
        }
        let names = inGroup.map { String($0.words.dropFirst(group.count + 1)) }
        guard arguments.count > 1 else {
            throw Arguments.refusal(OwnFailures.swiftCliArgumentsCommandAbsent, [
                "given": "wisent-errors-swift \(group)", "commands": names.joined(separator: ", "),
                "example": "wisent-errors-swift \(first.example)",
            ])
        }
        guard let command = inGroup.first(where: { $0.words == "\(group) \(arguments[1])" }) else {
            throw Arguments.refusal(OwnFailures.swiftCliArgumentsCommandUnknown, [
                "given": "wisent-errors-swift \(group)", "quoted_command": quoted(arguments[1]),
                "commands": names.joined(separator: ", "), "example": "wisent-errors-swift \(first.example)",
            ])
        }
        return command
    }
}
#endif
