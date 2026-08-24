# Walkthrough: adopting the envelope on a service

One toy service, `shelf`, taken from a hand-rolled failure object to the
fleet envelope, end to end: guard before, migrate, guard after, then real
requests against its edge with the captured answers. Every command and
every output block below was executed against this repository. The service
is JavaScript; the same walk holds for the other runtimes with the
per-runtime pages ([js](integrate/js.md), [python](integrate/python.md),
[rust](integrate/rust.md), [swift](integrate/swift.md)).

## The service before

`shelf` reads objects from its store and, when the store is unreachable,
answers with a failure object it wrote itself — the state most of the
fleet was in, six times over:

```js
// serve.mjs, before adoption
import { createServer } from 'node:http';

const STORE = 'http://127.0.0.1:19799';

const server = createServer(async (request, response) => {
  try {
    const upstream = await fetch(`${STORE}/object`);
    response.writeHead(upstream.status, { 'content-type': 'application/json' });
    response.end(await upstream.text());
  } catch (error) {
    response.writeHead(500, { 'content-type': 'application/json' });
    response.end(JSON.stringify({
      failure_point: 'shelf.store.read',
      error_code: 'store_down',
      severity: 'error',
      detail: String(error),
    }) + '\n');
  }
});

server.listen(9799, '127.0.0.1');
```

Three defects travel in that one literal, and none of them is a typo:
`store_down` is a code nobody can look up, `severity: 'error'` is chosen at
the call site (the catalogue says an unreachable dependency is `critical`),
and `500` is a status ladder of length one.

## Step 1: the guard names the fork

```
$ node ci/no-handrolled-envelope.mjs /tmp/toy-shelf
2 site(s) name an envelope key outside the package:
  /tmp/toy-shelf/serve.mjs:14  failure_point: 'shelf.store.read',
  /tmp/toy-shelf/serve.mjs:15  error_code: 'store_down',

Each needs a reason. Building an envelope here means the derived fields can be
wrong, so build it with wisent-errors instead. Three answers are legitimate and
common: an operator-visible log line whose format is already parsed, a field
declaration, and another API's own `error_code` -- Azure has one, and this guard
cannot tell it from ours. Read the line before believing the count.
```

Exit 1. Both sites here are the real thing, not false positives: a literal
that writes `failure_point` and `error_code` outside the package.

## Step 2: install and migrate

For this run the checkout was linked into `node_modules/@wisent/errors`
(`npm install ../wisent-errors` produces the same layout); a real consumer
pins a commit — `"@wisent/errors": "github:wisent-ai/wisent-errors#<sha>"`
([quick-start](quick-start.md)). The service after:

```js
// serve.mjs, after adoption
import { createServer } from 'node:http';
import { failure, failureOrFallback, render } from '@wisent/errors';
import { httpStatus, fromUpstreamStatus } from '@wisent/errors/codes';

const STORE = 'http://127.0.0.1:19799';
const SERVICE = 'shelf';

function answer(response, envelope) {
  console.error(render(envelope));
  response.writeHead(httpStatus(envelope.error_code), { 'content-type': 'application/json' });
  response.end(JSON.stringify(envelope) + '\n');
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url, `http://${SERVICE}`);
  if (url.pathname !== '/api/object') {
    return answer(response, failure({
      failurePoint: 'shelf.http.route',
      code: 'not_found',
      service: SERVICE,
      detail: `no route for ${url.pathname}`,
    }));
  }
  let upstream;
  try {
    upstream = await fetch(`${STORE}/object`);
  } catch (error) {
    // The store did not answer at all. Nothing here chooses a status or a
    // severity; the code does. The salvage builder, because this is an error
    // path and an error path must not throw.
    return answer(response, failureOrFallback({
      failurePoint: 'shelf.store.read',
      code: 'infra_down',
      service: SERVICE,
      impact: 'one object read',
      detail: error.cause?.message ?? error.message,
    }));
  }
  if (!upstream.ok) {
    // The store answered with a failure status: classify it, quote its words.
    return answer(response, failure({
      failurePoint: 'shelf.store.read',
      code: fromUpstreamStatus(upstream.status),
      service: SERVICE,
      impact: 'one object read',
      detail: `${upstream.status} -- ${(await upstream.text()).trim()}`,
    }));
  }
  response.writeHead(200, { 'content-type': 'application/json' });
  response.end(await upstream.text());
});

server.listen(9799, '127.0.0.1', () => console.error('shelf: listening on 127.0.0.1:9799'));
```

What moved where, per [integration](integration.md): the failure points
stayed (they are shelf's registry); the code, severity, status, and retry
verdict now come from the catalogue; the store's own words go into
`detail` verbatim; the error path uses the salvage builder so it cannot
throw; one `answer` helper is the whole emitter.

## Step 3: the guard again

```
$ node ci/no-handrolled-envelope.mjs /tmp/toy-shelf
no hand-built envelope in /tmp/toy-shelf
```

Exit 0. The service no longer writes an envelope key anywhere: the
builders do.

## Step 4: the store is down — 503, `infra_down`

With nothing listening on the store's port:

```
$ curl -is http://127.0.0.1:9799/api/object
HTTP/1.1 503 Service Unavailable
content-type: application/json

{"failure_point":"shelf.store.read","error_code":"infra_down","service":"shelf","impact":"one object read","severity":"critical","retryable":true,"outage":true,"detail":"connect ECONNREFUSED 127.0.0.1:19799"}
```

The edge status is `httpStatus('infra_down')` = 503, not a hand-chosen
500; the severity is the catalogue's `critical`, not the hand-chosen
`error`; the detail is what the socket layer actually said. The service's
own log got the rendered line:

```
infrastructure we depend on is unreachable — our failure; retry later {"failure_point":"shelf.store.read","error_code":"infra_down","service":"shelf","impact":"one object read","severity":"critical","retryable":true,"outage":true,"detail":"connect ECONNREFUSED 127.0.0.1:19799"}
```

## Step 5: the store throttles — 429, `rate_limit`

With the store answering 429:

```
$ curl -is http://127.0.0.1:9799/api/object
HTTP/1.1 429 Too Many Requests
content-type: application/json

{"failure_point":"shelf.store.read","error_code":"rate_limit","service":"shelf","impact":"one object read","severity":"warning","retryable":true,"outage":false,"detail":"429 -- slow down: shelf quota exhausted for this minute"}
```

`fromUpstreamStatus(429)` classified the store's answer as `rate_limit`,
`httpStatus('rate_limit')` answered 429 at shelf's own edge, and the
store's words crossed both hops uninvented. The log line:

```
an upstream is throttling us — the request or its credentials; retry later {"failure_point":"shelf.store.read","error_code":"rate_limit","service":"shelf","impact":"one object read","severity":"warning","retryable":true,"outage":false,"detail":"429 -- slow down: shelf quota exhausted for this minute"}
```

## Step 6: a wrong route — 404, and the healthy path

```
$ curl -is http://127.0.0.1:9799/api/shelves
HTTP/1.1 404 Not Found
content-type: application/json

{"failure_point":"shelf.http.route","error_code":"not_found","service":"shelf","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":"no route for /api/shelves"}
```

And with the store healthy, nothing of the package is on the path:

```
$ curl -is http://127.0.0.1:9799/api/object
HTTP/1.1 200 OK
content-type: application/json

{"id":"o-1","name":"first object"}
```

## What this bought

Every failure the service can now emit is one of seven codes anyone can
look up; the statuses at its edge come from one table shared by the whole
fleet; its log lines are grep-able render lines carrying the JSON; and the
guard keeps the next hand-rolled literal out of review. The rules behind
each step: [envelope](concepts/envelope.md),
[http-status-and-exit-code](concepts/http-status-and-exit-code.md),
[integration](integration.md); the tools:
[reference/tools](reference/tools.md).
