// One refusal of a declared cause, kept whole: the functionality it belongs
// to, the cause, and the values its sentences name. A caller says it as one
// line (`description`, what `Cause.refusal` says) or as the three lines a
// command prints, the form ci/support/refuse.mjs prints for this package's
// own commands:
//
//   Error: <failed>: <cause>; observed: <observed>
//   fix: <remedy>
//   cause: <operation>.<cause id>; <page>#<anchor>

/// One refusal of a declared cause.
public struct DeclaredRefusal: Error, CustomStringConvertible, Sendable {
    public let operation: Operation
    public let cause: Cause
    public let values: [String: String]

    public init(_ operation: Operation, _ cause: Cause, _ values: [String: String]) {
        self.operation = operation
        self.cause = cause
        self.values = values
    }

    /// The sentence and the fix as one line, as `Cause.refusal` says it.
    public var description: String { cause.refusal(values) }

    /// The three lines a command prints on stderr for it, without a final newline.
    public var lines: String {
        "Error: \(cause.sentence(values))\nfix: \(cause.fix(values))\ncause: \(operation.id).\(cause.id); \(operation.docs)#\(operation.anchor(cause))"
    }

    /// The status a command refusing it exits with: the usage status for a
    /// usage refusal, the retry status for a retryable code, the cause's own
    /// status, else `failureExit`.
    public func exitCode(failureExit: Int32) -> Int32 { cause.exitCode(failureExit: failureExit) }
}

extension Operation {
    /// The refusal of `cause`, one of this functionality's, with `values`.
    public func refusal(_ cause: Cause, _ values: [String: String]) -> DeclaredRefusal {
        DeclaredRefusal(self, cause, values)
    }
}
