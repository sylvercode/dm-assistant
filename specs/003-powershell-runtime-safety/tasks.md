# Tasks: PowerShell Runtime and Safe Operations

**Input**: Design documents from `specs/003-powershell-runtime-safety/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/powershell-runtime-contract.md`, and `quickstart.md`

**Tests**: Acceptance validation is required by FR-015 and the quickstart. Use synthetic, disposable vault fixtures only. Do not exercise campaign-note access unless the Feature 001 exact-vault authorization signal has been defined, delivered, and verified.

**Organization**: Tasks are grouped by user story so the future runtime can be delivered in safe, independently validated increments. The current repository is a plugin scaffold with no PowerShell runtime or test harness.

## Phase 1: Setup

**Purpose**: Establish release support and a safe acceptance-test foundation without adding runtime behavior to the plugin root.

- [ ] T001 Document the supported PowerShell 7 and operating-system combinations, exact runtime/add-on versions and selection date, provisioning guidance, unsupported combinations, and an empty "Verification evidence" section in `docs/powershell-runtime-support.md` and link to it from `README.md`.
- [ ] T002 Select and document a PowerShell acceptance-test runner, then create synthetic disposable-vault fixtures and a test-only authorization provider in `tests/powershell/`; inject the provider only through an explicit test-harness parameter so production skills cannot discover or load it.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared result contract and module/test conventions used by all future operations.

**⚠️ CRITICAL**: Story implementation depends on these shared contract and test conventions.

- [ ] T003 Implement the transport-neutral result object and validator in `skills/vault-orientation/scripts/RuntimeContract.psm1` with the exact field order `operation`, `completionStatus`, `completionCode`, `changedTargets`, `unchangedTargets`, `remainingWork`, and optional `errorDetails`; allow only the three statuses and the stable codes in `specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`.
- [ ] T004 Add contract tests for result field order, status/code mappings, target-list consistency, safe error details, and rejection of incomplete results marked `complete` in `tests/powershell/RuntimeContract.Tests.ps1`.

**Checkpoint**: Shared contract and synthetic test conventions are ready; all vault-facing operations must still fail closed until the Feature 001 authorization signal is verified.

---

## Phase 3: User Story 1 - Run a Script-Backed Workflow Safely (Priority: P1) 🎯 MVP

**Goal**: Check runtime and declared dependencies before script execution or vault access; provide a specific fail-closed result without automatic installation or upgrade.

**Independent Test**: In each claimed supported environment, test valid prerequisites and separately missing/unsupported runtime, modules, dependencies, and exact-vault authorization. Blocked requests must return a specific result before profile, guidance, or campaign-note access; no prerequisite is installed or upgraded.

- [ ] T005 [P] [US1] Add synthetic runtime, module, dependency, and inconclusive-authorization acceptance cases asserting a blocked result, zero profile/note reads or writes, and no automatic prerequisite installation in `tests/powershell/RuntimePreflight.Tests.ps1`.
- [ ] T006 [US1] Implement release-matrix checks for the documented PowerShell 7 version, supported operating system, and operation-required module versions; return the contract's prerequisite/unsupported-environment completion code without installing or upgrading prerequisites in `skills/vault-orientation/scripts/RuntimePreflight.psm1`.
- [ ] T007 [US1] Implement the Feature 001 dependency-readiness adapter using its authoritative inventory, checking resolver readiness, compatible version, and `resolve_obsidian_link` separately from vault authorization in `skills/vault-orientation/scripts/Preflight.psm1`.
- [ ] T008 [US1] Implement the exact-vault authorization handoff in `skills/vault-orientation/scripts/Preflight.psm1`; until Feature 001's note-content-free signal is defined and verified, return `VAULT_AUTHORIZATION_UNPROVEN` before reading the profile, guidance, or campaign notes and before any write. Production preflight accepts no authorization provider from any path, environment variable, or configuration.
- [ ] T009 [US1] Wire vault-facing invocations in `skills/vault-orientation/SKILL.md` to perform the ordered pre-note checks and runtime prerequisite check while keeping static plugin installation/discovery independent of PowerShell and preserving independent read-only assistance when scripts are blocked.
- [ ] T010 [US1] Run repeatability and failure acceptance cases in every documented supported environment, record sanitized results and exact versions in `docs/powershell-runtime-support.md`, and mark unverified platform/runtime combinations unsupported.

**Checkpoint**: Runtime/dependency failures block safely; exact-vault authorization remains fail-closed until Feature 001 supplies its signal.

---

## Phase 4: User Story 2 - Select and Inspect the Intended Vault (Priority: P1)

**Goal**: Select only an explicit vault target, enforce canonical path containment, inspect read-only, and load plugin resources independently of the working directory.

**Independent Test**: Use synthetic fixtures to issue the same read-only request from multiple working directories; test missing/ambiguous roots, forbidden path forms, in-vault and escaping intermediate/leaf symlinks, and verify inspection leaves fixture bytes unchanged. Confirm the authorization gate runs before profile, guidance, or campaign-note access.

- [ ] T011 [P] [US2] Add request validation for explicit absolute `vaultRoot`, campaign/group context, operation, mode, and ordered targets without inferring values from the current directory, plugin directory, notes, or environment expansion in `skills/vault-orientation/scripts/OperationRequest.psm1`.
- [ ] T012 [P] [US2] Implement lexical validation for vault-relative paths, requiring `/` separators and rejecting absolute forms, backslashes, drive/URI syntax, controls, wildcards, and `.` or `..` components in `skills/vault-orientation/scripts/VaultPathValidation.psm1`.
- [ ] T013 [US2] Implement canonical vault-root resolution and component-aware target containment, resolving existing path components including intermediate and leaf symbolic links; refuse unresolved or escaping targets and recheck boundaries before every access in `skills/vault-orientation/scripts/VaultBoundary.psm1`.
- [ ] T014 [US2] Implement read-only inspection using the validated explicit request and vault boundary; ensure inspect mode cannot create or change files and reports missing or ambiguous targets without guessing in `skills/vault-orientation/scripts/Inspect-Vault.psm1`.
- [ ] T015 [US2] Move the sole canonical schema artifact to the consuming skill's packaged resource location and update Feature 002, README, and architecture references without retaining a divergent duplicate in `skills/vault-orientation/assets/dmassist.schema.json`, `schemas/dmassist.schema.json`, `README.md`, `docs/architecture.md`, and `specs/002-vault-configuration-contract/`.
- [ ] T016 [US2] Implement installed owner-skill resource lookup for the packaged schema independent of the current directory; return the contract's missing/incompatible-resource code with no checkout, vault, or current-directory fallback in `skills/vault-orientation/scripts/PluginResources.psm1`.
- [ ] T017 [P] [US2] Add synthetic acceptance cases for working-directory independence, explicit/missing/ambiguous vault roots, forbidden lexical paths, in-vault and escaping symlinks, and byte-for-byte unchanged inspection in `tests/powershell/VaultSelection.Tests.ps1`.
- [ ] T018 [US2] Add installed-plugin acceptance checks that load and use the same schema artifact from at least two working directories and block on missing/incompatible resources, following `specs/003-powershell-runtime-safety/quickstart.md`, in `tests/powershell/InstalledResource.Tests.ps1`; record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md`.
- [ ] T019 [US2] Run repeatability and path-boundary acceptance cases in every claimed supported environment; record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md` and leave any unverified environment unsupported.

**Checkpoint**: Explicit target selection, read-only inspection, path boundaries, and installed-resource behavior are independently validated.

---

## Phase 5: User Story 4 - Validate Vault Configuration Before Use (Priority: P1)

**Goal**: Parse and validate an optional profile under Feature 002's contract, using one packaged schema and rejecting invalid or stale settings before dependent work.

**Independent Test**: With a synthetic authorization provider in isolated fixtures, test absent and valid profiles plus malformed YAML, duplicate keys, scalar normalization, invalid versions/fields, schema failures, missing configured folders, invalid references, shared or nested section mappings, undetermined destinations, path escapes, and changed inputs. Assert absent-profile discovery is read-only and a present invalid profile never falls back to discovery.

- [ ] T020 [P] [US4] Add synthetic parser/normalization cases for malformed or unsupported YAML, YAML aliases and merge keys (unsupported forms return `PROFILE_PARSE_INVALID`), duplicate mapping keys, typed scalar conversions, explicit nulls, collection values, and integer profile version in `tests/powershell/ProfileParsing.Tests.ps1`.
- [ ] T021 [P] [US4] Add synthetic schema/default cases proving normalized valid and invalid profiles use the installed Draft 2020-12 artifact and that schema annotations do not mutate the source profile in `tests/powershell/ProfileSchema.Tests.ps1`.
- [ ] T022 [US4] Implement YAML parsing with duplicate-key rejection and Feature 002 scalar normalization in `skills/vault-orientation/scripts/Resolve-VaultConfiguration.psm1`; use locale-independent non-empty strings, lowercase booleans, ISO 8601 dates/timestamps, reject null/collection values in string fields, and preserve `version` as integer `1`.
- [ ] T023 [US4] Implement normalized-profile validation against the installed canonical schema using Draft 2020-12 and apply only Feature 002's documented defaults after validation, without mutating the source profile or duplicating profile semantics in `skills/vault-orientation/scripts/Resolve-VaultConfiguration.psm1`.
- [ ] T024 [US4] Implement configured path/reference validation in `skills/vault-orientation/scripts/Resolve-VaultConfiguration.psm1`; verify canonical in-vault containment, required existence/readability/type, explicitly configured section-directory validity, and no folder creation or source substitution. Accept shared or nested section mappings; return `AMBIGUOUS_CONTEXT` when classification or destination is undetermined; never substitute a plugin default for an explicitly configured template, and report "no template available" and ask the DM when none applies; an absent, undesignated guidance file does not invalidate the profile.
- [ ] T025 [US4] Implement profile/reference version tracking and stale-input handling in `skills/vault-orientation/scripts/Resolve-VaultConfiguration.psm1`; stop dependent work, identify the changed dependency without exposing contents, and require revalidation without automatic retry or mixed old/new state.
- [ ] T026 [US4] Implement absent-versus-present profile behavior in `skills/vault-orientation/scripts/Resolve-VaultConfiguration.psm1`; use only Feature 002's read-only discovery when absent, report inferred candidates with reasons and alternatives, and never fall back to discovery for a present invalid profile.
- [ ] T027 [P] [US4] Add synthetic filesystem/reference cases for explicit missing directories, wrong-type/unreadable/missing references, symlink containment, shared or nested section mappings, undetermined destinations returning `AMBIGUOUS_CONTEXT`, no plugin-default substitution for an explicit template, an absent undesignated guidance file, deterministic resolution, and stale profile/reference changes in `tests/powershell/ProfileFilesystem.Tests.ps1`.
- [ ] T028 [P] [US4] Add synthetic profile-state cases for absent-profile read-only discovery, inferred-candidate behavior, present-invalid no-fallback behavior, and zero profile access before exact-vault authorization in `tests/powershell/ProfileState.Tests.ps1`.
- [ ] T029 [US4] Run configuration acceptance cases in every claimed supported environment; verify the installed artifact is used, record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md`, and defer positive profile-access checks until the exact-vault authorization signal is defined and verified.

**Checkpoint**: Configuration parsing, normalization, schema and filesystem validation, discovery, and staleness behavior satisfy Feature 002's contract without authorizing note access ahead of Feature 001.

---

## Phase 6: User Story 3 - Understand Results and Control Changes (Priority: P2)

**Goal**: Provide stable operation outcomes and safe, previewed, conflict-aware, atomic note changes with accurate partial-completion reporting.

**Independent Test**: Use synthetic notes to test ordered result fields/codes, inspection and preview with zero writes, exact-preview approvals, target changes after review, encoding preservation/conversion/refusal, interruption during a write, and multi-note first-failure behavior. Verify changed/unchanged/remaining target lists and no rollback. Confirm command-like content and paths are treated as data and diagnostics omit note content.

- [ ] T030 [P] [US3] Add synthetic result-contract cases for all completion codes/allowed statuses, deterministic target lists, safe error details, and rejection of incomplete results labeled complete at the preflight, inspect, preview, and apply entry points in `tests/powershell/RuntimeResults.Tests.ps1`.
- [ ] T031 [P] [US3] Add synthetic preview/approval cases proving preview is read-only, broad changes require approval of the exact current preview, a single named-note text edit proceeds without approval, and changed target versions or proposed effects invalidate approval in `tests/powershell/ChangeApproval.Tests.ps1`.
- [ ] T032 [P] [US3] Add synthetic encoding cases proving round-trippable bytes and line endings are preserved, conversion requires a warning and subsequent acknowledgement, and undecodable content is left byte-for-byte unchanged in `tests/powershell/EncodingSafety.Tests.ps1`.
- [ ] T033 [P] [US3] Add synthetic conflict/interruption/multi-target cases proving immediate pre-write rechecks, no partially written current note, first-failure stop, no rollback, and exact changed/unchanged/remaining target reports in `tests/powershell/AtomicBatchWrites.Tests.ps1`.
- [ ] T034 [P] [US3] Add synthetic data-handling cases proving command-like note content and paths (`$()`, backticks, `;`, `|`, `[`, `]`, `*`) are never executed or wildcard-expanded, plus a static audit of `skills/vault-orientation/scripts/` that fails on `Invoke-Expression`, `[scriptblock]::Create`, `Set-ExecutionPolicy`, `-ExecutionPolicy Bypass`, `Unblock-File`, non-literal path parameters, network APIs (`Invoke-WebRequest`, `Invoke-RestMethod`, `System.Net.*`), or any reference to `tests/` in `tests/powershell/DataHandling.Tests.ps1`.
- [ ] T035 [P] [US3] Add synthetic diagnostics cases proving error details contain no note content and no absolute paths beyond vault-relative targets in `tests/powershell/Diagnostics.Tests.ps1`.
- [ ] T036 [US3] Integrate the T003 result contract into the preflight, inspect, preview, and apply entry points so each returns a validated envelope, without a second envelope implementation, in `skills/vault-orientation/scripts/RuntimeContract.psm1`.
- [ ] T037 [US3] Implement safe local error reporting that omits full note contents and unnecessary sensitive paths and sends no usage or diagnostic telemetry off-device in `skills/vault-orientation/scripts/OperationDiagnostics.psm1`.
- [ ] T038 [US3] Implement read-only preview generation and exact-preview approval checks; allow a single named-note text edit without approval; require a new preview when targets, versions, scope, or proposed effects change; return `USER_CANCELLED` when the DM declines or withdraws a preview, while a stop during apply is `INTERRUPTED`, in `skills/vault-orientation/scripts/ChangePreview.psm1`.
- [ ] T039 [US3] Implement note-byte preparation that preserves unrelated Markdown, encoding, and line endings when reliably round-trippable; otherwise warn before writing and require a subsequent request acknowledging UTF-8 without BOM and LF conversion, while refusing undecodable content in `skills/vault-orientation/scripts/SafeNoteWriter.psm1`.
- [ ] T040 [US3] Implement per-note same-filesystem staging and rename-class atomic replacement, rechecking canonical boundary and target version immediately before replacement; ensure failure/interruption leaves the target complete and unchanged or complete and replaced, never partially written, in `skills/vault-orientation/scripts/SafeNoteWriter.psm1`.
- [ ] T041 [US3] Implement deterministic multi-note apply that stops at the first failure, retains earlier successful writes without rollback, skips later targets, and reports the specific cause plus exact changed, unchanged, and remaining work in `skills/vault-orientation/scripts/ApplyNoteChanges.psm1`.
- [ ] T042 [US3] Run all result, preview, conflict, preservation/conversion, interruption, partial-failure, data-handling, and diagnostics acceptance cases in every claimed supported environment and record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md`.

**Checkpoint**: Individual writes are safe and multi-note outcomes are accurate; failures never appear as full success or trigger rollback.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Verify the integrated future runtime, documentation, package layout, and supported-platform claims.

- [ ] T043 [P] Audit the skill inventory and every immediate-child skill against the plugin architecture; classify each vault-facing skill and verify its required ordered pre-note checks without claiming unimplemented runtime behavior in `skills/README.md` and `skills/*/SKILL.md`.
- [ ] T044 Verify that the one installed schema resource, dependency ownership, authorization gate, and supported runtime guidance agree in `README.md`, `AGENTS.md`, `docs/architecture.md`, `specs/002-vault-configuration-contract/`, and `specs/003-powershell-runtime-safety/contracts/`; update the "No build, test, or lint commands" statement in `AGENTS.md` once a test runner exists, and request a separate constitution PATCH through `/speckit-constitution` for the matching Development Workflow statement.
- [ ] T045 Review all user-facing result messages and run a usability walkthrough with at least 5 DMs; record an anonymized SC-006 pass rate in `docs/powershell-runtime-support.md`.
- [ ] T046 Run the complete synthetic Feature 003 quickstart in every declared supported environment and installed Copilot CLI client; verify the installed plugin either excludes `tests/` or gains no authorization bypass from it; record sanitized evidence in the "Verification evidence" section of `docs/powershell-runtime-support.md`, mark unverified combinations unsupported, and confirm the exact-vault authorization blocker remains closed until Feature 001's signal is verified.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No source dependencies; establishes support guidance and a synthetic acceptance harness.
- **Foundational (Phase 2)**: Depends on Setup; defines the common result contract and tests used by all story implementations.
- **User stories (Phases 3–6)**: Depend on the shared contract and harness. The stories are ordered by priority, subject to the dependencies below.
- **Polish (Phase 7)**: Depends on all selected stories and their platform acceptance results.

### User Story Dependencies

- **US1 (P1)**: First runtime increment; provides prerequisite checks and the fail-closed exact-vault gate.
- **US2 (P1)**: Depends on US1's preflight gate before any vault/resource consumer uses profile or note data.
- **US4 (P1)**: Depends on US1's authorization gate and US2's canonical installed schema packaging/resource lookup.
- **US3 (P2)**: Depends on US1's gate and US2's explicit request/path boundary; uses the common result contract and does not roll back previous writes.

Until Feature 001 defines a verifiable note-content-free exact-vault authorization signal, all acceptance tests of vault-facing work must expect a block before profile, guidance, or campaign-note access. Test-only authorization injection must remain isolated under `tests/powershell/` and must not create a production bypass.

### Within Each User Story

- Keep test fixtures synthetic and separate from any real vault.
- Implement prerequisite and boundary checks before profile/note reads or writes.
- Keep Feature 002 defaults and semantics authoritative; do not duplicate them in runtime code.
- Recheck path boundaries and note versions immediately before every access/write.
- Complete the story's synthetic acceptance cases before claiming that story works independently.

## Parallel Opportunities

- **Setup**: T001 and T002 can run in parallel.
- **Foundational**: T003 can run independently; T004 depends on T003.
- **US1**: T005 and T006 can start independently; T007 follows the dependency inventory and T008 must fail closed until the Feature 001 signal exists. T009 follows the gate wiring; T010 follows all implementation and acceptance cases.
- **US2**: T011 and T012 can run in parallel; T013 follows both; T014 and T015/T016 follow the boundary and authorization work. T017 can be authored against T011–T014; T018 follows T015–T016; T019 follows the story tests.
- **US4**: T020 and T021 can be authored in parallel with the parser work; T022 → T023 → T024 → T025/T026. T027 and T028 can run in parallel; T029 follows all implementation and tests.
- **US3**: T030–T035 are independent synthetic test suites. Implement T036–T037 independently; T038 depends on the request/result contract; T039 precedes T040; T041 depends on T040; T042 follows all story work.
- **Polish**: T043 can run independently; T044 and T045 follow story work; T046 follows all other tasks.
- Different story tasks may proceed in parallel only after US1's fail-closed gate and US2's shared request/path/resource contracts are stable.

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases.
2. Deliver US1 prerequisite checks and the explicit fail-closed authorization gate.
3. Validate blocked behavior in each claimed supported environment; do not claim campaign-note access before Feature 001 supplies the authorization signal.
4. Continue to US2 explicit target selection and read-only path-safe inspection; verify installed resource lookup from multiple working directories.

### Incremental Delivery

1. Add US4 profile parsing/normalization/schema/filesystem validation after US2 packages and verifies the canonical schema.
2. Add US3 result interpretation and safe writes after prerequisite and path boundaries are stable.
3. Complete cross-platform, installed-client, static inventory, and documentation checks.

## Notes

- Every task uses the required checklist format and includes a repository-relative file path.
- `[P]` marks only tasks that can proceed independently without editing the same artifact or depending on incomplete tasks.
- Acceptance tests use only synthetic, disposable vault fixtures; no real campaign content is required.
- No production capability is available until implemented, packaged, and verified in the installed plugin and every claimed supported environment.
- An unavailable exact-vault authorization signal is a blocking condition, not permission to weaken or bypass preflight.
