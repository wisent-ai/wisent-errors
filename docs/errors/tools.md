<!-- Generated from catalogue/failures/ by codegen/generate.mjs. Do not edit: change the part and regenerate. -->

# wisent-errors' own failures: tools

Every way the tools functionalities of this package fail, as their refusals say it.

## `wisent_errors.census.implementations`

find every repository under a root that restates this envelope's vocabulary instead of depending on the package

Started through: `node ci/find-implementations.mjs`. Uses: `wisent_errors.lint.arguments`, `wisent_errors.lint.paths`.

<a id="wisent_errors-census-implementations-vocabulary-restated"></a>

### `wisent_errors.census.implementations.vocabulary-restated`

- **What failed:** counting the implementations of the envelope under {roots}
- **Cause:** {count} repositories quote a majority of the catalogue's codes, infra_down among them, and depend on no revision of the package
- **Observed state shown:** each repository with the files that restate it, a file counting when it quotes {threshold} or more of the {codes} codes: {repositories}
- **Fix:** adopt the package in each, pinned to a revision, and delete its copy of the vocabulary from the files named; `node ci/find-implementations.mjs --unadopted-only` lists them again
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/tools/census.mjs::a_repository_restating_the_vocabulary_is_counted`

<a id="wisent_errors-census-implementations-file-unreadable"></a>

### `wisent_errors.census.implementations.file-unreadable`

- **What failed:** reading {path} while counting the implementations under {roots}
- **Cause:** the operating system refused the read, so whether it restates the vocabulary or declares the package is unknown
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running the census read it (chmod u+r {path}), or name roots that leave it out
- **Code:** `refused`, exit 1
- **Test:** JavaScript `tests/tools/census.mjs::an_unreadable_file_is_refused`

<a id="wisent_errors-census-implementations-git-absent"></a>

### `wisent_errors.census.implementations.git-absent`

- **What failed:** asking git where {repository} came from and what its remote tip holds
- **Cause:** no git program could be started, so a stale checkout cannot be told from a product that restates the vocabulary
- **Observed state shown:** PATH {path_variable}; starting git answered {error}
- **Fix:** install git or put it on PATH, then count again
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/census.mjs::a_census_without_git_is_refused`

## `wisent_errors.codegen.generate`

write the four runtimes' vocabulary, declaration rules and own failure catalogue from catalogue/, or with --check say which of them drifted

Started through: `node codegen/generate.mjs`, `node codegen/generate.mjs --check`. Uses: `wisent_errors.catalogue.parts`, `wisent_errors.lint.input`.

<a id="wisent_errors-codegen-generate-edition-undeclared"></a>

### `wisent_errors.codegen.generate.edition-undeclared`

- **What failed:** formatting the generated {target} with rustfmt
- **Cause:** {manifest} declares no edition, and rustfmt formats a module differently under each edition
- **Observed state shown:** {manifest} holds no line edition = "..."
- **Fix:** declare edition = "2021" under [package] in {manifest}
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::a_crate_with_no_edition_is_refused`

<a id="wisent_errors-codegen-generate-rustfmt-absent"></a>

### `wisent_errors.codegen.generate.rustfmt-absent`

- **What failed:** formatting the generated {target} with rustfmt
- **Cause:** no rustfmt program could be started, so the Rust module would not match what `cargo fmt --check` expects
- **Observed state shown:** PATH {path_variable}; starting rustfmt answered {error}
- **Fix:** install it with `rustup component add rustfmt`, then generate again
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::a_generation_without_rustfmt_is_refused`

<a id="wisent_errors-codegen-generate-rustfmt-refused"></a>

### `wisent_errors.codegen.generate.rustfmt-refused`

- **What failed:** formatting the generated {target} with rustfmt --edition {edition}
- **Cause:** rustfmt exited {status} on the generated module, so the generator wrote Rust that does not parse
- **Observed state shown:** rustfmt said {stderr}
- **Fix:** correct the renderer codegen/{renderer} or the catalogue value it quoted, then generate again
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::a_module_rustfmt_refuses_is_refused`

<a id="wisent_errors-codegen-generate-generated-drifted"></a>

### `wisent_errors.codegen.generate.generated-drifted`

- **What failed:** comparing the generated files with catalogue/
- **Cause:** {count} generated file(s) differ from what the catalogue writes, so the runtimes would not say what the catalogue declares
- **Observed state shown:** {drifted}
- **Fix:** run `node codegen/generate.mjs` and commit what it writes
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::a_drifted_generated_file_is_refused`

<a id="wisent_errors-codegen-generate-generated-unwritable"></a>

### `wisent_errors.codegen.generate.generated-unwritable`

- **What failed:** writing the generated {target}
- **Cause:** the operating system refused to create or write the file, so the runtime keeps what an older catalogue wrote
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running the generator write {target} and its directory, then generate again
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::an_unwritable_generated_file_is_refused`

<a id="wisent_errors-codegen-generate-generated-unremovable"></a>

### `wisent_errors.codegen.generate.generated-unremovable`

- **What failed:** removing the generated {target}, which no part of catalogue/failures/ writes any more
- **Cause:** the operating system refused to remove the file, so the runtime still holds a declaration the catalogue no longer has
- **Observed state shown:** {state}; its directory: {directory_state}; the operating system answered {error}
- **Fix:** let the user running the generator write {directory}, or remove {target} yourself, then generate again
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::an_unremovable_stale_module_is_refused`

## `wisent_errors.ship.check`

say whether this package may ship: the generated runtimes match catalogue/, the schema names the catalogue's vocabulary, and this package's own failure catalogue holds

Started through: `node ci/check.mjs`. Uses: `wisent_errors.codegen.generate`, `wisent_errors.lint.catalogue`, `wisent_errors.lint.input`.

<a id="wisent_errors-ship-check-vocabulary-differs"></a>

### `wisent_errors.ship.check.vocabulary-differs`

- **What failed:** comparing the {what} of {schema} with catalogue/codes.json
- **Cause:** the schema names other {what} than the catalogue, so a checked envelope and a generated runtime disagree
- **Observed state shown:** catalogue {catalogue_says}; schema {schema_says}
- **Fix:** change {schema} to name what catalogue/codes.json names
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/generate.mjs::a_schema_naming_other_codes_is_refused`

## `wisent_errors.inventory.list`

list the lines of one committed revision that match a pattern, for a defect register's completion probe

Started through: `node tests/inventory.mjs`. Uses: `wisent_errors.lint.arguments`.

<a id="wisent_errors-inventory-list-revision-unknown"></a>

### `wisent_errors.inventory.list.revision-unknown`

- **What failed:** listing the lines of {revision} that match {quoted_pattern}
- **Cause:** git knows no revision {revision} in {repository}
- **Observed state shown:** git exited {status} and said {stderr}
- **Fix:** name a commit, tag or branch the checkout holds; `git -C {repository} fetch` brings one it lacks
- **Code:** `not_found`, exit 2
- **Test:** JavaScript `tests/tools/inventory.mjs::an_unknown_revision_is_refused`

<a id="wisent_errors-inventory-list-pattern-refused"></a>

### `wisent_errors.inventory.list.pattern-refused`

- **What failed:** listing the lines of {revision} that match {quoted_pattern}
- **Cause:** git does not read {quoted_pattern} as an extended regular expression
- **Observed state shown:** git exited {status} and said {stderr}
- **Fix:** write the pattern as a POSIX extended regular expression, escaping the characters git names
- **Code:** `refused`, exit 2
- **Test:** JavaScript `tests/tools/inventory.mjs::a_pattern_git_refuses_is_refused`

<a id="wisent_errors-inventory-list-git-absent"></a>

### `wisent_errors.inventory.list.git-absent`

- **What failed:** listing the lines of {revision} that match {quoted_pattern}
- **Cause:** no git program could be started
- **Observed state shown:** PATH {path_variable}; starting git answered {error}
- **Fix:** install git or put it on PATH, then list again
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/inventory.mjs::a_listing_without_git_is_refused`

<a id="wisent_errors-inventory-list-repository-not-git"></a>

### `wisent_errors.inventory.list.repository-not-git`

- **What failed:** listing the lines of {revision} that match {quoted_pattern}
- **Cause:** {repository} holds no git repository, as an unpacked archive of the source does not, so no committed revision can be read
- **Observed state shown:** git exited {status} and said {stderr}
- **Fix:** run it in a clone of the repository, where `git -C {repository} log -1` names a commit
- **Code:** `config`, exit 1
- **Test:** JavaScript `tests/tools/inventory.mjs::a_listing_outside_a_repository_is_refused`

## `wisent_errors.catalogue.parts`

read the parts of this package's own failure catalogue in catalogue/failures/ and join them into one catalogue

Started through: run only by the functionalities that use it. Uses: none.

<a id="wisent_errors-catalogue-parts-parts-unlisted"></a>

### `wisent_errors.catalogue.parts.parts-unlisted`

- **What failed:** listing the failure catalogue parts in {directory}
- **Cause:** the directory cannot be listed, so no part of the catalogue can be read
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** restore it with `git checkout -- catalogue/failures`, or let the user running the command read it
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::an_unlisted_parts_directory_is_refused`

<a id="wisent_errors-catalogue-parts-parts-absent"></a>

### `wisent_errors.catalogue.parts.parts-absent`

- **What failed:** reading the failure catalogue parts in {directory}
- **Cause:** the directory holds no .json part, so this package would declare none of its own failures
- **Observed state shown:** it holds {listing}
- **Fix:** restore the parts with `git checkout -- catalogue/failures`
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::a_parts_directory_with_no_part_is_refused`

<a id="wisent_errors-catalogue-parts-part-unreadable"></a>

### `wisent_errors.catalogue.parts.part-unreadable`

- **What failed:** reading the failure catalogue part {path}
- **Cause:** the part is listed but cannot be read
- **Observed state shown:** {state}; the operating system answered {error}
- **Fix:** let the user running the command read it (chmod u+r {path}), or restore it with `git checkout -- {path}`
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::an_unreadable_part_is_refused`

<a id="wisent_errors-catalogue-parts-part-not-json"></a>

### `wisent_errors.catalogue.parts.part-not-json`

- **What failed:** reading the failure catalogue part {path}
- **Cause:** the part is not JSON
- **Observed state shown:** {bytes} bytes; the decoder answered {error}
- **Fix:** correct the JSON of {path}; `jq . {path}` points at the place it stops parsing
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::a_part_that_is_not_json_is_refused`

<a id="wisent_errors-catalogue-parts-part-wrong-shape"></a>

### `wisent_errors.catalogue.parts.part-wrong-shape`

- **What failed:** reading the failure catalogue part {path}
- **Cause:** the part is JSON but not an object with an area and a list of operations, each with an id, runtimes, entries (one list, or one list per runtime) and causes carrying their tests
- **Observed state shown:** at {where} it holds {found}
- **Fix:** write {path} as an object with "area" and "operations", the way the other parts are written
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::a_part_of_the_wrong_shape_is_refused`

<a id="wisent_errors-catalogue-parts-operation-declared-twice"></a>

### `wisent_errors.catalogue.parts.operation-declared-twice`

- **What failed:** reading the failure catalogue parts in {directory}
- **Cause:** the operation {operation} is declared in both {first} and {second}
- **Observed state shown:** {parts} part(s) read
- **Fix:** keep {operation} in one part and delete it from the other
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::an_operation_declared_in_two_parts_is_refused`

<a id="wisent_errors-catalogue-parts-uses-undeclared"></a>

### `wisent_errors.catalogue.parts.uses-undeclared`

- **What failed:** joining the failure catalogue parts in {directory}
- **Cause:** the operation {operation} uses {used}, which no part declares
- **Observed state shown:** declared operations: {declared}
- **Fix:** declare {used} in a part, or take it out of the uses of {operation}
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::a_use_no_part_declares_is_refused`

<a id="wisent_errors-catalogue-parts-raised-undeclared"></a>

### `wisent_errors.catalogue.parts.raised-undeclared`

- **What failed:** raising {raised}
- **Cause:** the command raises a cause that no part of catalogue/failures/ declares, so it has no sentence, code or test
- **Observed state shown:** {declared}
- **Fix:** declare {raised} in its part of catalogue/failures/, or raise the cause that is declared
- **Code:** `config`, exit 1
- **Test:** `tests/tools/parts.mjs::a_raised_cause_no_part_declares_is_refused`
