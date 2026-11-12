// Real tests of the Swift warning declaration a product builds its warnings
// from: the rules `Operation.problems` holds a warning to, the sentence an
// unconfirmed caller reads, and the JSON and page entry the product prints --
// the same cases tests/warnings/declaration.rs holds the Rust crate to.
//
//   swift test --filter WarningTests

import XCTest
@testable import WisentErrors

final class WarningTests: XCTestCase {
    private let removedForGood = Warning(
        id: "removed-for-good",
        hazard: .irreversible,
        effect: "{id} and every saved version of it are removed",
        consequence: "nothing restores them, not restore and not restore --at",
        safeguard: "keep a copy with `example backup <directory>`, which `example backup restore` puts back",
        confirm: "rerun with --yes",
        test: "tests/purge/purge.sh::purge_without_yes_removes_nothing"
    )

    private func purge(_ warnings: [Warning]) -> Operation {
        Operation(id: "example.item.purge", entries: ["example purge"], uses: [], summary: "remove a trashed item and every saved version for good", docs: "https://example.wisent.com/docs/errors", causes: [], warnings: warnings)
    }

    private func warningProblems(_ operation: Operation) -> [String] {
        operation.problems().filter { $0.contains("warning") }
    }

    func test_a_complete_warning_has_no_problem() {
        XCTAssertEqual(warningProblems(purge([removedForGood])), [])
    }

    func test_a_warning_declared_twice_is_a_problem() {
        XCTAssertEqual(warningProblems(purge([removedForGood, removedForGood])), [
            "operation example.item.purge: warning removed-for-good is declared twice; keep one declaration per id",
        ])
    }

    func test_an_empty_safeguard_and_a_malformed_test_are_problems() {
        let bare = Warning(id: removedForGood.id, hazard: .irreversible, effect: removedForGood.effect, consequence: removedForGood.consequence, safeguard: " ", confirm: removedForGood.confirm, test: "purge.sh")
        XCTAssertEqual(warningProblems(purge([bare])), [
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
        let json = purge([removedForGood]).warningsJSON(page: "https://example.wisent.com/docs/warnings")
        XCTAssertTrue(json.hasPrefix("{\"operation\":\"example.item.purge\",\"entries\":[\"example purge\"],\"summary\":\"remove a trashed item and every saved version for good\",\"warnings\":[{\"id\":\"removed-for-good\",\"hazard\":\"irreversible\""), json)
        XCTAssertTrue(json.hasSuffix("\"doc\":\"https://example.wisent.com/docs/warnings#example-item-purge-warning-removed-for-good\"}]}"), json)
        XCTAssertTrue(purge([removedForGood]).warningsMarkdown().contains("<a id=\"example-item-purge-warning-removed-for-good\"></a>"))
    }

    func test_a_functionality_that_warns_of_nothing_has_no_page_section() {
        XCTAssertEqual(purge([]).warningsMarkdown(), "")
    }

    func test_every_hazard_reads_back_from_its_name() {
        for hazard in Hazard.allCases { XCTAssertEqual(Hazard(rawValue: hazard.rawValue), hazard) }
        XCTAssertNil(Hazard(rawValue: "scary"))
    }
}
