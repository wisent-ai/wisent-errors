// `telemetry status|set|failure|show|flush|settings`: a product's telemetry
// kept from a terminal through `WisentTelemetry`, the same files its app
// keeps (docs/telemetry.md): under WISENT_TELEMETRY_HOME, else
// $XDG_STATE_HOME/<product>/telemetry, else ~/.local/state/<product>/telemetry.
// The product is named on the command line (`--product`, `--app`,
// `--app-version`), as an app's Info.plist names it. A refusal of the store,
// the collector or the consent is the library's declared refusal, printed
// whole; `telemetry failure` reports the way an app reports, so what it
// cannot keep or send is said on stderr by the library and never changes its
// exit status.

#if os(macOS)
import Foundation
import WisentErrors

enum TelemetryCommands {
    /// The options naming the product every telemetry and support command takes.
    static let product: [(option: String, example: String)] = [
        ("--product", "ster"), ("--app", "ster-desktop"), ("--app-version", "1.4.0"),
    ]

    static let levels = TelemetryLevel.allCases.map { ($0.rawValue, $0) }

    static func command(
        _ words: String, values: [(option: String, example: String)] = [], flags: [String] = [],
        operands: [String] = [], example: String, perform: @escaping (Given) async throws -> Int32
    ) -> Command {
        Command(
            words: words, values: product + values, lists: [], flags: flags, operands: operands, rest: false,
            example: example, perform: perform)
    }

    static let all: [Command] = [
        command("telemetry status", example: "telemetry status --product ster --app ster-desktop", perform: TelemetryCommands.status),
        command("telemetry set", operands: ["<off|errors|usage>"], example: "telemetry set errors --product ster --app ster-desktop", perform: TelemetryCommands.set),
        command(
            "telemetry failure",
            values: [
                ("--point", "ster.backend-start"), ("--code", "config"), ("--service", "ster"),
                ("--detail", "\"the backend exited 3\""), ("--remedy", "\"run ster doctor\""),
                ("--impact", "\"the backend\""), ("--cause-id", "backend-unstarted"),
            ],
            example: "telemetry failure --product ster --app ster-desktop --point ster.backend-start --code config --service ster",
            perform: TelemetryCommands.failure),
        command("telemetry show", example: "telemetry show --product ster --app ster-desktop", perform: TelemetryCommands.show),
        command("telemetry flush", example: "telemetry flush --product ster --app ster-desktop", perform: TelemetryCommands.flush),
        command("telemetry settings", example: "telemetry settings --product ster --app ster-desktop", perform: TelemetryCommands.settings),
    ]

    /// The telemetry of the product `given` names.
    static func opened(_ given: Given) throws -> WisentTelemetry {
        WisentTelemetry(product: TelemetryProduct(
            id: try given.required("--product"), appID: try given.required("--app"),
            // fallback: a product that names no version is sent as "unknown", as an app whose Info.plist names none.
            version: given.optional("--app-version") ?? "unknown"))
    }

    /// `body`, with what telemetry throws said as its declared refusal.
    static func refusing<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as TelemetryError {
            guard let refusal = error.refusal else { throw error }
            throw refusal
        }
    }

    static func status(_ given: Given) async throws -> Int32 {
        say(try printed(try opened(given).status()))
        return EXIT_SUCCESS
    }

    static func set(_ given: Given) async throws -> Int32 {
        let level = try given.choice("the level", given.operands[0], levels)
        let telemetry = try opened(given)
        try refusing { try telemetry.setLevel(level) }
        say("\(telemetry.product.id) telemetry: \(level.rawValue)\n")
        return EXIT_SUCCESS
    }

    static func failure(_ given: Given) async throws -> Int32 {
        let telemetry = try opened(given)
        let code = try given.choice("--code", try given.required("--code"), EnvelopeCommands.codes)
        var failure: Failure
        do {
            failure = try Failure(failurePoint: try given.required("--point"), code: code, service: try given.required("--service"))
        } catch let invalid as Invalid {
            throw invalid.refusal
        }
        if let impact = given.optional("--impact") { failure = failure.impact(impact) }
        failure = failure.detail(given.optional("--detail")).remedy(given.optional("--remedy"))
        let reported = failure
        await withCheckedContinuation { (settled: CheckedContinuation<Void, Never>) in
            telemetry.failure(reported, causeID: given.optional("--cause-id")) { settled.resume() }
        }
        return EXIT_SUCCESS
    }

    static func show(_ given: Given) async throws -> Int32 {
        let telemetry = try opened(given)
        say(try printed(try refusing { try telemetry.queued() }))
        return EXIT_SUCCESS
    }

    static func flush(_ given: Given) async throws -> Int32 {
        let delivered = try await opened(given).flush()
        say(try printed([
            "sent": delivered.sent, "remaining": delivered.remaining,
            // fallback: a flush that skipped nothing says so as null, as `delivery.json` keeps it.
            "skipped": delivered.skipped as Any? ?? NSNull(),
        ] as [String: Any]))
        if let refusal = delivered.refusal { throw refusal }
        if let stopped = delivered.stopped {
            // TelemetryError.noHome, which no WisentTelemetry this command makes throws: said whole.
            tell("Error: \(stopped)\n")
            return EXIT_FAILURE
        }
        return EXIT_SUCCESS
    }

    static func settings(_ given: Given) async throws -> Int32 {
        let telemetry = try opened(given)
        return try await SettingsWindow.open(telemetry)
    }
}
#endif
