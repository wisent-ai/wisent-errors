// `envelope build`: one failure envelope built from its options, strictly
// (`Failure(failurePoint:code:service:)`, whose refusals are the declared
// causes of `wisent_errors.envelope.build`) or with `--fallback`
// (`Failure.orFallback`, which never refuses and records the gap in the
// envelope's context), printed as JSON and, with `--out`, written to a file.
//
// `envelope read`: one envelope read from a JSON file (Input.swift) and
// printed for a person: `Failure.render()`, then `Failure.chain()`.

#if os(macOS)
import Foundation
import WisentErrors

enum EnvelopeCommands {
    static let codes = Code.allCases.map { ($0.rawValue, $0) }

    static let all: [Command] = [
        Command(
            words: "envelope build",
            values: [
                ("--point", "stado.fleet.enroll"), ("--code", "refused"), ("--service", "stado"),
                ("--detail", "\"the fleet answered 403\""), ("--remedy", "\"enroll the host first\""),
                ("--impact", "\"one enrollment\""), ("--out", "failure.json"),
            ],
            lists: [("--context", "host=example-host")],
            flags: ["--fallback"],
            operands: [],
            rest: false,
            example: "envelope build --point stado.fleet.enroll --code refused --service stado",
            perform: EnvelopeCommands.build
        ),
        Command(
            words: "envelope read",
            values: [],
            lists: [],
            flags: [],
            operands: ["<file>"],
            rest: false,
            example: "envelope read failure.json",
            perform: EnvelopeCommands.read
        ),
    ]

    static func build(_ given: Given) async throws -> Int32 {
        let point = try given.required("--point")
        let code = try given.choice("--code", try given.required("--code"), codes)
        let service = try given.required("--service")
        var failure: Failure
        if given.flags.contains("--fallback") {
            failure = Failure.orFallback(failurePoint: point, code: code, service: service)
        } else {
            do {
                failure = try Failure(failurePoint: point, code: code, service: service)
            } catch let invalid as Invalid {
                throw invalid.refusal
            }
        }
        if let impact = given.optional("--impact") { failure = failure.impact(impact) }
        failure = failure.detail(given.optional("--detail")).remedy(given.optional("--remedy"))
        for entry in given.all("--context") {
            let (key, value) = try given.pair("--context", entry, example: "--context host=example-host")
            failure = failure.withContext(key, value)
        }
        let json = failure.toJSON() + "\n"
        if let out = given.optional("--out") {
            let url = URL(fileURLWithPath: out)
            do {
                try Data(json.utf8).write(to: url, options: .atomic)
            } catch {
                throw OwnFailures.swiftCliEnvelopeBuild.refusal(OwnFailures.swiftCliEnvelopeBuildEnvelopeUnwritten, [
                    "path": url.path, "state": FileState.of(url.deletingLastPathComponent()), "error": error.explained,
                ])
            }
        }
        say(json)
        return EXIT_SUCCESS
    }

    /// An envelope as a JSON document holds it, every runtime's key names.
    final class Envelope: Decodable {
        let failurePoint: String
        let errorCode: Code
        let service: String
        let impact: String?
        let detail: String?
        let remedy: String?
        let cause: Envelope?
        let context: [String: String]?

        enum CodingKeys: String, CodingKey {
            case failurePoint = "failure_point", errorCode = "error_code", service, impact, detail, remedy, cause, context
        }

        /// The envelope it holds, built as strictly as `envelope build` builds one.
        func failure() throws -> Failure {
            var failure: Failure
            do {
                failure = try Failure(failurePoint: failurePoint, code: errorCode, service: service)
            } catch let invalid as Invalid {
                throw invalid.refusal
            }
            if let impact { failure = failure.impact(impact) }
            failure = failure.detail(detail).remedy(remedy)
            // fallback: an envelope without context carries none.
            for (key, value) in (context ?? [:]).sorted(by: { $0.key < $1.key }) {
                failure = failure.withContext(key, value)
            }
            if let cause { failure = failure.causedBy(try cause.failure()) }
            return failure
        }
    }

    static let document = Document<Envelope>(
        what: "the envelope",
        shape: "a failure envelope: an object with failure_point, error_code and service, and impact, detail, remedy, cause and context where it has them",
        example: #"{"failure_point":"stado.fleet.enroll","error_code":"refused","service":"stado"}"#
    )

    static func read(_ given: Given) async throws -> Int32 {
        let failure = try document.read(given.operands[0]).failure()
        say(failure.render() + "\n" + failure.chain().joined(separator: "\n") + "\n")
        return EXIT_SUCCESS
    }
}
#endif
