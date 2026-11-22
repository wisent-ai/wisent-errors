// What the `wisent-errors-swift program run` cases share, beside
// CommandCase.swift's own directory and cleared environment: real programs
// installed where their release installer places them, ~/.local/bin of the
// case's home, as copies (a copy keeps its code signature) of the files the
// gate's environment names -- WISENT_PROGRAM_TEST_NODE: node, which Node.js
// signs (identifier `node`, team HX7739G8FX), the runtime product command
// lines run on, run with `-e` so each case says what the program does;
// WISENT_PROGRAM_TEST_STADO: the fleet-signed stado. Both are named in
// .wisent-release.json `env`, and stado is installed for the gate run by its
// `test_products` entry. A case whose program is not named fails as
// blocked, never passes. Also: a system call's failure as WisentProgram
// names it, and the kernel's process table.

#if os(macOS)
import Darwin
import Foundation
import XCTest

class ProgramCase: CommandCase {
    /// The file `variable` names, copied to ~/.local/bin/`name` of the case's home.
    @discardableResult
    func install(from variable: String, meaning: String, as name: String) throws -> URL {
        let named = (try required(variable, meaning) as NSString).expandingTildeInPath
        let file = URL(fileURLWithPath: named).resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: file.path) else {
            throw Blocked(description: "blocked, not passed: \(variable) names \(named), which is no executable file; set it to \(meaning)")
        }
        let place = home.appendingPathComponent(".local/bin").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The file itself, not a link to it: the lookup admits the file it finds.
        try FileManager.default.copyItem(at: file, to: place)
        return place
    }

    /// node, installed as `node` in the case's home.
    @discardableResult
    func installNode() throws -> URL {
        try install(
            from: "WISENT_PROGRAM_TEST_NODE",
            meaning: "the Node.js-signed node Stado's node runtime installs (~/.local/share/stado-node/<version>/bin/node)", as: "node")
    }

    /// `program run node`, admitted as Node.js signs it, running `script` with `options` before it.
    func node(_ script: String, _ options: [String] = []) -> [String] {
        ["program", "run", "node", "--identifier", "node", "--team", "HX7739G8FX"] + options + ["--", "-e", script]
    }

    /// A refusal of `wisent_errors.swift_cli.program_run`.
    func programRun(_ cause: String, status: Int32, _ sentence: String, fix: String) -> Ran {
        Ran(status: status, stdout: "", stderr: refusal("wisent_errors.swift_cli.program_run", cause, page: "swift-cli", sentence, fix: fix))
    }

    /// Whether `pid` is stopped, as the kernel's process table says.
    func isStopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.pbi_status == UInt32(SSTOP)
    }

    /// Whether the kernel's process table still holds `pid`: kill(pid, 0) answers ESRCH once it is gone.
    func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }
}
#endif
