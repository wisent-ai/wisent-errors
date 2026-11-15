// What an installation's telemetry says of itself: the same fields as
// `<product> telemetry status` (docs/telemetry.md).

import Foundation

extension WisentTelemetry {
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
        // A file that is there and cannot be read is said as `level` and
        // `queued` say theirs, never shown as no file.
        let installation: Any
        do {
            installation = try file("installation.json").flatMap { try readObject($0, what: "the installation id") }?["id"] ?? NSNull()
        } catch { installation = ["unreadable": "\(error)"] }
        let queued: Any
        do { queued = try self.queued().count } catch { queued = ["unreadable": "\(error)"] }
        let lastDelivery: Any
        do {
            lastDelivery = try file("delivery.json").flatMap { try readObject($0, what: "the last delivery") }.map { $0 as Any } ?? NSNull()
        } catch { lastDelivery = ["unreadable": "\(error)"] }
        return [
            "product": product.id,
            "app_id": product.appID,
            "level": level,
            "do_not_track": Self.doNotTrack,
            "collector": collector,
            "collector_source": source,
            "installation": installation,
            "queued": queued,
            "last_delivery": lastDelivery,
            "directory": directory.map { Cleaner().clean($0.path) } as Any? ?? NSNull(),
        ]
    }
}
