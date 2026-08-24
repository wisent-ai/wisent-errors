// The failure reporter, for desktop components.
//
// One rule carries the whole file: reporting must never fail the caller. An
// error path that throws to report its error takes the diagnosis with it, so
// every misconfiguration -- no intake URL, no token, an unreachable Probierz,
// a refusal -- ends the same way: the report is dropped and the app behaves
// exactly as it did before.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends failure envelopes to a Probierz intake.
///
/// Configuration is the process environment, read at call time so a launcher
/// that sets it late still wins: `PROBIERZ_INTAKE_URL` (no path;
/// `/v1/failures` is appended) and `PROBIERZ_INTAKE_TOKEN` (the bearer). With
/// either absent, `report` is a no-op. The POST runs off the caller's path --
/// a detached task, a five-second timeout, the response body ignored, a
/// non-2xx answer swallowed.
public final class WisentFailureReporter: Sendable {
    public static let shared = WisentFailureReporter()

    /// One session for the process's reports: ephemeral, because an intake
    /// answer is read once and forgotten, and bounded, because a wedged
    /// Probierz must not hold a report open.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }()

    public init() {}

    /// Report one envelope. Never throws, never blocks: with the intake
    /// unconfigured this returns at once, and configured it hands the POST to
    /// a detached task and returns before a byte leaves.
    public func report(_ failure: Failure) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["PROBIERZ_INTAKE_URL"], !rawURL.isEmpty,
              let token = environment["PROBIERZ_INTAKE_TOKEN"], !token.isEmpty,
              let base = URL(string: rawURL)
        else { return }
        let url = base.appendingPathComponent("v1").appendingPathComponent("failures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(failure.toJSON().utf8)
        let session = self.session
        Task.detached(priority: .utility) {
            // The completion handler exists because the package's floor (iOS 13)
            // predates `URLSession.data(for:)`; the answer itself is ignored --
            // accepted, refused, or unreachable are the same to the caller.
            session.dataTask(with: request) { _, _, _ in }.resume()
        }
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
