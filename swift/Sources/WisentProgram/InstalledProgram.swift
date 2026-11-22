#if os(macOS)
import Darwin
import Foundation
import os
import WisentErrors

/// An installed Wisent command line program and one finite run of it, as a
/// desktop app that drives its product through the CLI runs it: the program
/// is the one the <name> release installer at
/// `stado://releases/<name>/<version>/<platform>/install.sh` places in
/// `~/.local/bin`, else a copy the retired `stado product install` left in
/// `~/.stado/bin`, and only when the fleet signed it (``FleetSignature``).
/// No environment variable and no `PATH` directory is looked in: either
/// lets any process of the user's account choose the program that is
/// handed the product's data, by a name alone.
///
/// A product declares it once (`InstalledProgram(name: "para", leading:
/// ["--json"])`) and says its four failures in its own words:
/// ``Failure/missing(searched:)``, ``Failure/unverified(path:reason:)``,
/// ``Failure/failedToStart(path:reason:)`` and
/// ``Failure/unfollowed(path:step:reason:)``. One run is `RunState`
/// (Run/RunState.swift and its extensions).
public struct InstalledProgram: Sendable {
    /// The program's file name in `~/.local/bin` and in `~/.stado/bin`.
    public let name: String
    /// The signing identifier the fleet signs the program as
    /// (`com.wisent.<name>`).
    public let identifier: String
    /// The arguments every run begins with (`--json`).
    public let leading: [String]
    /// The code requirement the file and the started process must meet:
    /// ``FleetSignature/requirement(identifier:team:)``.
    let requirement: String

    /// The fleet program `name`, signed as `com.wisent.<name>`.
    public init(name: String, leading: [String] = []) {
        self.init(name: name, identifier: "com.wisent.\(name)", leading: leading)
    }

    /// The fleet program `name`, signed as `identifier`.
    public init(name: String, identifier: String, leading: [String] = []) {
        self.init(name: name, identifier: identifier, team: FleetSignature.team, leading: leading)
    }

    /// A program another publisher signs (the Node.js runtime a product's
    /// CLI runs on): `name`, signed as `identifier` by the Apple developer
    /// team `team`.
    public init(name: String, identifier: String, team: String, leading: [String] = []) {
        self.init(name: name, identifier: identifier, leading: leading,
                  requirement: FleetSignature.requirement(identifier: identifier, team: team))
    }

    init(name: String, identifier: String, leading: [String], requirement: String) {
        precondition(
            !name.isEmpty && name != "." && name != ".." && !name.contains("/"),
            "a program's name is one file name, not a path: \(name)")
        self.name = name
        self.identifier = identifier
        self.leading = leading
        self.requirement = requirement
    }

    /// The prefixes of the app's own variables no run hands the program:
    /// the program's own (`PARA_` for para: where it keeps its state and
    /// keys), `XDG_` (where it looks for its configuration and data) and
    /// `DYLD_` (code the loader would put in it). Any process of the account
    /// can set these for the app (`launchctl setenv`), and so choose, for the
    /// signed program, where the product's data goes; what a run needs is
    /// set with `environment`.
    public var withheld: [String] {
        ["\(name.uppercased().replacingOccurrences(of: "-", with: "_"))_", "XDG_", "DYLD_"]
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
        /// The program at `path` (the file found, or the executable the
        /// kernel ran for the started process) is not one the fleet signed
        /// as ``InstalledProgram/identifier``: `reason` is Security's answer.
        /// A started process that is refused is killed before it is handed
        /// any input or resumed.
        case unverified(path: String, reason: String)
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
        func attach(_ run: RunState) -> Int {
            lock.withLock {
                self.run = run
                return early
            }
        }
    }

    /// The places looked in, in order: `~/.local/bin/<name>` and
    /// `~/.stado/bin/<name>` of `home`.
    public func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [home.appendingPathComponent(".local/bin/\(name)"), home.appendingPathComponent(".stado/bin/\(name)")]
    }

    /// The first executable among ``candidates(home:)``, when the fleet
    /// signed it; ``Failure/unverified(path:reason:)`` when it is not signed
    /// so (it is refused, never passed over for the next place), and
    /// ``Failure/missing(searched:)`` naming every place looked in when
    /// there is none.
    public func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let places = candidates(home: home)
        guard let found = places.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw Failure.missing(searched: places.map(\.path))
        }
        if case .failure(let refused) = FleetSignature.check(file: found, requirement: requirement) {
            throw Failure.unverified(path: refused.path, reason: refused.reason)
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
    /// is this app's, less every variable whose name begins with one of
    /// ``withheld`` or `withholding`, with `environment` set over it, each
    /// name holding no `=`. A runtime that obeys variables of its own
    /// (`NODE_OPTIONS=--require …`, `OPENSSL_CONF`) is run withholding each.
    ///
    /// The program is started suspended, and the process the kernel started
    /// must meet the requirement for ``identifier``
    /// (``FleetSignature/verify(process:identifier:team:)``), still be
    /// suspended and have run nothing, before it runs one instruction or is
    /// handed its input: whatever path `executable`
    /// names, and whatever replaced that file since it was found, a process
    /// that is not the signed program is killed and the run is
    /// ``Failure/unverified(path:reason:)`` naming the executable the kernel
    /// ran. The admitted process is recorded to the unified log (subsystem
    /// `com.wisent.WisentProgram`, category `admission`): its path, pid and
    /// the requirement it met.
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
        withholding: [String] = [],
        stop: Stop = Stop(),
        onOutput: @escaping @Sendable (Stream, String) -> Void = { _, _ in }
    ) async throws -> Outcome {
        let withholding = withheld + withholding
        let inherited = ProcessInfo.processInfo.environment.filter { variable in
            !withholding.contains { variable.key.hasPrefix($0) }
        }
        let run = RunState(
            path: executable.path, arguments: leading + arguments, input: input,
            environment: inherited.merging(environment) { _, given in given }, requirement: requirement,
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
#endif
