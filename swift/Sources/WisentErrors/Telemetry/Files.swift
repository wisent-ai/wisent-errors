// The files telemetry keeps, read and written whole, and the facts about this
// machine every event and record carries.

import Foundation

extension WisentTelemetry {
    func readObject(_ path: URL, what: String) throws -> [String: Any]? {
        try readSizedObject(path, what: what)?.object
    }

    /// ``readObject(_:what:)`` with how many bytes the file held, for a
    /// refusal of what the object says that names the file's own size.
    func readSizedObject(_ path: URL, what: String) throws -> (object: [String: Any], bytes: Int)? {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            throw TelemetryError.unreadable(OwnFailures.telemetryStoreFileReadRefused.refusal([
                "what": what, "path": path.path, "state": Self.stateOf(path), "error": error.explained, "product": product.id,
            ]))
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TelemetryError.unreadable(OwnFailures.telemetryStoreFileUnreadable.refusal([
                "what": what, "path": path.path, "why": "it is not a JSON object",
                "bytes": String(data.count), "product": product.id,
            ]))
        }
        return (object, data.count)
    }

    /// What is at `path`, as the refusal of a read says it.
    static func stateOf(_ path: URL) -> String {
        do {
            let values = try path.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            switch (values.isDirectory, values.fileSize) {
            case (true?, _): return "\(path.path) is a directory"
            case (_, let size?): return "\(path.path) is a file of \(size) bytes"
            default: return "\(path.path) is neither a file nor a directory"
            }
        } catch {
            return "\(path.path) cannot be examined either: \(error.explained)"
        }
    }

    func writeObject(_ object: [String: Any], to path: URL, what: String) throws {
        let folder = path.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object)
            lock.lock()
            defer { lock.unlock() }
            try data.write(to: path, options: .atomic)
        } catch {
            throw TelemetryError.unwritable(OwnFailures.telemetryStoreStoreUnwritable.refusal([
                "what": what, "path": path.path, "why": error.explained, "directory": folder.path,
            ]))
        }
    }

    /// Remove a file or directory telemetry keeps; one already gone is what
    /// removal wanted, any other failure is the store's own refusal.
    func remove(_ path: URL, what: String) throws {
        do {
            try FileManager.default.removeItem(at: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            throw TelemetryError.unwritable(OwnFailures.telemetryStoreStoreUnwritable.refusal([
                "what": what, "path": path.path, "why": error.explained,
                "directory": path.deletingLastPathComponent().path,
            ]))
        }
    }

    // MARK: Facts about this machine

    static var platform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    /// Now on this host's clock with its offset written out
    /// (`2026-11-16T14:03:07.120+01:00`, `+00:00` where local time is UTC,
    /// never `Z`): the moment of the last delivery, which the Settings window
    /// shows a person as "Last sent", in their own local time.
    static func localNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxxxx"
        return formatter.string(from: Date())
    }

    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    static func say(_ what: Any) {
        FileHandle.standardError.write(Data("wisent-errors: telemetry: \(what)\n".utf8))
    }
}
