// The telemetry settings every Wisent app shows in its Settings window: what
// this installation reports when something fails, the events waiting to be
// sent exactly as they will go, and sending them now. It reads and changes the
// same files the product's command line does (`WisentTelemetry`), so an app
// and its command line keep one choice and one queue.

#if canImport(SwiftUI)
import Foundation
import SwiftUI
import WisentErrors

@available(macOS 13, iOS 16, *)
@MainActor
public final class TelemetrySettings: ObservableObject {
    public let telemetry: WisentTelemetry?
    @Published public private(set) var status: [String: Any] = [:]
    @Published public private(set) var waiting: String?
    @Published public private(set) var outcome: String?
    @Published public private(set) var failure: String?

    public init(telemetry: WisentTelemetry?) {
        self.telemetry = telemetry
        refresh()
    }

    public var level: String { status["level"] as? String ?? "unanswered" }

    public func refresh() {
        status = telemetry?.status() ?? [:]
    }

    public func set(level: TelemetryLevel) {
        failure = nil
        do {
            try telemetry?.setLevel(level)
        } catch {
            failure = "\(error)"
        }
        refresh()
    }

    public func show() {
        failure = nil
        do {
            let events = try telemetry?.queued() ?? []
            let data = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            waiting = String(decoding: data, as: UTF8.self)
        } catch {
            failure = "\(error)"
        }
    }

    public func flush() async {
        guard let telemetry else { return }
        let delivered = await telemetry.flush()
        outcome = delivered.skipped.map { "Nothing sent: \($0)." } ?? "Sent \(delivered.sent) event(s)."
        failure = delivered.stopped
        refresh()
    }
}

/// The section an app puts in its `Settings` scene. `productName` is how the
/// user knows the product ("Jeden").
@available(macOS 13, iOS 16, *)
public struct TelemetrySettingsView: View {
    @StateObject private var settings: TelemetrySettings
    private let productName: String

    public init(productName: String, telemetry: WisentTelemetry?) {
        self.productName = productName
        _settings = StateObject(wrappedValue: TelemetrySettings(telemetry: telemetry))
    }

    public var body: some View {
        Form {
            if settings.telemetry == nil {
                Text("This build of \(productName) declares no product for telemetry, so it reports nothing.")
                    .foregroundStyle(.secondary)
            } else {
                Section("What \(productName) may send") {
                    Text(
                        "\(productName) can tell its maintainers when something fails on this device, so it gets fixed without you writing to anyone. Nothing you work on is sent: no files, prompts or command arguments, and your home folder and this device's name are taken out first. \(productName)'s command line, where it has one, uses the same choice."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Picker("Send", selection: Binding(
                        get: { settings.level },
                        set: { value in TelemetryLevel(rawValue: value).map(settings.set(level:)) }
                    )) {
                        if settings.level == "unanswered" {
                            Text("Not answered yet: nothing is sent").tag("unanswered")
                        }
                        Text("Send nothing").tag(TelemetryLevel.off.rawValue)
                        Text("Send failures").tag(TelemetryLevel.errors.rawValue)
                        Text("Send failures and what ran").tag(TelemetryLevel.usage.rawValue)
                    }
                    #if os(macOS)
                    .pickerStyle(.radioGroup)
                    #endif
                }
                Section("This installation") {
                    LabeledContent("Waiting to be sent", value: "\(settings.status["queued"] as? Int ?? 0)")
                    LabeledContent("Sent to", value: settings.status["collector"] as? String
                        ?? ((settings.status["collector_source"] as? [String: Any])?["refused"] as? String ?? "no address"))
                    if let delivery = settings.status["last_delivery"] as? [String: Any] {
                        LabeledContent("Last sent", value: delivery["at"] as? String ?? "never")
                    }
                    if (settings.status["do_not_track"] as? Bool) == true {
                        Text("DO_NOT_TRACK is set, so nothing is sent whatever is chosen above.").font(.callout)
                    }
                    HStack {
                        Button("Show what waits") { settings.show() }
                        Button("Send now") { Task { await settings.flush() } }
                    }
                    if let outcome = settings.outcome { Text(outcome).font(.callout) }
                    if let failure = settings.failure {
                        Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                if let waiting = settings.waiting {
                    Section("Waiting events, exactly as they will be sent") {
                        ScrollView {
                            Text(waiting).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 160)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
#endif
