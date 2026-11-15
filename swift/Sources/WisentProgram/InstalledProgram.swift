#if os(macOS)
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
/// "PARA", leading: ["--json"])`) and says its two failures in its own words:
/// ``Failure/missing(searched:)`` and ``Failure/failedToStart(path:reason:)``.
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

        public init(status: Int32, signalled: Bool, stdout: String, stderr: String) {
            self.status = status
            self.signalled = signalled
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public enum Stream: Sendable { case stdout, stderr }

    /// Why the program could not be run.
    public enum Failure: Error, Equatable {
        /// No executable program in any place looked in, in the order looked.
        case missing(searched: [String])
        /// The program was found and could not be started.
        case failedToStart(path: String, reason: String)
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

    /// Run `executable` with ``leading`` and `arguments` to completion, its
    /// standard input empty, handing each chunk it writes to `onOutput` with
    /// the stream it came from, in arrival order. Cancelling the calling task
    /// stops the run: the program is sent SIGTERM, and the run ends with
    /// `signalled` set once it has exited and its pipes closed. A program that
    /// cannot start is ``Failure/failedToStart(path:reason:)``; one cancelled
    /// before it started is `CancellationError`.
    public func run(
        _ arguments: [String],
        executable: URL,
        onOutput: @escaping @Sendable (Stream, String) -> Void = { _, _ in }
    ) async throws -> Outcome {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = leading + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        let run = RunState(process: process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.attach(continuation)
                for (pipe, stream) in [(stdout, Stream.stdout), (stderr, .stderr)] {
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                            run.closed(stream)
                            return
                        }
                        let text = String(decoding: data, as: UTF8.self)
                        run.append(text, to: stream)
                        onOutput(stream, text)
                    }
                }
                process.terminationHandler = { finished in
                    run.exited(finished.terminationStatus, signalled: finished.terminationReason == .uncaughtSignal)
                }
                do {
                    try run.start()
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    run.fail(
                        error is CancellationError
                            ? error : Failure.failedToStart(path: executable.path, reason: error.explained))
                }
            }
        } onCancel: {
            run.stop()
        }
    }
}

/// Lock-guarded state of one run: its process, both streams' output, which
/// of them has closed, the exit status, and the once-only resume of the
/// caller.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var started = false
    private var stopped = false
    private var continuation: CheckedContinuation<InstalledProgram.Outcome, Error>?
    private var stdout = ""
    private var stderr = ""
    private var open: Set<InstalledProgram.Stream> = [.stdout, .stderr]
    private var status: (code: Int32, signalled: Bool)?

    init(process: Process) {
        self.process = process
    }

    func attach(_ continuation: CheckedContinuation<InstalledProgram.Outcome, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    /// Start the process; one stopped before it started is refused here,
    /// and one stopped while starting is sent SIGTERM as soon as it runs.
    func start() throws {
        if lock.withLock({ stopped }) {
            throw CancellationError()
        }
        try process.run()
        let stopNow = lock.withLock { () -> Bool in
            started = true
            return stopped
        }
        if stopNow { process.terminate() }
    }

    /// Send the running process SIGTERM; a process not yet started is
    /// stopped when it starts.
    func stop() {
        let running = lock.withLock { () -> Bool in
            stopped = true
            return started
        }
        if running { process.terminate() }
    }

    func append(_ text: String, to stream: InstalledProgram.Stream) {
        lock.withLock {
            switch stream {
            case .stdout: stdout += text
            case .stderr: stderr += text
            }
        }
    }

    func closed(_ stream: InstalledProgram.Stream) {
        finishIfDone { open.remove(stream) }
    }

    func exited(_ code: Int32, signalled: Bool) {
        finishIfDone { status = (code, signalled) }
    }

    func fail(_ error: Error) {
        let waiting = lock.withLock { () -> CheckedContinuation<InstalledProgram.Outcome, Error>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(throwing: error)
    }

    /// The run is over once the process exited and both pipes reached end of
    /// file, so nothing written just before exit is lost.
    private func finishIfDone(_ change: () -> Void) {
        let ready = lock.withLock {
            () -> (CheckedContinuation<InstalledProgram.Outcome, Error>, InstalledProgram.Outcome)? in
            change()
            guard open.isEmpty, let status, let waiting = continuation else { return nil }
            continuation = nil
            return (
                waiting,
                InstalledProgram.Outcome(
                    status: status.code, signalled: status.signalled, stdout: stdout, stderr: stderr)
            )
        }
        if let ready {
            ready.0.resume(returning: ready.1)
        }
    }
}
#endif
