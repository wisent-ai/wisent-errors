//! Real tests of the Rust warning declaration a product builds its warnings
//! from: the rules `Operation::problems` holds a warning to, the sentence an
//! unconfirmed caller reads, and the JSON and page entry the product prints.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --test warnings

use wisent_errors::{Cause, Code, Hazard, Operation, Warning};

const REMOVED_FOR_GOOD: Warning = Warning {
    id: "removed-for-good",
    hazard: Hazard::Irreversible,
    effect: "{id} and every saved version of it are removed",
    consequence: "nothing restores them, not restore and not restore --at",
    safeguard: "keep a copy with `example backup <directory>`, which `example backup restore` puts back",
    confirm: "rerun with --yes",
    test: "tests/purge/purge.sh::purge_without_yes_removes_nothing",
};

/// The purge's one cause, so the functionality is complete and every
/// problem `Operation::problems` answers is the warning's.
const ITEM_ABSENT: Cause = Cause {
    id: "item-absent",
    code: Code::NotFound,
    usage: false,
    exit: None,
    failed: "purging the trashed item {id}",
    cause: "no trashed item has that id",
    observed: "trashed items: {ids}",
    remedy: "name one of the trashed items, or trash {id} first",
    test: "tests/purge/purge.sh::purge_of_an_absent_item_is_refused",
};

const PURGE: Operation = Operation {
    id: "example.item.purge",
    entries: &["example purge"],
    uses: &[],
    summary: "remove a trashed item and every saved version for good",
    docs: "https://example.wisent.com/docs/errors",
    causes: &[&ITEM_ABSENT],
    warnings: &[&REMOVED_FOR_GOOD],
};

#[test]
fn a_complete_warning_has_no_problem() {
    assert_eq!(PURGE.problems(), Vec::<String>::new());
}

#[test]
fn a_warning_declared_twice_is_a_problem() {
    const TWICE: Operation = Operation {
        warnings: &[&REMOVED_FOR_GOOD, &REMOVED_FOR_GOOD],
        ..PURGE
    };
    assert_eq!(
        TWICE.problems(),
        vec!["operation example.item.purge: warning removed-for-good is declared twice; keep one declaration per id".to_owned()]
    );
}

#[test]
fn an_empty_safeguard_and_a_malformed_test_are_problems() {
    const BARE: Warning = Warning {
        safeguard: " ",
        test: "purge.sh",
        ..REMOVED_FOR_GOOD
    };
    const WITH_BARE: Operation = Operation {
        warnings: &[&BARE],
        ..PURGE
    };
    assert_eq!(
        WITH_BARE.problems(),
        vec![
            "operation example.item.purge: warning removed-for-good: `safeguard` is empty; write what keeps a way back, done before confirming".to_owned(),
            "operation example.item.purge: warning removed-for-good: test \"purge.sh\" is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it".to_owned(),
        ]
    );
}

#[test]
fn an_unconfirmed_caller_reads_the_effect_the_loss_the_way_back_and_how_to_go_ahead() {
    assert_eq!(
        REMOVED_FOR_GOOD.unconfirmed(&[("id", "github")]),
        "github and every saved version of it are removed; nothing restores them, not restore and not restore --at; nothing was done. \
         Before confirming: keep a copy with `example backup <directory>`, which `example backup restore` puts back. To go ahead: rerun with --yes"
    );
}

#[test]
fn the_listing_links_each_warning_to_its_page_entry() {
    assert_eq!(
        PURGE.warnings_json("https://example.wisent.com/docs/warnings"),
        concat!(
            "{\"operation\":\"example.item.purge\",\"entries\":[\"example purge\"],\"summary\":\"remove a trashed item and every saved version for good\",\"warnings\":[",
            "{\"id\":\"removed-for-good\",\"hazard\":\"irreversible\",\"effect\":\"{id} and every saved version of it are removed\",\"consequence\":\"nothing restores them, not restore and not restore --at\",",
            "\"safeguard\":\"keep a copy with `example backup <directory>`, which `example backup restore` puts back\",\"confirm\":\"rerun with --yes\",\"test\":\"tests/purge/purge.sh::purge_without_yes_removes_nothing\",",
            "\"doc\":\"https://example.wisent.com/docs/warnings#example-item-purge-warning-removed-for-good\"}]}"
        )
    );
    assert_eq!(
        PURGE.warnings_markdown(),
        concat!(
            "## `example.item.purge`\n\nremove a trashed item and every saved version for good\n\nStarted through: `example purge`. 1 declared warning(s).\n",
            "\n<a id=\"example-item-purge-warning-removed-for-good\"></a>\n\n### `example.item.purge` warning `removed-for-good`\n\n",
            "- **Kind:** `irreversible`: removes or rewrites something nothing in the product restores afterwards\n",
            "- **What it does:** {id} and every saved version of it are removed\n",
            "- **What cannot be had back:** nothing restores them, not restore and not restore --at\n",
            "- **Before confirming:** keep a copy with `example backup <directory>`, which `example backup restore` puts back\n",
            "- **To go ahead:** rerun with --yes\n",
            "- **Test:** `tests/purge/purge.sh::purge_without_yes_removes_nothing`\n"
        )
    );
}

#[test]
fn a_functionality_that_warns_of_nothing_has_no_page_section() {
    const LIST: Operation = Operation {
        id: "example.item.list",
        warnings: &[],
        ..PURGE
    };
    assert_eq!(LIST.warnings_markdown(), "");
}

#[test]
fn every_hazard_reads_back_from_its_name() {
    for hazard in Hazard::ALL {
        assert_eq!(Hazard::parse(hazard.as_str()), Some(hazard));
    }
    assert_eq!(Hazard::parse("scary"), None);
}
