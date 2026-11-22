// `program run <name> [-- <arguments>]`: a product's installed command line
// program run the way its macOS app runs it, through WisentProgram. The
// program is looked for only where its release installer places it,
// $HOME/.local/bin/<name>, then $HOME/.stado/bin/<name>, and admitted only
// when its code signature shows its publisher signed it: the fleet's team
// (LNTWB5B9DV) as com.wisent.<name>, or the publisher --identifier and
// --team name. Its output is handed on as it comes, on the stream it came
// on; with --stdin this command's own standard input, read to its end, is
// the program's; --set NAME=VALUE is set over the environment and
// --withhold PREFIX withholds every variable named with it. SIGTERM or
// SIGINT sent to this command stops the program's whole process group with
// SIGTERM, and a second one kills it with SIGKILL. The command exits with
// the program's status, or 128 + the signal that ended it.

#if os(macOS)
import Darwin
import Foundation
import WisentErrors
import WisentProgram

enum ProgramCommands {
    static let all: [Command] = [
        Command(
            words: "program run",
            values: [("--identifier", "org.nodejs.node"), ("--team", "HX7739G8FX")],
            lists: [("--set", "STADO_CONFIG=/srv/example-host/empty.json"), ("--withhold", "PATH")],
            flags: ["--stdin"],
            operands: ["<name>"],
            rest: true,
            example: "program run stado -- --version",
            perform: ProgramCommands.run
        ),
    ]

    static func refusal(_ cause: Cause, _ values: [String: String]) -> DeclaredRefusal {
        OwnFailures.swiftCliProgramRun.refusal(cause, values)
    }

    /// The program `given` names, its publisher's identifier and team checked first.
    static func named(_ given: Given) throws -> InstalledProgram {
        let name = given.operands[0]
        if name.isEmpty || name == "." || name == ".." || name.contains("/") {
            throw given.malformed(
                "the program name", name, shape: "one file name, as the installer names the program",
                found: name.isEmpty ? "it is empty" : "it names a path, not one file name",
                example: "program run stado -- --version")
        }
        let identifier = given.optional("--identifier")
        if let identifier, identifier.isEmpty || identifier.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-")) }) {
            throw given.malformed(
                "--identifier", identifier, shape: "a signing identifier: ASCII letters, digits, '.' and '-'",
                found: identifier.isEmpty ? "it is empty" : "it holds a character a signing identifier never holds",
                example: "--identifier org.nodejs.node")
        }
        let team = given.optional("--team")
        if let team, team.count != 10 || team.contains(where: { !($0.isASCII && ($0.isUppercase || $0.isNumber)) }) {
            throw given.malformed(
                "--team", team, shape: "an Apple developer team id: ten uppercase letters and digits",
                found: "it is \(team.count) character(s), not ten uppercase letters and digits",
                example: "--team HX7739G8FX")
        }
        switch (identifier, team) {
        case (nil, nil): return InstalledProgram(name: name)
        case (let identifier?, nil): return InstalledProgram(name: name, identifier: identifier)
        // fallback: a team given alone signs the program under the fleet's own identifier for it.
        case (let identifier, let team?): return InstalledProgram(name: name, identifier: identifier ?? "com.wisent.\(name)", team: team)
        }
    }

    static func run(_ given: Given) async throws -> Int32 {
        let program = try named(given)
        // fallback: the team a program is checked against is the fleet's unless --team names another.
        let team = given.optional("--team") ?? FleetSignature.team
        // The home is the HOME this command was given, never the account's
        // record, so the program is the one installed for the home it runs in.
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else {
            throw refusal(OwnFailures.swiftCliProgramRunHomeUnset, [
                "name": program.name,
                // fallback: an unset HOME is said as the empty text it reads as.
                "quoted_home": quoted(ProcessInfo.processInfo.environment["HOME"] ?? ""),
            ])
        }
        let found: URL
        do {
            found = try program.executable(home: URL(fileURLWithPath: home, isDirectory: true))
        } catch let failure as InstalledProgram.Failure {
            throw refused(failure, program, team: team)
        }
        var input: Data?
        if given.flags.contains("--stdin") {
            do {
                // fallback: an input that ends at once is the empty input.
                input = try FileHandle.standardInput.readToEnd() ?? Data()
            } catch {
                throw refusal(OwnFailures.swiftCliProgramRunStdinUnread, ["name": program.name, "error": error.explained])
            }
        }
        var environment: [String: String] = [:]
        for entry in given.all("--set") {
            let (name, value) = try given.pair("--set", entry, example: "--set STADO_CONFIG=/srv/example-host/empty.json")
            environment[name] = value
        }
        let stop = InstalledProgram.Stop()
        let signals = Signals(stop: stop)
        defer { signals.end() }
        let outcome: InstalledProgram.Outcome
        do {
            outcome = try await program.run(
                given.rest, executable: found, input: input, environment: environment,
                withholding: given.all("--withhold"), stop: stop
            ) { stream, text in
                switch stream {
                case .stdout: say(text)
                case .stderr: tell(text)
                }
            }
        } catch let failure as InstalledProgram.Failure {
            throw refused(failure, program, team: team)
        } catch is CancellationError {
            // Stopped before the program started: it never ran, and the
            // status says which signal stopped it, as a shell says it.
            return 128 + signals.last
        }
        if !outcome.heldOpen.isEmpty {
            let streams = [InstalledProgram.Stream.stdout, .stderr].filter(outcome.heldOpen.contains)
                .map { $0 == .stdout ? "stdout" : "stderr" }.joined(separator: " and ")
            tell("note: a process \(program.name) left running still held its \(streams) when \(program.name) exited; what it writes there later is not shown\n")
        }
        if !outcome.inputDelivered {
            tell("note: \(program.name) closed its standard input or exited before all of it was written, so its answer may cover only part of the input\n")
        }
        return outcome.signalled ? 128 + outcome.status : outcome.status
    }

    /// `failure` as the declared refusal of `program run` it is.
    static func refused(_ failure: InstalledProgram.Failure, _ program: InstalledProgram, team: String) -> DeclaredRefusal {
        switch failure {
        case .missing(let searched):
            return refusal(OwnFailures.swiftCliProgramRunProgramMissing, [
                // fallback: the places looked in are never none; the first is where the installer puts it.
                "name": program.name, "searched": searched.joined(separator: ", "), "first": searched.first ?? "~/.local/bin",
            ])
        case .unverified(let path, let reason):
            return refusal(OwnFailures.swiftCliProgramRunProgramUnverified, [
                "path": path, "identifier": program.identifier, "team": team, "reason": reason, "name": program.name,
            ])
        case .failedToStart(let path, let reason):
            return refusal(OwnFailures.swiftCliProgramRunProgramUnstartable, ["path": path, "reason": reason])
        case .unfollowed(let path, let step, let reason):
            return refusal(OwnFailures.swiftCliProgramRunProgramUnfollowed, ["path": path, "step": step, "reason": reason])
        }
    }
}

/// SIGTERM and SIGINT sent to this command, each handed to the run as a
/// request to stop; SIGCHLD set back to its default, so the run, and nothing
/// this command inherited, reaps the program.
final class Signals: @unchecked Sendable {
    private let lock = NSLock()
    private var received: Int32 = SIGTERM
    private var sources: [DispatchSourceSignal] = []

    init(stop: InstalledProgram.Stop) {
        signal(SIGCHLD, SIG_DFL)
        for number in [SIGTERM, SIGINT] {
            // Ignored as a disposition, so the signal reaches the source below instead of ending this command.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [self] in
                lock.withLock { received = number }
                // The source says how many arrived since it last ran: each is a request.
                for _ in 0..<max(1, source.data) { stop.request() }
            }
            source.resume()
            sources.append(source)
        }
    }

    /// The last signal received, SIGTERM before any.
    var last: Int32 { lock.withLock { received } }

    func end() {
        for source in sources { source.cancel() }
    }
}
#endif
