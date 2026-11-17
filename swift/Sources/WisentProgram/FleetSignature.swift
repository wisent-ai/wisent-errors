#if os(macOS)
import Darwin
import Foundation
import Security

/// Whether a program is one its publisher signed: its code signature is
/// valid and meets the designated requirement every installed fleet CLI
/// carries (`codesign -d -r- ~/.stado/bin/stado`):
///
///     identifier "com.wisent.<name>" and anchor apple generic
///         and certificate leaf[subject.OU] = LNTWB5B9DV
///
/// or, for a program another publisher signs (the Node.js runtime a
/// product's CLI runs on), the same requirement with that publisher's
/// identifier and team. The fleet CLIs are signed with an Apple Development
/// certificate of the team, not Developer ID, so the requirement names the
/// team and no Developer ID marker: any certificate Apple issued the team
/// meets it.
///
/// A program's name, the directory it sits in, the variable or `PATH` that
/// led to it and its file's contents as a copy holds them say nothing about
/// who wrote it: a stand-in named `para` on `PATH`, a variable naming one,
/// or a copy of another signed program renamed `para` all pass a name check
/// and all fail this one. The check is made on the file before it is
/// started (``verify(file:identifier:team:)``) and on the process the
/// kernel started from it (``verify(process:identifier:team:)``), so a file
/// replaced between the two is caught on the process.
public enum FleetSignature {
    /// The fleet's Apple developer team.
    public static let team = "LNTWB5B9DV"

    /// The characters a signing identifier or team may hold here: letters,
    /// digits, `.`, `-` and `_`, so neither can close the requirement's
    /// quoted string and add a clause of its own.
    static let plain = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")

    /// The designated requirement of the program `identifier` that the
    /// team `team` signed. Both are constants a product declares; one that
    /// holds any other character is a programming error, stopped here.
    public static func requirement(identifier: String, team: String = FleetSignature.team) -> String {
        precondition(
            [identifier, team].allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(plain.contains) },
            "a signing identifier and team hold only letters, digits, . - and _: \(identifier) \(team)")
        return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// Why a program is not admitted: the file or process, and what
    /// Security answered.
    public struct Refusal: Error, Equatable, CustomStringConvertible {
        public let path: String
        public let reason: String

        public init(path: String, reason: String) {
            self.path = path
            self.reason = reason
        }

        public var description: String { "\(path) is not admitted: \(reason)" }
    }

    /// Who was admitted: the executable the kernel ran, the process, and the
    /// requirement it met.
    public struct Admission: Sendable, Equatable {
        public let path: String
        public let pid: pid_t
        public let requirement: String
    }

    /// Check the file at `file` against the requirement of `identifier`
    /// signed by `team`; throws ``Refusal``.
    public static func verify(file: URL, identifier: String, team: String = FleetSignature.team) throws {
        try check(file: file, requirement: requirement(identifier: identifier, team: team)).get()
    }

    /// Check the running process `pid`, a child of this app, against the
    /// requirement of `identifier` signed by `team`, and say who it is;
    /// throws ``Refusal``.
    @discardableResult
    public static func verify(process pid: pid_t, identifier: String, team: String = FleetSignature.team) throws -> Admission {
        try admission(process: pid, requirement: requirement(identifier: identifier, team: team)).get()
    }

    /// The static check: every architecture, strictly, against `text`.
    static func check(file: URL, requirement text: String) -> Result<Void, Refusal> {
        let refused = { (reason: String) in Refusal(path: file.path, reason: reason) }
        return compiled(text, refused).flatMap { requirement in
            var code: SecStaticCode?
            let made = SecStaticCodeCreateWithPath(file as CFURL, [], &code)
            guard made == errSecSuccess, let code else { return .failure(refused(said(made))) }
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
            let checked = SecStaticCodeCheckValidity(code, flags, requirement)
            return checked == errSecSuccess ? .success(()) : .failure(refused(said(checked)))
        }
    }

    /// The dynamic check: the code the kernel holds for `pid` (its main
    /// executable as exec mapped it), valid and meeting `text`. The path
    /// named is the one the kernel gives for the process (`proc_pidpath`),
    /// never one the caller passed.
    static func admission(process pid: pid_t, requirement text: String) -> Result<Admission, Refusal> {
        let path = executablePath(pid)
        let refused = { (reason: String) in Refusal(path: path, reason: reason) }
        return compiled(text, refused).flatMap { requirement in
            var code: SecCode?
            let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
            let found = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
            guard found == errSecSuccess, let code else { return .failure(refused(said(found))) }
            let checked = SecCodeCheckValidity(code, [], requirement)
            guard checked == errSecSuccess else { return .failure(refused(said(checked))) }
            return .success(Admission(path: path, pid: pid, requirement: text))
        }
    }

    /// The executable the kernel ran for `pid`, or what kept it from saying.
    /// The buffer is `PROC_PIDPATHINFO_MAXSIZE` (`4 * MAXPATHLEN`,
    /// `<sys/proc_info.h>`), the size `proc_pidpath` asks for.
    static func executablePath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "process \(pid) (proc_pidpath: \(String(cString: strerror(errno))))" }
        return String(cString: buffer)
    }

    /// `SSTOP`, the stopped state of `pbi_status` (`<sys/proc.h>`).
    private static let stopped = UInt32(SSTOP)

    /// That `pid`, started suspended, is still stopped and has run no
    /// instruction of its own: any process of the account may send a
    /// suspended child SIGCONT, and one resumed before it was admitted could
    /// have exec'd another program, so the code checked would not be the
    /// code that ran. Read from the kernel: the state `proc_pidinfo`
    /// (PROC_PIDTBSDINFO) gives and the user time `proc_pid_rusage` gives.
    static func unrun(_ pid: pid_t) -> Result<Void, Refusal> {
        let refused = { (reason: String) in Refusal(path: executablePath(pid), reason: reason) }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return .failure(refused("its state cannot be read: proc_pidinfo: \(String(cString: strerror(errno)))"))
        }
        guard info.pbi_status == stopped else {
            return .failure(refused("it was resumed by another process before it was admitted"))
        }
        var usage = rusage_info_v0()
        let read = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V0, $0) }
        }
        guard read == 0 else {
            return .failure(refused("its use cannot be read: proc_pid_rusage: \(String(cString: strerror(errno)))"))
        }
        guard usage.ri_user_time == 0 else {
            return .failure(refused("it ran \(usage.ri_user_time) of user time before it was admitted"))
        }
        return .success(())
    }

    private static func compiled(_ text: String, _ refused: (String) -> Refusal) -> Result<SecRequirement, Refusal> {
        var requirement: SecRequirement?
        let made = SecRequirementCreateWithString(text as CFString, [], &requirement)
        guard made == errSecSuccess, let requirement else { return .failure(refused(said(made))) }
        return .success(requirement)
    }

    /// Security's own words for `status`, with its number; the number alone,
    /// said so, when Security has no words for it.
    private static func said(_ status: OSStatus) -> String {
        guard let message = SecCopyErrorMessageString(status, nil) as String? else {
            return "OSStatus \(status), which Security has no message for"
        }
        return "\(message) (OSStatus \(status))"
    }
}
#endif
