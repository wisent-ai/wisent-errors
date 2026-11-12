// Support reports filed from an installed app: Help → Report a Problem files
// one with this installation's id and, when the user agrees, its newest queued
// failure; the same window reads each back with the key it was filed with.
// The contract is docs/support.md; the sentences are the Rust client's.

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
            throw SupportError.addressInvalid(
                "reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds \(runtime); fix: set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it")
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
            throw SupportError.descriptionEmpty(
                "filing a support report: the report has no description; observed: the description is empty; fix: say what you were doing and what happened")
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
        let answer = try await exchange(request, doing: "filing a support report", observed: "nothing was filed")
        guard let id = answer["id"] as? String, let key = answer["access_key"] as? String else {
            throw SupportError.answerUnreadable(
                "reading support's answer at \(address.absoluteString): the answer is not a support service's: \(answer); observed: HTTP 201; fix: check that \(address.absoluteString) is a support service's /v1/public/reports")
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
            if let report = try readObject(folder.appendingPathComponent(name), what: "a support report's key") {
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
                read.append(try await exchange(request, doing: "reading report \(id)", observed: "its state is unknown until support answers"))
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

    /// One request to support and its JSON answer, or the sentence naming
    /// what was being done, where, and why it stopped.
    private func exchange(_ request: URLRequest, doing: String, observed: String) async throws -> [String: Any] {
        let address = request.url?.absoluteString ?? ""
        let session = self.session
        let (data, status, failure): (Data?, Int, String?) = await withCheckedContinuation { answered in
            session.dataTask(with: request) { data, response, error in
                answered.resume(returning: (data, (response as? HTTPURLResponse)?.statusCode ?? 0, error?.explained))
            }.resume()
        }
        if let failure {
            throw SupportError.unreachable(
                "\(doing) at \(address): support could not be reached: \(failure); observed: \(observed); fix: run it again once the network or support is back")
        }
        let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if (200..<300).contains(status), let object { return object }
        let error = object?["error"] as? [String: Any]
        if !(200..<300).contains(status), let reason = (error?["message"] ?? error?["code"]) as? String {
            throw SupportError.refused(
                "\(doing) at \(address): support refused HTTP \(status): \(reason); observed: \(observed); fix: the answer is support's own reason: correct what it names and try again")
        }
        throw SupportError.answerUnreadable(
            "reading support's answer at \(address): the answer is not a support service's: \(text); observed: HTTP \(status); fix: check that \(address) is a support service's /v1/public/reports")
    }
}

/// Why a support report could not be filed or read, as the sentence it says.
public enum SupportError: Error, CustomStringConvertible, Sendable {
    case descriptionEmpty(String)
    case addressInvalid(String)
    case refused(String)
    case unreachable(String)
    case answerUnreadable(String)

    public var description: String {
        switch self {
        case .descriptionEmpty(let sentence), .addressInvalid(let sentence), .refused(let sentence),
             .unreachable(let sentence), .answerUnreadable(let sentence):
            return sentence
        }
    }
}
