# The boundary

What wisent-errors owns, and what it deliberately does not. The package
decides the content of a failure report — the vocabulary, the shape, the
derived fields, the trim rule — and almost nothing else. Everything on the
far side of this line stays in the products, on purpose.

## Owned here

- The seven codes, and everything derivable from a code: `severity`,
  `retryable`, `outage`, the edge HTTP status, the retryable exit-code rule
  ([catalogue](catalogue.md)).
- The classification of an upstream HTTP status into a code.
- The envelope shape, its stable key set, and its serialization order
  ([envelope](envelope.md)).
- The trim *rule* — hard cut, ends stripped — and the opt-in word-edge
  variant.
- The *shape* of a failure point: a dotted lowercase path, one segment or
  more.
- The proof that all four runtimes implement the above identically
  ([conformance](conformance.md)).

## Not owned here

**Product messages.** They go in `detail`, verbatim. The package truncates;
it never writes, paraphrases, or re-classifies a sentence.

**Provider text.** It passes through and is truncated, never paraphrased or
re-classified. Their words are data.

**Failure-point registries.** The package validates only the shape of
`failure_point`; which points exist, and how deep they go, is each product's
own registry. stado's come from its subcommand path and run from `cli` to
`cli.host.user.create`; probierz and growth-tactics are two-segment. A
shared rule that refused what five products already emit would be the
package being wrong, so depth deliberately carries no meaning.

**Logging plumbing.** Each product keeps its own emitter; this package
decides the content, not the transport. The one transport in this
repository is the Swift `WisentFailureReporter`, which exists for the two
native desktop clients and posts envelopes to a Probierz intake without
ever failing or blocking its caller ([runtimes](runtimes.md)); nothing in
the Rust, Python, or JavaScript runtimes ships or logs anything.

**Trim widths.** 2000 is the package's own bound (`DETAIL_LIMIT`), used
when it trims on your behalf. A product's width is the product's decision
and is passed as an argument.

**Exit-code conventions.** Only the retryable path is remapped, to 69
(`EX_UNAVAILABLE`). A caller that already chose an exit code keeps it.

**New codes.** Seven, exactly as the reference had. A case the seven cannot
describe is worth adding; nothing found so far is one. The closest call is
recorded rather than hidden: two native clients independently invented
`offline` — retryable, `warning`, deliberately not an outage, because a
device with no signal must not tell its owner our infrastructure is down.
It is still not in the catalogue for one reason: `http_status` and
`exit_code` are derived for every code, and neither applies to a code no
server can observe and no command can exit with. Inventing values there is
the exact shape of the rules this package had to withdraw on its first day,
so both clients keep `offline` beside the seven with the reason written
next to it. That changes if a third product needs it, or if the catalogue
grows a way to say "this derivation does not apply".

## Why the line sits here

Everything derivable from the code is derived; everything a caller decides
is an argument. A call site chooses where it broke, what the layer below
said, and which subject it concerns — it never chooses `severity`,
`retryable`, or `outage`, which is why one code cannot come to mean
different things in different products. The fleet's history is the
argument: five of six hand-kept copies drifted in the derived table, in the
same two lines, while the vocabulary — the part people compared — stayed
intact everywhere. Drift entered exactly where a copy had to be adapted;
the shared, generated, conformance-checked table is what removes that
surface. How a product adopts it is [integration](integration.md).
