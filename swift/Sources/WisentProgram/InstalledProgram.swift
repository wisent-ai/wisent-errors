#if os(macOS)
import Darwin
import Foundation
import WisentErrors

/// An installed Wisent command line program and one finite run of it, as a
/// desktop app that drives its product through the CLI runs it: the program
/// is the one the product's variable names, else the first on `PATH`, else
/// the one the <name> release installer at
/// `stado://releases/<name>/<version>/<platform>/install.sh` places in
/// `~/.local/bin`, else a copy the retired `stado product install` left in
/// `~/.stado/bin`. An app opened from Finder or the Dock runs with launchd's
/// `PATH`, which holds neither directory, so both are looked in by name.
///
/// A product declares it once (`InstalledProgram(name: "para", variable:
/// "PARA", leading: ["--json"])`) and says its three failures in its own
/// words: ``Failure/missing(searched:)``,
/// ``Failure/failedToStart(path:reason:)`` and
/// ``Failure/unfollowed(path:step:reason:)``.
public struct InstalledProgram: Sendable {
    /// The program's file name, on `PATH`, in `~/.local/bin` and in
    /// `~/.stado/bin`.
    public let name: String
    /// The environment variable naming the program itself.
    public let variable: String
    /// The arguments every run begins with (`--json`).
    public let leading: [String]

    public init(name: String, variable: String, leading: [String] = []) {
        self.name = name
        self.variable = variable
        self.leading = leading
    }

    public struct Outcome: Sendable, Equatable {
        /// The exit status, or the signal number when a signal ended it.
        public let status: Int32
        /// Whether a signal ended the run.
        public let signalled: Bool
        public let stdout: String
        public let stderr: String
        /// The streams a process the program started (left running in its
        /// process group) still held open when the program exited. The run
        /// ends on the program's exit with everything the streams held then
        /// and stops reading them, so what such a process writes afterwards
        /// is not in ``stdout`` or ``stderr`` (its write meets a closed pipe:
        /// SIGPIPE, or EPIPE where it ignores that signal); this says so
        /// instead of dropping it unsaid.
        public let heldOpen: Set<Stream>
        /// Whether the program was handed all of the run's `input`: false
        /// when it closed its standard input before every byte was written
        /// to it (the write met EPIPE) or exited with some still unwritten,
        /// so its answer may cover only part of the input. Bytes written that
        /// the program left unread in the pipe when it exited are not told
        /// apart. True for a run given no input.
        public let inputDelivered: Bool

        public init(
            status: Int32, signalled: Bool, stdout: String, stderr: String, heldOpen: Set<Stream> = [],
            inputDelivered: Bool = true
        ) {
            self.status = status
            self.signalled = signalled
            self.stdout = stdout
            self.stderr = stderr
            self.heldOpen = heldOpen
            self.inputDelivered = inputDelivered
        }
    }

    public enum Stream: Sendable, Hashable { case stdout, stderr }

    /// Why the program could not be run, or its run not followed to its end.
    public enum Failure: Error, Equatable {
        /// No executable program in any place looked in, in the order looked.
        case missing(searched: [String])
        /// The program was found and could not be started.
        case failedToStart(path: String, reason: String)
        /// The program started, and `step` — waiting for its exit, reaping
        /// it, reading its output, writing its input or signalling its
        /// process group — failed for `reason`, so its end cannot be told.
        /// `waitid` failing with "No child processes" means something else in
        /// this app reaped it (its SIGCHLD set to SIG_IGN, or a
        /// `waitpid(-1)`): stop that, then run it again.
        case unfollowed(path: String, step: String, reason: String)
    }

    /// Requests to end one run, besides cancelling the task that awaits it.
    /// The first request — this or that cancellation — sends the program's
    /// whole process group SIGTERM; each later one sends it SIGKILL, so a
    /// program that does not end on SIGTERM ends when asked again, never
    /// after a guessed wait. A request before the run started refuses it
    /// with `CancellationError`; one after it ended does nothing. One `Stop`
    /// serves one run.
    public final class Stop: @unchecked Sendable {
        private let lock = NSLock()
        private var run: RunState?
        private var early = 0

        public init() {}

        public func request() {
            let attached = lock.withLock { () -> RunState? in
                if run == nil { early += 1 }
                return run
            }
            attached?.stop()
        }

        /// Hand every later request to `run`, and say how many came before.
        fileprivate func attach(_ run: RunState) -> Int {
            lock.withLock {
                self.run = run
                return early
            }
        }
    }

    /// The places looked in, in order: the path `variable` names, when set
    /// and not empty; `name` in every `PATH` directory; then
    /// `~/.local/bin/<name>` and `~/.stado/bin/<name>` of `home`.
    public func candidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var found: [URL] = []
        if let named = environment[variable], !named.isEmpty {
            found.append(URL(fileURLWithPath: named))
        }
        if let path = environment["PATH"] {
            found += path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(name)
            }
        }
        found.append(home.appendingPathComponent(".local/bin/\(name)"))
        found.append(home.appendingPathComponent(".stado/bin/\(name)"))
        return found
    }

    /// The first executable among ``candidates(environment:home:)``;
    /// ``Failure/missing(searched:)`` naming every place looked in when there
    /// is none.
    public func executable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        let places = candidates(environment: environment, home: home)
        guard let found = places.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw Failure.missing(searched: places.map(\.path))
        }
        return found
    }

    /// Run `executable` with ``leading`` and `arguments` to its exit, handing
    /// each chunk it writes to `onOutput` with the stream it came from, in
    /// arrival order; a character whose UTF-8 bytes two reads split is
    /// handed on whole with the read that completes it.
    ///
    /// Its standard input is `input`, then its end, or empty (`/dev/null`)
    /// when there is none. The input is written while both output streams
    /// are read, so a program that answers before it reads all of its input
    /// cannot hold the run on a full pipe; one that closes its input or exits
    /// before reading it all is ``Outcome/inputDelivered`` false, never a
    /// signal to this app (the write end raises no SIGPIPE). Its environment
    /// is this app's with `environment` set over it, each name holding no
    /// `=`.
    ///
    /// The program runs in a process group of its own, so a stop reaches
    /// every process it started. Cancelling the calling task is the first
    /// request to stop (``Stop``): the group is sent SIGTERM; a later
    /// ``Stop/request()`` sends it SIGKILL. The run ends on the program's
    /// exit, with everything its streams held then: a process it left
    /// running that still holds a stream does not hold the run, and
    /// ``Outcome/heldOpen`` names that stream. A program that cannot start
    /// is ``Failure/failedToStart(path:reason:)``; one stopped before it
    /// started is `CancellationError`; one whose end cannot be told is
    /// ``Failure/unfollowed(path:step:reason:)``.
    public func run(
        _ arguments: [String],
        executable: URL,
        input: Data? = nil,
        environment: [String: String] = [:],
        stop: Stop = Stop(),
        onOutput: @escaping @Sendable (Stream, String) -> Void = { _, _ in }
    ) async throws -> Outcome {
        let run = RunState(
            path: executable.path, arguments: leading + arguments, input: input, environment: environment,
            onOutput: onOutput)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.begin(continuation, stop: stop)
            }
        } onCancel: {
            run.stop()
        }
    }
}

/// A system call that failed, by its name and its error number.
private struct SystemCallFailed: LocalizedError {
    let call: String
    let code: Int32

    var errorDescription: String? {
        "\(call) failed: \(String(cString: strerror(code))) (errno \(code))"
    }
}

/// An environment variable name no environment entry can hold: an empty
/// one, or one holding `=`, which ends an entry's name.
private struct UnnamedVariable: LocalizedError {
    let name: String

    var errorDescription: String? {
        "the environment variable name \"\(name)\" is empty or holds =, which ends a name in an environment entry"
    }
}

/// How a read of everything a stream holds now ended.
private enum Drained {
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
private final class RunState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "WisentProgram.InstalledProgram.run")
    private let path: String
    private let arguments: [String]
    /// The program's standard input, or none for `/dev/null`.
    private let input: Data?
    /// Set over this app's environment for the program.
    private let environment: [String: String]
    private let onOutput: @Sendable (InstalledProgram.Stream, String) -> Void
    private var continuation: CheckedContinuation<InstalledProgram.Outcome, Error>?
    /// The program's pid, which is its process group's id; none until it
    /// started and once it was reaped.
    private var group: pid_t?
    /// The requests to stop so far: the first sends SIGTERM, each later one
    /// SIGKILL.
    private var requests = 0
    private var sources: [InstalledProgram.Stream: DispatchSourceRead] = [:]
    private var descriptors: [InstalledProgram.Stream: Int32] = [:]
    /// The write end of the program's standard input while input is left to
    /// write, and the source saying when the pipe takes more.
    private var inputDescriptor: Int32?
    private var inputSource: DispatchSourceWrite?
    /// How many bytes of `input` were written.
    private var inputSent = 0
    /// False once a write of the input met EPIPE: the program closed its
    /// standard input before reading it all.
    private var inputAccepted = true
    private var stdout = ""
    private var stderr = ""
    private var split: [InstalledProgram.Stream: Data] = [:]

    init(
        path: String, arguments: [String], input: Data?, environment: [String: String],
        onOutput: @escaping @Sendable (InstalledProgram.Stream, String) -> Void
    ) {
        self.path = path
        self.arguments = arguments
        self.input = input
        self.environment = environment
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
    /// time, SIGKILL every later time.
    func stop() {
        queue.async { [self] in
            requests += 1
            guard continuation != nil, let group else { return }
            let signal = requests == 1 ? SIGTERM : SIGKILL
            if killpg(group, signal) == -1 {
                let code = errno
                unfollowed("killpg(\(group), \(String(cString: strsignal(signal))))", code)
            }
        }
    }

    private func start() throws {
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
        // set) and none blocked, whatever this app set; and no descriptor of
        // this app but the three it is handed.
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
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
        let variables = ProcessInfo.processInfo.environment.merging(environment) { _, given in given }
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
        if let feed, let input { write(input, to: feed.write) }
        Thread.detachNewThread { [self] in awaitExit(pid) }
    }

    /// A pipe for the program's standard input that no other program this
    /// app starts inherits, its write end not blocking and raising no
    /// SIGPIPE (`F_SETNOSIGPIPE`), so a program that closed its input makes
    /// the next write EPIPE, never a signal to this app.
    private static func inputPipe() throws -> (read: Int32, write: Int32) {
        var ends: [Int32] = [0, 0]
        guard Darwin.pipe(&ends) == 0 else { throw SystemCallFailed(call: "pipe", code: errno) }
        let (read, write) = (ends[0], ends[1])
        let flags = fcntl(write, F_GETFL)
        let set =
            fcntl(read, F_SETFD, FD_CLOEXEC) != -1 && fcntl(write, F_SETFD, FD_CLOEXEC) != -1
            && flags != -1 && fcntl(write, F_SETFL, flags | O_NONBLOCK) != -1
            && fcntl(write, F_SETNOSIGPIPE, 1) != -1
        guard set else {
            let code = errno
            Darwin.close(read)
            Darwin.close(write)
            throw SystemCallFailed(call: "fcntl", code: code)
        }
        return (read, write)
    }

    /// Write `input` to the program's standard input whenever the pipe takes
    /// more, while both output streams are read; an empty input is its end
    /// at once.
    private func write(_ input: Data, to descriptor: Int32) {
        guard !input.isEmpty else {
            Darwin.close(descriptor)
            return
        }
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [self] in writable(input) }
        source.setCancelHandler { Darwin.close(descriptor) }
        inputDescriptor = descriptor
        inputSource = source
        source.resume()
    }

    /// Write as much of the input as the pipe takes now. Once all of it is
    /// written, or the program closed its input (EPIPE), the pipe is closed,
    /// which is the input's end.
    private func writable(_ input: Data) {
        guard continuation != nil, let descriptor = inputDescriptor else { return }
        while inputSent < input.count {
            let sent = input.withUnsafeBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress.map { $0 + inputSent }, input.count - inputSent)
            }
            if sent > 0 {
                inputSent += sent
                continue
            }
            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN { return }
            if code == EPIPE {
                inputAccepted = false
                return endInput()
            }
            return unfollowed(SystemCallFailed(call: "write", code: code))
        }
        endInput()
    }

    /// Stop writing the input and close its pipe.
    private func endInput() {
        inputSource?.cancel()
        inputSource = nil
        inputDescriptor = nil
    }

    /// A pipe no other program this app starts inherits, its read end not
    /// blocking, so a read takes what is there and says when nothing is.
    private static func pipe() throws -> (read: Int32, write: Int32) {
        var ends: [Int32] = [0, 0]
        guard Darwin.pipe(&ends) == 0 else { throw SystemCallFailed(call: "pipe", code: errno) }
        let (read, write) = (ends[0], ends[1])
        let flags = fcntl(read, F_GETFL)
        let set =
            fcntl(read, F_SETFD, FD_CLOEXEC) != -1 && fcntl(write, F_SETFD, FD_CLOEXEC) != -1
            && flags != -1 && fcntl(read, F_SETFL, flags | O_NONBLOCK) != -1
        guard set else {
            let code = errno
            Darwin.close(read)
            Darwin.close(write)
            throw SystemCallFailed(call: "fcntl", code: code)
        }
        return (read, write)
    }

    /// `code`, which a posix_spawn call answers instead of setting errno, as
    /// the failure of `call` when it is not zero.
    private static func checked(_ call: String, _ code: Int32) throws {
        guard code == 0 else { throw SystemCallFailed(call: call, code: code) }
    }

    private func watch(_ stream: InstalledProgram.Stream, _ descriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [self] in readable(stream) }
        source.setCancelHandler { Darwin.close(descriptor) }
        descriptors[stream] = descriptor
        sources[stream] = source
        source.resume()
    }

    private func readable(_ stream: InstalledProgram.Stream) {
        guard continuation != nil else { return }
        switch drain(stream) {
        case .open: break
        case .closed: closed(stream)
        case .failed(let failed): unfollowed(failed)
        }
    }

    /// Read everything `stream` holds now and hand it on.
    private func drain(_ stream: InstalledProgram.Stream) -> Drained {
        guard let descriptor = descriptors[stream] else { return .closed }
        var buffer = [UInt8](repeating: 0, count: Int(PIPE_BUF))
        var read = Data()
        var ended: Drained
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                read.append(contentsOf: buffer[..<count])
                continue
            }
            if count == 0 {
                ended = .closed
                break
            }
            let code = errno
            if code == EINTR { continue }
            ended = code == EAGAIN ? .open : .failed(SystemCallFailed(call: "read", code: code))
            break
        }
        if !read.isEmpty { append(read, to: stream) }
        return ended
    }

    /// Every writer of `stream` closed it: what a read left split is said as
    /// it is, and it is no longer watched.
    private func closed(_ stream: InstalledProgram.Stream) {
        rest(stream)
        sources.removeValue(forKey: stream)?.cancel()
        descriptors.removeValue(forKey: stream)
    }

    /// Wait on a thread of its own until the program exits, without reaping
    /// it: until the queue reaps it, it keeps its process group's id from
    /// being given to another, so a stop sent before then reaches its group.
    private func awaitExit(_ pid: pid_t) {
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1 {
            let code = errno
            guard code == EINTR else {
                queue.async { [self] in unfollowed(SystemCallFailed(call: "waitid", code: code)) }
                return
            }
        }
        queue.async { [self] in exited(pid) }
    }

    /// The program exited: reap it, read what each stream holds, and end the
    /// run. A stream still open now is held by a process it started.
    private func exited(_ pid: pid_t) {
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
    private static func decoded(_ raw: Int32) -> (status: Int32, signalled: Bool) {
        let signal = raw & _WSTOPPED
        guard signal == 0 else { return (signal, true) }
        return (Int32(UInt8(truncatingIfNeeded: raw >> UInt8.bitWidth)), false)
    }

    private func unfollowed(_ failed: SystemCallFailed) {
        finish(.failure(InstalledProgram.Failure.unfollowed(path: path, step: failed.call, reason: failed.explained)))
    }

    private func unfollowed(_ call: String, _ code: Int32) {
        unfollowed(SystemCallFailed(call: call, code: code))
    }

    /// Resume the caller once, and stop watching both streams and writing
    /// the input.
    private func finish(_ result: Result<InstalledProgram.Outcome, Error>) {
        guard let waiting = continuation else { return }
        continuation = nil
        for source in sources.values { source.cancel() }
        sources = [:]
        descriptors = [:]
        endInput()
        waiting.resume(with: result)
    }

    /// Add a read from `stream` to its output and hand on the text it
    /// completes. Decoding each read on its own turned a character whose
    /// UTF-8 bytes the pipe delivered in two reads (`ó`, `ł`, `–`) into two
    /// U+FFFD, in the output and in the JSON a product parses from it; the
    /// bytes of a character still incomplete wait for the next read.
    private func append(_ data: Data, to stream: InstalledProgram.Stream) {
        var bytes = split[stream] ?? Data()
        bytes.append(data)
        let whole = Self.wholeCharacters(bytes)
        split[stream] = Data(bytes[whole...])
        say(String(decoding: bytes[..<whole], as: UTF8.self), on: stream)
    }

    /// At the end of a stream, the bytes of a character no read completed,
    /// decoded as they are (U+FFFD for what is not UTF-8) and handed on.
    private func rest(_ stream: InstalledProgram.Stream) {
        guard let bytes = split.removeValue(forKey: stream), !bytes.isEmpty else { return }
        say(String(decoding: bytes, as: UTF8.self), on: stream)
    }

    private func say(_ text: String, on stream: InstalledProgram.Stream) {
        guard !text.isEmpty else { return }
        switch stream {
        case .stdout: stdout += text
        case .stderr: stderr += text
        }
        onOutput(stream, text)
    }

    /// The index ending the longest prefix of `bytes` that holds no UTF-8
    /// sequence cut short: the lead byte of the last sequence, when fewer
    /// bytes follow it than it announces, else the end. Bytes that are not
    /// UTF-8 end nothing early; decoding says them as U+FFFD.
    private static func wholeCharacters(_ bytes: Data) -> Data.Index {
        var index = bytes.endIndex
        var following = 0
        while index > bytes.startIndex, following < 4 {
            index -= 1
            following += 1
            let byte = bytes[index]
            if byte & 0b1100_0000 == 0b1000_0000 { continue }
            let announced = byte >= 0b1111_0000 ? 4 : byte >= 0b1110_0000 ? 3 : byte >= 0b1100_0000 ? 2 : 1
            return announced > following ? index : bytes.endIndex
        }
        return bytes.endIndex
    }
}
#endif
