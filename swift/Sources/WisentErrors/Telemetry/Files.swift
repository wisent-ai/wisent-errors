// The files telemetry keeps, read and written whole, and the facts about this
// machine every event and record carries.

import Foundation

extension WisentTelemetry {
    func readObject(_ path: URL, what: String) throws -> [String: Any]? {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TelemetryError.unreadable(
                "reading \(what) from \(path.path): the file is not what telemetry wrote: it is not a JSON object; observed: the file holds \(data.count) bytes; fix: answer again in the app's settings, which rewrites it, or remove \(path.path)")
        }
        return object
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
            throw TelemetryError.unwritable(
                "keeping \(what) in \(path.path): the telemetry directory could not be written: \(error.explained); observed: directory \(folder.path); fix: make \(folder.path) writable by this user, or name a writable one with WISENT_TELEMETRY_HOME")
        }
    }

    /// Remove a file or directory telemetry keeps; one already gone is what
    /// removal wanted, any other failure says what stays because of it.
    func remove(_ path: URL, what: String, left: String) throws {
        do {
            try FileManager.default.removeItem(at: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            throw TelemetryError.unwritable(
                "removing \(what) at \(path.path): the telemetry directory refused it: \(error.explained); observed: \(left); fix: make \(path.deletingLastPathComponent().path) writable by this user, then try again")
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
