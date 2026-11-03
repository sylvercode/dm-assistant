---

description: "Implementation tasks for read-only vault orientation and inventory"
---

# Tasks: Read-Only Vault Orientation and Inventory

**Input**: Design documents from `/specs/006-vault-orientation-inventory/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/vault-orientation-inventory.md`, `quickstart.md`

**Tests**: Pester acceptance tasks are included because `quickstart.md` explicitly defines required acceptance scenarios.

**Organization**: Tasks are grouped by user story so each capability can be implemented and checked as an increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Tasks that can run in parallel touch different files and have no unfinished-task dependency.
- **[Story]**: User-story traceability label; setup and foundational tasks have no story label.
- Every task names the exact repository file it changes or validates.

## Path Conventions

- PowerShell plugin runtime: `skills/vault-orientation/scripts/`
- Focused acceptance tests: `tests/powershell/VaultOrientationInventory.Tests.ps1`

## Phase 1: Setup

**Purpose**: The repository already has the plugin structure, pinned PowerShell/Pester runtime, and acceptance-test harness. No project initialization or dependency-manifest changes are required.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Register and validate the inventory operation before any story-specific behavior is implemented.

- [ ] T001 Register `vault.orientation.inventory` as inspect-only with zero write targets in `skills/vault-orientation/scripts/OperationRequest.psm1`; validate `selectedGuidance` as an optional ordered array of explicit vault-relative Markdown paths, de-duplicate paths while preserving first-selection order, allow dot-prefixed paths only when explicitly selected, default `proposeProfile` to `false`, require it to be Boolean when supplied, and reject unknown operation arguments.

**Checkpoint**: Operation requests have an explicit, read-only shape before story work begins. Production authorization remains fail-closed; test-only authorization fixtures do not establish production authorization.

---

## Phase 3: User Story 1 - Safely Orient to a Campaign Vault (Priority: P1)

**Goal**: Establish the exact vault and satisfy dependency, authorization, shared-reference, profile, and applicable-guidance gates before any campaign-note reads.

**Independent Test**: With disposable fixtures and the existing synthetic authorization provider, verify preflight ordering and that each failed prerequisite blocks profile, guidance, and note reads. Separately verify production remains blocked when trusted active-session authorization is unproven.

### Tests for User Story 1

- [ ] T002 [US1] Add focused Pester cases in `tests/powershell/VaultOrientationInventory.Tests.ps1` proving explicit-vault establishment, dependency readiness, shared-reference loading, and exact-vault authorization all precede dependent reads; assert missing readiness and unproven authorization return their existing failure codes without reading profile, guidance, or notes.
- [ ] T003 [US1] Extend `tests/powershell/VaultOrientationInventory.Tests.ps1` with configured/default profile and guidance cases, asserting an invalid present profile is not treated as absent, required missing/unreadable guidance blocks dependent reads, and no configured profile or guidance can authorize a different vault.
- [ ] T004 [US1] Add selected-guidance cases to `tests/powershell/VaultOrientationInventory.Tests.ps1`, asserting request-selected sources are additive to configured/default guidance, validated before note reads, deduplicated in selection order, and permit dot-prefixed Markdown only by explicit selection.

### Implementation for User Story 1

- [ ] T005 [US1] Extend `skills/vault-orientation/scripts/VaultConfiguration.psm1` to load and validate request-selected guidance separately from Feature 002 configured/default guidance; preserve the `selectionKind` values `configured`, `default-designated`, and `request-selected`, and the `loadState` values `not-applicable`, `pending`, `loaded`, `missing`, `unreadable`, `invalid`, and `blocked`.
- [ ] T006 [US1] Implement the `Invoke-DmInventory` entry point and ordered preflight in `skills/vault-orientation/scripts/VaultInventory.psm1`, reusing `Invoke-DmPreflight` and `Get-DmPreNoteContext` before any vault enumeration or content read, then loading explicit extra guidance only after the existing runtime, readiness, authorization, shared-reference, and profile gates pass.
- [ ] T007 [US1] Add failure-path checks to `skills/vault-orientation/scripts/VaultInventory.psm1` so invalid profiles and task-essential missing, unreadable, invalid, or non-Markdown guidance stop dependent reads with existing safe completion codes and no partial report; do not substitute guessed guidance or bypass the production authorization block.
- [ ] T008 [P] [US1] Update `skills/vault-orientation/SKILL.md` with the inventory operation's required pre-note sequence, distinction between dependency readiness and exact-vault authorization, explicit guidance-selection rules, and fail-closed production authorization limitation.

**Checkpoint**: Preflight and guidance selection are independently verified; no operation may proceed to content inspection until every applicable gate succeeds.

---

## Phase 4: User Story 2 - Understand an Existing Vault Layout (Priority: P1)

**Goal**: Produce a deterministic, read-only report of observed vault organization, provisional candidate mappings, and consequential ambiguities without imposing a layout or reading disallowed contents.

**Independent Test**: Run the focused acceptance cases against representative disposable layouts; verify exact observations, cautious mappings, required alternatives, allowed content access only after guidance, and unchanged fixture snapshots on both success and failure.

### Tests for User Story 2

- [ ] T009 [US2] Add layout and traversal cases to `tests/powershell/VaultOrientationInventory.Tests.ps1` for root-level, single-file, folder-based, mixed, renamed-section, and additional-Lore layouts; assert unrelated root notes are not classified as Adventures, the existing organization is preserved, and output ordering is deterministic.
- [ ] T010 [US2] Add content-boundary cases to `tests/powershell/VaultOrientationInventory.Tests.ps1`, asserting names-only behavior without applicable local guidance, Markdown/frontmatter reads only after configured/default or selected guidance loads, dot-prefixed inventory exclusion, non-dot Markdown inclusion regardless of Hidden/System attributes, and no attachment or non-Markdown content reads.
- [ ] T011 [US2] Add mapping, ambiguity, and failure cases to `tests/powershell/VaultOrientationInventory.Tests.ps1`, asserting mappings remain provisional, consequential ambiguity provides at least two alternatives and defers reliance for DM direction, traversal/read failures omit partial reports, and errors expose no raw note contents or absolute paths.
- [ ] T012 [US2] Add boundary and side-effect cases to `tests/powershell/VaultOrientationInventory.Tests.ps1` for directory links, escaping/cyclic/unresolvable links, symlink races or swaps, and before/after vault snapshots; assert every blocked, failed, and successful inventory run leaves the fixture unchanged.

### Implementation for User Story 2

- [ ] T013 [US2] Implement safe, deterministic enumeration in `skills/vault-orientation/scripts/VaultInventory.psm1`: enumerate eligible names without following directory links, exclude dot-prefixed entries, retain original spelling, sort by normalized vault-relative path with a case-insensitive comparison and ordinal tie-break, and include non-dot Markdown regardless of OS Hidden/System attributes.
- [ ] T014 [US2] Implement observed-entry records in `skills/vault-orientation/scripts/VaultInventory.psm1` with `relativePath` as one vault-relative path, `name` as the observed basename preserving casing, `kind` in `directory`, `markdown`, `attachment`, or `other-file`, `contentState` in `not-read-no-local-guidance`, `not-markdown`, `attachment-skipped`, `read`, `unavailable`, or `not-attempted`, and `frontmatterInspected` true only when the guidance gate permits inspection.
- [ ] T015 [US2] Implement guarded content inspection in `skills/vault-orientation/scripts/VaultInventory.psm1`: remain names-only when applicable local guidance is absent; otherwise read only eligible Markdown/frontmatter after all guidance loads, never open attachment or non-Markdown contents, and revalidate component-aware vault containment before every access using existing boundary APIs.
- [ ] T016 [US2] Implement provisional candidate mappings in `skills/vault-orientation/scripts/VaultInventory.psm1` with `role`, one or more observed-entry targets, basis values limited to `profile-configured`, `default-convention`, `entry-name`, `folder-name`, `frontmatter`, `markdown-content`, and `dm-selected-guidance`, concise evidence, non-empty uncertainty when present, and status in `configured`, `provisional`, `conflicted`, or `awaiting-dm-confirmation`; never confirm a mapping from a folder or filename alone.
- [ ] T017 [US2] Implement ambiguity and atomic-report behavior in `skills/vault-orientation/scripts/VaultInventory.psm1`: each ambiguity has at least two alternatives, impact in `informational`, `task-relevant`, or `blocks-dependent-work`, and a required `decisionNeeded` for task-relevant cases; return no partial `inventoryReport` after any traversal/read failure and sanitize failure details.
- [ ] T018 [P] [US2] Update `skills/vault-orientation/SKILL.md` with names-only versus guidance-enabled behavior, inventory exclusions, deterministic read-only reporting, provisional mapping and ambiguity semantics, and the behavior when traversal or reads fail.

**Checkpoint**: Each supported layout is inventoried without writes, disallowed content reads, unsafe link traversal, forced mapping, or partial results.

---

## Phase 5: User Story 3 - Review Proposed Mappings Without Losing Control (Priority: P2)

**Goal**: Allow the DM to request and review an evidence-backed profile proposal while preserving explicit control and leaving the vault unchanged.

**Independent Test**: Request and decline proposals on disposable fixtures; verify observed facts, inferred mappings, ambiguities, and proposed profile content are distinguishable, the proposal remains unapproved, and no profile or campaign files change.

### Tests for User Story 3

- [ ] T019 [US3] Add proposal opt-in cases to `tests/powershell/VaultOrientationInventory.Tests.ps1`, asserting omitted or false `proposeProfile` yields no proposal and true yields only a reviewable, `drafted-unapproved` proposal with evidence, uncertainty, and unresolved alternatives.
- [ ] T020 [US3] Add profile-review side-effect cases to `tests/powershell/VaultOrientationInventory.Tests.ps1`, snapshotting the vault before and after ordinary, ambiguous, declined, and proposed runs and asserting no file or directory is created, modified, moved, renamed, or deleted.
- [ ] T021 [US3] Add mapping-conflict cases to `tests/powershell/VaultOrientationInventory.Tests.ps1`, asserting configured profile facts, observed layout, provisional mappings, ambiguities, and proposal evidence remain separate and no competing mapping is silently selected.

### Implementation for User Story 3

- [ ] T022 [US3] Implement opt-in profile proposal output in `skills/vault-orientation/scripts/VaultInventory.psm1`: produce zero or one proposal only when requested, include evidence, uncertainty, and unresolved alternatives, and expose only the `drafted-unapproved` state without invoking any write operation.
- [ ] T023 [US3] Integrate the proposal with the inventory report in `skills/vault-orientation/scripts/VaultInventory.psm1`, keeping observed entries, configured mappings, provisional mappings, ambiguities, and proposed profile content distinct; ensure decline or omission produces no write target or persistence action.
- [ ] T024 [P] [US3] Update `skills/vault-orientation/SKILL.md` to explain proposal opt-in, evidence and uncertainty review, DM control over ambiguity, decline behavior, and the prohibition on profile writes or vault reorganization in this operation.

**Checkpoint**: Proposals are optional, evidence-backed, unapproved, and review-only; every outcome leaves the vault unchanged.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate the complete feature against its acceptance scenarios and preserve the documented support boundary.

- [ ] T025 Run the focused acceptance suite and full Pester acceptance suite using `tests/powershell/Invoke-Tests.ps1` and the command in `specs/006-vault-orientation-inventory/quickstart.md`; resolve regressions only in the inventory operation files and `tests/powershell/VaultOrientationInventory.Tests.ps1`.
- [ ] T026 Verify the implementation and user-facing behavior in `skills/vault-orientation/SKILL.md` and `docs/powershell-runtime-support.md` continue to distinguish synthetic test authorization from production authorization and do not claim installed-client or unverified-platform support.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No setup work is required; the plugin structure, runtime, and test harness already exist.
- **Foundational (Phase 2)**: T001 registers and validates the operation request shape; it blocks all user-story implementation.
- **User Stories (Phases 3–5)**: Each depends on T001. US2 also depends on US1's preflight/guidance integration; US3 depends on US2's mapping and ambiguity report.
- **Polish (Phase 6)**: Depends on all desired stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after T001; establishes safe preflight and guidance gates. Production operation remains blocked until trusted active-session exact-vault authorization is verified.
- **User Story 2 (P1)**: Starts after US1; depends on its preflight and guidance gates before any enumeration or content read.
- **User Story 3 (P2)**: Starts after US2; depends on observed entries, mappings, and ambiguities to construct an evidence-backed proposal.

### Within Each User Story

- Add that story's Pester acceptance cases before implementation.
- Within US1, selected-guidance loading and inventory entry-point integration depend on the request contract from T001; update the skill after the preflight behavior is established.
- Within US2, implement enumeration before content inspection, then mappings and ambiguities, then update the workflow documentation.
- Within US3, implement proposals only after mapping/ambiguity behavior exists; documentation may proceed in parallel with proposal implementation.

### Parallel Opportunities

- US1 skill documentation (T008) can run in parallel with its implementation tasks after the preflight contract is fixed.
- US2 skill documentation (T018) can run in parallel with implementation tasks after the report contract is stable.
- US3 skill documentation (T024) can run in parallel with proposal implementation.
- Story phases themselves are sequential because US2 relies on US1's gates and US3 relies on US2's report; test tasks share one focused test file and should not be parallelized against one another.

### Dependency Graph

```text
T001
 └── US1: T002–T008
      └── US2: T009–T018
           └── US3: T019–T024
                └── Polish: T025–T026
```

## Parallel Example: User Story 2

```text
After the US2 report contract is stable:
Task: "Implement safe enumeration, observed records, and guarded reads in skills/vault-orientation/scripts/VaultInventory.psm1"
Task: "Document the inventory behavior in skills/vault-orientation/SKILL.md"
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 to register and validate the read-only request.
2. Complete US1 to enforce exact-vault preflight and guidance gates.
3. Run US1 focused acceptance cases with disposable fixtures and test-only authorization.
4. Stop before production use unless trusted active-session authorization is independently verified.

### Incremental Delivery

1. Complete the request foundation and US1 safety gates.
2. Add US2 read-only inventory and independently validate layout/content boundaries.
3. Add US3 opt-in review-only profile proposals and independently validate no-write behavior.
4. Run the full Pester acceptance suite; do not claim support beyond the verified runtime/client/platform boundary.

## Notes

- The feature is a design proposal; tasks create new behavior rather than describing already implemented runtime functionality.
- Reuse existing Feature 001/002/003 preflight, profile, guidance, boundary, and result contracts; do not add authorization bypasses or duplicate those features.
- Test-only authorization proves synthetic acceptance behavior only. Production script-backed profile, guidance, and note access remain fail-closed until a trusted active-session authorization handoff is verified.
- No scale, latency, throughput, or vault-size threshold is specified; do not invent one.
- `[P]` tasks operate in different files with no unfinished-task dependency; user stories remain sequenced by their documented dependencies.
