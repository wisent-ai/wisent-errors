#if os(macOS)
import Darwin
import Foundation
import os
import WisentErrors

// One run of an InstalledProgram (InstalledProgram.swift): its state, its
// start and admission, and a request to stop it. Its input is written in
// RunState+Input.swift, its output read in RunState+Output.swift, and its
// exit followed in RunState+Exit.swift.

/// A system call that failed, by its name and its error number.
struct SystemCallFailed: LocalizedError {
    let call: String
    let code: Int32

    var errorDescription: String? {
        "\(call) failed: \(String(cString: strerror(code))) (errno \(code))"
    }
}

/// An environment variable name no environment entry can hold: an empty
/// one, or one holding `=`, which ends an entry's name.
struct UnnamedVariable: LocalizedError {
    let name: String

    var errorDescription: String? {
        "the environment variable name \"\(name)\" is empty or holds =, which ends a name in an environment entry"
    }
}

/// How a read of everything a stream holds now ended.
enum Drained {
    /// Nothing more is there yet, and a writer still holds the stream.
    case open
    /// Every writer closed it.
    case closed
    case failed(SystemCallFailed)
}

/// One run. Every event of it — its start, a read, a write of its input,
/// its exit, a request to stop — happens on one serial queue, in the order
/// it came, so its state needs no lock: the process group's id, every
/// stream's descriptor and output, the input written so far, the bytes of
/// a character a read split, and the once-only resume of the caller.
final class RunState: @unchecked Sendable {
    let queue = DispatchQueue(label: "WisentProgram.InstalledProgram.run")
    let path: String
    let arguments: [String]
    /// The program's standard input, or none for `/dev/null`.
    let input: Data?
    /// The program's whole environment: what it inherits, and what is set.
    let environment: [String: String]
    /// The code requirement the started process must meet before it runs.
    let requirement: String
    let onOutput: @Sendable (InstalledProgram.Stream, String) -> Void
    var continuation: CheckedContinuation<InstalledProgram.Outcome, Error>?
    /// The program's pid, which is its process group's id; none until it
    /// started and once it was reaped.
    var group: pid_t?
    /// The requests to stop so far: the first sends SIGTERM, each later one
    /// SIGKILL.
    var requests = 0
    var sources: [InstalledProgram.Stream: DispatchSourceRead] = [:]
    var descriptors: [InstalledProgram.Stream: Int32] = [:]
    /// The write end of the program's standard input while input is left to
    /// write, and the source saying when the pipe takes more.
    var inputDescriptor: Int32?
    var inputSource: DispatchSourceWrite?
    /// How many bytes of `input` were written.
    var inputSent = 0
    /// False once a write of the input met EPIPE: the program closed its
    /// standard input before reading it all.
    var inputAccepted = true
    var stdout = ""
    var stderr = ""
    var split: [InstalledProgram.Stream: Data] = [:]

    init(
        path: String, arguments: [String], input: Data?, environment: [String: String], requirement: String,
        onOutput: @escaping @Sendable (InstalledProgram.Stream, String) -> Void
    ) {
        self.path = path
        self.arguments = arguments
        self.input = input
        self.environment = environment
        self.requirement = requirement
        self.onOutput = onOutput
    }

    /// Start the run for `continuation`; a stop requested before it started
    /// refuses it with `CancellationError`.
    func begin(_ continuation: CheckedContinuation<InstalledProgram.Outcome, Error>, stop: InstalledProgram.Stop) {
        queue.async { [self] in
            self.continuation = continuation
            requests += stop.attach(self)
            guard requests == 0 else { return finish(.failure(CancellationError())) }
            do {
                try start()
            } catch {
                finish(.failure(InstalledProgram.Failure.failedToStart(path: path, reason: error.explained)))
            }
        }
    }

    /// One request to stop: SIGTERM to the program's process group the first
    /// time, SIGKILL every later time. killpg answers ESRCH, or EPERM where
    /// the caller runs in POSIX mode, when it signalled no member: macOS's
    /// killpg skips a zombie (killpg1's group filter `p->p_stat != SZOMB`:
    /// https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_sig.c),
    /// and a live member this app may not signal is not counted either. So
    /// such an answer is left to `exited` only when the program itself has
    /// exited, its exit waiting to be reaped (`exited` is queued or about to
    /// be, and ends the run with its outcome); while it still runs, the stop
    /// did not reach it and the run ends as unfollowed, naming the call.
    func stop() {
        queue.async { [self] in
            requests += 1
            guard continuation != nil, let group else { return }
            let signal = requests == 1 ? SIGTERM : SIGKILL
            if killpg(group, signal) == -1 {
                let code = errno
                if (code == ESRCH || code == EPERM) && Self.hasExited(group) { return }
                unfollowed("killpg(\(group), \(String(cString: strsignal(signal))))", code)
            }
        }
    }

    /// Whether `pid`, a child of this process, has exited and waits to be
    /// reaped: waitid without waiting or reaping it (WNOHANG | WNOWAIT)
    /// names it only then.
    static func hasExited(_ pid: pid_t) -> Bool {
        var info = siginfo_t()
        var waited: Int32
        repeat {
            waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
        } while waited == -1 && errno == EINTR
        return waited == 0 && info.si_pid == pid
    }

    func start() throws {
        if let unnamed = environment.keys.first(where: { $0.isEmpty || $0.contains("=") }) {
            throw UnnamedVariable(name: unnamed)
        }
        var ends: [(read: Int32, write: Int32)] = []
        var started = false
        // The write ends belong to the program once it holds its copies;
        // every end goes when it could not start. Closing a pipe's end this
        // process opened fails for nothing it can act on.
        defer {
            for end in ends {
                Darwin.close(end.write)
                if !started { Darwin.close(end.read) }
            }
        }
        for _ in [InstalledProgram.Stream.stdout, .stderr] { ends.append(try Self.pipe()) }
        // The program's standard input: `input` through a pipe whose write
        // end is this app's, or empty. Its read end belongs to the program
        // once it holds its copy; its write end goes when it could not start.
        let feed = try input.map { _ in try Self.inputPipe() }
        defer {
            if let feed {
                Darwin.close(feed.read)
                if !started { Darwin.close(feed.write) }
            }
        }

        var actions: posix_spawn_file_actions_t?
        try Self.checked("posix_spawn_file_actions_init", posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let feed {
            try Self.checked(
                "posix_spawn_file_actions_adddup2", posix_spawn_file_actions_adddup2(&actions, feed.read, STDIN_FILENO))
        } else {
            try Self.checked(
                "posix_spawn_file_actions_addopen",
                posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        }
        try Self.checked(
            "posix_spawn_file_actions_adddup2", posix_spawn_file_actions_adddup2(&actions, ends[0].write, STDOUT_FILENO))
        try Self.checked(
            "posix_spawn_file_actions_adddup2", posix_spawn_file_actions_adddup2(&actions, ends[1].write, STDERR_FILENO))

        var attributes: posix_spawnattr_t?
        try Self.checked("posix_spawnattr_init", posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        // A process group of its own (group 0: the program's own pid), so a
        // stop reaches every process it starts; every signal a process may
        // set at its default (all but SIGKILL and SIGSTOP, which none can
        // set) and none blocked, whatever this app set; no descriptor of
        // this app but the three it is handed; and suspended before its
        // first instruction, until the process is admitted (`admit`).
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
            | POSIX_SPAWN_START_SUSPENDED
        try Self.checked("posix_spawnattr_setflags", posix_spawnattr_setflags(&attributes, Int16(flags)))
        try Self.checked("posix_spawnattr_setpgroup", posix_spawnattr_setpgroup(&attributes, 0))
        var every = sigset_t()
        sigfillset(&every)
        sigdelset(&every, SIGKILL)
        sigdelset(&every, SIGSTOP)
        try Self.checked("posix_spawnattr_setsigdefault", posix_spawnattr_setsigdefault(&attributes, &every))
        var none = sigset_t()
        sigemptyset(&none)
        try Self.checked("posix_spawnattr_setsigmask", posix_spawnattr_setsigmask(&attributes, &none))

        let words = ([path] + arguments).map { strdup($0) }
        let variables = environment
            .map { strdup("\($0.key)=\($0.value)") }
        defer { (words + variables).forEach { free($0) } }
        guard !(words + variables).contains(where: { $0 == nil }) else {
            throw SystemCallFailed(call: "strdup", code: ENOMEM)
        }
        var pid: pid_t = 0
        try Self.checked("posix_spawn", posix_spawn(&pid, path, &actions, &attributes, words + [nil], variables + [nil]))
        started = true
        group = pid
        for (stream, end) in zip([InstalledProgram.Stream.stdout, .stderr], ends) {
            watch(stream, end.read)
        }
        guard admit(pid) else {
            // Killed while suspended: it ran nothing and is handed nothing.
            if let feed { Darwin.close(feed.write) }
            return
        }
        if let feed, let input { write(input, to: feed.write) }
        // Only once it runs: macOS answers a waitid for WEXITED alone with
        // the suspended child's stop (CLD_STOPPED), as if it had exited.
        Thread.detachNewThread { [self] in awaitExit(pid) }
    }

    /// Check the suspended process `pid` against `requirement`, then that it
    /// is still suspended and ran nothing (``FleetSignature/unrun(_:)``),
    /// and resume it, recording who was admitted. A process that is refused
    /// is killed with its whole group (SIGKILL reaches a suspended process),
    /// reaped, recorded, and the run ends as unverified; a resume that fails
    /// does the same and ends it as unfollowed, naming the call.
    func admit(_ pid: pid_t) -> Bool {
        let checked = FleetSignature.admission(process: pid, requirement: requirement).flatMap { admitted in
            FleetSignature.unrun(pid).map { admitted }
        }
        switch checked {
        case .success(let admitted):
            Self.admissions.notice(
                "admitted \(admitted.path, privacy: .public) pid \(admitted.pid) meeting \(admitted.requirement, privacy: .public)")
        case .failure(let refusal):
            killed(pid)
            Self.admissions.error(
                "refused \(refusal.path, privacy: .public) pid \(pid): \(refusal.reason, privacy: .public)")
            finish(.failure(InstalledProgram.Failure.unverified(path: refusal.path, reason: refusal.reason)))
            return false
        }
        guard Darwin.kill(pid, SIGCONT) == 0 else {
            let code = errno
            killed(pid)
            unfollowed("kill(\(pid), SIGCONT)", code)
            return false
        }
        return true
    }

    /// End the suspended process `pid`, with every process its group holds,
    /// and reap it, so no stop or later run meets it. The process itself is
    /// signalled as well as its group: one resumed early may have moved to
    /// another group (`setpgid`), which killpg would then not reach. A
    /// system that reaps children itself (SIGCHLD ignored) leaves waitpid
    /// nothing to reap, which ends it all the same.
    func killed(_ pid: pid_t) {
        Darwin.kill(pid, SIGKILL)
        Darwin.killpg(pid, SIGKILL)
        var raw: Int32 = 0
        while waitpid(pid, &raw, 0) == -1 && errno == EINTR {}
        group = nil
    }

    /// Where each admitted process is recorded.
    static let admissions = Logger(subsystem: "com.wisent.WisentProgram", category: "admission")
}
#endif
