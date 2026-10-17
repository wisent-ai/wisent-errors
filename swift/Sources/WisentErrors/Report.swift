// The failure reporter, for desktop components.
//
// One rule carries the whole file: reporting must never fail the caller. An
// error path that throws to report its error takes the diagnosis with it, so
// every misconfiguration -- no intake URL, no token, an unreachable Probierz,
// a refusal -- ends the same way for the caller: the app behaves exactly as it
// did before. A report that did not land is still said on stderr, so a quiet
// intake is never mistaken for a healthy app.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends failure envelopes to a Probierz intake.
///
/// Configuration is the process environment, read at call time so a launcher
/// that sets it late still wins: `PROBIERZ_INTAKE_URL` (no path;
/// `/v1/failures` is appended) and `PROBIERZ_INTAKE_TOKEN` (the bearer). With
/// either absent, the running intake's own files are read: the address it
/// listens on from `~/.probierz/intake-url` (written when it binds) and the
/// token from `~/.probierz/intake-token` (created on its first run), which is
/// exactly the configuration a Finder-launched app inherits nothing of. With
/// no token file, `report` is a no-op; a token without an address, or either
/// file that exists but cannot be read is said on stderr. The POST runs off
/// the caller's path -- a detached task -- and an answer other than the
/// intake's `{"accepted": true}`, or a transport error, is said on stderr.
public final class WisentFailureReporter: Sendable {
    public static let shared = WisentFailureReporter()

    /// One session for the process's reports: ephemeral, because an intake
    /// answer is read once and forgotten. The request runs on a detached task,
    /// so a slow Probierz holds that task and never the caller.
    private let session = URLSession(configuration: .ephemeral)

    public init() {}

    /// Report one envelope. Never throws, never blocks: with the intake
    /// unconfigured this returns at once, and configured it hands the POST to
    /// a detached task and returns before a byte leaves.
    public func report(_ failure: Failure) {
        report(failure, settled: {})
    }

    /// Report one envelope and call `settled` once the intake has answered,
    /// refused, or could not be reached, or at once when reporting is off.
    /// A process about to exit awaits this instead of guessing how long the
    /// detached POST needs; a long-running app has no reason to.
    public func report(_ failure: Failure, settled: @escaping @Sendable () -> Void) {
        let environment = ProcessInfo.processInfo.environment
        guard let configuration = Self.intakeConfiguration(environment) else {
            settled()
            return
        }
        guard let base = URL(string: configuration.url) else {
            Self.say("the intake address \(configuration.url) is not a URL, so failure reports are off")
            settled()
            return
        }
        let (rawURL, token) = (configuration.url, configuration.token)
        let url = base.appendingPathComponent("v1").appendingPathComponent("failures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(failure.toJSON().utf8)
        let session = self.session
        Task.detached(priority: .utility) {
            // The completion handler exists because the package's floor (iOS 13)
            // predates `URLSession.data(for:)`. Accepted, refused or unreachable
            // are the same to the caller, but a report the intake did not take
            // is said on stderr, so a quiet intake is never taken for a healthy
            // app. The intake answers {"accepted": true} when it stores the
            // envelope.
            session.dataTask(with: request) { data, response, error in
                defer { settled() }
                if let error {
                    Self.say("failure report to \(rawURL) was not sent: \(error.localizedDescription)")
                    return
                }
                if let refusal = Self.refusal(data, response) {
                    Self.say("failure report to \(rawURL) was not accepted: \(refusal)")
                }
            }.resume()
        }
    }

    /// Why the intake's answer is not its acceptance, or nil when it is.
    private static func refusal(_ data: Data?, _ response: URLResponse?) -> String? {
        let status: String
        if let http = response as? HTTPURLResponse {
            status = "HTTP \(http.statusCode)"
        } else {
            status = "an answer that is not HTTP"
        }
        guard let data else { return "\(status) with no body" }
        let answer: Any
        do {
            answer = try JSONSerialization.jsonObject(with: data)
        } catch {
            return "\(status), body is not JSON (\(error.localizedDescription)): \(String(decoding: data, as: UTF8.self))"
        }
        if let object = answer as? [String: Any], object["accepted"] as? Bool == true {
            return nil
        }
        return "\(status): \(String(decoding: data, as: UTF8.self))"
    }

    private static func say(_ sentence: String) {
        FileHandle.standardError.write(Data("wisent-errors: \(sentence)\n".utf8))
    }
    /// Environment first; otherwise the intake's own token and address files.
    /// An absent token file means reporting is off; a token whose intake
    /// never wrote its address, or a file that exists but cannot be read (a
    /// sandboxed app and the 0600 owner-only file), is said on stderr, then
    /// reporting stays off.
    private static func intakeConfiguration(_ environment: [String: String]) -> (url: String, token: String)? {
        if let url = environment["PROBIERZ_INTAKE_URL"], !url.isEmpty,
           let token = environment["PROBIERZ_INTAKE_TOKEN"], !token.isEmpty {
            return (url, token)
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".probierz")
        let tokenFile = directory.appendingPathComponent("intake-token")
        guard FileManager.default.fileExists(atPath: tokenFile.path) else { return nil }
        guard let token = intakeFile(tokenFile, holding: "intake token") else { return nil }
        let urlFile = directory.appendingPathComponent("intake-url")
        guard FileManager.default.fileExists(atPath: urlFile.path) else {
            say("the intake token \(tokenFile.path) has no address beside it (\(urlFile.path) is written when probierz intake serve binds), so failure reports are off")
            return nil
        }
        guard let url = intakeFile(urlFile, holding: "intake address") else { return nil }
        return (url, token)
    }

    /// One of the intake's own files, trimmed; unreadable or empty is said on
    /// stderr and answers nil.
    private static func intakeFile(_ file: URL, holding what: String) -> String? {
        let value: String
        do {
            value = try String(contentsOf: file, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            say("the \(what) \(file.path) cannot be read, so failure reports are off: \(error.localizedDescription)")
            return nil
        }
        guard !value.isEmpty else {
            say("the \(what) \(file.path) is empty, so failure reports are off")
            return nil
        }
        return value
    }

    /// Report one failure from its parts, coercing like `Failure.orFallback`:
    /// a malformed point is kept verbatim with the violation recorded in
    /// `context`, an unknown code becomes `.unknown`, and nothing throws.
    public func report(
        failurePoint: String?,
        code: String,
        service: String?,
        detail: String? = nil,
        impact: String? = nil,
        cause: Failure? = nil
    ) {
        var failure = Failure.orFallback(
            failurePoint: failurePoint,
            code: Code(rawValue: code) ?? .unknown,
            service: service
        )
        if let detail { failure = failure.detail(detail) }
        if let impact { failure = failure.impact(impact) }
        if let cause { failure = failure.causedBy(cause) }
        report(failure)
    }
}
