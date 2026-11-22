// Support reports filed from an installed app: Help → Report a Problem files
// one with this installation's id and, when the user agrees, its newest queued
// failure; the same window reads each back with the key it was filed with.
// The contract is docs/support.md; the sentences are the declared causes of
// catalogue/failures/telemetry.json, generated into OwnFailuresTelemetry.swift
// and into the Rust client from the same entries.

import Foundation

extension WisentTelemetry {
    /// The public address Wisent's support takes reports on. Every app files
    /// here unless `WISENT_SUPPORT_URL` names another support service.
    public static let publicSupport = URL(string: "https://support.wisent.com/v1/public/reports")!

    /// The support address and what named it: `WISENT_SUPPORT_URL`, or
    /// `wisent-errors` for Wisent's public support.
    public func supportAddress() throws -> (url: URL, source: String) {
        var runtime = ProcessInfo.processInfo.environment["WISENT_SUPPORT_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while runtime.hasSuffix("/") { runtime.removeLast() }
        guard !runtime.isEmpty else { return (Self.publicSupport, "wisent-errors") }
        guard let url = URL(string: runtime), Self.supportAcceptable(url) else {
            throw SupportError.addressInvalid(OwnFailures.supportExchange.refusal(OwnFailures.supportExchangeSupportAddressInvalid, ["address": runtime]))
        }
        return (url, "WISENT_SUPPORT_URL")
    }

    private static func supportAcceptable(_ url: URL) -> Bool {
        switch url.scheme {
        case "https": return url.host != nil
        case "http": return ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
        default: return false
        }
    }

    /// File one report and keep its id and access key in
    /// `support/<id>.json` under the telemetry directory. Answers what
    /// support answered, without the key.
    public func fileReport(subject: String?, description: String, email: String?, withFailure: Bool) async throws -> [String: Any] {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            throw SupportError.descriptionEmpty(OwnFailures.supportReport.refusal(OwnFailures.supportReportSupportDescriptionEmpty, ["product": product.id]))
        }
        let address = try supportAddress().url
        guard let folder = file("support") else { throw TelemetryError.noHome }
        let failure: Any = withFailure ? (try newestFailure() ?? NSNull()) : NSNull()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let trimmed = { (text: String?) -> Any in
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? NSNull() : value
        }
        let body: [String: Any] = [
            "product": product.id,
            "app": product.appID,
            "version": product.version,
            "os": "\(Self.platform == "ios" ? "iOS" : "macOS") \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "installation": try installationID(),
            "subject": trimmed(subject),
            "description": description,
            "email": trimmed(email),
            "failure": failure,
        ]
        var request = URLRequest(url: address)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (answer, status) = try await exchange(request, doing: "filing a support report", observed: "nothing was filed")
        guard let id = answer["id"] as? String, let key = answer["access_key"] as? String else {
            throw SupportError.answerUnreadable(OwnFailures.supportExchange.refusal(OwnFailures.supportExchangeSupportAnswerUnreadable, [
                "address": address.absoluteString, "answer": Self.oneLine(answer), "status": String(status),
            ]))
        }
        let kept = folder.appendingPathComponent("\(id).json")
        try writeObject([
            "id": id, "access_key": key, "address": address.absoluteString,
            "subject": body["subject"] as Any, "filed_at": Self.now(),
        ], to: kept, what: "a support report's key")
        return [
            "id": id,
            "status": answer["status"] as Any? ?? NSNull(),
            "created_at": answer["created_at"] as Any? ?? NSNull(),
            "address": address.absoluteString,
            "kept": kept.path,
            "with_failure": !(failure is NSNull),
        ]
    }

    /// Every report this installation filed, oldest first, as support answers
    /// it now: `status` and `replies`, or `unread` with the sentence that
    /// stopped the reading.
    public func reports() async throws -> [[String: Any]] {
        guard let folder = file("support") else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
        var kept: [[String: Any]] = []
        for name in names where name.hasSuffix(".json") {
            if let report = try readObject(
                folder.appendingPathComponent(name), what: "a support report's key",
                damaged: OwnFailures.telemetryStoreSupportKeyUnreadable, refused: OwnFailures.telemetryStoreSupportKeyReadRefused)
            {
                kept.append(report)
            }
        }
        kept.sort { ($0["filed_at"] as? String ?? "") < ($1["filed_at"] as? String ?? "") }
        var read: [[String: Any]] = []
        for report in kept {
            let id = report["id"] as? String ?? ""
            let address = report["address"] as? String ?? Self.publicSupport.absoluteString
            guard let url = URL(string: "\(address)/\(id)") else { continue }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(report["access_key"] as? String ?? "")", forHTTPHeaderField: "Authorization")
            do {
                read.append(try await exchange(request, doing: "reading report \(id)", observed: "its state is unknown until support answers").answer)
            } catch {
                read.append(["id": id, "subject": report["subject"] as Any? ?? NSNull(), "unread": "\(error)"])
            }
        }
        return read
    }

    /// The properties of the newest failure waiting in the queue, or nil.
    private func newestFailure() throws -> [String: Any]? {
        try queued()
            .filter { $0["eventName"] as? String == "failure" }
            .max { ($0["occurredAt"] as? String ?? "") < ($1["occurredAt"] as? String ?? "") }?["properties"] as? [String: Any]
    }

    /// One request to support, its JSON answer and the HTTP status it came
    /// with, or the sentence naming what was being done, where, and why it
    /// stopped.
    private func exchange(_ request: URLRequest, doing: String, observed: String) async throws -> (answer: [String: Any], status: Int) {
        let address = request.url?.absoluteString ?? ""
        let session = self.session
        let (data, status, failure): (Data?, Int, String?) = await withCheckedContinuation { answered in
            session.dataTask(with: request) { data, response, error in
                answered.resume(returning: (data, (response as? HTTPURLResponse)?.statusCode ?? 0, error?.explained))
            }.resume()
        }
        if let failure {
            throw SupportError.unreachable(OwnFailures.supportExchange.refusal(OwnFailures.supportExchangeSupportUnreachable, [
                "doing": doing, "address": address, "why": failure, "observed": observed, "product": product.id,
            ]))
        }
        let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if (200..<300).contains(status), let object { return (object, status) }
        let error = object?["error"] as? [String: Any]
        if !(200..<300).contains(status), let reason = (error?["message"] ?? error?["code"]) as? String {
            throw SupportError.refused(OwnFailures.supportExchange.refusal(OwnFailures.supportExchangeSupportRefused, [
                "doing": doing, "address": address, "status": String(status), "answer": reason, "observed": observed,
                "product": product.id,
            ]))
        }
        throw SupportError.answerUnreadable(OwnFailures.supportExchange.refusal(OwnFailures.supportExchangeSupportAnswerUnreadable, [
            "address": address, "answer": Self.oneLine(text), "status": String(status),
        ]))
    }
}

/// Why a support report could not be filed or read: the refusal of a
/// declared cause of catalogue/failures/telemetry.json
/// (`OwnFailures.supportReport…`, `OwnFailures.supportExchange…`), said as
/// its sentence.
public enum SupportError: Error, CustomStringConvertible, Sendable {
    case descriptionEmpty(DeclaredRefusal)
    case addressInvalid(DeclaredRefusal)
    case refused(DeclaredRefusal)
    case unreachable(DeclaredRefusal)
    case answerUnreadable(DeclaredRefusal)

    public var description: String { refusal.description }

    /// The declared refusal it carries.
    public var refusal: DeclaredRefusal {
        switch self {
        case .descriptionEmpty(let refusal), .addressInvalid(let refusal), .refused(let refusal),
             .unreachable(let refusal), .answerUnreadable(let refusal):
            return refusal
        }
    }
}
