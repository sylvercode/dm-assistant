---

description: "Implementation tasks for read-only vault orientation and inventory"
---

# Tasks: Read-Only Vault Orientation and Inventory

**Input**: Design documents in `specs\006-vault-orientation-inventory\`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts\vault-orientation-inventory.md`, and `quickstart.md`

**Tests**: Pester acceptance tasks are included because the feature specifies test scenarios and measurable success criteria. Use only synthetic, disposable vaults and the test-only authorization provider.

**Scope**: Inventory and proposals are read-only. This feature does not implement a profile writer or a generic-editor guard. Historical references below to an always-blocked authorization handoff are superseded by Feature 003's caller-confirmation contract: the caller performs live MCP checks and PowerShell validates the root-scoped confirmation without independently authenticating MCP. Installed-client and production qualification remain unverified.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task can run in parallel with other marked tasks once their stated prerequisites are complete; concurrent tasks do not modify the same files or depend on one another.
- **[Story]**: User-story traceability label; setup, foundational, and cross-cutting tasks have no story label.
- Each task names the repository files it changes or validates.

## Phase 1: Setup

**Purpose**: Prepare safe fixture evidence using the existing plugin and test infrastructure. No dependency installation or project scaffolding is planned.

- [X] T001 Add tests in `tests\powershell\TestHarness.Tests.ps1` for an ownership-checked, no-follow fixture snapshot that captures files, hashes, timestamps, directories, and link metadata without traversing or reading link targets, including outside and dangling links.
- [X] T002 Add the tested no-follow snapshot helper in `tests\powershell\TestHarness.psm1`; preserve existing fixture and snapshot behavior, restrict it to owned disposable fixtures, and keep harness snapshot reads distinguishable from instrumented operation reads.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make the shared request and pre-note contracts safe for inventory without breaking existing operations.

- [X] T003 [P] Add request-contract tests in `tests\powershell\VaultSelection.Tests.ps1` for `vault.orientation.inventory`, `inspect`, `targets: []`, null campaign/group, read-only registration metadata, strict argument types, unknown fields, and omitted approval fields. Assert `selectedGuidance` and `optionalGuidance` default to ordered string arrays `[]`, `proposeProfile` is Boolean with default `false`, and `mappingDecisions` is an array of exact non-empty, single-line `{ ambiguityId, alternativeId }` records supplied only with `proposeProfile: true`; reject duplicate decisions, scalar coercion, and invalid paths without prematurely rejecting a syntactically valid non-Markdown selection.
- [X] T004 [P] Add guidance-read regression tests in `tests\powershell\ProfileFilesystem.Tests.ps1` proving configured/default guidance's visible path and resolved target are Markdown before any guidance byte, fingerprint, or version read, including non-Markdown link targets and boundary failures; retain valid non-guidance reference behavior.
- [X] T005 [P] Extend `tests\powershell\ProfileState.Tests.ps1` with pre-note regression cases for configured/default guidance, invalid present profiles, and existing `notes.inspect` consumers; verify inventory does not perform conventional discovery before its request-selected guidance has passed validation.
- [X] T006 [P] Register `vault.orientation.inventory` in `skills\vault-orientation\scripts\OperationRequest.psm1` with `FactChanging=false`, `ChangeKind=read`, `MinTargets=0`, `MaxTargets=0`, `RequiresMappings=false`, `RequiresCampaignGroup=false`, and `inspect` only. Extend argument validation compatibly for the ordered arrays and decision records tested in T003, normalize and deduplicate paths stably, require the normalized optional set to be a selected subset, and preserve existing scalar-operation validation; registration validates metadata and does not dispatch.
- [X] T007 [P] Extend `skills\vault-orientation\scripts\VaultConfiguration.psm1` so `Test-DmProfileReference`, guidance dependency snapshots, and `Get-DmPreNoteContext` verify both the visible guidance name and contained final target are Markdown before every guidance read or fingerprint. Defer conventional discovery for inventory until selected-guidance checks finish, without changing profile reads, non-guidance references, or existing callers.

**Checkpoint**: T003-T005 can be written in parallel after setup; after those tests exist, T006 and T007 can proceed in parallel. Production authorization remains fail-closed.

---

## Phase 3: User Story 1 - Safely Orient to a Campaign Vault (Priority: P1)

**Goal**: Establish the exact vault and satisfy runtime, dependency, authorization, shared-reference, profile, and applicable-guidance gates before dependent note reads.

**Independent Test**: With disposable fixtures, exercise successful preflight and each blocked gate independently; verify no premature profile, guidance, discovery, or note read and no production authorization claim. A complete inventory result awaits US2.

### Tests for User Story 1

- [X] T008 [US1] Create `tests\powershell\VaultOrientationInventory.Tests.ps1` with preflight-order cases for an explicit absolute vault root, runtime readiness, required dependencies, independent exact-vault authorization, the plugin-owned shared reference, profile, configured/default guidance, and then selected guidance. Explicitly import `skills\vault-orientation\scripts\VaultInventory.psm1` and call its exported `Invoke-DmInventory -Request $request`; assert the call is reachable through this documented boundary without a dispatcher, returns the shared `{ result, inventoryReport }` shape, and has a null report with existing failure codes on blocked preflight. The plugin installation directory is never the vault.
- [X] T009 [US1] Add isolated guidance-loader cases in `tests\powershell\VaultOrientationInventory.Tests.ps1` for essential-by-default and explicitly optional selections: missing, unreadable, non-Markdown, empty, whitespace-only, frontmatter-only, and heading-only sources; a usable source has at least one non-empty body-text line outside frontmatter and headings. Assert optional skips use the first retained selection's original zero-based index and never echo its path, configured/default or essential aliases cannot be weakened, invalid or uncontained paths fail closed, and usable but silent guidance does not block.
- [X] T010 [US1] Add gate-level cases in `tests\powershell\VaultOrientationInventory.Tests.ps1` proving a profile or shared reference alone does not open the content gate, absent or all-skipped local guidance permits names only, and selected dot-prefixed Markdown loads only by explicit selection. Instrument note reads and fingerprints, and verify changed profile or loaded guidance returns `TARGET_CONFLICT` with a null report; exercise the gate without fabricating a completed inventory before US2.

### Implementation for User Story 1

- [X] T011 [US1] Create `skills\vault-orientation\scripts\VaultInventory.psm1` and export `Invoke-DmInventory -Request $request` as the supported manual caller boundary in `specs\006-vault-orientation-inventory\quickstart.md`; require explicit module import and invocation rather than a registry dispatcher. Reuse `Invoke-DmPreflight` and `Get-DmPreNoteContext` in the contract's order, preserve the Feature 003 `result` envelope, and return `{ result, inventoryReport }` with a null report for validation or preflight failure; T008 verifies the import/call path without claiming installed-client dispatch.
- [X] T012 [US1] Implement request-selected guidance handling in `skills\vault-orientation\scripts\VaultInventory.psm1` after configured/default guidance. Preserve selection provenance `configured`, `default-designated`, or `request-selected` and internal load states `not-applicable`, `pending`, `loaded`, `missing`, `unreadable`, `non-markdown`, `unusable`, or `blocked`; essential missing, unreadable, non-Markdown, or unusable guidance returns `REFERENCE_UNAVAILABLE`, while optional skips contain only `{ selectionIndex, reason }` with reason `missing`, `unreadable`, `non-markdown`, or `unusable`. Invalid or uncontained paths fail with the appropriate request or boundary code and are never skipped.
- [X] T013 [US1] In `skills\vault-orientation\scripts\VaultInventory.psm1`, safely read configured/default Markdown guidance against the pre-note dependency snapshot and capture validated versions for selected guidance; the pre-note helper's load state is not guidance text. Check visible and resolved paths before reads, recheck the profile and every loaded guidance version before returning, fail closed on changed sources, and never permit campaign-note content reads without successfully loaded applicable local guidance.
- [X] T014 [US1] Update `skills\vault-orientation\SKILL.md` with the explicit call and pre-note sequence, assistant-side loading of the shared reference independently of script-reported state, essential versus optional guidance, and names-only fallback. Retain the Resolver 2.1.0+ dependency and both required tools; establish authorization from a normalized exact `get_server_info` `vaults[].path` match, not service availability or link resolution, never use the Resolver for inventory traversal, and explain the unverified production handoff without claiming a complete inventory before US2.

**Checkpoint**: Preflight and guidance gates are independently testable; failures stop before dependent note reads and no write operation is available.

---

## Phase 4: User Story 2 - Understand an Existing Vault Layout (Priority: P1)

**Goal**: Produce a deterministic, read-only report of eligible entries, evidence-backed mappings, and meaningful uncertainty without imposing a layout or reading disallowed content.

**Independent Test**: Run orientation-only requests over the six synthetic layouts in `spec.md`, verify names, mapping classifications, exclusions, ambiguity, and unchanged no-follow snapshots, and exercise each content gate and failure path.

### Tests for User Story 2

- [X] T015 [US2] Add layout and no-write cases in `tests\powershell\VaultOrientationInventory.Tests.ps1` for each of the six fixtures and exact expected entries, candidate roles, evidence bases, and classifications in `specs\006-vault-orientation-inventory\quickstart.md`. Assert unsupported entries have no candidate mapping, no forced migration or invented folders, the unrelated root note is not an adventure, and owned-fixture snapshots remain unchanged.
- [X] T016 [US2] Add traversal and privacy cases in `tests\powershell\VaultOrientationInventory.Tests.ps1` for dot-prefixed entries, suffixed directories, non-dot Markdown with Hidden/System attributes, all non-Markdown filenames, and directory/file links. Verify directory links are never followed; both a file link's visible name and contained target are Markdown with no dot-prefixed target component; escaping, cyclic, unresolvable, and raced accesses fail safely without outside reads or partial reports.
- [X] T017 [US2] Add exact report-shape, ordering, evidence, and mapping tests in `tests\powershell\VaultOrientationInventory.Tests.ps1`: entries are only `{ path, kind }`, with `kind` `directory` or `markdown`; enforce FR-017's exact conventional-component and whole-word role-token rules, permitted explicit note-content labels, and rejection of thematic resemblance alone. Mapping classification is `observed` only when directly stated by the loaded profile or guidance and otherwise `inferred`, even after DM selection. Assert no absolute paths, raw note/guidance text, or excluded non-Markdown filename appears anywhere in a report or diagnostic except the fixed `.dmassist.yaml` identity.
- [X] T018 [US2] Add content-gate and source-change cases in `tests\powershell\VaultOrientationInventory.Tests.ps1`: names-only runs read no note contents or fingerprints, loaded applicable local guidance permits only eligible Markdown/frontmatter reads, and profile, loaded-guidance, or note-evidence mutation yields `TARGET_CONFLICT` with a null report. Instrument operation reads separately from fixture setup and snapshots.
- [X] T019 [US2] Add ambiguity and ID cases in `tests\powershell\VaultOrientationInventory.Tests.ps1` for all four SC-004 cases: a renamed section that changes requested task scope, a profile/observed-organization conflict affecting the task, multiple plausible mappings affecting proposed profile content, and an orientation-only ambiguity. Assert the first three present alternatives and are not relied on before DM direction; orientation-only ambiguity reports alternatives and completes. Also verify opaque IDs are stable across request IDs/timestamps but change with canonical root, alternatives, or relevant evidence, reveal no absolute path or raw content, and require no extra note read.

### Implementation for User Story 2

- [X] T020 [US2] Implement deterministic, component-contained enumeration in `skills\vault-orientation\scripts\VaultInventory.psm1`: retain eligible directory and Markdown names and original casing, omit every dot-prefixed inventory entry and non-Markdown filename, keep suffixed directories and eligible Hidden/System Markdown, and never follow directory links. Revalidate each file link before reporting or opening it; omit it unless both its visible name and contained final target are Markdown and its target path has no dot-prefixed component, and fail closed on escaping, cyclic, unresolvable, or raced accesses.
- [X] T021 [US2] Implement the content gate and transient inspection state in `skills\vault-orientation\scripts\VaultInventory.psm1`: no applicable local guidance means names-only with no note-content or note-fingerprint read; otherwise inspect only eligible Markdown and frontmatter after all required guidance passes. Never open attachment or other non-Markdown contents, use existing boundary APIs, and recheck all note-content evidence versions before return.
- [X] T022 [US2] Build the ordered report in `skills\vault-orientation\scripts\VaultInventory.psm1` with `schemaVersion: 1`, `operation: vault.orientation.inventory`, `scan`, `guidance`, `entries`, `candidateMappings`, `ambiguities`, and nullable `profileProposal`. Set `scan.contentInspected` from actual note reads and the exact flags `dotPrefixedEntriesExcluded: true`, `nonMarkdownEntriesExcluded: true`, `nonDotMarkdownIncludedRegardlessOfOsAttributes: true`, `nonMarkdownContentsRead: false`, and `attachmentContentsRead: false`; entries are only `{ path, kind }` with `kind` `directory` or `markdown`.
- [X] T023 [US2] Populate `guidance` and deterministic report ordering in `skills\vault-orientation\scripts\VaultInventory.psm1`: ordered `loadedSources` are `{ path, selectionKind }`, ordered `skippedOptionalSources` are `{ selectionIndex, reason }` without paths, and `contentInspectionBasis` is `guidance_loaded` or `names_only` alongside `configuredOrDefaultLoaded` and ordered `requestSelectedLoaded`. Sort entries by normalized path case-insensitively with ordinal tie-breaks; sort mappings by role/path/classification/evidence and ambiguities by subject/ID.
- [X] T024 [US2] Implement candidate mappings in `skills\vault-orientation\scripts\VaultInventory.psm1` with one non-empty `role`, one vault-relative `path`, `classification` exactly `observed` or `inferred`, non-empty deduplicated `basis`, non-empty `{ basis, source, summary }` evidence, and non-empty `uncertainty` for inferred or conflicted mappings otherwise `null`. Apply FR-017: require an explicit profile/guidance assignment, an exact recognized conventional section name, an explicit role token in an eligible entry name, or a permitted note-content role label/self-identification; general thematic resemblance alone is insufficient and unsupported entries have no candidate mapping. Restrict `basis` to `profile-configured`, `configured-guidance`, `default-guidance`, `dm-selected-guidance`, `default-convention`, `entry-name`, `folder-name`, `frontmatter`, and `markdown-content` in their specified order; each evidence `basis` must occur in the mapping's basis set, summaries are non-verbatim, and a configured location is not proof it exists.
- [X] T025 [US2] Implement ambiguities and atomic failure handling in `skills\vault-orientation\scripts\VaultInventory.psm1`: each has an opaque `ambiguityId`, normalized `subject`, at least two `{ alternativeId, interpretation, path, evidence }` alternatives with non-empty `interpretation` and vault-relative or null `path`, non-empty `reason`, Boolean `requiresDmDecision`, and nullable `selectedAlternativeId`. Set `requiresDmDecision` only for an unresolved proposal-affecting choice; derive the ambiguity ID from canonical root, subject, relevant evidence, and ordered alternative descriptors without IDs, then derive each alternative ID from its parent and descriptor. Sort output alternatives by normalized interpretation/path/ID and return no partial report on traversal/read failure or changed checked source.
- [X] T026 [US2] Update `skills\vault-orientation\SKILL.md` with implemented names-only versus guidance-enabled behavior, eligible-name and link exclusions, provisional evidence-based mappings, informational versus task-relevant ambiguity, safe failure behavior, and the unchanged production-authorization limitation.

**Checkpoint**: Orientation is independently usable with synthetic authorization and `proposeProfile: false`; it never writes, exposes excluded filenames, or silently chooses a consequential mapping.

---

## Phase 5: User Story 3 - Review Proposed Mappings Without Losing Control (Priority: P2)

**Goal**: Offer a reviewable, evidence-backed profile proposal without treating a mapping choice as authorization or changing the vault.

**Independent Test**: Request and decline proposals on disposable fixtures, including an existing profile and unresolved/stale choices; verify the exact result shapes, valid complete proposals, preservation, and no vault changes.

### Tests for User Story 3

- [X] T027 [US3] Add proposal opt-in and schema tests in `tests\powershell\VaultOrientationInventory.Tests.ps1`: omitted or false `proposeProfile` gives `profileProposal: null`; a fully determined proposal is `drafted-unapproved`, validates against `skills\vault-orientation\assets\dmassist.schema.json`, and separates observed from inferred evidence without introducing unsupported profile fields or folders.
- [X] T028 [US3] Add fresh, unresolved, stale, and unknown decision tests in `tests\powershell\VaultOrientationInventory.Tests.ps1`. Valid choices must match IDs from a fresh scan; unresolved or stale choices return `not completed` / `AMBIGUOUS_CONTEXT` with the report and current alternatives but null proposal `content` and `differences`, and unmatched choices produce ordered `{ decisionIndex, reason: 'stale-or-unknown' }` without echoing IDs.
- [X] T029 [US3] Add existing-profile preservation and privacy tests in `tests\powershell\VaultOrientationInventory.Tests.ps1` for unrelated values, user data, comments, changed-mapping comment associations, formatting, line endings, absent profiles, and complete diffs. When safe preservation or disclosure is impossible, including an excluded non-Markdown filename in preserved content, assert `OPERATION_FAILED` and a null report even if ambiguity also exists.
- [X] T030 [US3] Add no-follow before/after fixture snapshots in `tests\powershell\VaultOrientationInventory.Tests.ps1` for ordinary, resolved, ambiguous, stale, declined, and failed requests with and without a profile; assert no file, directory, link, or profile is created, modified, moved, renamed, or deleted and no persistent cache or write target appears.

### Implementation for User Story 3

- [X] T031 [US3] In `skills\vault-orientation\scripts\VaultInventory.psm1`, rescan and revalidate each explicit `{ ambiguityId, alternativeId }` decision against current evidence-bound IDs; do not persist a decision, change its evidence classification, fabricate alternatives, or treat it as authorization or approval. Keep unmatched decision issues in request order as `{ decisionIndex, reason: 'stale-or-unknown' }`.
- [X] T032 [US3] Generate a request-scoped profile proposal in `skills\vault-orientation\scripts\VaultInventory.psm1` only when `proposeProfile` is true. Set `status` to `drafted-unapproved`, retain candidate evidence and unresolved alternatives, and provide schema-valid Feature 002 version-1 YAML in `content` only when every required decision is resolved; otherwise `content` and `differences` are `null`.
- [X] T033 [US3] Preserve existing profile values, user-authored data, comments, changed-mapping comment associations, unaffected formatting, and line endings in `skills\vault-orientation\scripts\VaultInventory.psm1`; show every intended change in `differences`, an explicit unchanged result when applicable, or all proposed content for an absent profile. If exact preservation or a complete safe diff is impossible, including disclosure of an excluded filename, return `OPERATION_FAILED` with `inventoryReport: null` rather than silently discarding data.
- [X] T034 [US3] Integrate the proposal outcomes in `skills\vault-orientation\scripts\VaultInventory.psm1`: orientation-only requests complete without pausing for informational ambiguity; unresolved or stale proposal choices return `AMBIGUOUS_CONTEXT` with the report; preservation failures take precedence and return no report. Recheck profile, guidance, and note-evidence versions, perform no write or persistent caching, and never invoke `note.replace-text` or a direct file writer.
- [X] T035 [US3] Update `skills\vault-orientation\SKILL.md` and `docs\powershell-runtime-support.md` with proposal review, explicit DM decisions, decline behavior, and the future-only profile-specific write boundary: preview the exact target, content, encoding, and bytes; obtain explicit approval in a later message; bind `approvedPreviewId`, `reviewedVersions`, and `reviewedDependencyVersions`; revalidate authorization, root, target, dependencies, and plugin/runtime/module identity; use no-clobber creation or guarded replacement and report actual or uncertain post-commit outcomes. Document, without claiming a fix, that the existing generic `note.replace-text` operation can target an existing `.dmassist.yaml` after its own gates, that a single ordinary-target edit need not have a preview, and that replacement YAML is not validated as a profile; implement neither writer nor guard.

**Checkpoint**: Proposals are optional, evidence-backed, unapproved, and review-only; every outcome leaves the vault unchanged.

---

## Phase 6: Polish & Cross-Cutting Validation

**Purpose**: Validate the complete feature without conflating synthetic tests, local discovery, installed-client behavior, or production authorization.

- [X] T036 [P] Perform the static skill inventory and source audit using `skills\README.md` and `specs\001-shared-vault-guidance\spec.md`: enumerate every immediate-child `skills\*\SKILL.md`, require a one-to-one inventory with no missing, extra, duplicate, or unclassified skills, and inspect every vault-facing skill for shared-reference loading, designated guidance, required dependencies, and authorization before note access.
- [ ] T037 [P] Follow the local plugin-discovery procedure in `README.md` and `specs\006-vault-orientation-inventory\quickstart.md` after the plugin changes: from the repository root start a fresh `copilot --plugin-dir .` session, check `/skills list` and `/agent`, and separately run `copilot --plugin-dir . plugin list`. Confirm `vault-orientation` is listed, the plugin bundles no Copilot-specific agents, and `dm-assistant` appears under External Plugins (via `--plugin-dir`); other installed agents may still appear. If the CLI or interactive session is unavailable, record the blocker and leave the task incomplete. Do not treat session-scoped discovery as installed-client resource, runtime, or authorization validation.
- [X] T038 [P] Run the focused synthetic acceptance suite with `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1 -Path tests\powershell\VaultOrientationInventory.Tests.ps1`, then the full Pester 6.2.0 suite with `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`; include the shared request, guidance, and fixture regressions and report any environment-dependent link skips rather than claiming they passed. **2026-11-11:** on Windows with PowerShell 7.7.0, focused: 44 passed, 0 failed, 1 skipped; full: 459 passed, 0 failed, 7 skipped. Skips require file symlink creation unavailable in this environment.
- [X] T039 **Deferred to [#13](https://github.com/sylvercode/dm-assistant/issues/13); SC-005 not run or passed.** Conduct the real-DM SC-005 walkthrough in `specs\006-vault-orientation-inventory\quickstart.md`: five real DMs independently review the same synthetic proposal with at least six mappings, including at least two `observed` and two `inferred`, against a separate answer key. Pass only if at least four of the five each correctly classify every mapping and all five can decline with no vault changes verified by before/after snapshots. Record anonymized individual and aggregate outcomes, proposal identity, and environment in the quickstart without campaign content.
- [X] T040 Update `README.md` and `docs\powershell-runtime-support.md` with the implemented behavior and actual validation evidence, distinguishing synthetic authorization, session-scoped local discovery, any outstanding five-DM review, unverified installed-client behavior, and the still-blocked production authorization handoff.

T037 remains incomplete: `/skills list` found `vault-orientation` and `/agent`
found no custom agents, but `copilot --plugin-dir . plugin list` showed
`dm-assistant` under Installed plugins rather than the expected External
Plugins grouping. T039 is checked to record its deferral to
[#13](https://github.com/sylvercode/dm-assistant/issues/13), not a pass.
Feature acceptance still requires the five-DM walkthrough to meet SC-005.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup**: T001 precedes T002; both use disposable fixtures.
- **Foundational**: T003-T005 are independent test tasks after setup. T006 depends on T003, and T007 depends on T004-T005; T006 and T007 touch different modules and can run in parallel.
- **US1**: T008-T014 depend on the foundation; tests share one file and are sequenced. The US1 safety gates are the first incremental milestone, not a complete inventory release.
- **US2**: T015-T026 depend on US1's preflight and guidance gates. Its implementation tasks share `VaultInventory.psm1` and must be coordinated in order.
- **US3**: T027-T035 depend on US2's fresh scan, evidence, and ambiguity records. Decision handling and proposals are review-only; no write operation is part of this feature.
- **Validation**: T036-T038 can run independently after US3 and stabilized plugin files. T039 additionally requires a completed proposal workflow, passing focused tests, and five real DMs. T040 follows T036-T039 and records the actual outcomes or blockers; feature acceptance still requires T039 to pass.

### User Story Dependencies

- **US1 (P1)**: Depends only on the foundational request and pre-note safeguards.
- **US2 (P1)**: Depends on US1's authorization, guidance, and content gates.
- **US3 (P2)**: Depends on US2's observations, evidence, and fresh-scan ambiguity IDs.

### Dependency Graph

```text
T001 -> T002
T002 -> { T003 -> T006, T004 -> T007, T005 -> T007 }
T006 + T007 -> US1: T008-T014 -> US2: T015-T026 -> US3: T027-T035
US3 -> { T036, T037, T038 -> T039 }
T036 + T037 + T039 -> T040
```

### Parallel Opportunities

- After setup, T003, T004, and T005 add tests in different files; after their prerequisite tests, T006 and T007 modify different runtime modules.
- After US3 is stable, the read-only static audit T036, fresh local discovery check T037, and synthetic Pester validation T038 can run independently.
- Story acceptance cases share `tests\powershell\VaultOrientationInventory.Tests.ps1`, and story implementations share `skills\vault-orientation\scripts\VaultInventory.psm1`; do not edit those shared files concurrently.

### Parallel Examples by Story

- **US1**: After setup, write the prerequisite request and shared-guidance regression tests T003-T005 in separate files in parallel; once those tests exist, T006 and T007 can proceed in parallel before the US1 test file is changed.
- **US2**: After US1 is complete, the local plugin-discovery procedure in `README.md` can be rehearsed independently of drafting US2's layout cases; repeat T037 after the final plugin changes for acceptance.
- **US3**: After US2's report contract is stable, prepare the synthetic proposal and answer key described in `specs\006-vault-orientation-inventory\quickstart.md` independently of implementing proposal logic; conduct T039 only against the finished, stable proposal.

## Implementation Strategy

### MVP First

1. Complete setup, foundation, and US1 as the safety-gate milestone.
2. Independently validate US1 with synthetic authorization and stop on any failed preflight.
3. Add US2 before presenting the operation as a complete read-only inventory; production use remains blocked until the trusted active-session authorization handoff is verified.

### Incremental Delivery

1. Add US2 and verify layout coverage, privacy, link boundaries, evidence, and informational ambiguity.
2. Add US3 and verify fresh DM choices, complete reviewable proposals, preservation, and no writes.
3. Run the independent static audit, local discovery, and Pester checks; then conduct the real five-DM walkthrough and record its actual outcome.
4. Keep installed-client validation and production authorization explicitly unverified unless independently established; synthetic tests and local discovery do not establish either.

## Notes

- All behavior is planned until implemented; no task authorizes a profile writer, generic-editor guard, vault restructuring, or direct campaign-vault access.
- Reuse Feature 001/002/003 authorization, profile, boundary, and result contracts; test-only authorization never establishes production access.
- Report no non-Markdown filenames anywhere in the inventory report except the fixed `.dmassist.yaml` identity when needed; never expose raw note or guidance text.
- No scale, latency, throughput, or vault-size threshold is specified; do not invent one.
