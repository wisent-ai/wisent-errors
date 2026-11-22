<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: telemetry

Every way the telemetry functionalities of this package fail, as their refusals say it.

## `wisent-errors.telemetry.record`

queue one event an installed copy will send, at the level the user chose

Started through: `Telemetry::failure`, `Telemetry::command`. Uses: `wisent-errors.telemetry.store`.

## `wisent-errors.telemetry.consent`

keep the level of telemetry the user chose

Started through: `<product> telemetry on|off`, `Telemetry::ask`, `Telemetry::set_level`. Uses: `wisent-errors.telemetry.store`.

<a id="wisent-errors-telemetry-consent-level-unknown"></a>

### `wisent-errors.telemetry.consent.level-unknown`

- **What failed:** setting the telemetry level to {level}
- **Cause:** telemetry knows the levels off, errors and usage
- **Observed state shown:** got {level}
- **Fix:** name one of off, errors or usage
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events`

## `wisent-errors.telemetry.export`

write every queued event to a file the user names, as it would be sent, for a machine with no network

Started through: `<product> telemetry export`, `Telemetry::export`. Uses: `wisent-errors.telemetry.store`.

<a id="wisent-errors-telemetry-export-export-unwritable"></a>

### `wisent-errors.telemetry.export.export-unwritable`

- **What failed:** writing the {count} queued event(s) to {path}
- **Cause:** the file could not be written: {why}
- **Observed state shown:** {state}; the events stay queued
- **Fix:** name a file in a directory this user can write, as in `{product} telemetry export ./events.json`
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/store.rs::telemetry_export_writes_the_queue_as_it_will_be_sent`

## `wisent-errors.telemetry.deliver`

send every queued event to the collector and drop the ones it accepted

Started through: Rust `<product> telemetry flush`, Rust `Telemetry::flush`, Rust `Telemetry::spawn_flush`, Swift `WisentTelemetry.flush`, Swift `WisentTelemetry.flushInBackground`. Uses: `wisent-errors.telemetry.store`.

<a id="wisent-errors-telemetry-deliver-collector-invalid"></a>

### `wisent-errors.telemetry.deliver.collector-invalid`

- **What failed:** reading the collector address from {source}
- **Cause:** a collector address must be https://, or http:// on a loopback host
- **Observed state shown:** {source} holds {address}
- **Fix:** set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/delivery/unreached.rs::a_plain_http_collector_is_refused_by_name`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_keeps_what_no_collector_took_with_why`

<a id="wisent-errors-telemetry-deliver-collector-refused"></a>

### `wisent-errors.telemetry.deliver.collector-refused`

- **What failed:** sending event {event} to {collector}
- **Cause:** the collector refused HTTP {status}: {answer}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app {app} in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush
- **Class:** `refused`, exit 1
- **Test:** Rust `tests/telemetry/delivery/reached.rs::an_app_the_collector_does_not_declare_stays_queued_with_its_refusal`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_delivers_to_the_real_collector_or_keeps_its_refusal`

<a id="wisent-errors-telemetry-deliver-collector-failed"></a>

### `wisent-errors.telemetry.deliver.collector-failed`

- **What failed:** sending event {event} to {collector}
- **Cause:** the collector failed on its own side, HTTP {status}: {answer}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `{product} support report`, or from an app's Help → Report a Problem
- **Class:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/delivery/reached.rs::a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_keeps_the_events_a_collector_failing_on_its_side_did_not_take`

<a id="wisent-errors-telemetry-deliver-collector-unreachable"></a>

### `wisent-errors.telemetry.deliver.collector-unreachable`

- **What failed:** sending event {event} to {collector}
- **Cause:** the collector could not be reached: {why}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** nothing to do: the events are sent on the next flush once the network or the collector is back
- **Class:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/delivery/unreached.rs::an_unreachable_collector_keeps_the_events`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_keeps_what_no_collector_took_with_why`

<a id="wisent-errors-telemetry-deliver-collector-answer-unreadable"></a>

### `wisent-errors.telemetry.deliver.collector-answer-unreadable`

- **What failed:** reading the collector's answer to event {event}
- **Cause:** the answer is not the collector's {accepted}: {answer}
- **Observed state shown:** HTTP {status} from {collector}
- **Fix:** check that {collector} is the Echo app collector, /api/analytics/mobile/collect
- **Class:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/delivery/reached.rs::an_address_that_is_not_a_collector_is_named`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_delivers_to_the_real_collector_or_keeps_its_refusal`

<a id="wisent-errors-telemetry-deliver-flush-unstarted"></a>

### `wisent-errors.telemetry.deliver.flush-unstarted`

- **What failed:** starting {program} to send the queued events
- **Cause:** the process could not be started: {why}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** run `{product} telemetry flush` yourself; the events wait until it runs
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/delivery/unreached.rs::a_flush_that_cannot_start_is_named`

## `wisent-errors.support.report`

file a support report from this installation and keep the key that reads it back

Started through: Rust `<product> support report`, Rust `Telemetry::file_report`, Swift `WisentTelemetry.fileReport`. Uses: `wisent-errors.support.exchange`, `wisent-errors.telemetry.store`.

<a id="wisent-errors-support-report-support-description-empty"></a>

### `wisent-errors.support.report.support-description-empty`

- **What failed:** filing a support report
- **Cause:** the report has no description
- **Observed state shown:** the description is empty
- **Fix:** say what you were doing and what happened: in an app's Report a Problem window, or with `{product} support report --description "…"`
- **Class:** `usage`, exit 2
- **Test:** Rust `tests/telemetry/support.rs::support_report_refuses_what_it_cannot_file_before_anything_is_kept`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_report_refuses_what_cannot_be_filed_and_files_nothing`

## `wisent-errors.support.status`

read each report this installation filed back from support: its state and the replies

Started through: `<product> support status`, `Telemetry::reports`. Uses: `wisent-errors.support.exchange`, `wisent-errors.telemetry.store`.

## `wisent-errors.telemetry.store`

keep the files telemetry writes (the consent, the installation id, the queue, the last delivery, the keys of support reports) and read them back

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent-errors-telemetry-store-store-unwritable"></a>

### `wisent-errors.telemetry.store.store-unwritable`

- **What failed:** keeping {what} in {path}
- **Cause:** the telemetry directory could not be written: {why}
- **Observed state shown:** directory {directory}
- **Fix:** make {directory} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events`, Swift `tests/telemetry/swift/ConsentAndStoreTests.swift::test_telemetry_set_keeps_the_answer_the_app_and_the_command_line_share`

<a id="wisent-errors-telemetry-store-home-unset"></a>

### `wisent-errors.telemetry.store.home-unset`

- **What failed:** finding where to keep {what}
- **Cause:** telemetry keeps its files in WISENT_TELEMETRY_HOME, else under XDG_STATE_HOME, else under HOME, and none of the three is set
- **Observed state shown:** WISENT_TELEMETRY_HOME, XDG_STATE_HOME and HOME are all unset in the environment {product} ran with
- **Fix:** run {product} with HOME set to the user's home directory, or name the directory telemetry keeps its files in with WISENT_TELEMETRY_HOME
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events`

<a id="wisent-errors-telemetry-store-file-is-directory"></a>

### `wisent-errors.telemetry.store.file-is-directory`

- **What failed:** keeping {what} in {path}
- **Cause:** a directory stands where telemetry keeps that file, so the file cannot be written there
- **Observed state shown:** {path} is a directory
- **Fix:** move the directory {path} out of the way, and telemetry writes the file there again; or name another telemetry directory with WISENT_TELEMETRY_HOME
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events`

<a id="wisent-errors-telemetry-store-file-unreadable"></a>

### `wisent-errors.telemetry.store.file-unreadable`

- **What failed:** reading {what} from {path}
- **Cause:** the file is not what telemetry wrote: {why}
- **Observed state shown:** the file holds {bytes} bytes
- **Fix:** answer again, in an app's settings or with `{product} telemetry on|off`, which rewrites it, or remove {path}
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/store.rs::telemetry_status_says_every_file_as_it_finds_it`, Swift `tests/telemetry/swift/ConsentAndStoreTests.swift::test_telemetry_failure_queues_only_what_the_user_agreed_to_send`

<a id="wisent-errors-telemetry-store-support-key-unreadable"></a>

### `wisent-errors.telemetry.store.support-key-unreadable`

- **What failed:** reading {what} from {path}
- **Cause:** the file is not the key filing a report kept: {why}
- **Observed state shown:** the file holds {bytes} bytes
- **Fix:** remove {path} and file the report again, with `{product} support report` or from an app's Report a Problem window, which keeps the new report's key; the replies to the report that file held the key of cannot be read without that key
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/support.rs::support_status_names_a_key_file_it_did_not_write`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_status_reads_the_reports_kept_or_names_a_key_it_cannot`

<a id="wisent-errors-telemetry-store-support-key-read-refused"></a>

### `wisent-errors.telemetry.store.support-key-read-refused`

- **What failed:** reading {what} from {path}
- **Cause:** the operating system refused the read, so the key it keeps for the report was never looked at
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running {product} read it (chmod u+r {path}): it holds the only copy of the report's key, which reads its replies; nothing in {product} writes it again, so if it cannot be read, remove {path} and file the report again with `{product} support report` or from an app's Report a Problem window
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/support.rs::support_status_names_a_key_file_it_did_not_write`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_status_reads_the_reports_kept_or_names_a_key_it_cannot`

<a id="wisent-errors-telemetry-store-queued-event-unreadable"></a>

### `wisent-errors.telemetry.store.queued-event-unreadable`

- **What failed:** reading {what} from {path}
- **Cause:** the file is not an event telemetry queued: {why}
- **Observed state shown:** the file holds {bytes} bytes
- **Fix:** remove {path}: the event it held is lost, as nothing in {product} queues it again, and the events beside it are sent as they were
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/queued/events.rs::telemetry_show_prints_the_queue_each_event_as_declared`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_show_prints_the_queue_exactly_as_it_will_go`

<a id="wisent-errors-telemetry-store-queued-event-read-refused"></a>

### `wisent-errors.telemetry.store.queued-event-read-refused`

- **What failed:** reading {what} from {path}
- **Cause:** the operating system refused the read, so the event it holds was never looked at
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running {product} read it (chmod u+r {path}) so the event is sent; or remove {path}, and the event it held is lost, as nothing in {product} queues it again
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/queued/events.rs::telemetry_show_prints_the_queue_each_event_as_declared`, Swift `tests/telemetry/swift/DeliveryTests.swift::test_telemetry_show_prints_the_queue_exactly_as_it_will_go`

<a id="wisent-errors-telemetry-store-file-read-refused"></a>

### `wisent-errors.telemetry.store.file-read-refused`

- **What failed:** reading {what} from {path}
- **Cause:** the operating system refused the read, so what the file holds was never looked at
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running {product} read it (chmod u+r {path}), or remove {path} so telemetry writes it again
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/store.rs::telemetry_status_says_every_file_as_it_finds_it`, Swift `tests/telemetry/swift/ConsentAndStoreTests.swift::test_telemetry_status_says_the_installation_as_its_files_hold_it`

## `wisent-errors.support.exchange`

find the support address, send support one request and read its answer

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent-errors-support-exchange-support-address-invalid"></a>

### `wisent-errors.support.exchange.support-address-invalid`

- **What failed:** reading the support address from WISENT_SUPPORT_URL
- **Cause:** a support address must be https://, or http:// on a loopback host
- **Observed state shown:** WISENT_SUPPORT_URL holds {address}
- **Fix:** set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it
- **Class:** `config`, exit 1
- **Test:** Rust `tests/telemetry/support.rs::support_report_refuses_what_it_cannot_file_before_anything_is_kept`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_report_refuses_what_cannot_be_filed_and_files_nothing`

<a id="wisent-errors-support-exchange-support-refused"></a>

### `wisent-errors.support.exchange.support-refused`

- **What failed:** {doing} at {address}
- **Cause:** support refused HTTP {status}: {answer}
- **Observed state shown:** {observed}
- **Fix:** the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `{product} support report`
- **Class:** `refused`, exit 1
- **Test:** Rust `tests/telemetry/support.rs::support_report_files_with_the_real_support_and_keeps_its_key`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_report_files_to_the_real_service_or_says_what_it_refused`

<a id="wisent-errors-support-exchange-support-unreachable"></a>

### `wisent-errors.support.exchange.support-unreachable`

- **What failed:** {doing} at {address}
- **Cause:** support could not be reached: {why}
- **Observed state shown:** {observed}
- **Fix:** send the report again once the network or support is back, from an app's Report a Problem window or with `{product} support report`
- **Class:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/support.rs::support_report_refuses_what_it_cannot_file_before_anything_is_kept`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_report_refuses_what_cannot_be_filed_and_files_nothing`

<a id="wisent-errors-support-exchange-support-answer-unreadable"></a>

### `wisent-errors.support.exchange.support-answer-unreadable`

- **What failed:** reading support's answer at {address}
- **Cause:** the answer is not a support service's: {answer}
- **Observed state shown:** HTTP {status}
- **Fix:** check that {address} is a support service's /v1/public/reports
- **Class:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/support.rs::support_report_names_an_address_that_is_not_support`, Swift `tests/telemetry/swift/SupportReportTests.swift::test_support_report_names_the_status_of_an_answer_that_holds_no_key`
