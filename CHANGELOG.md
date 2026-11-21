# Changelog

## Unreleased

- A rendered failure says its own code's summary and whose it is, so a
  failure that is not an outage no longer reads as a policy refusal of the
  request or its credentials (defect 9594AF64). Proved by
  `tests/envelope/build.rs::each_code_renders_its_own_summary_and_whose_it_is`.
- `telemetry status` names an installation or delivery file it cannot read
  as `{"unreadable": …}` with the refusal's sentence, as `level` and `queued`
  do, instead of `null` (defect ABBA57B5). Proved by
  `tests/telemetry/store.rs::status_names_an_installation_or_delivery_file_it_cannot_read`.
- Turning Swift telemetry off throws the store's refusal when the queue
  cannot be removed instead of dropping it with `try?` (defect EB65B832).
  Proved by
  `tests/telemetry/swift/ConsentAndStoreTests.swift::test_turning_off_names_a_queue_it_cannot_remove`.
- An upstream's 501 and 505 are both `config` in every runtime's catalogue
  (defect 89D58BED). Proved by `tests/upstream/server-side.mjs`.
