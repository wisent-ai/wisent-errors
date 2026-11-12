import Foundation

extension Error {
    /// What this error says to a person, in full.
    ///
    /// `localizedDescription` says a Swift error that declares no description
    /// as "The operation couldn't be completed. (Module.SomeError error 1.)", a
    /// `DecodingError` as "The data couldn't be read because it isn't in the
    /// correct format", and drops the underlying error a Cocoa error carries.
    /// This says a declared description as declared, a decoding failure with
    /// its coding path, a Cocoa error with its domain and code, any other error
    /// as its type and value, and then each underlying error, joined by ": ".
    /// The chain is read until it ends or comes back to an error already said,
    /// and a sentence an earlier one already holds is not said again.
    public var explained: String {
        var said: [String] = []
        var seen: Set<String> = []
        var next: Error? = self
        while let error = next {
            let sentence = errorSentence(error)
            guard seen.insert(sentence).inserted else { break }
            if !said.contains(where: { $0.contains(sentence) }) { said.append(sentence) }
            next = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }
        return said.joined(separator: ": ")
    }
}

/// One error's own sentence, without the errors under it.
private func errorSentence(_ error: Error) -> String {
    if let decoding = error as? DecodingError { return decodingReason(decoding) }
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    let bridged = error as NSError
    let cocoa = bridged.domain.hasPrefix("NS") || bridged.domain.hasPrefix("kCF")
    if bridged.userInfo[NSLocalizedDescriptionKey] != nil || cocoa {
        return "\(bridged.localizedDescription) (\(bridged.domain) \(bridged.code))"
    }
    return String(reflecting: error)
}

/// The coding path a decoding failure stopped at, or "the top level".
private func codingPath(_ context: DecodingError.Context) -> String {
    let keys = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
    return keys.isEmpty ? "the top level" : keys.joined(separator: ".")
}

/// A decoding failure with the coding path it stopped at and the decoder's reason.
private func decodingReason(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context):
        return "key \"\(key.stringValue)\" is missing at \(codingPath(context))"
    case .valueNotFound(let expected, let context):
        return "\(expected) is null at \(codingPath(context))"
    case .typeMismatch(let expected, let context):
        return "\(codingPath(context)) is not \(expected): \(context.debugDescription)"
    case .dataCorrupted(let context):
        let underlying = context.underlyingError as NSError?
        let detail = underlying?.userInfo[NSDebugDescriptionErrorKey] as? String
        return "\(context.debugDescription)\(detail.map { " (\($0))" } ?? "") at \(codingPath(context))"
    @unknown default:
        return String(reflecting: error)
    }
}
