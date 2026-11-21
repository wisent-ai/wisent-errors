#if os(macOS)
import Darwin
import Foundation

/// The pipes of a run and the writing of its program's standard input.
extension RunState {
    /// A pipe for the program's standard input that no other program this
    /// app starts inherits, its write end not blocking and raising no
    /// SIGPIPE (`F_SETNOSIGPIPE`), so a program that closed its input makes
    /// the next write EPIPE, never a signal to this app.
    static func inputPipe() throws -> (read: Int32, write: Int32) {
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
    func write(_ input: Data, to descriptor: Int32) {
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
    func writable(_ input: Data) {
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
    func endInput() {
        inputSource?.cancel()
        inputSource = nil
        inputDescriptor = nil
    }

    /// A pipe no other program this app starts inherits, its read end not
    /// blocking, so a read takes what is there and says when nothing is.
    static func pipe() throws -> (read: Int32, write: Int32) {
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
    static func checked(_ call: String, _ code: Int32) throws {
        guard code == 0 else { throw SystemCallFailed(call: call, code: code) }
    }
}
#endif
