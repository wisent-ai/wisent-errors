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
// Rule 4: every `run(...)` and `start(...)` below is CommandCase's
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195). That child opens a real
// AppKit window holding the real SwiftUI section, and the case drives the
// window the way a person does, through the window server: it finds the
// child's window, reads its radio buttons and presses "Send failures" and
// the close button with AXUIElementPerformAction, the Accessibility action
// a click and VoiceOver send to the same element. Accessibility is not a
// stand-in for the product, it is how a test with no person at the screen
// clicks the real window; the person is the one thing the case replaces,
// as every UI test does. Nothing of the section's model is made or called
// in this process. This needs what the flow needs, and a host without it
// fails the case as blocked, never passed: a logged-in macOS session (a gate
// run over SSH has none), and the Accessibility permission for the process
// running the tests (System Settings → Privacy & Security → Accessibility).
// A host outside a session is where the session refusal is provoked, and
// the case asserts it there before failing as blocked for the window it
// cannot show.
// Rule 5: each step asserts the command's exit status and both streams
// whole, and reads state back: nothing kept after a refusal, the radio
// button selected as the window shows it, consent.json on disk after the
// window closed, and what `telemetry status` reads from it.
// Rule 6: every refusal `telemetry settings` can say, each whole: each of
// its two required options left out, an option it does not have, an option
// given as the last argument without its value, an operand it does not
// take, and, outside a logged-in session, the window it cannot show. It
// reads no file before the window opens, so no refusal of the store is
// its: a consent the window cannot keep is said in the window, not by the
// command.
// Rule 8: the command's environment is cleared and given only HOME,
// CFFIXED_USER_HOME, TMPDIR and XDG_* inside the case's directory under
// .build, and WISENT_TELEMETRY_HOME, the product's own variable naming the
// directory its consent is kept in, inside the case's own: the only backend
// telemetry has; nothing of the operator's is read or written.
// Rule 9: every argument refusal below and the line the command prints once
// the window is shown were copied from live runs of wisent-errors-swift
// built from this tree (`swift build --product wisent-errors-swift`,
// 2026-11-21), run by hand inside a logged-in session under `env -i` given
// only HOME, CFFIXED_USER_HOME, TMPDIR, XDG_* and WISENT_TELEMETRY_HOME
// inside target/probe-swift/settings; the window opened, its line was read,
// and the command was ended with SIGTERM, keeping nothing. Unprobed: the
// presses through Accessibility and the exit 0 after closing (pressing from
// the probing shell would need the operator to grant it the Accessibility
// permission, which was not asked for), and the session refusal, which
// needs a process outside any logged-in session; its sentence is the
// cause's template in catalogue/failures/swift-cli.json with this user's
// name.

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

        // Its command line: each required option left out, an option it lacks, one without its value, an operand it does not take.
        XCTAssertEqual(try run(["telemetry", "settings", "--app", "wisent-errors-test-desktop"], environment: telemetry()), usage(
            "option-required",
            "reading the options of `wisent-errors-swift telemetry settings`: it needs --product, and --product was not given; observed: options given: --app",
            fix: "add --product, as in `--product ster`"))
        XCTAssertEqual(try run(["telemetry", "settings", "--product", "wisent-errors-test"], environment: telemetry()), usage(
            "option-required",
            "reading the options of `wisent-errors-swift telemetry settings`: it needs --app, and --app was not given; observed: options given: --product",
            fix: "add --app, as in `--app ster-desktop`"))
        XCTAssertEqual(try run(settings + ["--level", "errors"], environment: telemetry()), usage(
            "option-unknown",
            "reading the options of `wisent-errors-swift telemetry settings`: \"--level\" is not one of its options; observed: its options: --app, --app-version, --product",
            fix: "drop \"--level\", or give one of --app, --app-version, --product"))
        XCTAssertEqual(try run(["telemetry", "settings", "--app", "wisent-errors-test-desktop", "--product"], environment: telemetry()), usage(
            "option-value-absent",
            "reading the options of `wisent-errors-swift telemetry settings`: --product takes a value, and it is the last argument; observed: arguments: [\"--app\",\"wisent-errors-test-desktop\",\"--product\"]",
            fix: "give --product its value, as in `--product ster`"))
        XCTAssertEqual(try run(["telemetry", "settings", "errors"] + product(), environment: telemetry()), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift telemetry settings`: it takes no operand, and 1 were given; observed: operands: [\"errors\"]",
            fix: "run it as `wisent-errors-swift telemetry settings`"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "a refused command line kept nothing")

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
