---

description: "Implementation tasks for the Vault Configuration Contract"
---

# Tasks: Vault Configuration Contract

**Input**: Design documents from `specs/002-vault-configuration-contract/`

**Prerequisites**: `plan.md`, `spec.md`; supporting context in `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`

**Scope**: Produce the written version-1 `.dmassist.yaml` contract and normalized-profile JSON Schema, with design-only validation scenarios. Do not implement a YAML reader, PowerShell runtime, loader, validator integration, filesystem checks, or plugin packaging. The canonical schema file currently lives at provisional repository path `schemas/dmassist.schema.json`; Issue #4 decides its final location alongside the consuming plugin component and verifies installed packaging and loader use.

**Tests**: No executable repository test suite or runtime loader exists. The one-off Draft 2020-12 schema verification below is required by SC-006 and must not add a repository/runtime dependency.

## Format and Path Conventions

- Every task uses `- [ ] T### [P?] [US#?] Description with exact file path(s)`.
- `[P]` marks tasks that edit different files and have no incomplete prerequisites.
- The schema path `schemas/dmassist.schema.json` is provisional as an installed-plugin location; plugin packaging and installed discovery belong to Issue #4.

## Phase 1: Setup

**Purpose**: Confirm the design-artifact scope and repository paths before story work.

- [ ] T001 Record the design-only deliverables, current repository paths, explicit Issue #4 runtime boundary, and Spec 001 preflight/authorization boundary before profile or campaign-note access in `specs/002-vault-configuration-contract/plan.md`.

---

## Phase 2: Foundational

**Purpose**: Establish the normalized profile and validation decisions used by all stories.

- [ ] T002 Document the Draft 2020-12 schema dialect, normalized-profile boundary, annotation-only defaults, scalar normalization contract, and Feature 002 versus Issue #4 ownership in `specs/002-vault-configuration-contract/research.md`.

**Checkpoint**: Profile and ownership decisions are clear before story-specific contract work.

---

## Phase 3: User Story 1 - Use an Existing Vault Without Migration (Priority: P1) 🎯 MVP

**Goal**: Describe read-only use of an existing vault without requiring configuration, a prescribed layout, or migration.

**Independent Test**: Review contract and scenarios for the Spec 001 preflight, including distinct dependency-readiness and vault-authorization checks, plus absent configuration, conventional/renamed/missing sections, root-level adventure candidates, and ambiguity. Blocked work must stop before profile or campaign-note access; inferred locations must not authorize edits.

- [ ] T003 [US1] Define the ordered Spec 001 preflight before reading `.dmassist.yaml` or campaign notes: establish the authorized vault, separately verify `obsidian-link-resolver`/`resolve_obsidian_link` readiness and explicit authorization of the intended vault, complete remaining guidance and campaign/group checks before campaign-note access, and prohibit profile-based authorization expansion; also define absent-profile read-only discovery and its no-migration/no-creation safeguards in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`.
- [ ] T004 [US1] Add design-only scenarios for successful and blocked Spec 001 preflight, distinct resolver-readiness and vault-authorization failures, profile-based authorization escalation attempts, and post-preflight conventional, renamed, missing, ambiguous, and root-level adventure discovery in `specs/002-vault-configuration-contract/quickstart.md`; verify blocked workflows stop before profile or campaign-note access and discovery creates or changes no files.
- [ ] T005 [US1] Verify the User Story 1 acceptance scenarios in `specs/002-vault-configuration-contract/spec.md` trace to the contract and quickstart, including preflight-before-access, separate resolver readiness and vault authorization, profile non-escalation, and failed-preflight stopping behavior without treating inference as edit authorization.

**Checkpoint**: User Story 1 is independently reviewable as a read-only existing-vault contract.

---

## Phase 4: User Story 2 - Describe Vault-Specific Organization (Priority: P2)

**Goal**: Define optional profile fields and the machine-readable schema for the normalized version-1 profile.

**Independent Test**: Compare the written contract, data model, schema, and scenarios for minimal and customized profiles. Confirm field shapes and defaults agree, `preparation` omission resolves to `session_section`/`Preparation`, a present preparation object requires `mode` and rejects `{}`, an absent default guidance candidate is optional, unavailable designated guidance pauses dependent work, configured template failures stop authoring without fallback, and schema validation does not mutate instances.

- [ ] T006 [US2] Define each version-1 field's normalized type, required/optional status, default, and invalid outcome in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`; require integer `version: 1`, custom IDs matching `^[a-z][a-z0-9_]*$` without built-in collisions, custom section entries with exactly non-empty `path` and `description`, present `preparation` objects with required `mode`, and distinguish absent optional default `.dmassist-guidance.md` from present unreadable/invalid/unavailable default or explicit guidance that blocks dependent work.
- [ ] T007 [P] [US2] Create the Draft 2020-12 normalized-profile schema at provisional path `schemas/dmassist.schema.json`, requiring integer `version: 1`, rejecting unknown properties, enforcing non-empty strings and custom identifier constraints, requiring custom section `path` and `description`, expressing preparation conditionals, and documenting defaults as annotations only.
- [ ] T008 [P] [US2] Document normalized profile entities, field types, requiredness/defaults, relationships, preparation mode rules, Spec 001 preflight and authorization boundaries, default-guidance absence/failure semantics, and schema-versus-runtime validation boundaries in `specs/002-vault-configuration-contract/data-model.md`.
- [ ] T009 [US2] Add future schema acceptance cases for minimal/customized profiles, types and unknown properties, custom identifiers, preparation conditionals, null/empty values, and annotation-only defaults in `specs/002-vault-configuration-contract/quickstart.md`.
- [ ] T010 [US2] Verify `schemas/dmassist.schema.json` against the Draft 2020-12 meta-schema and representative valid/invalid normalized instances from `specs/002-vault-configuration-contract/quickstart.md`; confirm validation does not apply defaults or mutate instances and add no repository/runtime dependency.
- [ ] T011 [US2] Document `schemas/dmassist.schema.json` as the current provisional source location and defer final installed-plugin placement, packaging, discovery, and runtime use to Issue #4 in `specs/002-vault-configuration-contract/plan.md`.

**Checkpoint**: The normalized-profile schema and written field contract agree; no parser, runtime validator, or installed resource path is implied.

---

## Phase 5: User Story 3 - Receive Clear Validation and Safe Path Handling (Priority: P1)

**Goal**: Specify all-or-nothing validation failures and vault-boundary safeguards while keeping their implementation in Issue #4.

**Independent Test**: Review malformed-profile, unavailable-validation, explicit missing-directory, unsafe path/symlink, and stale-input scenarios. Each must stop dependent work before unsafe access or writes, reject partial settings, and require revalidation when inputs change.

- [ ] T012 [US3] Define all-or-nothing profile validation, actionable errors, deterministic resolution, required explicit section directories, no fallback on invalid profiles, and stale-input behavior in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`.
- [ ] T013 [P] [US3] Specify safe vault-relative path syntax, canonicalization and symlink containment, pre-access boundary checks, and the distinction between schema string constraints and filesystem validation in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`.
- [ ] T014 [P] [US3] Document validation states and Issue #4 ownership in `specs/002-vault-configuration-contract/data-model.md`; require every explicitly configured section directory to exist and pass boundary checks, reject the whole profile on failure, and keep path existence, readability, and symlink checks outside JSON Schema.
- [ ] T015 [US3] Add separate future schema and Issue #4 integration scenarios for malformed YAML, duplicate keys, scalar normalization, explicit missing directories, unsafe paths/symlinks, unavailable validation, stale inputs, blocked Spec 001 preflight, absent versus unavailable default guidance, and configured-template failures without silent fallback in `specs/002-vault-configuration-contract/quickstart.md`.
- [ ] T016 [US3] Trace User Story 3 acceptance criteria and validation/path requirements in `specs/002-vault-configuration-contract/spec.md` to the contract and quickstart, preserving the boundary between normalized JSON Schema checks and parser/filesystem runtime checks.

**Checkpoint**: User Story 3 documents safe outcomes without claiming the reader, validator integration, or filesystem behavior is implemented.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Keep project status accurate and verify artifacts together.

- [ ] T017 [P] Update `README.md`, `docs/architecture.md`, and `docs/vault-guidance-brainstorm.md` to link to the proposed contract/schema while stating runtime support is not implemented.
- [ ] T018 Review `specs/002-vault-configuration-contract/spec.md`, `specs/002-vault-configuration-contract/plan.md`, `specs/002-vault-configuration-contract/research.md`, `specs/002-vault-configuration-contract/data-model.md`, `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`, `schemas/dmassist.schema.json`, `specs/002-vault-configuration-contract/quickstart.md`, `README.md`, `docs/architecture.md`, and `docs/vault-guidance-brainstorm.md` for requirement coverage, Spec 001 preflight and authorization boundaries, default-guidance failure behavior, consistent defaults, schema/runtime ownership, and proposal-versus-implementation language.

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No prerequisites.
- **Foundational (Phase 2)**: Depends on Setup; establishes shared profile/schema decisions.
- **User Stories (Phases 3–5)**: Depend on the foundational phase. User Story 1 and User Story 2 can proceed independently after the foundation; User Story 3 follows the validation/profile decisions.
- **Polish (Phase 6)**: Depends on the desired story tasks.

### User Story Dependencies

- **User Story 1 (P1)**: Depends on the foundation; its preflight contract precedes discovery scenarios and traceability review.
- **User Story 2 (P2)**: Depends on the foundation; profile contract/schema definitions precede schema scenarios and verification. Guidance and template runtime outcomes remain design scenarios, not runtime implementation.
- **User Story 3 (P1)**: Depends on the foundation and the normalized-profile rules from User Story 2; its quickstart scenarios follow the contract/data-model rules.

### Parallel Opportunities

- T003 follows T002; T004 follows T003 so scenarios use the agreed preflight contract; T005 follows T003 and T004.
- T007 and T008 may proceed in parallel after T002 because they edit distinct artifacts.
- T013 and T014 may proceed in parallel after T012's validation contract is established, provided edits are limited to their distinct files.
- T017 may proceed independently of the user-story artifacts; T018 waits for all desired story and status updates.

## Parallel Example: User Story 2

```text
Task: T007 Create the normalized-profile JSON Schema in schemas/dmassist.schema.json
Task: T008 Document profile entities and validation boundaries in specs/002-vault-configuration-contract/data-model.md
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Setup and Foundational phases.
2. Complete User Story 1's read-only existing-vault contract and scenarios.
3. Review that inferred candidates never authorize edits or file creation.

This MVP is a design increment only; it does not implement read-only discovery.

### Incremental Delivery

1. Add the existing-vault and absent-profile contract (User Story 1).
2. Add the version-1 profile contract, schema, and schema-level verification (User Story 2).
3. Add validation outcomes, path boundaries, and runtime ownership scenarios (User Story 3).
4. Complete cross-artifact review. Keep the final installed schema location and consuming loader verification in Issue #4.

## Notes

- All tasks are generated as unchecked work items; checkbox state is not a claim that the design artifacts or runtime are unimplemented or implemented.
- `[P]` marks tasks that edit different files and have no incomplete prerequisites.
- User Story tasks use `[US1]`, `[US2]`, or `[US3]` for traceability to `spec.md`.
- Schema verification is a design-artifact check. YAML parsing, duplicate-key detection, scalar normalization, validator integration, filesystem checks, and installed-plugin schema packaging/runtime discovery remain Issue #4 responsibilities.
