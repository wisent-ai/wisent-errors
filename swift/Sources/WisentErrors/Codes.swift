// Generated from catalogue/codes.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

/// How loud this failure is. Derived from the code, never chosen at a call site.
public enum Severity: String, CaseIterable, Sendable, Hashable, Codable {
    case warning
    case error
    case critical
}

/// The fleet's whole failure vocabulary.
public enum Code: String, CaseIterable, Sendable, Hashable, Codable {
    case config
    case auth
    case notFound = "not_found"
    case rateLimit = "rate_limit"
    case timeout
    case infraDown = "infra_down"
    case unknown

    /// The exit code a retryable failure leaves the process with.
    public static let retryExit: Int32 = 69

    public var severity: Severity {
        switch self {
        case .config: .critical
        case .auth: .warning
        case .notFound: .warning
        case .rateLimit: .warning
        case .timeout: .error
        case .infraDown: .critical
        case .unknown: .error
        }
    }

    /// Worth running the same thing again without changing anything.
    public var retryable: Bool {
        switch self {
        case .config: false
        case .auth: false
        case .notFound: false
        case .rateLimit: true
        case .timeout: true
        case .infraDown: true
        case .unknown: false
        }
    }

    /// Our side is broken, as opposed to the request being wrong.
    public var outage: Bool {
        switch self {
        case .config: true
        case .auth: false
        case .notFound: false
        case .rateLimit: false
        case .timeout: true
        case .infraDown: true
        case .unknown: false
        }
    }

    /// The HTTP status a service answers with when this failure reaches its edge.
    public var httpStatus: Int {
        switch self {
        case .config: 503
        case .auth: 401
        case .notFound: 404
        case .rateLimit: 429
        case .timeout: 504
        case .infraDown: 503
        case .unknown: 500
        }
    }

    /// One sentence for the human who just ran the command: ours or theirs?
    public var operatorSummary: String {
        switch self {
        case .config: "our deployment configuration is incomplete or wrong"
        case .auth: "the credentials this command used were rejected"
        case .notFound: "what the command asked for is not there"
        case .rateLimit: "an upstream is throttling us"
        case .timeout: "an upstream did not answer in time"
        case .infraDown: "infrastructure we depend on is unreachable"
        case .unknown: "the command failed and we could not attribute the failure"
        }
    }

    /// The exit code this failure leaves the process with, given the chosen one.
    public func exitCode(chosen: Int32) -> Int32 {
        retryable ? Self.retryExit : chosen
    }

    /// Classify a status an upstream answered one of our calls with.
    public static func fromUpstream(status: Int) -> Code {
        switch status {
        case 401: .auth
        case 403: .auth
        case 404: .notFound
        case 407: .auth
        case 408: .timeout
        case 410: .notFound
        case 429: .rateLimit
        case 501: .config
        case 504: .timeout
        case 505: .config
        case 500...599: .infraDown
        default: .unknown
        }
    }

    /// The code when the catalogue knows this text, otherwise the fallback.
    ///
    /// Never fails. Products wrote this coercion by hand during their migration.
    public static func orFallback(_ text: String?) -> Code {
        guard let text, let code = Code(rawValue: text) else { return .unknown }
        return code
    }
}

public let fallbackCode: Code = .unknown
public let failurePointPattern = "^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*)*$"
