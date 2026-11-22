// What every Swift case shares: wisent-errors-swift, the package's own
// command line (swift/Sources/wisent-errors-swift), run as a process from the
// products directory beside the test bundle, where `swift test` builds it
// because the test target depends on it; a directory of the case's own under
// the checkout's .build, removed when the case ends; and an environment
// cleared of everything but what the case gives it. The child gets only
// HOME (and CFFIXED_USER_HOME, which Foundation reads for the home on macOS),
// TMPDIR and XDG_CONFIG_HOME/XDG_STATE_HOME/XDG_DATA_HOME/XDG_CACHE_HOME, each
// a directory inside the case's own, plus the product's own variables a case
// adds (WISENT_TELEMETRY_HOME, WISENT_TELEMETRY_COLLECTOR_URL,
// WISENT_SUPPORT_URL, DO_NOT_TRACK): those are the only backends the command
// line has, so nothing of the operator's home, state or configuration is read
// or written.
//
// A refusal is compared as the three lines the command prints on stderr --
// `Error: <sentence>`, `fix: <remedy>`, `cause: <operation>.<cause>; <page>#<anchor>`
// -- each sentence copied from a live run of the command built from this
// tree, with the values the case observes in it. What the operating system,
// Foundation or a transport answered is pinned as that run printed it: the
// child's environment carries no language, so those words are English on
// every host.

#if os(macOS)
import Darwin
import Foundation
import XCTest

/// A case that needs a real component the environment does not name: it
/// fails naming the variable or the host's missing capability, never passes.
struct Blocked: Error, CustomStringConvertible {
    let description: String
}

/// One finished run of the command: its exit status, or the signal that
/// ended it, and both streams whole.
struct Ran: Equatable, CustomStringConvertible {
    let status: Int32
    let stdout: String
    let stderr: String
    var signalled = false

    var description: String {
        "\(signalled ? "signal" : "exit") \(status)\n--- stdout\n\(stdout)--- stderr\n\(stderr)--- end"
    }
}

/// What the command's standard input is.
enum Input {
    /// /dev/null.
    case none
    /// These bytes, then its end.
    case bytes(Data)
    /// The file or directory at this path, opened for reading.
    case file(URL)
}

/// A run of the command still going: its stdout read line by line as it
/// arrives, signalled, then finished.
final class Running: @unchecked Sendable {
    let process: Process
    private let condition = NSCondition()
    private var out = Data()
    private var err = Data()
    private var open = 2
    private var handed = 0

    init(_ process: Process, stdout: Pipe, stderr: Pipe) {
        self.process = process
        read(stdout.fileHandleForReading) { [self] in out.append($0) }
        read(stderr.fileHandleForReading) { [self] in err.append($0) }
    }

    private func read(_ handle: FileHandle, into append: @escaping (Data) -> Void) {
        Thread.detachNewThread { [self] in
            while true {
                let chunk = handle.availableData
                condition.lock()
                if chunk.isEmpty { open -= 1 } else { append(chunk) }
                condition.broadcast()
                condition.unlock()
                if chunk.isEmpty { return }
            }
        }
    }

    /// The next line the command writes on stdout, without its newline; nil
    /// when its stdout ends first.
    func line() -> String? {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let end = out[handed...].firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: out[handed..<end], as: UTF8.self)
                handed = end + 1
                return line
            }
            if open == 0 { return nil }
            condition.wait()
        }
    }

    /// Send `number` to the command.
    func signal(_ number: Int32) {
        XCTAssertEqual(kill(process.processIdentifier, number), 0, String(cString: strerror(errno)))
    }

    /// Wait for the command's exit and both streams' end.
    func finish() -> Ran {
        process.waitUntilExit()
        condition.lock()
        while open > 0 { condition.wait() }
        let (stdout, stderr) = (out, err)
        condition.unlock()
        return Ran(
            status: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self), signalled: process.terminationReason == .uncaughtSignal)
    }
}

class CommandCase: XCTestCase {
    /// The checkout: tests/swift-cli/<this file> is two levels below it.
    static let checkout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The package's build directory, where every case keeps its directory.
    static let build = checkout.appendingPathComponent(".build")

    /// wisent-errors-swift as `swift test` built it, in the products
    /// directory that holds the test bundle.
    static var executable: URL {
        Bundle(for: CommandCase.self).bundleURL.deletingLastPathComponent().appendingPathComponent("wisent-errors-swift")
    }

    /// The case's own directory under .build, removed when the case ends.
    private(set) var root: URL!
    var home: URL { root.appendingPathComponent("home") }
    var tmp: URL { root.appendingPathComponent("tmp") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = Self.build.appendingPathComponent("cases").appendingPathComponent(UUID().uuidString)
        for directory in ["home", "tmp", "config", "state", "data", "cache"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        let built = Self.executable.path
        guard FileManager.default.isExecutableFile(atPath: built) else {
            throw Blocked(description: "\(built) is not there: `swift test` builds wisent-errors-swift beside the test bundle; run the cases with it")
        }
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// The environment every run starts from: the case's own home, temporary
    /// directory and XDG directories, and nothing else.
    var environment: [String: String] {
        [
            "HOME": home.path, "CFFIXED_USER_HOME": home.path, "TMPDIR": tmp.path + "/",
            "XDG_CONFIG_HOME": root.appendingPathComponent("config").path,
            "XDG_STATE_HOME": root.appendingPathComponent("state").path,
            "XDG_DATA_HOME": root.appendingPathComponent("data").path,
            "XDG_CACHE_HOME": root.appendingPathComponent("cache").path,
        ]
    }

    /// Start `wisent-errors-swift <arguments>` in `directory` with exactly `environment`.
    func start(
        _ arguments: [String], environment: [String: String]? = nil, input: Input = .none, in directory: URL? = nil
    ) throws -> Running {
        let process = Process()
        process.executableURL = Self.executable
        process.arguments = arguments
        // fallback: a run given no environment of its own gets the case's.
        process.environment = environment ?? self.environment
        // fallback: a run given no directory runs in the case's own.
        process.currentDirectoryURL = directory ?? root
        let (stdout, stderr) = (Pipe(), Pipe())
        process.standardOutput = stdout
        process.standardError = stderr
        var writing: (Pipe, Data)?
        switch input {
        case .none:
            process.standardInput = FileHandle.nullDevice
        case .bytes(let data):
            let pipe = Pipe()
            // A command that stops reading early makes the write fail with EPIPE, not kill this process with SIGPIPE.
            XCTAssertNotEqual(fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1), -1, String(cString: strerror(errno)))
            process.standardInput = pipe
            writing = (pipe, data)
        case .file(let url):
            process.standardInput = try FileHandle(forReadingFrom: url)
        }
        try process.run()
        if case let (pipe, data)? = writing {
            Thread.detachNewThread {
                do {
                    try pipe.fileHandleForWriting.write(contentsOf: data)
                } catch {
                    // discarded: a command that closed its input early is the case's own evidence, read from its streams.
                }
                do {
                    try pipe.fileHandleForWriting.close()
                } catch {
                    // discarded: the write end is this process's own; closing it fails only if it is already closed.
                }
            }
        }
        return Running(process, stdout: stdout, stderr: stderr)
    }

    /// Run `wisent-errors-swift <arguments>` to its end.
    func run(_ arguments: [String], environment: [String: String]? = nil, input: Input = .none, in directory: URL? = nil) throws -> Ran {
        try start(arguments, environment: environment, input: input, in: directory).finish()
    }

    /// The three lines the command prints for a refusal: `sentence` (failed:
    /// cause; observed: …), `fix`, and the cause line naming `operation`,
    /// `cause` and its anchor on docs/errors/`page`.md.
    func refusal(_ operation: String, _ cause: String, page: String, _ sentence: String, fix: String) -> String {
        let anchor = "\(operation.replacingOccurrences(of: ".", with: "-"))-\(cause)"
        return "Error: \(sentence)\nfix: \(fix)\ncause: \(operation).\(cause); https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/\(page).md#\(anchor)\n"
    }

    /// A refusal of `wisent_errors.swift_cli.arguments`, which exits 2.
    func usage(_ cause: String, _ sentence: String, fix: String) -> Ran {
        Ran(status: 2, stdout: "", stderr: refusal("wisent_errors.swift_cli.arguments", cause, page: "swift-cli", sentence, fix: fix))
    }

    /// Every path under `directory`, relative to it, sorted.
    func tree(_ directory: URL) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()
    }

    /// The file at `url`, read from disk as text.
    func text(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// The file at `url`, read from disk as the JSON object written there.
    func object(_ url: URL) throws -> [String: Any] {
        try object(Data(contentsOf: url), url.path)
    }

    /// `data` as the JSON object it holds; `what` names it when it holds none.
    func object(_ data: Data, _ what: String) throws -> [String: Any] {
        let read = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(read as? [String: Any], "\(what) holds a JSON object")
    }

    /// The value of `name` in this process's environment, or the case fails naming it.
    func required(_ name: String, _ meaning: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw Blocked(description: "blocked, not passed: \(name) is not set; set it to \(meaning): this case runs against the real one")
        }
        return value
    }
}
#endif
