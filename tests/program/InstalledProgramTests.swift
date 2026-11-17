// Real tests of how a desktop app runs its product's installed CLI, once the
// process the kernel started is admitted: a run hands back both streams whole
// with the exit status, its input is the program's standard input and a
// program that closes it early is told apart, its environment is the app's
// that it inherits with what is set over it and a name holding = is refused,
// cancelling the caller stops the program's whole process group with SIGTERM
// and a second request with SIGKILL, a stop that arrives after the group
// exited keeps the run's outcome, a process the program left holding its
// output does not hold the run, and a run whose exit cannot be waited for is
// refused naming the wait. Where the program is found, and that a program
// the fleet did not sign is refused, is FleetSignatureTests.swift.
//
// The runs here are of /bin/sh, which Apple signs (`codesign -d -r- /bin/sh`:
// identifier "com.apple.sh" and anchor apple), so they are admitted under
// that requirement, given through the module's own initializer
// (`@testable`), and pass the same suspended-start check a fleet program does.
//
//   swift test --filter InstalledProgramTests

#if os(macOS)
import Foundation
@testable import WisentProgram
import XCTest

final class InstalledProgramTests: XCTestCase {
    private let program = InstalledProgram(
        name: "sh", identifier: "com.apple.sh", leading: ["-c"],
        requirement: #"identifier "com.apple.sh" and anchor apple"#)

    func testAVariableTheRunWithholdsDoesNotReachTheProgram() async throws {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["HOME"], "the test needs HOME set to withhold it")
        let outcome = try await program.run(
            [#"printf '%s' "${HOME:-withheld}""#], executable: URL(fileURLWithPath: "/bin/sh"),
            withholding: ["HOME"])
        XCTAssertEqual(outcome.stdout, "withheld")
    }

    func testTheProgramsOwnVariablesAndTheLoadersAreWithheldByDefault() {
        XCTAssertEqual(InstalledProgram(name: "trends-cli").withheld, ["TRENDS_CLI_", "XDG_", "DYLD_"])
    }

    func testARunHandsBackBothStreamsWholeAndItsStatus() async throws {
        let outcome = try await program.run(
            ["printf out; printf err >&2; exit 3"], executable: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(outcome, InstalledProgram.Outcome(status: 3, signalled: false, stdout: "out", stderr: "err"))
    }

    func testTheInputIsTheProgramsStandardInputThenItsEnd() async throws {
        let outcome = try await program.run(
            ["cat; printf done >&2"], executable: URL(fileURLWithPath: "/bin/sh"), input: Data("one\ntwo\n".utf8))
        XCTAssertEqual(
            outcome, InstalledProgram.Outcome(status: 0, signalled: false, stdout: "one\ntwo\n", stderr: "done"))
        XCTAssertTrue(outcome.inputDelivered)
    }

    func testAProgramThatClosesItsInputEarlyIsToldApartAndSignalsNothingHere() async throws {
        // More than the largest buffer a macOS pipe holds (BIG_PIPE_SIZE,
        // https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/pipe.h),
        // so some of it is still unwritten when the program closes its input.
        let input = Data(repeating: UInt8(ascii: "x"), count: 2 * 64 * 1024)
        let outcome = try await program.run(
            ["exec <&-; printf closed"], executable: URL(fileURLWithPath: "/bin/sh"), input: input)
        XCTAssertEqual(outcome.status, 0)
        XCTAssertEqual(outcome.stdout, "closed")
        XCTAssertFalse(outcome.inputDelivered)
    }

    func testTheEnvironmentIsSetOverTheAppsOwn() async throws {
        let home = try XCTUnwrap(ProcessInfo.processInfo.environment["HOME"], "the test needs HOME set to inherit it")
        let outcome = try await program.run(
            [#"printf '%s|%s' "$WISENT_PROGRAM_TEST" "$HOME""#], executable: URL(fileURLWithPath: "/bin/sh"),
            environment: ["WISENT_PROGRAM_TEST": "set"])
        XCTAssertEqual(outcome.stdout, "set|\(home)", "HOME is the app's own, inherited")
    }

    func testAnEnvironmentNameHoldingAnEqualsSignIsRefusedBeforeTheProgramStarts() async {
        let shell = URL(fileURLWithPath: "/bin/sh")
        do {
            let outcome = try await program.run(["echo ran"], executable: shell, environment: ["A=B": "x"])
            XCTFail("a name holding = was run: \(outcome)")
        } catch InstalledProgram.Failure.failedToStart(let path, let reason) {
            XCTAssertEqual(path, shell.path)
            XCTAssertTrue(reason.contains("\"A=B\" is empty or holds ="), reason)
        } catch {
            XCTFail("refused with \(error)")
        }
    }

    func testEachChunkIsHandedOnWithItsStreamAsItArrives() async throws {
        final class Chunks: @unchecked Sendable {
            private let lock = NSLock()
            private var held: [String] = []
            func add(_ text: String) { lock.withLock { held.append(text) } }
            var all: String { lock.withLock { held.joined() } }
        }
        let seen = Chunks()
        let outcome = try await program.run(["printf one; printf two >&2"], executable: URL(fileURLWithPath: "/bin/sh")) {
            stream, text in seen.add(stream == .stdout ? "out:\(text);" : "err:\(text);")
        }
        XCTAssertTrue(seen.all.contains("out:one;") && seen.all.contains("err:two;"), seen.all)
        XCTAssertEqual(outcome.stdout, "one")
    }

    /// `ł` (C5 82) written in two halves reaches the run in two reads; each
    /// read decoded on its own said it as two U+FFFD.
    func testACharacterTwoReadsSplitIsSaidWhole() async throws {
        let outcome = try await program.run(
            ["printf 'Rachuba \\305'; sleep 0.2; printf '\\202\\303\\263d'"], executable: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(outcome.stdout, "Rachuba łód")
    }

    func testCancellingTheCallerStopsTheProgram() async throws {
        let run = Task { try await program.run(["exec sleep 30"], executable: URL(fileURLWithPath: "/bin/sh")) }
        try await Task.sleep(nanoseconds: 200_000_000)
        run.cancel()
        let outcome = try await run.value
        XCTAssertTrue(outcome.signalled, "\(outcome)")
        XCTAssertEqual(outcome.status, SIGTERM)
    }

    /// The first line a run writes on stdout, handed to the test as it
    /// arrives, and answered by the `add` that completes it.
    private final class FirstLine: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        private var line: String?
        private var waiting: CheckedContinuation<String, Never>?

        @discardableResult
        func add(_ chunk: String) -> String? {
            let ready = lock.withLock { () -> (CheckedContinuation<String, Never>?, String)? in
                text += chunk
                guard line == nil, let end = text.firstIndex(of: "\n") else { return nil }
                let first = String(text[..<end])
                line = first
                let waiting = self.waiting
                self.waiting = nil
                return (waiting, first)
            }
            guard let ready else { return nil }
            ready.0?.resume(returning: ready.1)
            return ready.1
        }

        func next() async -> String {
            await withCheckedContinuation { (waiting: CheckedContinuation<String, Never>) in
                let ready = lock.withLock { () -> String? in
                    if let line { return line }
                    self.waiting = waiting
                    return nil
                }
                if let ready { waiting.resume(returning: ready) }
            }
        }
    }

    private let shell = URL(fileURLWithPath: "/bin/sh")

    /// The program starts `tail`, which never ends by itself, and waits for
    /// it, trapping SIGTERM only to wait again: it exits only once `tail`
    /// has, so the run ending at all is the evidence the stop reached `tail`
    /// too, which signalling the program alone never did.
    func testCancellingTheCallerStopsEveryProcessOfTheProgramsGroup() async throws {
        let first = FirstLine()
        let run = Task {
            try await program.run(
                ["tail -f /dev/null & trap 'wait; exit' TERM; echo $!; wait"], executable: shell
            ) { stream, text in
                if stream == .stdout { first.add(text) }
            }
        }
        let line = await first.next()
        let started = try XCTUnwrap(pid_t(line), "the pid of the process the program started: \(line)")
        run.cancel()
        let outcome = try await run.value
        XCTAssertFalse(outcome.signalled, "\(outcome)")
        XCTAssertEqual(outcome.heldOpen, [], "nothing the program started outlived it: \(outcome)")
        let alive = kill(started, 0)
        let code = errno
        XCTAssertEqual(alive, -1, "the process the program started is gone")
        XCTAssertEqual(code, ESRCH)
    }

    /// A program that ignores SIGTERM ends on the second request, with
    /// SIGKILL, and no wait is guessed between the two.
    func testASecondRequestKillsAProgramThatIgnoresTheFirst() async throws {
        let stop = InstalledProgram.Stop()
        let first = FirstLine()
        let run = Task {
            try await program.run(
                ["trap '' TERM; echo ready; exec tail -f /dev/null"], executable: shell, stop: stop
            ) { stream, text in
                if stream == .stdout { first.add(text) }
            }
        }
        let ready = await first.next()
        XCTAssertEqual(ready, "ready")
        stop.request()
        stop.request()
        let outcome = try await run.value
        XCTAssertTrue(outcome.signalled, "\(outcome)")
        XCTAssertEqual(outcome.status, SIGKILL)
    }

    func testAStopRequestedBeforeTheRunRefusesIt() async {
        let stop = InstalledProgram.Stop()
        stop.request()
        do {
            let outcome = try await program.run(["echo ran"], executable: shell, stop: stop)
            XCTFail("the run is refused, not \(outcome)")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// A stop that reaches the run after the program's whole group exited,
    /// but before its exit is reaped, keeps the run's outcome. The output
    /// callback runs on the run's queue, so while it holds that queue it
    /// requests a stop (queued behind it, ahead of the exit), ends the
    /// program with SIGTERM itself and waits, without reaping, until it has
    /// exited. The stop then signals a group whose only member is a zombie,
    /// which killpg on macOS skips, answering ESRCH, or EPERM in POSIX mode
    /// (XNU bsd/kern/kern_sig.c, killpg1), and the run ends with the
    /// program's own SIGTERM.
    func testAStopAfterTheGroupExitedKeepsTheRunsOutcome() async throws {
        let stop = InstalledProgram.Stop()
        let first = FirstLine()
        let outcome = try await program.run(
            ["echo $$; exec tail -f /dev/null"], executable: shell, stop: stop
        ) { stream, text in
            guard stream == .stdout, let line = first.add(text), let pid = pid_t(line) else { return }
            stop.request()
            XCTAssertEqual(kill(pid, SIGTERM), 0, String(cString: strerror(errno)))
            var info = siginfo_t()
            var waited: Int32
            repeat { waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) } while waited == -1 && errno == EINTR
            XCTAssertEqual(waited, 0, String(cString: strerror(errno)))
        }
        XCTAssertTrue(outcome.signalled, "\(outcome)")
        XCTAssertEqual(outcome.status, SIGTERM)
    }

    /// The program leaves `tail` running with both its streams: the run ends
    /// when the program exits, with what it wrote, and says both streams were
    /// still held, where it used to stand until `tail` ended.
    func testAProcessTheProgramLeftHoldingItsOutputDoesNotHoldTheRun() async throws {
        let outcome = try await program.run(["tail -f /dev/null & echo $!"], executable: shell)
        let left = try XCTUnwrap(pid_t(outcome.stdout.trimmingCharacters(in: .newlines)), outcome.stdout)
        defer { kill(left, SIGKILL) }
        XCTAssertEqual(outcome.status, 0)
        XCTAssertFalse(outcome.signalled)
        XCTAssertEqual(outcome.heldOpen, [.stdout, .stderr])
    }

    func testAProgramThatCannotStartIsRefusedNamingWhy() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            let outcome = try await program.run([], executable: missing)
            XCTFail("the run is refused, not \(outcome)")
        } catch {
            guard case .failedToStart(let path, let reason)? = error as? InstalledProgram.Failure else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(path, missing.path)
            XCTAssertTrue(reason.contains("posix_spawn failed: No such file or directory"), reason)
        }
    }

    /// With SIGCHLD ignored the system reaps every child itself, as in an app
    /// that sets it, so the program's exit cannot be waited for: the run is
    /// refused naming that wait, instead of standing forever.
    func testAProgramSomethingElseReapedIsRefusedNamingTheWait() async {
        let previous = signal(SIGCHLD, SIG_IGN)
        defer { signal(SIGCHLD, previous) }
        do {
            let outcome = try await program.run(["exit 0"], executable: shell)
            XCTFail("the run is refused, not \(outcome)")
        } catch {
            guard case .unfollowed(let path, let step, let reason)? = error as? InstalledProgram.Failure else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(path, shell.path)
            XCTAssertEqual(step, "waitid")
            XCTAssertTrue(reason.contains("No child processes"), reason)
        }
    }
}
#endif
