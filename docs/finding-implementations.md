# Finding every implementation of this envelope

Why `ci/find-implementations.mjs` searches the way it does, and what it
cannot find. This was the header comment of that file until 2026-09-21, when
the file stood at 302 lines — two past the three-hundred-line limit every
file in this workshop lives under.

## Why it keys on the codes

I answered "everything is migrated" three times from a list I had written, and
was wrong three times. Each search axis found a different subset: the first list
came from reading, the second from grepping `failure_point`, and the third from
grepping `infra_down` — which found six more products, because a copy need not
use the field name but must contain the vocabulary.

So the check keys on the thing an implementation cannot avoid: the codes
themselves. A file naming three or more of the seven is a candidate, and the only
question left is whether its repository depends on the package or restates it.

## Two passes, because they answer two questions

The literal scan finds files that restate the vocabulary; a fully migrated
consumer quotes no codes at all, so it produces no row and is invisible to that
pass — which is correct for the gate and useless for counting adopters. The
manifest sweep answers "who depends on this" by reading the dependency files.
`weles-web-blog` is the proof case: perfectly migrated, zero rows, and the
earlier version of this tool would have counted it as neither.

## What neither pass can find

A module that generates or interpolates the code strings instead of writing
them. Every implementation in this fleet spelled them out verbatim — which is
also where the copies did not drift — but a future one need not. Stated here so
nobody trusts the tool further than it goes.

## Calibration

A first attempt asked for three of the seven and reported 541 repositories,
because four of the seven codes are ordinary tokens in any codebase — it matched
minified Next.js chunks. The discriminator is the one code that is not an
English phrase: a file that says `infra_down` is talking about this taxonomy and
nothing else. Requiring it plus a majority of the rest reproduces exactly the
nineteen implementations found by hand, and nothing else.

A code counts only when it is quoted. Those same four ordinary words, unquoted,
made `probierz/agent/stado.mjs` look like a copy when its only mention of the
vocabulary is a prose comment, and made `skarbiec-hub` look like one when it
emits a single literal into its own error field. An implementation writes the
codes as strings.

## One repository is one remote

Two checkouts of the same remote are two working copies of one product, and this
fleet has several — counting them separately is what made an earlier count of
thirteen read as thirty-seven. A local checkout can also be stale: reading the
candidate file out of `origin/HEAD` is the difference between "this product
restates the taxonomy" and "this directory is out of date", which are opposite
findings about the same bytes.

## Usage

```
node ci/find-implementations.mjs [<root>...]   # default: the parent of this repository
node ci/find-implementations.mjs --unadopted-only
```
