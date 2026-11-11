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
    private let lock = NSLock()

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
            try? FileManager.default.removeItem(at: queue)
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

    // MARK: Delivery

    /// Send the queue on a detached task; `settled` runs when the attempt ends.
    public func flushInBackground(settled: @escaping @Sendable () -> Void = {}) {
        Task.detached(priority: .utility) { [self] in
            if let stopped = await self.flush().stopped { Self.say(stopped) }
            settled()
        }
    }

    /// What one flush did: how many went, how many wait, and why it stopped.
    public struct Delivered: Sendable {
        public let sent: Int
        public let remaining: Int
        public let stopped: String?
        public let skipped: String?
    }

    /// Send every queued event oldest first, dropping each the collector
    /// accepted; the first refusal or transport error stops it, and the
    /// outcome is kept in `delivery.json`.
    public func flush() async -> Delivered {
        let events: [[String: Any]]
        do { events = try queued() } catch { return Delivered(sent: 0, remaining: 0, stopped: "\(error)", skipped: nil) }
        if Self.doNotTrack { return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "DO_NOT_TRACK") }
        switch (try? level()) ?? nil {
        case nil: return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "unanswered")
        case .off?: return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "off")
        default: break
        }
        let target: URL
        do {
            target = try collector().url
        } catch {
            let delivered = Delivered(sent: 0, remaining: events.count, stopped: "\(error)", skipped: nil)
            keep(delivered)
            return delivered
        }
        var sent = 0
        var stopped: String?
        for (index, event) in events.enumerated() {
            let eventID = event["eventId"] as? String ?? ""
            let waiting = events.count - index
            switch await post(event, to: target) {
            case .accepted:
                if let path = file("queue")?.appendingPathComponent("\(eventID).json") {
                    try? FileManager.default.removeItem(at: path)
                }
                sent += 1
                continue
            case .refused(let status, let answer):
                stopped = "sending event \(eventID) to \(target.absoluteString): the collector refused HTTP \(status): \(answer); observed: \(waiting) event(s) stay queued; fix: the answer names what the collector refuses; when it is Unknown mobile analytics app, declare app \(product.appID) in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON; the events are sent again on the next flush"
            case .failed(let status, let answer):
                stopped = "sending event \(eventID) to \(target.absoluteString): the collector failed on its own side, HTTP \(status): \(answer); observed: \(waiting) event(s) stay queued; fix: nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported from Help → Report a Problem"
            case .notCollector(let status, let answer):
                stopped = "reading the collector's answer to event \(eventID): the answer is not the collector's {\"ok\": true}: \(answer); observed: HTTP \(status) from \(target.absoluteString); fix: check that \(target.absoluteString) is the Echo app collector, /api/analytics/mobile/collect"
            case .unreachable(let cause):
                stopped = "sending event \(eventID) to \(target.absoluteString): the collector could not be reached: \(cause); observed: \(waiting) event(s) stay queued; fix: nothing to do: the events are sent on the next flush once the network or the collector is back"
            }
            break
        }
        let delivered = Delivered(sent: sent, remaining: events.count - sent, stopped: stopped, skipped: nil)
        keep(delivered)
        return delivered
    }

    private enum Answer {
        case accepted
        case refused(Int, String)
        case failed(Int, String)
        case notCollector(Int, String)
        case unreachable(String)
    }

    private func post(_ event: [String: Any], to url: URL) async -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: event)
        let session = self.session
        return await withCheckedContinuation { (answered: CheckedContinuation<Answer, Never>) in
            session.dataTask(with: request) { data, response, error in
                if let error { return answered.resume(returning: .unreachable(error.localizedDescription)) }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                if (200..<300).contains(status), object?["ok"] as? Bool == true {
                    return answered.resume(returning: .accepted)
                }
                // A server error is the collector's own failure, whatever its
                // body; below that, the collector refuses with a JSON object.
                if status >= 500 {
                    return answered.resume(returning: .failed(status, body))
                }
                if !(200..<300).contains(status), object != nil {
                    return answered.resume(returning: .refused(status, body))
                }
                answered.resume(returning: .notCollector(status, body))
            }.resume()
        }
    }

    private func keep(_ delivered: Delivered) {
        guard let path = file("delivery.json") else { return }
        let record: [String: Any] = [
            "at": Self.now(),
            "sent": delivered.sent,
            "remaining": delivered.remaining,
            "stopped": delivered.stopped.map { ["detail": $0] } as Any? ?? NSNull(),
            "skipped": delivered.skipped as Any? ?? NSNull(),
        ]
        do { try writeObject(record, to: path, what: "the last delivery") } catch { Self.say(error) }
    }

    // MARK: Status

    /// Everything a person needs to know about this installation's telemetry,
    /// with the same fields as `<product> telemetry status`.
    public func status() -> [String: Any] {
        let level: Any
        do { level = try self.level()?.rawValue ?? "unanswered" } catch { level = ["unreadable": "\(error)"] }
        let collector: Any
        let source: Any
        do {
            let found = try self.collector()
            (collector, source) = (found.url.absoluteString, found.source)
        } catch {
            (collector, source) = (NSNull(), ["refused": "\(error)"])
        }
        let installation = file("installation.json").flatMap { try? readObject($0, what: "the installation id") }?["id"]
        let queued: Any
        do { queued = try self.queued().count } catch { queued = ["unreadable": "\(error)"] }
        let lastDelivery = file("delivery.json").flatMap { try? readObject($0, what: "the last delivery") }
        return [
            "product": product.id,
            "app_id": product.appID,
            "level": level,
            "do_not_track": Self.doNotTrack,
            "collector": collector,
            "collector_source": source,
            "installation": installation ?? NSNull(),
            "queued": queued,
            "last_delivery": lastDelivery as Any? ?? NSNull(),
            "directory": directory.map { Cleaner().clean($0.path) } as Any? ?? NSNull(),
        ]
    }

    // MARK: Files

    func readObject(_ path: URL, what: String) throws -> [String: Any]? {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TelemetryError.unreadable(
                "reading \(what) from \(path.path): the file is not what telemetry wrote: it is not a JSON object; observed: the file holds \(data.count) bytes; fix: answer again in the app's settings, which rewrites it, or remove \(path.path)")
        }
        return object
    }

    func writeObject(_ object: [String: Any], to path: URL, what: String) throws {
        let folder = path.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object)
            lock.lock()
            defer { lock.unlock() }
            try data.write(to: path, options: .atomic)
        } catch {
            throw TelemetryError.unwritable(
                "keeping \(what) in \(path.path): the telemetry directory could not be written: \(error.localizedDescription); observed: directory \(folder.path); fix: make \(folder.path) writable by this user, or name a writable one with WISENT_TELEMETRY_HOME")
        }
    }

    // MARK: Facts about this machine

    static var platform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    static func say(_ what: Any) {
        FileHandle.standardError.write(Data("wisent-errors: telemetry: \(what)\n".utf8))
    }
}

/// Why telemetry could not keep or send something, as the sentence it says.
public enum TelemetryError: Error, CustomStringConvertible, Sendable {
    case noHome
    case unwritable(String)
    case unreadable(String)
    case collectorInvalid(String)

    public var description: String {
        switch self {
        case .noHome: return "neither WISENT_TELEMETRY_HOME, XDG_STATE_HOME nor a home directory is known, so nothing can be kept"
        case .unwritable(let sentence), .unreadable(let sentence), .collectorInvalid(let sentence): return sentence
        }
    }
}

/// What is taken out of every text before it is queued: the home directory
/// and this machine's host name.
struct Cleaner {
    let home: String
    let hosts: [String]

    init() {
        var home = NSHomeDirectory()
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        self.home = home
        let host = ProcessInfo.processInfo.hostName
        var hosts: [String] = []
        if !host.isEmpty, host != "localhost" {
            hosts.append(host)
            if let short = host.split(separator: ".").first, String(short) != host, !short.isEmpty {
                hosts.append(String(short))
            }
        }
        self.hosts = hosts
    }

    func clean(_ text: String) -> String {
        var cleaned = home.count > 1 ? text.replacingOccurrences(of: home, with: "~") : text
        for host in hosts { cleaned = cleaned.replacingOccurrences(of: host, with: "<this-host>") }
        return cleaned
    }
}
