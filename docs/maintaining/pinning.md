# Pinning a revision, and the codes the catalogue holds

How a consumer names the revision it depends on, and why the catalogue holds
the codes it holds.

## Pin a commit, or a tag in SwiftPM

Every consumer names the exact revision in its own dependency spec, not just in a
lockfile: npm, cargo and pip by the commit, SwiftPM by the version tag on it.

```
npm    "@wisent/errors": "github:wisent-ai/wisent-errors#<sha>"
cargo  wisent-errors = { git = "https://github.com/wisent-ai/wisent-errors", rev = "<sha>" }
pip    wisent-errors @ git+https://github.com/wisent-ai/wisent-errors@<sha>#subdirectory=python
spm    .package(url: "https://github.com/wisent-ai/wisent-errors.git", exact: "<tag>")
```

SwiftPM pins a tag because it refuses a `revision:` dependency anywhere but in
the root package: a Swift package another one depends on by version (a shared
desktop library an app depends on) cannot itself depend on a commit, so every
SwiftPM consumer names a tag with `exact:`. A version range (`"2.5.0"..<"3.0.0"`)
is not a pin: it leaves the revision to `Package.resolved`, which a resolve
moves; a consumer that holds one moves it to `exact:` when it next bumps. The
tags are `<major>.<minor>.<patch>` with no prefix; Stado's queue cuts them on
the commits it lands and on each commit a dependent's lock pins (its
`version_tags`), and a tag, once pushed, never moves.

The `version` in `package.json`, `rust/Cargo.toml` and `python/pyproject.toml`
stays `1.0.0`, below the tag line (`2.6.x`). Cargo checks it: customer-support-cli,
email-sequencing-cli, humans-cli, kasa, kupiec, most, tama and user-feedback-cli
declare `wisent-errors = { git = …, version = "1.0.0" }`, and cargo refuses a
git source whose crate version does not meet that requirement, so raising it
would refuse each of them at its next lock. It moves only together with those
declarations. No other resolver reads it to choose a revision (npm and pip pin
the commit, SwiftPM the tag), and the queue tags without editing it; it is
never a pin, and `git describe --tags` says exactly where a checkout stands.

Upgrading therefore costs one deliberate one-line bump per consumer, which is
the price of the guarantee.

Consumers may sit on different revisions, and that is stated rather than tidied:
a consumer bumps when the diff it would pick up touches something it calls, and
proves that diff before moving. The catalogue, the schema and the derivations
are what every consumer must agree on; a revision that changes none of them is
inert for a consumer that never calls what it added. An unpinned spec lets a
product pick up a rule change and drop it again with no commit anywhere
recording either move. A lockfile stops a checkout from drifting; it does not
stop the command a person types.

## The eighth code, decided

`oko-desktop` and `wisent-ios` each invented `offline`: retryable, `warning`, and
deliberately not an outage, because a device with no signal must not tell its owner
our infrastructure is down. Two independent inventions clear this package's own bar
for adding something, and adding it would be additive — no consumer emits it, so no
behaviour would move, and both clients could delete about six lines each.

It is still not in the catalogue, for one reason. `http_status` and `exit_code` are
derived for every code, and neither applies to a code no server can observe and no
command can exit with. Putting invented values there is the exact shape of the four
rules this package had to withdraw on its first day. Both clients keep `offline`
beside the seven with the reason written next to it, which costs six lines twice and
invents nothing.

That changes if a third product needs it, or if the catalogue grows a way to say
"this derivation does not apply".

