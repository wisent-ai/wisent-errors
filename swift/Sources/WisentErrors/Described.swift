import Foundation

/// A decoding failure that says what was decoded and where it went wrong.
///
/// `DecodingError` describes itself to a person only as "The data couldn't be
/// read because it isn't in the correct format", which is the sentence
/// `error.localizedDescription` shows. This error names the type, the coding
/// path and the reason the decoder gave, the sentence `Error.explained` says
/// for the `DecodingError` it carries.
public struct DescribedDecodingError: LocalizedError {
    /// The type that could not be decoded, as `String(describing:)` names it.
    public let type: String
    /// The decoder's own failure.
    public let underlying: DecodingError

    public init(type: String, underlying: DecodingError) {
        self.type = type
        self.underlying = underlying
    }

    public var errorDescription: String? {
        "\(type) could not be decoded: \(decodingReason(underlying))"
    }
}

extension JSONDecoder {
    /// `decode`, with a failure that names the type and the coding path that failed.
    public func decodeDescribed<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch let error as DecodingError {
            throw DescribedDecodingError(type: String(describing: type), underlying: error)
        }
    }
}

/// Text `JSONSerialization` could not read, with Foundation's reason: the
/// character and the position where the text stopped being JSON. Its own
/// error describes itself only as "The data couldn't be read because it isn't
/// in the correct format".
public struct DescribedJSONError: LocalizedError {
    /// Foundation's reason, or the whole failure when Foundation gave none.
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var errorDescription: String? { reason }
}

extension JSONSerialization {
    /// `jsonObject(with:options:)`, with a failure that says where the text stopped being JSON.
    public static func describedObject(with data: Data, options: ReadingOptions = []) throws -> Any {
        do {
            return try jsonObject(with: data, options: options)
        } catch {
            let said = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw DescribedJSONError(reason: said ?? error.explained)
        }
    }
}
