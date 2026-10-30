# Tasks: PowerShell Runtime and Safe Operations

**Input**: Design documents from `specs/003-powershell-runtime-safety/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/powershell-runtime-contract.md`, and `quickstart.md`

**Tests**: Acceptance validation is required by FR-015 and the quickstart. Use synthetic, disposable vault fixtures only; never use a real campaign vault. Tests run in the two tiers defined in `plan.md` (Technical Context → Testing):

- **Production-gate tests** run the real preflight with no authorization provider and must observe `VAULT_AUTHORIZATION_UNPROVEN` before any profile, guidance, or note access and before any write. T005, the production-gate case in T028, and the T010 and T046 runs exercise the T008 gate this way.
- **Downstream tests** (path containment, inspection, profile parsing/schema/filesystem, preview, safe write, conflict, interruption, partial completion) reach their behavior only through a test-only authorization provider that the harness injects through an explicit parameter. It is confined to `tests/powershell/`, is never discoverable by production code or any skill, and never proves that Feature 001's signal exists.

**Organization**: Tasks are grouped by user story so the runtime can be delivered in safe, independently validated increments. Runtime modules and a synthetic harness now exist; production authorization and release qualification remain blocked or unverified.

## Phase 1: Setup

**Purpose**: Establish release support and a safe acceptance-test foundation without adding runtime behavior to the plugin root.

- [X] T001 Document the supported PowerShell 7 and operating-system combinations in `docs/powershell-runtime-support.md` and link to it from `README.md`. Select the latest stable PowerShell 7 release at selection time (7.4 or later, so built-in `Test-Json -Schema` provides the Draft 2020-12 validator), plus the exact `powershell-yaml` (YAML reader) version, and record the selection date and provisioning guidance. List a combination as supported only after it passes the prerequisite, repeatability, and failure checks and can reliably perform the path-resolution, atomic-replace, and encoding checks the contract requires; document every other combination as unsupported. Add an empty "Verification evidence" section.
- [X] T002 Pin the test-only Pester 6 acceptance runner (confirmed against the T001 PowerShell release) and record its exact version in `docs/powershell-runtime-support.md`; it is never a prerequisite for plugin installation or a DM's workflow. Then create synthetic disposable-vault fixtures and a test-only authorization provider in `tests/powershell/`. Inject the provider only through an explicit test-harness parameter, never from a path, environment variable, or configuration, so production modules and skills cannot discover, load, or reference it.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared result contract and module/test conventions used by all future operations.

**⚠️ CRITICAL**: Story implementation depends on these shared contract and test conventions.

- [X] T003 Implement the transport-neutral result object and validator in `skills/vault-orientation/scripts/RuntimeContract.psm1` with the exact field order `operation`, `completionStatus`, `completionCode`, `changedTargets`, `unchangedTargets`, `remainingWork`, and optional `errorDetails`; allow only the three statuses and the stable codes in `specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`. Define a target record as a vault-relative path plus an outcome (`written`, `deleted`, `unchanged`, `conflict`, `failed`, or `not attempted`), require `changedTargets` and `unchangedTargets` to partition the requested targets, and establish the module conventions every script follows: `-LiteralPath` for every filesystem cmdlet, no `Invoke-Expression`, `[scriptblock]::Create`, or `-Command`/argument strings, and no reference to `tests/` (audited by T034).
- [X] T004 Add contract tests for result field order, status/code mappings, target-record outcomes and the changed/unchanged partition, safe error details, and rejection of incomplete results marked `complete` in `tests/powershell/RuntimeContract.Tests.ps1`.

**Checkpoint**: Shared contract and synthetic test conventions are ready; all vault-facing operations must still fail closed until the Feature 001 authorization signal is verified.

---

## Phase 3: User Story 1 - Run a Script-Backed Workflow Safely (Priority: P1) 🎯 MVP

**Goal**: Check runtime and declared dependencies before script execution or vault access; provide a specific fail-closed result without automatic installation or upgrade.

**Independent Test**: In each claimed supported environment, run the real preflight with no authorization provider and test valid prerequisites and, separately, a missing or unsupported runtime, module, or dependency and absent or inconclusive exact-vault authorization. The authorization case returns `VAULT_AUTHORIZATION_UNPROVEN` until Feature 001's signal is verified. Blocked requests must return a specific result before profile, guidance, or campaign-note access, and no prerequisite is installed or upgraded. Separately verify that installing and discovering the plugin and its skills succeeds with no PowerShell present (FR-005, SC-001).

- [X] T005 [P] [US1] Add production-gate acceptance cases, run with no authorization provider, in `tests/powershell/RuntimePreflight.Tests.ps1`: a missing or unsupported runtime, module, or dependency returns `PREREQUISITE_MISSING`, and absent or inconclusive exact-vault authorization returns `VAULT_AUTHORIZATION_UNPROVEN`. Assert `not completed`, zero profile/note reads or writes, no automatic prerequisite installation, and that no authorization assertion in a request field, path, environment variable, configuration, or profile changes the result.
- [X] T006 [US1] Implement release-matrix checks for the documented PowerShell 7 version, supported operating system, and operation-required module versions; return `PREREQUISITE_MISSING` for a missing or unsupported prerequisite without installing or upgrading anything in `skills/vault-orientation/scripts/RuntimePreflight.psm1`.
- [X] T007 [US1] Implement the Feature 001 dependency-readiness adapter in `skills/vault-orientation/scripts/DependencyPreflight.psm1` using Feature 001's authoritative inventory (**Expected Runtime Dependencies** in `specs/001-shared-vault-guidance/spec.md`) without maintaining a divergent Feature 003 copy. Check each declared dependency's `readinessState` (`ready`, `missing`, `incompatible`, or `unknown`; initially `obsidian-link-resolver` 2.0.0 or later exposing `resolve_obsidian_link`) separately from exact-vault authorization, recording only non-content-bearing evidence. Per `data-model.md`, "`unknown` is not success. Do not resolve a campaign link to establish authorization."
- [X] T008 [US1] Implement the exact-vault authorization handoff in `skills/vault-orientation/scripts/DependencyPreflight.psm1`; until Feature 001's note-content-free signal is defined and verified, return `VAULT_AUTHORIZATION_UNPROVEN` before reading the profile, guidance, or campaign notes and before any write. Production preflight accepts no authorization assertion from request fields, paths, environment variables, configuration, or the profile, and never discovers or loads the test-only provider (contract section 3).
- [X] T009 [US1] Wire vault-facing invocations in `skills/vault-orientation/SKILL.md` to run the runtime prerequisite check and then the FR-027 ordered pre-note sequence: establish the authorized vault; verify readiness and exact-vault authorization for every declared dependency; load the plugin-owned shared reference and any designated local guidance; establish campaign/group and player-facing output context; then access only relevant notes. When no local guidance is designated, permit only a specific read-only lookup that does not depend on uncertain folder or note-role mappings and stop for DM direction otherwise (FR-023). Do not treat script execution as proof that the assistant loaded shared guidance, keep static plugin installation/discovery independent of PowerShell, and preserve independent read-only assistance when scripts are blocked.
- [ ] T010 [US1] Run the production-gate repeatability and failure acceptance cases in every documented supported environment and verify that installing the plugin and discovering its skills succeeds with no PowerShell present (FR-005, SC-001). Record sanitized results and exact versions in the "Verification evidence" section of `docs/powershell-runtime-support.md`, and mark unverified platform/runtime combinations unsupported.

  **Partial:** Local production-gate repeatability/failure checks pass. Static
  source inspection does not complete the required installation and discovery
  run without PowerShell; that evidence remains outstanding with T046.

**Checkpoint**: Runtime/dependency failures block safely; exact-vault authorization remains fail-closed until Feature 001 supplies its signal.

---

## Phase 4: User Story 2 - Select and Inspect the Intended Vault (Priority: P1)

**Goal**: Select only an explicit vault target, enforce canonical path containment, inspect read-only, and load plugin resources independently of the working directory.

**Independent Test**: Use synthetic fixtures to issue the same read-only request from multiple working directories; test missing/ambiguous roots, forbidden path forms, in-vault and escaping intermediate/leaf symlinks, and verify inspection leaves fixture bytes unchanged. Reach inspection only through the harness-injected provider (downstream tier), and confirm with no provider that the authorization gate still runs first and blocks before profile, guidance, or campaign-note access.

- [X] T011 [P] [US2] Add request validation in `skills/vault-orientation/scripts/OperationRequest.psm1` for the contract section 2 fields: `contractVersion` (currently `1`), `requestId` (a correlation identifier, never an authorization token), `operation`, explicit absolute `vaultRoot`, `campaignGroup` (explicit `campaign` and `group` values or explicit `null`), `mode` (`inspect`, `preview`, or `apply`), `arguments`, ordered `targets`, `approvedPreviewId`, `reviewedVersions` (required with `approvedPreviewId`, one entry per target in `targets` order carrying its `observedVersion`, `replacementVersion`, and `preserve` `conversionDecision`), `reviewedDependencyVersions` (required with `approvedPreviewId`, ordered dependency identities and versions), and `declinedReviewId` (valid only with `mode: apply`). Reject `declinedReviewId` combined with `approvedPreviewId`, reject unknown request fields and operation arguments, and infer no value from the current directory, plugin directory, notes, profile, or environment/home-directory expansion; validate request shape only, leaving root resolution to T013 after the authorization gate; and return `INVALID_REQUEST` for absent, malformed, or invalid inputs.
- [X] T012 [P] [US2] Implement lexical validation for vault-relative paths in `skills/vault-orientation/scripts/VaultPathValidation.psm1`, requiring a non-empty path with `/` separators and rejecting absolute forms, a leading `/`, backslashes, drive/URI syntax, NUL/control characters, wildcards, and `.` or `..` components with `PATH_INVALID`; expand no variables, home-directory markers, or Obsidian links.
- [X] T013 [US2] Implement canonical vault-root resolution, only after the authorization gate, and component-aware target containment in `skills/vault-orientation/scripts/VaultBoundary.psm1`, resolving existing path components including intermediate and leaf symbolic links without invoking an external shell command. Return `VAULT_TARGET_INVALID` when the root is missing, ambiguous, inaccessible, or not a valid explicit target; refuse an unresolved, cyclic, inaccessible, or out-of-bound resolution before accessing the target, returning `PATH_OUTSIDE_VAULT` for an escape or when containment cannot be proven (a cyclic or unresolvable link chain) and `READ_FAILED` when a path component is inaccessible; recheck the boundary before every access; create no missing directory and infer no replacement target.
- [X] T014 [US2] Implement read-only inspection in `skills/vault-orientation/scripts/VaultInspection.psm1`, running only after the authorization gate and using the validated explicit request and vault boundary; ensure inspect mode cannot create or change files, reports missing or ambiguous targets without guessing, returns `complete` with `OK` (or `NO_CHANGES` when the request needed no change) when inspection finishes, and uses `READ_FAILED` for an operational read failure.
- [X] T015 [US2] Move the sole canonical schema artifact to the consuming skill's packaged resource location and update Feature 002, README, and architecture references without retaining a divergent duplicate in `skills/vault-orientation/assets/dmassist.schema.json`, `schemas/dmassist.schema.json`, `README.md`, `docs/architecture.md`, and `specs/002-vault-configuration-contract/`.
- [X] T016 [US2] Implement installed owner-skill resource lookup for the packaged schema in `skills/vault-orientation/scripts/PluginResources.psm1`, independent of the current directory; return `RESOURCE_MISSING` when the artifact cannot be found or read and `RESOURCE_INCOMPATIBLE` when it does not match the required contract or Draft 2020-12 dialect, with no checkout, vault, or current-directory fallback.
- [X] T017 [P] [US2] Add downstream-tier synthetic acceptance cases in `tests/powershell/VaultSelection.Tests.ps1` for working-directory independence, explicit/missing/ambiguous vault roots (`VAULT_TARGET_INVALID`), malformed requests (`INVALID_REQUEST`), forbidden lexical paths (`PATH_INVALID`), in-vault and escaping intermediate/leaf symlinks and cyclic link chains (`PATH_OUTSIDE_VAULT` for escapes and cycles), and byte-for-byte unchanged inspection.
- [X] T018 [US2] Add installed-plugin acceptance checks in `tests/powershell/InstalledResource.Tests.ps1` that load and use the same schema artifact from at least two working directories and return `RESOURCE_MISSING` or `RESOURCE_INCOMPATIBLE`, blocking before profile use, for a missing or incompatible resource, following `specs/003-powershell-runtime-safety/quickstart.md`; record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md`.
- [X] T019 [US2] Run repeatability and path-boundary acceptance cases in every claimed supported environment; record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md` and leave any unverified environment unsupported.

**Checkpoint**: Explicit target selection, read-only inspection, path boundaries, and installed-resource behavior are independently validated.

---

## Phase 5: User Story 4 - Validate Vault Configuration Before Use (Priority: P1)

**Goal**: Parse and validate an optional profile under Feature 002's contract, using one packaged schema and rejecting invalid or stale settings before dependent work.

**Independent Test**: With the harness-only authorization provider (downstream tier) in isolated fixtures, test absent and valid profiles plus malformed YAML, duplicate keys, scalar normalization, invalid versions/fields, schema failures, missing configured folders, invalid references, shared or nested section mappings, undetermined destinations, path escapes, and changed inputs. Assert absent-profile discovery is read-only, a present invalid profile never falls back to discovery, and, with no provider, no profile is read.

- [X] T020 [P] [US4] Add downstream-tier synthetic parser/normalization cases in `tests/powershell/ProfileParsing.Tests.ps1` for malformed or unsupported YAML and duplicate mapping keys (`PROFILE_PARSE_INVALID`); YAML aliases and merge keys (forms the selected reader does not support return `PROFILE_PARSE_INVALID`, and supported forms are accepted only when the resolved profile passes schema validation); typed scalar conversions; explicit nulls and collection values in scalar positions (`PROFILE_NORMALIZATION_INVALID`); and the integer profile version.
- [X] T021 [P] [US4] Add downstream-tier synthetic schema/default cases in `tests/powershell/ProfileSchema.Tests.ps1` proving normalized valid and invalid profiles are validated against the installed Draft 2020-12 artifact (a schema violation returns `PROFILE_SCHEMA_INVALID`; a PowerShell release whose `Test-Json` lacks Draft 2020-12 support returns `PREREQUISITE_MISSING`) and that schema `default` annotations do not mutate or populate the source profile.
- [X] T022 [US4] Implement YAML parsing and Feature 002 scalar normalization in `skills/vault-orientation/scripts/VaultConfiguration.psm1`. Reject malformed or unsupported syntax and duplicate mapping keys with `PROFILE_PARSE_INVALID`, and handle aliases and merge keys only as the selected reader supports them (`powershell-yaml`/YamlDotNet merge-key mode is opt-in and must be enabled explicitly if used). Normalize to locale-independent non-empty strings, lowercase booleans, and ISO 8601 dates/timestamps, reject null/collection values in string fields with `PROFILE_NORMALIZATION_INVALID`, and preserve `version` as integer `1`.
- [X] T023 [US4] Implement normalized-profile validation in `skills/vault-orientation/scripts/VaultConfiguration.psm1` against the installed canonical schema using built-in `Test-Json -Schema` (Draft 2020-12), serializing the normalized profile to JSON first, returning `PROFILE_SCHEMA_INVALID` for a schema violation without echoing profile values and `PREREQUISITE_MISSING` when the PowerShell release lacks Draft 2020-12 `Test-Json` support; apply only Feature 002's documented defaults after successful validation, without mutating the source profile or duplicating profile semantics.
- [X] T024 [US4] Implement configured path/reference validation in `skills/vault-orientation/scripts/VaultConfiguration.psm1`. Apply the T012 lexical rules (`PATH_INVALID`) and T013 canonical containment to every configured section, guidance, party, preparation, and template path (FR-021). During profile validation, a configured path that escapes the vault, or a configured section folder that is missing or not a folder, rejects the entire profile with `PROFILE_FILESYSTEM_INVALID`; check the existence, readability, and type of a configured guidance file, template, party note, or preparation location only when an operation needs it, returning `REFERENCE_UNAVAILABLE` (contract section 8 configured-path code selection). Accept shared or nested section mappings; return `AMBIGUOUS_CONTEXT` when classification or destination is undetermined; create no folder and substitute no source; never substitute a plugin default for an explicitly configured template, and report "no template available" and ask the DM when none applies; an absent, undesignated guidance file does not invalidate the profile, but then permit only a specific `inspect` lookup that does not depend on uncertain folder or note-role mappings and stop any other request before campaign-note access with `AMBIGUOUS_CONTEXT` (FR-023).
- [X] T025 [US4] Implement profile/reference version tracking and stale-input handling in `skills/vault-orientation/scripts/VaultConfiguration.psm1`; stop dependent work with `TARGET_CONFLICT`, identify the changed profile or reference without exposing contents, and require revalidation without automatic retry or mixed old/new state.
- [X] T026 [US4] Implement absent-versus-present profile behavior in `skills/vault-orientation/scripts/VaultConfiguration.psm1`; use only Feature 002's read-only discovery when absent, report inferred candidates with reasons and alternatives, and never fall back to discovery for a present invalid profile.
- [X] T027 [P] [US4] Add downstream-tier synthetic filesystem/reference cases in `tests/powershell/ProfileFilesystem.Tests.ps1` for forbidden lexical forms in configured paths (`PATH_INVALID`), explicit missing or wrong-type section directories and escaping configured paths during profile validation (`PROFILE_FILESYSTEM_INVALID`), a missing, unreadable, or invalid guidance file, template, party note, or preparation location at use time (`REFERENCE_UNAVAILABLE`), symlink containment, shared or nested section mappings, undetermined destinations (`AMBIGUOUS_CONTEXT`), no plugin-default substitution for an explicit template, an absent undesignated guidance file, deterministic resolution, and stale profile/reference changes (`TARGET_CONFLICT`).
- [X] T028 [P] [US4] Add synthetic profile-state cases in `tests/powershell/ProfileState.Tests.ps1` for absent-profile read-only discovery, inferred-candidate behavior, and present-invalid no-fallback behavior (downstream tier), plus a production-gate case proving zero profile access before exact-vault authorization when no provider is supplied, and a downstream-tier ordering case that, with the harness provider and every gate passing, records access order and asserts the contract section 3 sequence (vault root, dependency readiness and authorization, shared reference, profile designation and guidance, campaign/group context) with no campaign-note access before the last gate (FR-027), and a downstream-tier case with a valid profile and no designated local guidance proving a specific mapping-independent `inspect` lookup completes while a mapping-dependent lookup, a preview, or an apply returns `AMBIGUOUS_CONTEXT` before campaign-note access (FR-023).
- [X] T029 [US4] Run the downstream-tier configuration acceptance cases in every claimed supported environment; verify the installed artifact is used and record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md`. Profile access under the real exact-vault authorization signal stays unverified until Feature 001's signal is defined and verified.

**Checkpoint**: Configuration parsing, normalization, schema and filesystem validation, discovery, and staleness behavior satisfy Feature 002's contract without authorizing note access ahead of Feature 001.

---

## Phase 6: User Story 3 - Understand Results and Control Changes (Priority: P2)

**Goal**: Provide stable operation outcomes and safe, previewed, conflict-aware, atomic note changes with accurate partial-completion reporting.

**Independent Test**: Through the harness-injected provider (downstream tier), use synthetic notes to test ordered result fields/codes, inspection and preview with zero writes, exact-preview approvals, target changes after review, supported encoding preservation and unsupported-encoding refusal, interruption during a write, and multi-note first-failure behavior. Verify changed/unchanged/remaining target lists and no rollback. Confirm command-like content and paths are treated as data and diagnostics omit note content.

- [X] T030 [P] [US3] Add synthetic result-contract cases in `tests/powershell/RuntimeResults.Tests.ps1` that exercise every applicable contract completion code with each of its allowed statuses, deterministic target lists, safe error details, and rejection of incomplete results labeled complete at the preflight, inspect, preview, and apply entry points; where a code allows two statuses, assert `partially completed` only when an earlier target changed.
- [X] T031 [P] [US3] Add synthetic preview/approval cases in `tests/powershell/ChangeApproval.Tests.ps1` proving preview is read-only, broad changes require approval of the exact current preview (`CONFIRMATION_REQUIRED` when approval is absent or does not match), a single named-note text edit proceeds without approval, changed `arguments` or targets produce a non-matching digest (`CONFIRMATION_REQUIRED`), a template, guidance file, or profile changed after preview makes the old approval return `TARGET_CONFLICT` with zero writes, a rebuilt replacement that no longer matches the carried `replacementVersion` returns `CONFIRMATION_REQUIRED` (induced by a harness-registered test-only operation under `tests/powershell/` whose replacement bytes differ between invocations, creating no production bypass), a changed `runtimeVersion` between preview and apply returns `CONFIRMATION_REQUIRED`, the same preview computed in two separate processes yields the same `previewId`, the removed `allowEncodingConversion` request field is rejected, and a DM decline or withdrawal submitted as `declinedReviewId` returns `USER_CANCELLED` with zero writes.
- [X] T032 [P] [US3] Add synthetic encoding cases in `tests/powershell/EncodingSafety.Tests.ps1` proving BOM-marked UTF-8/UTF-16 and BOM-less UTF-8 bytes and original line endings are preserved exactly, unsupported or undecodable content returns `ENCODING_UNSAFE` and is left byte-for-byte unchanged, an unsafe target does not produce an applicable preview, and encoding is assessed for every target before the first write.
- [X] T033 [P] [US3] Add synthetic conflict/interruption/multi-target cases in `tests/powershell/AtomicBatchWrites.Tests.ps1` proving immediate pre-write rechecks (a target mutated after preview and before the final check returns `TARGET_CONFLICT`; an escape found at the recheck returns `PATH_OUTSIDE_VAULT`), no partially written current note, first-failure stop with `WRITE_FAILED` or `INTERRUPTED` and `partially completed` only when an earlier target changed, no rollback, and exact changed/unchanged/remaining target reports.
- [X] T034 [P] [US3] Add synthetic data-handling cases in `tests/powershell/DataHandling.Tests.ps1` proving command-like note content and paths (`$()`, backticks, `;`, `|`, `[`, `]`, `*`) are never executed or wildcard-expanded, plus a static audit of `skills/vault-orientation/scripts/` that fails on `Invoke-Expression`, `[scriptblock]::Create`, `-Command`/argument strings, `Set-ExecutionPolicy`, `-ExecutionPolicy Bypass`, `Unblock-File`, non-literal path parameters, network APIs (`Invoke-WebRequest`, `Invoke-RestMethod`, `System.Net.*`), or any reference to `tests/`.
- [X] T035 [P] [US3] Add synthetic diagnostics cases in `tests/powershell/Diagnostics.Tests.ps1` proving error details contain no note content and no absolute paths beyond vault-relative targets.
- [X] T036 [US3] Add the shared entry-point result adapter in `skills/vault-orientation/scripts/RuntimeContract.psm1` that builds every entry-point result through the T003 envelope, without a second envelope implementation; return `OK` or `NO_CHANGES` for successful work and map an unhandled failure to `OPERATION_FAILED` with a status that reflects whether any requested target changed. Apply it to the existing preflight (`skills/vault-orientation/scripts/DependencyPreflight.psm1`) and inspect (`skills/vault-orientation/scripts/VaultInspection.psm1`) entry points; T038 and T041 adopt it for preview and apply.
- [X] T037 [US3] Implement safe local error reporting in `skills/vault-orientation/scripts/OperationDiagnostics.psm1` that omits full note contents and unnecessary sensitive paths and sends no usage or diagnostic telemetry off-device.
- [X] T038 [US3] Implement stateless read-only preview generation and exact-preview approval checks in `skills/vault-orientation/scripts/ChangePreview.psm1`, returning results only through the T036 adapter: a preview identifies the exact targets, proposed operation per target, each target's `observedVersion`, `replacementVersion`, and `conversionDecision`, and the ordered dependency versions from T016 resource identities and T025 profile/reference versions, without note content; unsafe targets return `ENCODING_UNSAFE` without an applicable preview. Compute `previewId` as the contract section 9 RFC 8785 JCS-serialized deterministic digest of `contractVersion`, `runtimeVersion`, `operation`, canonical `vaultRoot`, `campaignGroup`, ordered `targets`, `arguments`, reviewed target versions, replacement versions, and encoding decisions, and dependency versions, never relying on hashtable enumeration order and storing no preview state; classify multi-target, deletion, and reorganization changes and require approval when the registered operation declares fact-changing effects or the change cannot be classified, never letting a request lower that classification; allow a single named-note text edit without approval; on an approved apply, return `CONFIRMATION_REQUIRED` when required approval is absent or the digest recomputed from the request and carried reviewed versions does not match `approvedPreviewId`, then `TARGET_CONFLICT` when a current target or dependency version differs from its carried version, then `CONFIRMATION_REQUIRED` when a rebuilt replacement differs from its carried `replacementVersion`; return `USER_CANCELLED` with no write for a `declinedReviewId`, while a stop during apply is `INTERRUPTED`.
- [X] T039 [US3] Implement note-byte preparation in `skills/vault-orientation/scripts/SafeNoteWriter.psm1`, assessing encoding and decodability for every target before the first write. Preserve unrelated Markdown, supported encoding, and line endings when BOM-marked UTF-8/UTF-16 or BOM-less UTF-8 strictly decode and round-trip byte-for-byte; otherwise return `ENCODING_UNSAFE` without writing. Do not convert note encodings or create a warning/acknowledgment flow.
- [X] T040 [US3] Implement per-note same-filesystem staging and rename-class atomic replacement in `skills/vault-orientation/scripts/SafeNoteWriter.psm1`, never truncating and rewriting the live file; recheck the canonical boundary and target/dependency version (T016 resource identities and T025 profile/reference versions) immediately before replacement against the carried reviewed versions for an approved apply, or the versions read earlier in the same invocation otherwise (`TARGET_CONFLICT` for a changed target or dependency, `PATH_OUTSIDE_VAULT` for an escape) and clean up abandoned staging data when possible. Ensure a `WRITE_FAILED` or `INTERRUPTED` outcome leaves the target complete and unchanged or complete and replaced, never partially written, and claim no stronger concurrency guarantee than the platform primitive provides.
- [X] T041 [US3] Implement deterministic multi-note apply in `skills/vault-orientation/scripts/ApplyNoteChanges.psm1`, returning results only through the T036 adapter and processing targets in the previewed order; stop at the first failure or interruption, retain earlier successful writes without rollback, skip later targets (reported as `not attempted` and in `remainingWork`), and report the specific cause (`WRITE_FAILED`, `INTERRUPTED`, `TARGET_CONFLICT`, or `OPERATION_FAILED`) with `partially completed` only when an earlier target changed, plus exact changed, unchanged, and remaining work.
- [X] T042 [US3] Run all result, preview, conflict, preservation/refusal, interruption, partial-failure, data-handling, and diagnostics acceptance cases in every claimed supported environment and record sanitized results in the "Verification evidence" section of `docs/powershell-runtime-support.md`.

**Local acceptance evidence (2026-10-30):** Full suite: 296 passed, 0 failed,
4 file-symlink cases skipped. T042 records the local Windows candidate run,
not production platform qualification; no platform is claimed supported.
Installed-client and full environment qualification remain T046.

**Checkpoint**: Individual writes are safe and multi-note outcomes are accurate; failures never appear as full success or trigger rollback.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Verify the integrated future runtime, documentation, package layout, and supported-platform claims.

- [X] T043 [P] Audit the skill inventory and every immediate-child skill against the plugin architecture; classify each vault-facing skill and verify its required ordered pre-note checks without claiming unimplemented runtime behavior in `skills/README.md` and `skills/*/SKILL.md`.
- [X] T044 Verify that the one installed schema resource, dependency ownership, authorization gate, and supported runtime guidance agree in `README.md`, `AGENTS.md`, `docs/architecture.md`, `specs/002-vault-configuration-contract/`, and `specs/003-powershell-runtime-safety/contracts/`; update the "No build, test, or lint commands" statement in `AGENTS.md` once a test runner exists, and request a separate constitution PATCH through `/speckit-constitution` for the matching Development Workflow statement.
- [ ] T045 Review all user-facing result messages and run a usability walkthrough with at least 5 DMs; record an anonymized SC-006 pass rate in `docs/powershell-runtime-support.md`.
- [ ] T046 Run the complete synthetic Feature 003 quickstart in every declared supported environment and installed Copilot CLI client. Verify that production preflight still returns `VAULT_AUTHORIZATION_UNPROVEN` when no harness provider is supplied, that the installed plugin either excludes `tests/` or gains no authorization bypass from it, and that plugin installation and skill discovery succeed without PowerShell. Record sanitized evidence in the "Verification evidence" section of `docs/powershell-runtime-support.md`, mark unverified combinations unsupported, and confirm the exact-vault authorization blocker remains closed until Feature 001's signal is verified.

**Polish evidence (2026-10-30):** T043's static audit found exactly one
immediate-child skill (`vault-orientation`), matching its vault-facing inventory
entry and ordered pre-note safeguards. T044 reconciles runtime/module status,
canonical schema packaging, dependency ownership, and support limitations;
the separate constitution 1.0.1 PATCH is committed. T045 needs five real DM
participants. T010/T046 still need actual client and PowerShell-free discovery
evidence; simulated package tests do not complete them.

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
- **US3 (P2)**: Depends on US1's gate, US2's explicit request/path boundary and installed-resource identity (T016), and US4's profile/reference version tracking (T025) for preview dependency versions; uses the common result contract and does not roll back previous writes.

Until Feature 001 defines a verifiable note-content-free exact-vault authorization signal, production vault-facing work stays blocked. Production-gate tests (T005, the production-gate case in T028, and the T010 and T046 runs) run with no provider and expect `VAULT_AUTHORIZATION_UNPROVEN` before any profile, guidance, or campaign-note access. Downstream behavior tests (US2, US4, and US3) reach their behavior only through the harness-injected test provider; it stays isolated under `tests/powershell/`, is never discoverable by production code or skills, and creates no production bypass.

### Within Each User Story

- Keep test fixtures synthetic and separate from any real vault.
- Implement prerequisite and boundary checks before profile/note reads or writes.
- Keep Feature 002 defaults and semantics authoritative; do not duplicate them in runtime code.
- Recheck path boundaries and note versions immediately before every access/write.
- Complete the story's synthetic acceptance cases before claiming that story works independently.

## Parallel Opportunities

- **Setup**: T001 selects the PowerShell release first; T002 pins the test runner against it, and its fixture and test-provider authoring can run in parallel with T001.
- **Foundational**: T003 can run independently; T004 depends on T003.
- **US1**: T005 and T006 can start independently; T007 follows the dependency inventory and T008 must fail closed until the Feature 001 signal exists. T009 follows the gate wiring; T010 follows all implementation and acceptance cases.
- **US2**: T011 and T012 can run in parallel; T013 follows both; T014 and T015/T016 follow the boundary and authorization work. T017 can be authored against T011–T014 and may fail until they exist; T018 follows T015–T016; T019 follows the story tests.
- **US4**: T020 and T021 can be authored in parallel with the parser work; T022 → T023 → T024 → T025/T026. T027 and T028 can run in parallel; T029 follows all implementation and tests.
- **US3**: T030–T035 are independent synthetic test suites. T036 follows T008 and T014; T037 is independent; T038 depends on T016, T025, T036, and the request/result contract; T039 precedes T040, which also depends on T016 and T025; T041 depends on T036 and T040; T042 follows all story work.
- **Polish**: T043 can run independently; T044 and T045 follow story work; T046 follows all other tasks.
- Different story tasks may proceed in parallel only after US1's fail-closed gate and US2's shared request/path/resource contracts are stable; US3's T038 and T040 also wait for US4's T025 version tracking.

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
- `[P]` marks only tasks that can proceed independently without editing the same artifact or depending on incomplete tasks. A `[P]` test task is authored against the contract and may fail until its implementation tasks land.
- Acceptance tests use only synthetic, disposable vault fixtures; no real campaign content is required. They run in the two tiers described in the Tests section above: production-gate tests supply no authorization provider, and downstream tests use only the harness-injected provider confined to `tests/powershell/`.
- No production capability is available until implemented, packaged, and verified in the installed plugin and every claimed supported environment.
- An unavailable exact-vault authorization signal is a blocking condition, not permission to weaken or bypass preflight.
