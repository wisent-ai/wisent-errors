// The failure reporter, for desktop and iOS apps.
//
// One rule carries the whole file: reporting must never fail the caller. Every
// misconfiguration -- no product declared in Info.plist, no consent yet, no
// collector, a refusal -- ends the same way for the caller: the app behaves
// exactly as it did before. A report that could not be kept or sent is said on
// stderr, so a quiet reporter is never mistaken for a healthy app.

import Foundation

/// Reports failures through the app's telemetry (`WisentTelemetry`): queued
/// under the product's state directory once the user agreed to send errors,
/// and sent to Echo's app collector. The product comes from the app's
/// Info.plist (`WisentTelemetryProduct`, `WisentTelemetryAppID`); an app that
/// declares no product reports nothing, said once on stderr.
public final class WisentFailureReporter: Sendable {
    public static let shared = WisentFailureReporter()

    /// The app's telemetry, nil when its Info.plist declares no product.
    public let telemetry: WisentTelemetry?

    public init(telemetry: WisentTelemetry?) {
        self.telemetry = telemetry
    }

    private convenience init() {
        let (product, missing) = TelemetryProduct.fromMainBundle()
        if let missing {
            WisentTelemetry.say("this app's Info.plist declares no \(missing), so it reports no failure")
        }
        self.init(telemetry: product.map { WisentTelemetry(product: $0) })
    }

    /// Report one envelope. Never throws, never blocks: the event is queued
    /// at once when the user agreed to send errors, and sent on a detached task.
    public func report(_ failure: Failure) {
        report(failure, settled: {})
    }

    /// Report one envelope and call `settled` once the collector answered,
    /// refused or could not be reached, or at once when nothing was queued. A
    /// process about to exit awaits this; a long-running app has no reason to.
    public func report(_ failure: Failure, settled: @escaping @Sendable () -> Void) {
        guard let telemetry else { return settled() }
        telemetry.failure(failure, settled: settled)
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
