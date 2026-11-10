// Help → Report a Problem in every Wisent app: write to support with the
// installation's facts attached, and read the replies to every report this
// installation filed. It files and reads exactly what `<product> support
// report|status` does (`WisentTelemetry.fileReport`, `reports`).

#if canImport(SwiftUI)
import Foundation
import SwiftUI
import WisentErrors

@available(macOS 13, iOS 16, *)
@MainActor
public final class SupportReports: ObservableObject {
    public let telemetry: WisentTelemetry?
    @Published public var subject = ""
    @Published public var details = ""
    @Published public var email = ""
    @Published public var withFailure = true
    @Published public private(set) var sending = false
    @Published public private(set) var filed: String?
    @Published public private(set) var failure: String?
    @Published public private(set) var reports: [[String: Any]] = []

    public init(telemetry: WisentTelemetry?) {
        self.telemetry = telemetry
    }

    public func send() async {
        guard let telemetry else { return }
        sending = true
        failure = nil
        filed = nil
        defer { sending = false }
        do {
            let answer = try await telemetry.fileReport(subject: subject, description: details, email: email, withFailure: withFailure)
            filed = "Filed as \(answer["id"] as? String ?? "?"). Replies appear below."
            subject = ""
            details = ""
            await refresh()
        } catch {
            failure = "\(error)"
        }
    }

    public func refresh() async {
        guard let telemetry else { return }
        do {
            reports = try await telemetry.reports()
        } catch {
            failure = "\(error)"
        }
    }
}

/// The window's content: the report form and this installation's reports.
@available(macOS 13, iOS 16, *)
public struct SupportReportView: View {
    @StateObject private var model: SupportReports
    private let productName: String

    public init(productName: String, telemetry: WisentTelemetry?) {
        self.productName = productName
        _model = StateObject(wrappedValue: SupportReports(telemetry: telemetry))
    }

    public var body: some View {
        Form {
            if model.telemetry == nil {
                Text("This build of \(productName) declares no product, so it cannot file a report.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Ask \(productName)'s support") {
                    TextField("Subject", text: $model.subject)
                    TextEditor(text: $model.details)
                        .frame(minHeight: 120)
                        .accessibilityLabel("What you were doing and what happened")
                    TextField("Email for the reply (optional)", text: $model.email)
                    Toggle("Attach the last failure \(productName) recorded", isOn: $model.withFailure)
                    Text("Sent with it: \(productName)'s version, this system's version and this installation's id. Without an email, the reply appears here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(model.sending ? "Sending…" : "Send report") { Task { await model.send() } }
                        .disabled(model.sending || model.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let filed = model.filed { Text(filed).font(.callout) }
                    if let failure = model.failure {
                        Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Section("Your reports") {
                    if model.reports.isEmpty {
                        Text("No report filed from this installation yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.reports.enumerated()), id: \.offset) { _, report in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(report["id"] as? String ?? "?") · \(report["subject"] as? String ?? "")").bold()
                            if let unread = report["unread"] as? String {
                                Text(unread).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                            } else {
                                Text("Status: \(report["status"] as? String ?? "unknown")").font(.callout)
                                ForEach(Array(((report["replies"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, reply in
                                    Text(reply["text"] as? String ?? "").textSelection(.enabled)
                                }
                            }
                        }
                    }
                    Button("Refresh") { Task { await model.refresh() } }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
    }
}

#if os(macOS)
/// The Report a Problem window an app adds beside its other scenes.
@available(macOS 13, *)
public struct WisentSupportWindow: Scene {
    public static let id = "wisent-support"
    private let productName: String
    private let telemetry: WisentTelemetry?

    public init(productName: String, telemetry: WisentTelemetry?) {
        self.productName = productName
        self.telemetry = telemetry
    }

    public var body: some Scene {
        Window("Report a Problem", id: Self.id) {
            SupportReportView(productName: productName, telemetry: telemetry)
                .frame(minWidth: 520, minHeight: 560)
        }
    }
}

/// Help → Report a Problem…, opening `WisentSupportWindow`.
@available(macOS 13, *)
public struct WisentReportProblemCommand: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("Report a Problem…") { openWindow(id: WisentSupportWindow.id) }
    }
}
#endif
#endif
