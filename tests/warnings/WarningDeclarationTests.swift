// Real tests, through the package's public API, of the Swift warning
// declaration a product builds its warnings from: the rules
// `Operation.problems` holds a warning to, the sentence an unconfirmed caller
// reads, and the JSON and page entry the product prints -- the same cases
// tests/warnings/declaration.rs holds the Rust crate to.
//
//   swift test --filter WarningDeclarationTests

import XCTest
import WisentErrors

final class WarningDeclarationTests: XCTestCase {
    private let removedForGood = Warning(
        id: "removed-for-good",
        hazard: .irreversible,
        effect: "{id} and every saved version of it are removed",
        consequence: "nothing restores them, not restore and not restore --at",
        safeguard: "keep a copy with `example backup <directory>`, which `example backup restore` puts back",
        confirm: "rerun with --yes",
        test: "tests/purge/purge.sh::purge_without_yes_removes_nothing"
    )

    /// The purge's one cause, so the functionality is complete and every
    /// problem `Operation.problems` answers is the warning's.
    private let itemAbsent = Cause(
        id: "item-absent", code: .notFound, usage: false, exit: nil,
        failed: "purging the trashed item {id}",
        cause: "no trashed item has that id",
        observed: "trashed items: {ids}",
        remedy: "name one of the trashed items, or trash {id} first",
        test: "tests/purge/purge.sh::purge_of_an_absent_item_is_refused"
    )

    // WisentErrors.Operation, not Foundation's (NSOperation), which XCTest imports.
    private func purge(_ warnings: [Warning], id: String = "example.item.purge") -> WisentErrors.Operation {
        WisentErrors.Operation(
            id: id, entries: ["example purge"], uses: [], summary: "remove a trashed item and every saved version for good",
            docs: "https://example.wisent.com/docs/errors", causes: [itemAbsent], warnings: warnings)
    }

    func test_a_complete_warning_has_no_problem() {
        XCTAssertEqual(purge([removedForGood]).problems(), [])
    }

    func test_a_warning_declared_twice_is_a_problem() {
        XCTAssertEqual(purge([removedForGood, removedForGood]).problems(), [
            "operation example.item.purge: warning removed-for-good is declared twice; keep one declaration per id",
        ])
    }

    func test_an_empty_safeguard_and_a_malformed_test_are_problems() {
        let bare = Warning(
            id: removedForGood.id, hazard: .irreversible, effect: removedForGood.effect,
            consequence: removedForGood.consequence, safeguard: " ", confirm: removedForGood.confirm, test: "purge.sh")
        XCTAssertEqual(purge([bare]).problems(), [
            "operation example.item.purge: warning removed-for-good: `safeguard` is empty; write what keeps a way back, done before confirming",
            "operation example.item.purge: warning removed-for-good: test \"purge.sh\" is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it",
        ])
    }

    func test_an_unconfirmed_caller_reads_the_effect_the_loss_the_way_back_and_how_to_go_ahead() {
        XCTAssertEqual(
            removedForGood.unconfirmed(["id": "github"]),
            "github and every saved version of it are removed; nothing restores them, not restore and not restore --at; nothing was done. Before confirming: keep a copy with `example backup <directory>`, which `example backup restore` puts back. To go ahead: rerun with --yes"
        )
    }

    func test_the_listing_links_each_warning_to_its_page_entry() {
        let purge = purge([removedForGood])
        XCTAssertEqual(
            purge.warningsJSON(page: "https://example.wisent.com/docs/warnings"),
            "{\"operation\":\"example.item.purge\",\"entries\":[\"example purge\"],\"summary\":\"remove a trashed item and every saved version for good\",\"warnings\":["
                + "{\"id\":\"removed-for-good\",\"hazard\":\"irreversible\",\"effect\":\"{id} and every saved version of it are removed\",\"consequence\":\"nothing restores them, not restore and not restore --at\","
                + "\"safeguard\":\"keep a copy with `example backup <directory>`, which `example backup restore` puts back\",\"confirm\":\"rerun with --yes\",\"test\":\"tests/purge/purge.sh::purge_without_yes_removes_nothing\","
                + "\"doc\":\"https://example.wisent.com/docs/warnings#example-item-purge-warning-removed-for-good\"}]}"
        )
        XCTAssertEqual(
            purge.warningsMarkdown(),
            "## `example.item.purge`\n\nremove a trashed item and every saved version for good\n\nStarted through: `example purge`. 1 declared warning(s).\n"
                + "\n<a id=\"example-item-purge-warning-removed-for-good\"></a>\n\n### `example.item.purge` warning `removed-for-good`\n\n"
                + "- **Kind:** `irreversible`: removes or rewrites something nothing in the product restores afterwards\n"
                + "- **What it does:** {id} and every saved version of it are removed\n"
                + "- **What cannot be had back:** nothing restores them, not restore and not restore --at\n"
                + "- **Before confirming:** keep a copy with `example backup <directory>`, which `example backup restore` puts back\n"
                + "- **To go ahead:** rerun with --yes\n"
                + "- **Test:** `tests/purge/purge.sh::purge_without_yes_removes_nothing`\n"
        )
    }

    func test_a_functionality_that_warns_of_nothing_has_no_page_section() {
        XCTAssertEqual(purge([], id: "example.item.list").warningsMarkdown(), "")
    }

    func test_every_hazard_reads_back_from_its_name() {
        XCTAssertEqual(
            Hazard.allCases.map(\.rawValue),
            ["irreversible", "overwrites", "cuts-off-access", "exposes-secret", "external-change", "costs-money"])
        for hazard in Hazard.allCases { XCTAssertEqual(Hazard(rawValue: hazard.rawValue), hazard) }
        XCTAssertNil(Hazard(rawValue: "scary"))
    }
}
