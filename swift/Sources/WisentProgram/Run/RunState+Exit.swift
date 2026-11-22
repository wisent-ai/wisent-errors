#if os(macOS)
import Darwin
import Foundation
import WisentErrors

/// Following a run's program to its exit, and ending the run once.
extension RunState {
    /// Wait on a thread of its own until the program exits, without reaping
    /// it: until the queue reaps it, it keeps its process group's id from
    /// being given to another, so a stop sent before then signals only that
    /// group's members still alive, or finds none (see `stop`). macOS answers
    /// this wait with a stop of the program too (`CLD_STOPPED`, or
    /// `CLD_TRAPPED` under a debugger), as if it had exited: that report is
    /// taken (a wait for `WSTOPPED` without `WNOWAIT`, so it is not answered
    /// again) and the wait goes on until the program exits, is killed or
    /// dumps core.
    func awaitExit(_ pid: pid_t) {
        var info = siginfo_t()
        while true {
            guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == 0 else {
                let code = errno
                if code == EINTR { continue }
                queue.async { [self] in unfollowed(SystemCallFailed(call: "waitid", code: code)) }
                return
            }
            if [CLD_EXITED, CLD_KILLED, CLD_DUMPED].contains(info.si_code) { break }
            var stopped = siginfo_t()
            while waitid(P_PID, id_t(pid), &stopped, WSTOPPED | WNOHANG) == -1 && errno == EINTR {}
        }
        queue.async { [self] in exited(pid) }
    }

    /// The program exited: reap it, read what each stream holds, and end the
    /// run. A stream still open now is held by a process it started.
    func exited(_ pid: pid_t) {
        var raw: Int32 = 0
        var reaped: pid_t
        repeat { reaped = waitpid(pid, &raw, 0) } while reaped == -1 && errno == EINTR
        guard continuation != nil else { return }
        guard reaped == pid else { return unfollowed(SystemCallFailed(call: "waitpid", code: errno)) }
        group = nil
        var held: Set<InstalledProgram.Stream> = []
        for stream in [InstalledProgram.Stream.stdout, .stderr] where descriptors[stream] != nil {
            switch drain(stream) {
            case .closed: closed(stream)
            case .open:
                held.insert(stream)
                rest(stream)
            case .failed(let failed): return unfollowed(failed)
            }
        }
        let (status, signalled) = Self.decoded(raw)
        // The input reached the program when every byte was written and no
        // write met a closed input; a run given none is delivered.
        let delivered: Bool
        switch input {
        case .some(let given): delivered = inputAccepted && inputSent == given.count
        case .none: delivered = true
        }
        endInput()
        finish(.success(InstalledProgram.Outcome(
            status: status, signalled: signalled, stdout: stdout, stderr: stderr, heldOpen: held,
            inputDelivered: delivered)))
    }

    /// The exit status, or the number of the signal that ended it, as
    /// `<sys/wait.h>` packs them: the bits under `_WSTOPPED` (`_WSTATUS`) are
    /// zero for an exit and the signal's number otherwise, and the exit
    /// status is the byte above them (`WEXITSTATUS`). No run is traced or
    /// stopped, so no status is a stop.
    static func decoded(_ raw: Int32) -> (status: Int32, signalled: Bool) {
        let signal = raw & _WSTOPPED
        guard signal == 0 else { return (signal, true) }
        return (Int32(UInt8(truncatingIfNeeded: raw >> UInt8.bitWidth)), false)
    }

    func unfollowed(_ failed: SystemCallFailed) {
        finish(.failure(InstalledProgram.Failure.unfollowed(path: path, step: failed.call, reason: failed.explained)))
    }

    func unfollowed(_ call: String, _ code: Int32) {
        unfollowed(SystemCallFailed(call: call, code: code))
    }

    /// Resume the caller once, and stop watching both streams and writing
    /// the input.
    func finish(_ result: Result<InstalledProgram.Outcome, Error>) {
        guard let waiting = continuation else { return }
        continuation = nil
        for source in sources.values { source.cancel() }
        sources = [:]
        descriptors = [:]
        endInput()
        waiting.resume(with: result)
    }
}
#endif
