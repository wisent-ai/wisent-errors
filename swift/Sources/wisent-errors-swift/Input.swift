// Reading the one JSON document a command was named: the file's bytes, then
// JSON (`JSONSerialization.describedObject`, which says where the text
// stopped being JSON), then the type the command reads
// (`JSONDecoder.decodeDescribed`, which names the coding path that failed).
// Each way it fails is a declared cause of `wisent_errors.swift_cli.input`,
// and what the operating system or the decoder answered is said through
// `Error.explained`.

#if os(macOS)
import Foundation
import WisentErrors

/// What a command reads from a file: what it is called, the shape it must have, and an example of it.
struct Document<T: Decodable> {
    let what: String
    let shape: String
    let example: String

    /// The file at `path` read and decoded, or the refusal naming why not.
    func read(_ path: String) throws -> T {
        // Absolute, so the refusal names the file and its directory whole, a relative path read from the working directory.
        let url = URL(fileURLWithPath: path).absoluteURL
        let values = ["what": what, "path": url.path, "cwd": FileManager.default.currentDirectoryPath]
        let refusal = { (cause: Cause, more: [String: String]) in
            OwnFailures.swiftCliInput.refusal(cause, values.merging(more) { $1 })
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError {
            let answered = error.explained
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                throw refusal(OwnFailures.swiftCliInputInputAbsent, ["parent": FileState.parent(of: url), "error": answered])
            }
            let state = FileState.of(url)
            if FileState.isDirectory(url) {
                throw refusal(OwnFailures.swiftCliInputInputIsDirectory, ["state": state, "error": answered])
            }
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                throw refusal(OwnFailures.swiftCliInputInputNotPermitted, ["state": state, "error": answered])
            }
            throw refusal(OwnFailures.swiftCliInputInputReadFailed, ["state": state, "error": answered])
        }
        let bytes = ["bytes": String(data.count)]
        do {
            _ = try JSONSerialization.describedObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw refusal(OwnFailures.swiftCliInputInputNotJson, bytes.merging(["error": error.explained]) { $1 })
        }
        do {
            return try JSONDecoder().decodeDescribed(T.self, from: data)
        } catch {
            throw refusal(OwnFailures.swiftCliInputInputWrongShape, bytes.merging([
                "error": error.explained, "shape": shape, "example": example,
            ]) { $1 })
        }
    }
}

/// What is at a path, as a refusal says it: what it is, its size and its mode.
enum FileState {
    static func of(_ url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            // fallback: every item the file system describes has permissions; 0 says none were given.
            let mode = String((attributes[.posixPermissions] as? Int) ?? 0, radix: 8)
            if attributes[.type] as? FileAttributeType == .typeDirectory {
                return "\(url.path) is a directory of mode \(mode)"
            }
            // fallback: an item with no size is said as 0 bytes.
            let size = (attributes[.size] as? Int) ?? 0
            return "\(url.path) is a file of \(size) bytes, mode \(mode)"
        } catch {
            return "\(url.path) cannot be examined: \(error.explained)"
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// The directory `url` would be in, and what it holds.
    static func parent(of url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: parent.path).sorted()
        } catch {
            return "its directory \(parent.path) cannot be listed either: \(error.explained)"
        }
        let shown = names.prefix(10).joined(separator: ", ")
        let more = names.count > 10 ? " and \(names.count - 10) more" : ""
        return names.isEmpty ? "its directory \(parent.path) is empty" : "its directory \(parent.path) holds \(shown)\(more)"
    }
}
#endif
