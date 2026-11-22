// `telemetry settings`: the telemetry section every Wisent app puts in its
// Settings (`TelemetrySettingsView` of WisentTelemetryUI), opened in a window
// of its own for the product the command line names, so a product without an
// app of its own, or an operator at its terminal, answers the same question
// the app asks. The choice made in it is the file the command line reads.
// The command prints one line once the window is shown, and ends, exiting 0,
// when the window is closed. A process outside a logged-in macOS session has
// no window server to show it, and is refused saying so.

#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI
import WisentErrors
import WisentTelemetryUI

enum SettingsWindow {
    @MainActor
    static func open(_ telemetry: WisentTelemetry) throws -> Int32 {
        let product = telemetry.product
        guard CGSessionCopyCurrentDictionary() != nil else {
            throw OwnFailures.swiftCliSettingsWindow.refusal(OwnFailures.swiftCliSettingsWindowWindowSessionAbsent, [
                "product": product.id, "user": NSUserName(), "app": product.appID,
            ])
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let title = "\(product.id) telemetry"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TelemetrySettingsView(productName: product.id, telemetry: telemetry))
        let closing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            // The window closed: the run loop ends, and with it the command.
            application.stop(nil)
            if let wake = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: 0, data1: 0, data2: 0)
            {
                application.postEvent(wake, atStart: true)
            }
        }
        defer { NotificationCenter.default.removeObserver(closing) }
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        say("the telemetry settings of \(product.id) are open in the window \"\(title)\"; closing it ends this command\n")
        application.run()
        return EXIT_SUCCESS
    }
}
#endif
