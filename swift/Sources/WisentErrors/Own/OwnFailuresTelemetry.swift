// Generated from catalogue/failures/telemetry.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

extension OwnFailures {
    public static let telemetryDeliverCollectorInvalid = Cause(
        id: "collector-invalid", code: .config, usage: false, exit: nil,
        failed: "reading the collector address from {source}",
        cause: "a collector address must be https://, or http:// on a loopback host",
        observed: "{source} holds {address}",
        remedy: "set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_keeps_what_no_collector_took_with_why"
    )

    public static let telemetryDeliverCollectorRefused = Cause(
        id: "collector-refused", code: .refused, usage: false, exit: nil,
        failed: "sending event {event} to {collector}",
        cause: "the collector refused HTTP {status}: {answer}",
        observed: "{queued} event(s) stay queued",
        remedy: "the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app {app} in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_delivers_to_the_real_collector_or_keeps_its_refusal"
    )

    public static let telemetryDeliverCollectorFailed = Cause(
        id: "collector-failed", code: .infraDown, usage: false, exit: nil,
        failed: "sending event {event} to {collector}",
        cause: "the collector failed on its own side, HTTP {status}: {answer}",
        observed: "{queued} event(s) stay queued",
        remedy: "nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `{product} support report`, or from an app's Help → Report a Problem",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_keeps_the_events_a_collector_failing_on_its_side_did_not_take"
    )

    public static let telemetryDeliverCollectorUnreachable = Cause(
        id: "collector-unreachable", code: .infraDown, usage: false, exit: nil,
        failed: "sending event {event} to {collector}",
        cause: "the collector could not be reached: {why}",
        observed: "{queued} event(s) stay queued",
        remedy: "nothing to do: the events are sent on the next flush once the network or the collector is back",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_keeps_what_no_collector_took_with_why"
    )

    public static let telemetryDeliverCollectorAnswerUnreadable = Cause(
        id: "collector-answer-unreadable", code: .infraDown, usage: false, exit: nil,
        failed: "reading the collector's answer to event {event}",
        cause: "the answer is not the collector's {accepted}: {answer}",
        observed: "HTTP {status} from {collector}",
        remedy: "check that {collector} is the Echo app collector, /api/analytics/mobile/collect",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_flush_delivers_to_the_real_collector_or_keeps_its_refusal"
    )

    public static let telemetryDeliver = Operation(
        id: "wisent-errors.telemetry.deliver",
        entries: ["WisentTelemetry.flush", "WisentTelemetry.flushInBackground"],
        uses: [telemetryStore],
        summary: "send every queued event to the collector and drop the ones it accepted",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
        causes: [telemetryDeliverCollectorInvalid, telemetryDeliverCollectorRefused, telemetryDeliverCollectorFailed, telemetryDeliverCollectorUnreachable, telemetryDeliverCollectorAnswerUnreadable]
    )

    public static let supportReportSupportDescriptionEmpty = Cause(
        id: "support-description-empty", code: .refused, usage: true, exit: nil,
        failed: "filing a support report",
        cause: "the report has no description",
        observed: "the description is empty",
        remedy: "say what you were doing and what happened: in an app's Report a Problem window, or with `{product} support report --description \"…\"`",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_report_refuses_what_cannot_be_filed_and_files_nothing"
    )

    public static let supportReport = Operation(
        id: "wisent-errors.support.report",
        entries: ["WisentTelemetry.fileReport"],
        uses: [supportExchange, telemetryStore],
        summary: "file a support report from this installation and keep the key that reads it back",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
        causes: [supportReportSupportDescriptionEmpty]
    )

    public static let telemetryStoreStoreUnwritable = Cause(
        id: "store-unwritable", code: .config, usage: false, exit: nil,
        failed: "keeping {what} in {path}",
        cause: "the telemetry directory could not be written: {why}",
        observed: "directory {directory}",
        remedy: "make {directory} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME",
        test: "tests/telemetry/swift/ConsentAndStoreTests.swift::test_telemetry_set_keeps_the_answer_the_app_and_the_command_line_share"
    )

    public static let telemetryStoreFileUnreadable = Cause(
        id: "file-unreadable", code: .config, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the file is not what telemetry wrote: {why}",
        observed: "the file holds {bytes} bytes",
        remedy: "answer again, in an app's settings or with `{product} telemetry on|off`, which rewrites it, or remove {path}",
        test: "tests/telemetry/swift/ConsentAndStoreTests.swift::test_telemetry_failure_queues_only_what_the_user_agreed_to_send"
    )

    public static let telemetryStoreSupportKeyUnreadable = Cause(
        id: "support-key-unreadable", code: .config, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the file is not the key filing a report kept: {why}",
        observed: "the file holds {bytes} bytes",
        remedy: "remove {path} and file the report again, with `{product} support report` or from an app's Report a Problem window, which keeps the new report's key; the replies to the report that file held the key of cannot be read without that key",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_status_reads_the_reports_kept_or_names_a_key_it_cannot"
    )

    public static let telemetryStoreSupportKeyReadRefused = Cause(
        id: "support-key-read-refused", code: .config, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the operating system refused the read, so the key it keeps for the report was never looked at",
        observed: "{state}; the operating system answered {error}",
        remedy: "let the user running {product} read it (chmod u+r {path}): it holds the only copy of the report's key, which reads its replies; nothing in {product} writes it again, so if it cannot be read, remove {path} and file the report again with `{product} support report` or from an app's Report a Problem window",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_status_reads_the_reports_kept_or_names_a_key_it_cannot"
    )

    public static let telemetryStoreQueuedEventUnreadable = Cause(
        id: "queued-event-unreadable", code: .config, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the file is not an event telemetry queued: {why}",
        observed: "the file holds {bytes} bytes",
        remedy: "remove {path}: the event it held is lost, as nothing in {product} queues it again, and the events beside it are sent as they were",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_show_prints_the_queue_exactly_as_it_will_go"
    )

    public static let telemetryStoreQueuedEventReadRefused = Cause(
        id: "queued-event-read-refused", code: .config, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the operating system refused the read, so the event it holds was never looked at",
        observed: "{state}; the operating system answered {error}",
        remedy: "let the user running {product} read it (chmod u+r {path}) so the event is sent; or remove {path}, and the event it held is lost, as nothing in {product} queues it again",
        test: "tests/telemetry/swift/DeliveryTests.swift::test_telemetry_show_prints_the_queue_exactly_as_it_will_go"
    )

    public static let telemetryStoreFileReadRefused = Cause(
        id: "file-read-refused", code: .config, usage: false, exit: nil,
        failed: "reading {what} from {path}",
        cause: "the operating system refused the read, so what the file holds was never looked at",
        observed: "{state}; the operating system answered {error}",
        remedy: "let the user running {product} read it (chmod u+r {path}), or remove {path} so telemetry writes it again",
        test: "tests/telemetry/swift/ConsentAndStoreTests.swift::test_telemetry_status_says_the_installation_as_its_files_hold_it"
    )

    public static let telemetryStore = Operation(
        id: "wisent-errors.telemetry.store",
        entries: [],
        uses: [],
        summary: "keep the files telemetry writes (the consent, the installation id, the queue, the last delivery, the keys of support reports) and read them back",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
        causes: [telemetryStoreStoreUnwritable, telemetryStoreFileUnreadable, telemetryStoreSupportKeyUnreadable, telemetryStoreSupportKeyReadRefused, telemetryStoreQueuedEventUnreadable, telemetryStoreQueuedEventReadRefused, telemetryStoreFileReadRefused]
    )

    public static let supportExchangeSupportAddressInvalid = Cause(
        id: "support-address-invalid", code: .config, usage: false, exit: nil,
        failed: "reading the support address from WISENT_SUPPORT_URL",
        cause: "a support address must be https://, or http:// on a loopback host",
        observed: "WISENT_SUPPORT_URL holds {address}",
        remedy: "set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_report_refuses_what_cannot_be_filed_and_files_nothing"
    )

    public static let supportExchangeSupportRefused = Cause(
        id: "support-refused", code: .refused, usage: false, exit: nil,
        failed: "{doing} at {address}",
        cause: "support refused HTTP {status}: {answer}",
        observed: "{observed}",
        remedy: "the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `{product} support report`",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_report_files_to_the_real_service_or_says_what_it_refused"
    )

    public static let supportExchangeSupportUnreachable = Cause(
        id: "support-unreachable", code: .infraDown, usage: false, exit: nil,
        failed: "{doing} at {address}",
        cause: "support could not be reached: {why}",
        observed: "{observed}",
        remedy: "send the report again once the network or support is back, from an app's Report a Problem window or with `{product} support report`",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_report_refuses_what_cannot_be_filed_and_files_nothing"
    )

    public static let supportExchangeSupportAnswerUnreadable = Cause(
        id: "support-answer-unreadable", code: .infraDown, usage: false, exit: nil,
        failed: "reading support's answer at {address}",
        cause: "the answer is not a support service's: {answer}",
        observed: "HTTP {status}",
        remedy: "check that {address} is a support service's /v1/public/reports",
        test: "tests/telemetry/swift/SupportReportTests.swift::test_support_report_names_the_status_of_an_answer_that_holds_no_key"
    )

    public static let supportExchange = Operation(
        id: "wisent-errors.support.exchange",
        entries: [],
        uses: [],
        summary: "find the support address, send support one request and read its answer",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
        causes: [supportExchangeSupportAddressInvalid, supportExchangeSupportRefused, supportExchangeSupportUnreachable, supportExchangeSupportAnswerUnreadable]
    )
}
