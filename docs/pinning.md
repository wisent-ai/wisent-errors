# Pinning a revision, and the codes the catalogue holds

How a consumer names the revision it depends on, and why the catalogue holds
the codes it holds.

## Pin the commit

Every consumer names the exact revision in its own dependency spec, not just in a
lockfile:

```
npm    "@wisent/errors": "github:wisent-ai/wisent-errors#<sha>"
cargo  wisent-errors = { git = "https://github.com/wisent-ai/wisent-errors", rev = "<sha>" }
pip    wisent-errors @ git+https://github.com/wisent-ai/wisent-errors@<sha>#subdirectory=python
spm    .package(url: "https://github.com/wisent-ai/wisent-errors", revision: "<sha>")
```

Upgrading therefore costs thirteen deliberate one-line bumps, which is the price
of the guarantee.

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

