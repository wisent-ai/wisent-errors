# Changelog

## Unreleased

- A rendered failure says its own code's summary and whose it is, so a
  failure that is not an outage no longer reads as a policy refusal of the
  request or its credentials. Proved by
  `tests/envelope/build.rs::each_code_renders_its_own_summary_and_whose_it_is`.
- `telemetry status` names an installation or delivery file it cannot read
  as `{"unreadable": …}` with the refusal's sentence, as `level` and `queued`
  do, instead of `null`. Proved by
  `tests/telemetry/store.rs::telemetry_status_says_every_file_as_it_finds_it`.
- Turning Swift telemetry off throws the store's refusal when the queue
  cannot be removed instead of dropping it with `try?`.
  Proved by
  `tests/telemetry/swift/ConsentAndStoreTests.swift::test_turning_off_names_a_queue_it_cannot_remove`.
- An upstream's 501 and 505 are both `config` in every runtime's catalogue.
  Proved by `tests/upstream/server-side.mjs`.
