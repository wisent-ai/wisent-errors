// A real test that a program which stops itself after it was admitted does
// not hold the run: macOS answers the run's wait for the program's exit with
// its stop (CLD_STOPPED), and a run that took that for the exit sat in
// waitpid on its queue, where no request to stop could reach it. The program
// stops itself and ignores SIGTERM; once it is seen stopped, two requests to
// stop must end it with SIGKILL.
//
//   swift test --filter StoppedProgramTests

#if os(macOS)
import Darwin
import Foundation
@testable import WisentProgram
import XCTest

final class StoppedProgramTests: XCTestCase {
    private let program = InstalledProgram(
        name: "sh", identifier: "com.apple.sh", leading: ["-c"],
        requirement: #"identifier "com.apple.sh" and anchor apple"#)

    /// The pid the program prints on its first line.
    private final class Pid: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        private var waiting: CheckedContinuation<pid_t, Never>?
        private var found: pid_t?

        func add(_ chunk: String) {
            let ready = lock.withLock { () -> (CheckedContinuation<pid_t, Never>, pid_t)? in
                text += chunk
                guard found == nil, let end = text.firstIndex(of: "\n"), let pid = pid_t(text[..<end]) else {
                    return nil
                }
                found = pid
                defer { waiting = nil }
                return waiting.map { ($0, pid) }
            }
            ready.map { $0.0.resume(returning: $0.1) }
        }

        func next() async -> pid_t {
            await withCheckedContinuation { (waiting: CheckedContinuation<pid_t, Never>) in
                let ready = lock.withLock { () -> pid_t? in
                    if let found { return found }
                    self.waiting = waiting
                    return nil
                }
                ready.map { waiting.resume(returning: $0) }
            }
        }
    }

    /// Whether `pid` is stopped, as the kernel's process table says.
    private func isStopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.pbi_status == UInt32(SSTOP)
    }

    func testAProgramThatStopsItselfIsStillStoppedOnRequest() async throws {
        let stop = InstalledProgram.Stop()
        let pid = Pid()
        let run = Task {
            try await program.run(
                ["trap '' TERM; echo $$; kill -STOP $$; exec tail -f /dev/null"],
                executable: URL(fileURLWithPath: "/bin/sh"), stop: stop,
                onOutput: { stream, text in if stream == .stdout { pid.add(text) } })
        }
        let stopped = await pid.next()
        while !isStopped(stopped) { await Task.yield() }
        stop.request()
        stop.request()
        let outcome = try await run.value
        XCTAssertTrue(outcome.signalled, "\(outcome)")
        XCTAssertEqual(outcome.status, SIGKILL)
    }
}
#endif
