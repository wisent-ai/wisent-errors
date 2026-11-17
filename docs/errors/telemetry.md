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
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/telemetry/consent.rs::an_unknown_level_is_refused`

## `wisent-errors.telemetry.deliver`

send every queued event to the collector and drop the ones it accepted

Started through: Rust `<product> telemetry flush`, Rust `Telemetry::flush`, Rust `Telemetry::spawn_flush`, Swift `WisentTelemetry.flush`, Swift `WisentTelemetry.flushInBackground`. Uses: `wisent-errors.telemetry.store`.

<a id="wisent-errors-telemetry-deliver-collector-invalid"></a>

### `wisent-errors.telemetry.deliver.collector-invalid`

- **What failed:** reading the collector address from {source}
- **Cause:** a collector address must be https://, or http:// on a loopback host
- **Observed state shown:** {source} holds {address}
- **Fix:** set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it
- **Code:** `config`, exit 1
- **Test:** Rust `tests/telemetry/delivery.rs::a_plain_http_collector_is_refused_by_name`, Swift `tests/telemetry/swift/TelemetryTests.swift::testAPlainHttpCollectorIsRefusedByName`

<a id="wisent-errors-telemetry-deliver-collector-refused"></a>

### `wisent-errors.telemetry.deliver.collector-refused`

- **What failed:** sending event {event} to {collector}
- **Cause:** the collector refused HTTP {status}: {answer}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** the answer names what the collector refuses; when it is Unknown mobile analytics app, declare app {app} in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON; the events are sent again on the next flush
- **Code:** `refused`, exit 1
- **Test:** Rust `tests/telemetry/delivery.rs::an_app_the_collector_does_not_declare_stays_queued_with_its_refusal`, Swift `tests/telemetry/swift/TelemetryTests.swift::testAnAppTheCollectorDoesNotDeclareStaysQueuedWithItsRefusal`

<a id="wisent-errors-telemetry-deliver-collector-failed"></a>

### `wisent-errors.telemetry.deliver.collector-failed`

- **What failed:** sending event {event} to {collector}
- **Cause:** the collector failed on its own side, HTTP {status}: {answer}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `{product} support report`, or from an app's Help → Report a Problem
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/delivery.rs::a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure`, Swift `tests/telemetry/swift/TelemetryTests.swift::testACollectorFailingOnItsSideKeepsTheEventsWithItsOwnFailure`

<a id="wisent-errors-telemetry-deliver-collector-unreachable"></a>

### `wisent-errors.telemetry.deliver.collector-unreachable`

- **What failed:** sending event {event} to {collector}
- **Cause:** the collector could not be reached: {why}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** nothing to do: the events are sent on the next flush once the network or the collector is back
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/delivery.rs::an_unreachable_collector_keeps_the_events`, Swift `tests/telemetry/swift/TelemetryTests.swift::testAnUnreachableCollectorKeepsTheEvents`

<a id="wisent-errors-telemetry-deliver-collector-answer-unreadable"></a>

### `wisent-errors.telemetry.deliver.collector-answer-unreadable`

- **What failed:** reading the collector's answer to event {event}
- **Cause:** the answer is not the collector's {accepted}: {answer}
- **Observed state shown:** HTTP {status} from {collector}
- **Fix:** check that {collector} is the Echo app collector, /api/analytics/mobile/collect
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/delivery.rs::an_address_that_is_not_a_collector_is_named`, Swift `tests/telemetry/swift/TelemetryTests.swift::testAnAddressThatIsNotACollectorIsNamed`

<a id="wisent-errors-telemetry-deliver-flush-unstarted"></a>

### `wisent-errors.telemetry.deliver.flush-unstarted`

- **What failed:** starting {program} to send the queued events
- **Cause:** the process could not be started: {why}
- **Observed state shown:** {queued} event(s) stay queued
- **Fix:** run `{product} telemetry flush` yourself; the events wait until it runs
- **Code:** `config`, exit 1
- **Test:** Rust `tests/telemetry/delivery.rs::a_flush_that_cannot_start_is_named`

## `wisent-errors.support.report`

file a support report from this installation and keep the key that reads it back

Started through: Rust `<product> support report`, Rust `Telemetry::file_report`, Swift `WisentTelemetry.fileReport`. Uses: `wisent-errors.support.exchange`, `wisent-errors.telemetry.store`.

<a id="wisent-errors-support-report-support-description-empty"></a>

### `wisent-errors.support.report.support-description-empty`

- **What failed:** filing a support report
- **Cause:** the report has no description
- **Observed state shown:** the description is empty
- **Fix:** say what you were doing and what happened: `{product} support report --description "…"`
- **Code:** `refused`, exit 2
- **Test:** Rust `tests/telemetry/support.rs::a_report_without_a_description_is_refused_before_sending`, Swift `tests/telemetry/swift/SupportTests.swift::testAReportWithoutADescriptionIsRefusedBeforeSending`

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
- **Code:** `config`, exit 1
- **Test:** Rust `tests/telemetry/store.rs::an_unwritable_directory_is_named_and_nothing_is_lost_silently`, Swift `tests/telemetry/swift/TelemetryTests.swift::testAnUnwritableDirectoryIsNamedAndNothingIsLostSilently`

<a id="wisent-errors-telemetry-store-file-unreadable"></a>

### `wisent-errors.telemetry.store.file-unreadable`

- **What failed:** reading {what} from {path}
- **Cause:** the file is not what telemetry wrote: {why}
- **Observed state shown:** the file holds {bytes} bytes
- **Fix:** answer again with `{product} telemetry on|off`, which rewrites it, or remove {path}
- **Code:** `config`, exit 1
- **Test:** Rust `tests/telemetry/consent.rs::a_damaged_consent_file_is_refused_and_nothing_is_sent`, Swift `tests/telemetry/swift/TelemetryTests.swift::testADamagedConsentFileIsRefusedAndNothingIsSent`

## `wisent-errors.support.exchange`

find the support address, send support one request and read its answer

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent-errors-support-exchange-support-address-invalid"></a>

### `wisent-errors.support.exchange.support-address-invalid`

- **What failed:** reading the support address from WISENT_SUPPORT_URL
- **Cause:** a support address must be https://, or http:// on a loopback host
- **Observed state shown:** WISENT_SUPPORT_URL holds {address}
- **Fix:** set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it
- **Code:** `config`, exit 1
- **Test:** Rust `tests/telemetry/support.rs::a_plain_http_support_address_is_refused_by_name`, Swift `tests/telemetry/swift/SupportTests.swift::testAPlainHttpSupportAddressIsRefusedByName`

<a id="wisent-errors-support-exchange-support-refused"></a>

### `wisent-errors.support.exchange.support-refused`

- **What failed:** {doing} at {address}
- **Cause:** support refused HTTP {status}: {answer}
- **Observed state shown:** {observed}
- **Fix:** the answer is support's own reason: correct what it names and run the command again
- **Code:** `refused`, exit 1
- **Test:** Rust `tests/telemetry/support.rs::a_report_support_refuses_says_why`, Swift `tests/telemetry/swift/SupportTests.swift::testAReportSupportRefusesSaysWhyAndKeepsNothing`

<a id="wisent-errors-support-exchange-support-unreachable"></a>

### `wisent-errors.support.exchange.support-unreachable`

- **What failed:** {doing} at {address}
- **Cause:** support could not be reached: {why}
- **Observed state shown:** {observed}
- **Fix:** run the command again once the network or support is back
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/support.rs::an_unreachable_support_files_nothing`, Swift `tests/telemetry/swift/SupportTests.swift::testAnUnreachableSupportFilesNothing`

<a id="wisent-errors-support-exchange-support-answer-unreadable"></a>

### `wisent-errors.support.exchange.support-answer-unreadable`

- **What failed:** reading support's answer at {address}
- **Cause:** the answer is not a support service's: {answer}
- **Observed state shown:** HTTP {status}
- **Fix:** check that {address} is a support service's /v1/public/reports
- **Code:** `infra_down`, exit 69
- **Test:** Rust `tests/telemetry/support.rs::an_address_that_is_not_support_is_named`, Swift `tests/telemetry/swift/SupportTests.swift::testAnAddressThatIsNotSupportIsNamed`
