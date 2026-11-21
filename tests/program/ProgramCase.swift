// What the WisentProgram cases share: a home of their own under the
// checkout's .build, removed when the case ends; the real programs they run
// through the package's public API, never looked for in the operator's own
// home -- each is the file a variable names (WISENT_PROGRAM_TEST_NODE: node,
// which Node.js signs, identifier `node`, team HX7739G8FX, run with `-e` so
// each case says what the program does; WISENT_PROGRAM_TEST_STADO: the fleet's
// stado), copied into ~/.local/bin of a home under .build (a copy keeps its
// code signature) and found and verified there as an app finds it;
// Security's own words for a status, as the library says them; and the
// first line a run writes, handed to the case as it arrives.

#if os(macOS)
import Darwin
import Foundation
import Security
import WisentProgram
import XCTest

/// A case that needs a real program the environment does not name: it
/// fails naming the variable, never passes.
struct Blocked: Error, CustomStringConvertible {
    let description: String
}

class ProgramCase: XCTestCase {
    /// The checkout's build directory: tests/program/<this file> is three levels below the checkout.
    static let build = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build")

    /// node, the runtime product CLIs run on, run with `-e <script>`.
    let node = InstalledProgram(name: "node", identifier: "node", team: "HX7739G8FX", leading: ["-e"])

    /// The homes under .build holding each program's copy, by name: made on
    /// first use, so a large program is copied once per test class.
    private static var homes: [String: URL] = [:]

    override class func tearDown() {
        for home in ProgramCase.homes.values { try? FileManager.default.removeItem(at: home) }
        ProgramCase.homes = [:]
        super.tearDown()
    }

    /// `program` as an app finds it: the file `variable` names, copied into
    /// ~/.local/bin of a home under .build, found there and its signature checked.
    func installed(_ program: InstalledProgram, from variable: String, meaning: String) throws -> URL {
        if let home = ProgramCase.homes[program.name] { return try program.executable(home: home) }
        guard let given = ProcessInfo.processInfo.environment[variable], !given.isEmpty else {
            throw Blocked(description: "blocked, not passed: \(variable) is not set; set it to the path of \(meaning): this case runs it")
        }
        let home = Self.build.appendingPathComponent("program-swift").appendingPathComponent("installed-\(UUID().uuidString)")
        let place = home.appendingPathComponent(".local/bin/\(program.name)")
        try FileManager.default.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
        ProgramCase.homes[program.name] = home
        // The file itself, not a link to it: the lookup reads the place it finds.
        try FileManager.default.copyItem(atPath: URL(fileURLWithPath: given).resolvingSymlinksInPath().path, toPath: place.path)
        return try program.executable(home: home)
    }

    /// The Node.js-signed node the run cases run.
    func installedNode() throws -> URL {
        try installed(node, from: "WISENT_PROGRAM_TEST_NODE", meaning: "the Node.js-signed node Stado's node runtime installs (~/.local/share/stado-node/<version>/bin/node)")
    }

    /// A home of the case's own, removed when the case ends.
    func caseHome() throws -> URL {
        let home = Self.build.appendingPathComponent("program-swift").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    /// Security's words for `status` with its number, as FleetSignature says a refusal.
    func security(_ status: OSStatus) -> String {
        guard let message = SecCopyErrorMessageString(status, nil) as String? else {
            return "OSStatus \(status), which Security has no message for"
        }
        return "\(message) (OSStatus \(status))"
    }

    /// What a system call failing with `code` says, as WisentProgram names it.
    func failed(_ call: String, _ code: Int32) -> String {
        "\(call) failed: \(String(cString: strerror(code))) (errno \(code))"
    }

    /// Whether `pid` is stopped, as the kernel's process table says.
    func isStopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.pbi_status == UInt32(SSTOP)
    }
}

/// The first line a run writes on stdout, handed to the case as it arrives.
final class FirstLine: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var line: String?
    private var waiting: CheckedContinuation<String, Never>?

    /// Add a chunk; answers the first line once this chunk completes it.
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
#endif
