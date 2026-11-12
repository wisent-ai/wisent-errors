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
}
