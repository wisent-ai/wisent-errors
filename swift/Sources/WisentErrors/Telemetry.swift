// Telemetry from installed copies, for Swift apps: the same contract, files and
// event shape as the Rust crate's `telemetry` feature (docs/telemetry.md), so a
// product's command line and its app keep one consent, one installation id and
// one queue under `$XDG_STATE_HOME/<product>/telemetry`.
//
// Nothing is queued before the user answers, and nothing here ever changes the
// app's own behaviour: every failure of telemetry is said once on stderr,
// starting with `wisent-errors: telemetry:`, and the app goes on.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What the user agreed to send.
public enum TelemetryLevel: String, Sendable, CaseIterable, Comparable {
    case off, errors, usage

    private var rank: Int {
        switch self {
        case .off: return 0
        case .errors: return 1
        case .usage: return 2
        }
    }

    public static func < (left: TelemetryLevel, right: TelemetryLevel) -> Bool {
        left.rank < right.rank
    }
}

/// Which product is reporting, read from the app's Info.plist:
/// `WisentTelemetryProduct` (the product id, `ster`) and `WisentTelemetryAppID`
/// (the app the collector declares, `ster-desktop`).
public struct TelemetryProduct: Sendable, Equatable {
    public let id: String
    public let appID: String
    public let version: String

    public init(id: String, appID: String, version: String) {
        self.id = id
        self.appID = appID
        self.version = version
    }

    /// The product the main bundle declares, or nil naming the missing key.
    public static func fromMainBundle() -> (product: TelemetryProduct?, missing: String?) {
        let info = Bundle.main.infoDictionary ?? [:]
        let value = { (key: String) -> String? in
            (info[key] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let id = value("WisentTelemetryProduct") else { return (nil, "WisentTelemetryProduct") }
        guard let app = value("WisentTelemetryAppID") else { return (nil, "WisentTelemetryAppID") }
        let version = value("CFBundleShortVersionString") ?? "unknown"
        return (TelemetryProduct(id: id, appID: app, version: version), nil)
    }
}

/// The telemetry of one product: its consent, its queue, and sending it.
public final class WisentTelemetry: @unchecked Sendable {
    public let product: TelemetryProduct
    public let directory: URL?
    let session = URLSession(configuration: .ephemeral)
    private let sessionID = UUID().uuidString.lowercased()
    let lock = NSLock()

    public init(product: TelemetryProduct, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.product = product
        self.directory = Self.directory(product: product.id, environment: environment)
    }

    static func directory(product: String, environment: [String: String]) -> URL? {
        let set = { (name: String) -> String? in environment[name].flatMap { $0.isEmpty ? nil : $0 } }
        if let home = set("WISENT_TELEMETRY_HOME") { return URL(fileURLWithPath: home, isDirectory: true) }
        if let state = set("XDG_STATE_HOME") {
            return URL(fileURLWithPath: state, isDirectory: true)
                .appendingPathComponent(product).appendingPathComponent("telemetry")
        }
        // NSHomeDirectory, not homeDirectoryForCurrentUser: the latter is
        // unavailable on iOS, which this package declares.
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".local").appendingPathComponent("state")
            .appendingPathComponent(product).appendingPathComponent("telemetry")
    }

    func file(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    // MARK: Consent

    /// `DO_NOT_TRACK` set to `1` or `true` turns every level off.
    public static var doNotTrack: Bool {
        let value = ProcessInfo.processInfo.environment["DO_NOT_TRACK"]?.trimmingCharacters(in: .whitespaces)
        return value == "1" || value == "true"
    }

    /// The level the user chose, nil while unanswered; a file telemetry did
    /// not write is refused naming it.
    public func level() throws -> TelemetryLevel? {
        guard let path = file("consent.json"), let consent = try readObject(path, what: "the telemetry consent") else {
            return nil
        }
        let text = consent["level"] as? String ?? ""
        guard let level = TelemetryLevel(rawValue: text) else {
            throw TelemetryError.unreadable(
                "reading the telemetry consent from \(path.path): the file is not what telemetry wrote: level \"\(text)\" is not off, errors or usage; fix: answer again in the app's settings, which rewrites it, or remove \(path.path)")
        }
        return level
    }

    /// Keep the user's answer; turning telemetry off drops what waits.
    public func setLevel(_ level: TelemetryLevel) throws {
        guard let path = file("consent.json") else { throw TelemetryError.noHome }
        try writeObject(["level": level.rawValue, "answered_at": Self.now()], to: path, what: "the telemetry consent")
        if level == .off, let queue = file("queue") {
            try remove(queue, what: "the event queue", left: "the events queued before telemetry was turned off are still kept, and are sent if it is turned on again")
        }
    }

    private func effective() -> TelemetryLevel {
        if Self.doNotTrack { return .off }
        return ((try? level()) ?? nil) ?? .off
    }

    // MARK: Collector

    /// The public address Wisent's collector answers telemetry on. Every
    /// product sends here unless `WISENT_TELEMETRY_COLLECTOR_URL` names another
    /// collector, such as a self-hosted Echo or a test's.
    public static let publicCollector = URL(string: "https://telemetry.wisent.com/api/analytics/mobile/collect")!

    /// The collector address and what named it: `WISENT_TELEMETRY_COLLECTOR_URL`,
    /// or `wisent-errors` for the public collector; an address that is not
    /// https (or http on the loopback) is refused naming it.
    public func collector() throws -> (url: URL, source: String) {
        let runtime = ProcessInfo.processInfo.environment["WISENT_TELEMETRY_COLLECTOR_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = runtime, !address.isEmpty else {
            return (Self.publicCollector, "wisent-errors")
        }
        guard let url = URL(string: address), Self.acceptable(url) else {
            throw TelemetryError.collectorInvalid(
                "reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds \(address)")
        }
        return (url, "WISENT_TELEMETRY_COLLECTOR_URL")
    }

    private static func acceptable(_ url: URL) -> Bool {
        switch url.scheme {
        case "https": return url.host != nil
        case "http": return ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
        default: return false
        }
    }

    // MARK: Recording

    /// Queue one failure when the user agreed to send errors, and send the
    /// queue. `settled` runs once that attempt ended, at once when nothing was
    /// queued.
    public func failure(_ failure: Failure, causeID: String? = nil, settled: @escaping @Sendable () -> Void = {}) {
        guard effective() >= .errors else { return settled() }
        do {
            try queue(eventName: "failure", properties: failureProperties(failure, causeID: causeID))
            try noteFailure(failure)
        } catch {
            Self.say(error)
            return settled()
        }
        flushInBackground(settled: settled)
    }

    /// `frustration.repeat_failure` when the failure before this one had the
    /// same failure point, with how many in a row and the seconds since the
    /// previous (docs/telemetry.md, Frustration signals). The state is the
    /// command line's `signals.json`, so an app and its CLI count one run.
    private func noteFailure(_ failure: Failure) throws {
        guard let path = file("signals.json") else { throw TelemetryError.noHome }
        var state = try readObject(path, what: "the frustration signals") ?? [:]
        let now = Int(Date().timeIntervalSince1970)
        let last = state["last_failure"] as? [String: Any]
        let previous = (last?["failure_point"] as? String) == failure.failurePoint ? last : nil
        let consecutive = ((previous?["consecutive"] as? Int) ?? 0) + 1
        state["last_failure"] = ["failure_point": failure.failurePoint, "consecutive": consecutive, "at": now]
        if consecutive >= 2 {
            let since: Any = (previous?["at"] as? Int).map { max(0, now - $0) } ?? NSNull()
            try queue(eventName: "frustration.repeat_failure", properties: [
                "failure_point": failure.failurePoint, "consecutive": consecutive, "seconds_since_previous": since,
            ])
        }
        try writeObject(state, to: path, what: "the frustration signals")
    }

    private func queue(eventName: String, properties: [String: Any]) throws {
        guard let queue = file("queue") else { throw TelemetryError.noHome }
        let installation = try installationID()
        let eventID = UUID().uuidString.lowercased()
        var event: [String: Any] = [
            "eventId": eventID,
            "appId": product.appID,
            "platform": Self.platform,
            "eventName": eventName,
            "anonymousId": installation,
            "sessionId": sessionID,
            "appVersion": product.version,
            "occurredAt": Self.now(),
            "properties": properties,
        ]
        let version = ProcessInfo.processInfo.operatingSystemVersion
        event["osVersion"] = "\(Self.platform == "ios" ? "iOS" : "macOS") \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        try writeObject(event, to: queue.appendingPathComponent("\(eventID).json"), what: "an event")
    }

    func installationID() throws -> String {
        guard let path = file("installation.json") else { throw TelemetryError.noHome }
        if let existing = try readObject(path, what: "the installation id"), let id = existing["id"] as? String {
            return id
        }
        let id = UUID().uuidString.lowercased()
        try writeObject(["id": id, "created_at": Self.now()], to: path, what: "the installation id")
        return id
    }

    private func failureProperties(_ failure: Failure, causeID: String?) -> [String: Any] {
        let clean = Cleaner()
        var causes: [[String: Any]] = []
        var below = failure.cause.first
        while let cause = below {
            causes.append([
                "failure_point": cause.failurePoint,
                "error_code": cause.code.rawValue,
                "service": cause.service,
                "detail": cause.detail.map(clean.clean) as Any? ?? NSNull(),
            ])
            below = cause.cause.first
        }
        return [
            "failure_point": failure.failurePoint,
            "error_code": failure.code.rawValue,
            "severity": failure.severity.rawValue,
            "retryable": failure.retryable,
            "outage": failure.outage,
            "service": failure.service,
            "impact": failure.impact.map(clean.clean) as Any? ?? NSNull(),
            "detail": failure.detail.map(clean.clean) as Any? ?? NSNull(),
            "remedy": failure.remedy.map(clean.clean) as Any? ?? NSNull(),
            "cause_id": causeID as Any? ?? NSNull(),
            "context": failure.context.mapValues(clean.clean),
            "causes": causes,
        ]
    }

    // MARK: The queue

    /// Every event waiting to be sent, oldest first, exactly as it will go.
    public func queued() throws -> [[String: Any]] {
        guard let queue = file("queue") else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: queue.path)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
        var events: [[String: Any]] = []
        for name in names where name.hasSuffix(".json") {
            if let event = try readObject(queue.appendingPathComponent(name), what: "a queued event") {
                events.append(event)
            }
        }
        return events.sorted { ($0["occurredAt"] as? String ?? "") < ($1["occurredAt"] as? String ?? "") }
    }
}
