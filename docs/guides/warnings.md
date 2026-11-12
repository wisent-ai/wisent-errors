# Declared warnings

What a functionality does that its caller must know before it runs, declared
beside its causes. The README states how causes are declared; this page is the
same for warnings.

## Every functionality that loses its caller something declares a warning

A failure catalogue says how a functionality can go wrong. A warning says what
it does when it goes right and its caller still loses something, so the caller
reads it before confirming: an item purged for good, every consumer's grant
withdrawn, a secret written to a plain-text file, a password changed at its
provider, money spent. It is declared on the same `Operation`, beside the
causes, in `warnings`:

```rust
use wisent_errors::{Hazard, Operation, Warning};

pub static REMOVED_FOR_GOOD: Warning = Warning {
    id: "removed-for-good",
    hazard: Hazard::Irreversible,
    effect: "{id} and every saved version of it are removed",
    consequence: "nothing restores them, not restore and not restore --at",
    safeguard: "keep a copy with `skarbiec backup <directory>`, which `skarbiec backup restore` puts back",
    confirm: "rerun with --yes",
    test: "tests/purge/purge.sh::purge_without_yes_removes_nothing",
};
```

`hazard` is one of six, each a loss the caller cannot take back by running
another command of the same product:

| hazard | the functionality |
|---|---|
| `irreversible` | removes or rewrites something nothing in the product restores afterwards |
| `overwrites` | puts something else in place of the current state; what it replaces is kept only where the warning says |
| `cuts-off-access` | takes access a person or a program has now |
| `exposes-secret` | lets a secret value leave the place that protects it: a plain-text file, a screen, another person or system |
| `external-change` | changes a system outside the product, which the product cannot undo |
| `costs-money` | spends money |

Most functionalities declare none, and that is the rule, not a gap: a warning
on an ordinary read or a recoverable edit teaches its reader to confirm
without reading, which is the one thing a warning exists to prevent. A
functionality warns exactly when it asks for a confirmation, and asks for one
exactly when it warns.

One declaration gives everything a warning is shown as:

- before confirming: `Warning::unconfirmed(values)` is `<effect>;
  <consequence>; nothing was done. Before confirming: <safeguard>. To go
  ahead: <confirm>`, answered only when the functionality did nothing;
  `sentence`, `safeguard` and `confirmation` give the parts to a confirming
  dialog;
- the listing a product prints from `<product> warnings list|show`
  (`Operation::warnings_json(page)`: `operation`, `entries`, `summary`,
  `warnings`, each with its `doc` anchor on the product's warnings page) and
  that page (`Operation::warnings_markdown`, empty for a functionality that
  warns of nothing).

`Operation::problems` refuses a warning that is not one: an empty `effect`,
`consequence`, `safeguard` or `confirm`, a generic sentence in any of them, a
test that is not `tests/<area>/<file>::<name>`, a malformed or duplicate id.
A JavaScript product declares the same objects and `@wisent/errors` gives it
`HAZARDS`, `warningSentence`, `unconfirmed`, `warningAnchor`,
`warningProblems`, `warningsCatalogue(operation, page)` and
`warningsMarkdown`, with the same rules and the same JSON. A Swift product
declares `Warning(id:hazard:effect:consequence:safeguard:confirm:test:)` in
`Operation(..., warnings:)` and gets `sentence`, `safeguarding`,
`confirmation`, `unconfirmed`, `anchor`, `warningsJSON(page:)` and
`warningsMarkdown()`; a Python product declares `Warning` in
`Operation(warnings=...)`, held to the same rules by `Operation.problems()`.

`ci/warning-standard.mjs` holds a product to it:

```
$ node ci/warning-standard.mjs warnings.json --repository ../skarbiec --confirmations confirmations.json
ok    skarbiec.item.purge: 3 declared warning(s)
```

It applies the declaration rules to the product's `warnings list --json`; with
`--repository` it reads each warning's test; with `--confirmations`, a JSON
list of every entry that asks for a confirmation before it acts, it refuses an
entry that asks while no functionality it starts declares what for, and a
functionality that warns while none of its entries asks, so the warning is
never read before it runs.

