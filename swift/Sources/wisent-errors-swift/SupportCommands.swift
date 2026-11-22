// `support report`: one support report filed for the product the command
// line names, as its app's Help → Report a Problem window files it
// (`WisentTelemetry.fileReport`, docs/support.md): its description, subject
// and email, and with `--with-failure` the newest failure waiting in the
// telemetry queue. Support's answer is printed as JSON, and the report's key
// is kept under the telemetry directory, where `support status` reads it.
//
// `support status`: every report this installation filed, as support answers
// it now (`WisentTelemetry.reports`), printed as JSON.
//
// A refusal of the support service, its address or the store is the
// library's declared refusal, printed whole.

#if os(macOS)
import Foundation
import WisentErrors

enum SupportCommands {
    static let all: [Command] = [
        TelemetryCommands.command(
            "support report",
            values: [
                ("--description", "\"the pairs import stops on a file that opens fine\""),
                ("--subject", "\"pairs import fails\""), ("--email", "person@example.com"),
            ],
            flags: ["--with-failure"],
            example: "support report --product ster --app ster-desktop --description \"the pairs import stops on a file that opens fine\"",
            perform: SupportCommands.report),
        TelemetryCommands.command(
            "support status", example: "support status --product ster --app ster-desktop", perform: SupportCommands.status),
    ]

    /// `body`, with what support or telemetry throws said as its declared refusal.
    static func refusing<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as SupportError {
            throw error.refusal
        } catch let error as TelemetryError {
            guard let refusal = error.refusal else { throw error }
            throw refusal
        }
    }

    static func report(_ given: Given) async throws -> Int32 {
        let telemetry = try TelemetryCommands.opened(given)
        let description = try given.required("--description")
        let filed = try await refusing {
            try await telemetry.fileReport(
                subject: given.optional("--subject"), description: description, email: given.optional("--email"),
                withFailure: given.flags.contains("--with-failure"))
        }
        say(try printed(filed))
        return EXIT_SUCCESS
    }

    static func status(_ given: Given) async throws -> Int32 {
        let telemetry = try TelemetryCommands.opened(given)
        let reports = try await refusing { try await telemetry.reports() }
        say(try printed(reports))
        return EXIT_SUCCESS
    }
}
#endif
