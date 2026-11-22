// `wisent-errors-swift telemetry settings`, the package's command line
// opening the telemetry section every Wisent app shows in its Settings
// (`TelemetrySettingsView` of WisentTelemetryUI) in a window of its own,
// run as a process and driven the way a person drives it: through the
// window server, by the macOS Accessibility API. The window shows the
// question unanswered; "Send failures" pressed in it is the answer the
// command line reads back from consent.json; closing the window ends the
// command. A process outside a logged-in macOS session is refused a window.
//
//   swift test --filter SettingsWindowTests
//
// Rule 4: the case runs the built wisent-errors-swift (CommandCase.swift),
// which opens a real AppKit window holding the real SwiftUI section; the
// case presses its radio button and its close button through
// AXUIElementPerformAction, as VoiceOver or a person's click does. Nothing
// of the section's model is made or called in this process. This needs what
// the flow needs, and a host without it fails the case as blocked, never
// passed: a logged-in macOS session (a gate run over SSH has none), and the
// Accessibility permission for the process running the tests (System
// Settings → Privacy & Security → Accessibility). A host outside a session
// is where the refusal is provoked, and the case asserts it there before
// failing as blocked for the window it cannot show.
// Rule 5: each step asserts the command's exit status and both streams
// whole, and reads state back: the radio button selected as the window
// shows it, consent.json on disk after the window closed, and what
// `telemetry status` reads from it.
// Rule 8: the command's environment is cleared and given only HOME,
// CFFIXED_USER_HOME, TMPDIR and XDG_* inside the case's directory under
// .build, and WISENT_TELEMETRY_HOME, the product's own variable naming the
// directory its consent is kept in, inside the case's own: the only backend
// telemetry has; nothing of the operator's is read or written.

#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation
import XCTest

final class SettingsWindowTests: TelemetryCase {
    /// `attribute` of `element`, as Accessibility answers it.
    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    /// Every element under `element`, depth first.
    private func descendants(_ element: AXUIElement) -> [AXUIElement] {
        // fallback: an element with no children has none to search.
        let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return children + children.flatMap(descendants)
    }

    /// The radio button titled `title` in `window`.
    private func radio(_ title: String, in window: AXUIElement) throws -> AXUIElement {
        try XCTUnwrap(
            descendants(window).first { element in
                value(element, kAXRoleAttribute) as? String == kAXRadioButtonRole && value(element, kAXTitleAttribute) as? String == title
            },
            "the window shows the choice \"\(title)\"")
    }

    /// The element `attribute` of `element` names, when it names one.
    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let found = value(element, attribute), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(found, to: AXUIElement.self)
    }

    private func press(_ element: AXUIElement, _ what: String) {
        XCTAssertEqual(AXUIElementPerformAction(element, kAXPressAction as CFString), .success, "pressing \(what)")
    }

    func test_telemetry_settings_opens_the_section_the_app_shows_and_keeps_the_choice_made_in_it() throws {
        let settings = ["telemetry", "settings"] + product()

        XCTAssertEqual(try run(["telemetry", "settings", "--app", "wisent-errors-test-desktop"], environment: telemetry()), usage(
            "option-required",
            "reading the options of `wisent-errors-swift telemetry settings`: it needs --product, and --product was not given; observed: options given: --app",
            fix: "add --product, as in `--product ster`"))

        guard CGSessionCopyCurrentDictionary() != nil else {
            // This process, and the command it starts, run outside a logged-in session.
            XCTAssertEqual(try run(settings, environment: telemetry()), Ran(status: 1, stdout: "", stderr: refusal(
                "wisent_errors.swift_cli.settings_window", "window-session-absent", page: "swift-cli",
                "opening the telemetry settings window of wisent-errors-test: this process runs outside a logged-in macOS session, so the window server shows it no window; observed: the window server knows no session of user \(NSUserName()) for this process",
                fix: "run it from a terminal inside the logged-in session of \(NSUserName()), or set the level from here with `wisent-errors-swift telemetry set <off|errors|usage> --product wisent-errors-test --app wisent-errors-test-desktop`")))
            XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "a refused window kept nothing")
            throw Blocked(description: "blocked, not passed: the window part needs a logged-in macOS session; run the tests from a terminal inside one")
        }
        guard AXIsProcessTrusted() else {
            throw Blocked(description: "blocked, not passed: driving the window needs the Accessibility permission for the process running the tests (System Settings → Privacy & Security → Accessibility)")
        }

        let window = try start(settings, environment: telemetry())
        XCTAssertEqual(
            window.line(),
            "the telemetry settings of wisent-errors-test are open in the window \"wisent-errors-test telemetry\"; closing it ends this command")
        let app = AXUIElementCreateApplication(window.process.processIdentifier)
        let shown = try XCTUnwrap((value(app, kAXWindowsAttribute) as? [AXUIElement])?.first, "the command shows a window")
        XCTAssertEqual(value(shown, kAXTitleAttribute) as? String, "wisent-errors-test telemetry")

        // Unanswered: the window says so, and nothing is kept yet.
        XCTAssertEqual((value(try radio("Not answered yet: nothing is sent", in: shown), kAXValueAttribute) as? NSNumber)?.intValue, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: consent.path))

        // "Send failures", pressed; then the window closed, which ends the command.
        let failures = try radio("Send failures", in: shown)
        press(failures, "Send failures")
        press(try XCTUnwrap(element(shown, kAXCloseButtonAttribute), "the window has a close button"), "the close button")
        XCTAssertEqual(window.finish(), Ran(
            status: 0, stdout: "the telemetry settings of wisent-errors-test are open in the window \"wisent-errors-test telemetry\"; closing it ends this command\n",
            stderr: ""))

        // The choice is the file the command line reads.
        XCTAssertEqual(try object(consent)["level"] as? String, "errors")
        let status = try run(["telemetry", "status"] + product("wisent-errors-test-cli"), environment: telemetry())
        XCTAssertEqual((try printed(status) as? [String: Any])?["level"] as? String, "errors", status.stdout)
    }
}
#endif
