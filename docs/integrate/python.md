# Integrating the Python runtime

The package is `wisent-errors` (import name `wisent_errors`), living under
`python/` — hence the `subdirectory` in the pip spec. It requires Python
≥ 3.9 and carries zero dependencies. Two modules: `wisent_errors` (builders,
render, chain, trims, plus re-exported catalogue functions) and
`wisent_errors.codes` (the generated catalogue module alone).

## Install

Pin the exact commit in the requirement itself:

```
wisent-errors @ git+https://github.com/wisent-ai/wisent-errors@<sha>#subdirectory=python
```

A local path install works the same and is how the runs below were produced;
both were executed:

```bash
pip install /path/to/wisent-errors/python
```

```
$ python -c "import wisent_errors, json; print(json.dumps(wisent_errors.failure(
    failure_point='toy.first', code='config', service='toy', detail='TOY_TOKEN is unset')))"
{"failure_point": "toy.first", "error_code": "config", "service": "toy", "impact": null, "severity": "critical", "retryable": false, "outage": true, "detail": "TOY_TOKEN is unset"}
```

## A complete example, executed

```python
from wisent_errors import failure, failure_or_fallback, render, chain
from wisent_errors.codes import from_upstream_status, exit_code, code_or_none, RETRY_EXIT

refused = failure(
    failure_point="toy.vault.read",
    code="infra_down",
    service="toy",
    detail="connection refused (127.0.0.1:9700)",
)
envelope = failure(
    failure_point="toy.job.credentials",
    code="infra_down",
    service="toy",
    impact="every job this worker claims",
    detail="secret resolution failed",
    cause=refused,
    context={"job": "j-3f21"},
)
print("render:", render(envelope))
for row in chain(envelope):
    print("  " + row)
```

Output, verbatim:

```
render: infrastructure we depend on is unreachable — our failure; retry later {"failure_point":"toy.job.credentials","error_code":"infra_down","service":"toy","impact":"every job this worker claims","severity":"critical","retryable":true,"outage":true,"detail":"secret resolution failed","cause":{"failure_point":"toy.vault.read","error_code":"infra_down","service":"toy","impact":null,"severity":"critical","retryable":true,"outage":true,"detail":"connection refused (127.0.0.1:9700)"},"context":{"job":"j-3f21"}}
  toy.job.credentials [infra_down] secret resolution failed
  toy.vault.read [infra_down] connection refused (127.0.0.1:9700)
```

And the rest of the surface, from the same executed session:

```
from_upstream_status(407): auth
from_upstream_status(501): config
exit_code('infra_down', 3): 69 (RETRY_EXIT = 69)
exit_code('not_found', 3): 3
code_or_none('offline'): None
trim_detail('  padded detail  ', 300): 'padded detail'
strict refusal: failure_point 'Not A Point' is not a dotted lowercase path
strict refusal: code 'panic' is not in the catalogue; one of config, auth, not_found, rate_limit, timeout, infra_down, unknown
salvaged: {"failure_point":"unknown","error_code":"unknown","service":"unknown","impact":null,"severity":"error","retryable":false,"outage":false,"detail":null,"context":{"wisent_errors.failure_point":"absent","wisent_errors.error_code":"off-catalogue: panic","wisent_errors.service":"absent"}}
```

The runnable script is [examples/first_envelope.py](../examples/first_envelope.py).

## Python-specific behaviour worth knowing

- **All builder arguments are keyword-only** (`failure(*, failure_point,
  code, service, impact=None, detail=None, cause=None, context=None)`).
- Envelopes are plain `dict`s; `cause` and `context` are shallow-copied with
  `dict(...)`.
- The strict builder raises `TypeError` with the exact sentences
  `failure_point {point!r} is not a dotted lowercase path`, `code {code!r}
  is not in the catalogue; one of ...`, and `{field} must be a non-empty
  string` for `failure_point`, `service`, or a provided `detail` that is not
  a non-empty `str`.
- `raise_failure(**fields)` raises `FailureError`, which carries a copy of
  the envelope as `.envelope`.
- `render` serializes with `separators=(",", ":")` and `ensure_ascii=False`
  so its JSON half is byte-identical to the other runtimes.
- The salvage builder `failure_or_fallback(**fields)` accepts anything;
  non-string values are coerced through `str()` by `_optional`, an unknown
  or non-string `code` becomes `unknown` and is recorded as
  `wisent_errors.error_code: "off-catalogue: <code>"` (or `"absent"` for
  `None`).

## Guard your tree

```bash
node ci/no-handrolled-envelope.mjs <your-source-tree>
```

The guard and census contracts are in [reference/tools](../reference/tools.md);
the full API is [reference/python](../reference/python.md); the adoption
strategy (what to delete, what to keep) is [integration](../integration.md).
