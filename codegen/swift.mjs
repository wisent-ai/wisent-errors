// Render the Swift vocabulary from the generator's prepared catalogue.

// Swift, because two native clients hold their own copies: oko-desktop and
// wisent-ios. Cases are camelCase with the catalogue's string as the raw value,
// which is the spelling both already use, so neither has to rename anything.
export function swift({ catalogue, codes, exact, ranges, fallback, banner }) {
  const swiftName = (code) =>
    code.split('_').map((part, index) => (index === 0 ? part : part[0].toUpperCase() + part.slice(1))).join('');
  const cases = codes
    .map((entry) =>
      swiftName(entry.code) === entry.code
        ? `    case ${entry.code}`
        : `    case ${swiftName(entry.code)} = "${entry.code}"`,
    )
    .join('\n');
  const arm = (entry, value) => `        case .${swiftName(entry.code)}: ${value}`;
  const severityArms = codes.map((entry) => arm(entry, `.${entry.severity}`)).join('\n');
  const retryableArms = codes.map((entry) => arm(entry, entry.retryable)).join('\n');
  const outageArms = codes.map((entry) => arm(entry, entry.outage)).join('\n');
  const statusArms = codes.map((entry) => arm(entry, entry.http_status)).join('\n');
  const summaryArms = codes.map((entry) => arm(entry, JSON.stringify(entry.operator_summary))).join('\n');
  const exactArms = exact.map(([status, code]) => `        case ${status}: .${swiftName(code)}`).join('\n');
  const rangeArms = ranges
    .map((range) => `        case ${range.from}...${range.to}: .${swiftName(range.code)}`)
    .join('\n');

  return `${banner('//')}

/// How loud this failure is. Derived from the code, never chosen at a call site.
public enum Severity: String, CaseIterable, Sendable, Hashable, Codable {
${catalogue.severities.map((name) => `    case ${name}`).join('\n')}
}

/// The fleet's whole failure vocabulary.
public enum Code: String, CaseIterable, Sendable, Hashable, Codable {
${cases}

    /// The exit code a retryable failure leaves the process with.
    public static let retryExit: Int32 = ${catalogue.exit_code.retry}

    public var severity: Severity {
        switch self {
${severityArms}
        }
    }

    /// Worth running the same thing again without changing anything.
    public var retryable: Bool {
        switch self {
${retryableArms}
        }
    }

    /// Our side is broken, as opposed to the request being wrong.
    public var outage: Bool {
        switch self {
${outageArms}
        }
    }

    /// The HTTP status a service answers with when this failure reaches its edge.
    public var httpStatus: Int {
        switch self {
${statusArms}
        }
    }

    /// One sentence for the human who just ran the command: ours or theirs?
    public var operatorSummary: String {
        switch self {
${summaryArms}
        }
    }

    /// The exit code this failure leaves the process with, given the chosen one.
    public func exitCode(chosen: Int32) -> Int32 {
        retryable ? Self.retryExit : chosen
    }

    /// Classify a status an upstream answered one of our calls with.
    public static func fromUpstream(status: Int) -> Code {
        switch status {
${exactArms}
${rangeArms}
        default: .${swiftName(fallback)}
        }
    }

    /// The code when the catalogue knows this text, otherwise the fallback.
    ///
    /// Never fails. Products wrote this coercion by hand during their migration.
    public static func orFallback(_ text: String?) -> Code {
        guard let text, let code = Code(rawValue: text) else { return .${swiftName(fallback)} }
        return code
    }
}

public let fallbackCode: Code = .${swiftName(fallback)}
public let failurePointPattern = ${JSON.stringify(catalogue.failure_point.pattern)}
`;
}

