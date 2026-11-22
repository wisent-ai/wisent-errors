// Why telemetry could not keep or send something, and what is taken out of
// every text before it is queued.

import Foundation

/// Why telemetry could not keep or send something: each case but `noHome`
/// carries the refusal of a declared cause of catalogue/failures/telemetry.json
/// (`OwnFailures.telemetryStore…`, `OwnFailures.telemetryDeliver…`), said as
/// the same sentence the Rust client says.
public enum TelemetryError: Error, CustomStringConvertible, Sendable {
    case noHome
    case unwritable(DeclaredRefusal)
    case unreadable(DeclaredRefusal)
    case collectorInvalid(DeclaredRefusal)

    public var description: String {
        switch self {
        case .noHome: return "neither WISENT_TELEMETRY_HOME, XDG_STATE_HOME nor a home directory is known, so nothing can be kept"
        case .unwritable(let refusal), .unreadable(let refusal), .collectorInvalid(let refusal): return refusal.description
        }
    }

    /// The declared refusal it carries; nil for `noHome`, which only a
    /// `WisentTelemetry` that knows no directory throws, and
    /// `WisentTelemetry(product:environment:)` always knows one.
    public var refusal: DeclaredRefusal? {
        switch self {
        case .noHome: return nil
        case .unwritable(let refusal), .unreadable(let refusal), .collectorInvalid(let refusal): return refusal
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
