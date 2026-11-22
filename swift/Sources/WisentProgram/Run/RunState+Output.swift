#if os(macOS)
import Darwin
import Foundation

/// The reading of a run's output streams and the text they hand on.
extension RunState {
    func watch(_ stream: InstalledProgram.Stream, _ descriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [self] in readable(stream) }
        source.setCancelHandler { Darwin.close(descriptor) }
        descriptors[stream] = descriptor
        sources[stream] = source
        source.resume()
    }

    func readable(_ stream: InstalledProgram.Stream) {
        guard continuation != nil else { return }
        switch drain(stream) {
        case .open: break
        case .closed: closed(stream)
        case .failed(let failed): unfollowed(failed)
        }
    }

    /// Read everything `stream` holds now and hand it on.
    func drain(_ stream: InstalledProgram.Stream) -> Drained {
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
    func closed(_ stream: InstalledProgram.Stream) {
        rest(stream)
        sources.removeValue(forKey: stream)?.cancel()
        descriptors.removeValue(forKey: stream)
    }

    /// Add a read from `stream` to its output and hand on the text it
    /// completes. Decoding each read on its own turned a character whose
    /// UTF-8 bytes the pipe delivered in two reads (`ó`, `ł`, `–`) into two
    /// U+FFFD, in the output and in the JSON a product parses from it; the
    /// bytes of a character still incomplete wait for the next read.
    func append(_ data: Data, to stream: InstalledProgram.Stream) {
        // fallback: a stream with no bytes held back yet starts from none.
        var bytes = split[stream] ?? Data()
        bytes.append(data)
        let whole = Self.wholeCharacters(bytes)
        split[stream] = Data(bytes[whole...])
        say(String(decoding: bytes[..<whole], as: UTF8.self), on: stream)
    }

    /// At the end of a stream, the bytes of a character no read completed,
    /// decoded as they are (U+FFFD for what is not UTF-8) and handed on.
    func rest(_ stream: InstalledProgram.Stream) {
        guard let bytes = split.removeValue(forKey: stream), !bytes.isEmpty else { return }
        say(String(decoding: bytes, as: UTF8.self), on: stream)
    }

    func say(_ text: String, on stream: InstalledProgram.Stream) {
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
    static func wholeCharacters(_ bytes: Data) -> Data.Index {
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
