---

description: "Implementation tasks for the Vault Configuration Contract"
---

# Tasks: Vault Configuration Contract

**Input**: Design documents from `specs/002-vault-configuration-contract/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Scope**: Feature 002 produces a written version-1 configuration contract and JSON Schema artifact. YAML parsing, scalar normalization, runtime validation, filesystem operations, and integration tests are owned by Issue #4 and are not implemented by these tasks.

**Tests**: No executable tests are defined for this documentation-and-metadata scaffold. The quickstart records future schema and runtime acceptance scenarios; do not invent a current loader or test command.

## Phase 1: Setup

**Purpose**: Keep planned deliverables and feature scope aligned.

- [ ] T001 Update the artifact inventory and design-only scope in `specs/002-vault-configuration-contract/plan.md`, including `contracts/dmassist.schema.json` and the Issue #4 runtime boundary.

---

## Phase 2: Foundational

**Purpose**: Establish shared profile and validation decisions before finalizing story-specific contracts.

- [ ] T002 [P] Record the JSON Schema Draft 2020-12 choice, normalized-profile boundary, annotation-only defaults, scalar normalization contract, and Issue #3/Issue #4 ownership in `specs/002-vault-configuration-contract/research.md`.
- [ ] T003 Define the version-1 normalized profile entities, fields, required/default status, validation constraints, and runtime-only checks in `specs/002-vault-configuration-contract/data-model.md`.

**Checkpoint**: The profile shape and ownership boundaries are established; story work may proceed.

---

## Phase 3: User Story 1 - Use an Existing Vault Without Migration (Priority: P1) 🎯 MVP

**Goal**: Specify how an existing vault can be discovered read-only without requiring a profile, prescribed layout, or migration.

**Independent Test**: Review the contract and future scenarios for an absent profile, conventional and renamed sections, root-level adventure candidates, and ambiguous candidates. Each scenario reports evidence and uncertainty without creating or modifying files; inferred locations never authorize edits.

- [ ] T004 Define absent-profile behavior, read-only discovery, candidate locations, ambiguity reporting, and the no-migration/no-creation safeguards in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`.
- [ ] T005 Document future acceptance scenarios for conventional, renamed, missing, root-level, and ambiguous discovery cases in `specs/002-vault-configuration-contract/quickstart.md`.

**Checkpoint**: The written contract describes the existing-vault and absent-profile journey without claiming a discovery runtime exists.

---

## Phase 4: User Story 2 - Describe Vault-Specific Organization (Priority: P2)

**Goal**: Define the optional profile fields and publish a machine-readable schema for the normalized version-1 profile.

**Independent Test**: Check that the written field contract, data model, and schema agree for a minimal profile and a customized profile containing sections, custom sections, party, preparation, guidance, templates, and custom templates. Confirm omitted defaults are annotations/resolution behavior and validation does not mutate the instance.

- [ ] T006 [P] Specify each profile field's accepted type, required/optional status, default, and invalid-value outcome—including section paths, custom section `path` and `description`, `party.note`, preparation modes, guidance, and built-in/custom template paths—in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`.
- [ ] T007 [P] Create the Draft 2020-12 schema in `specs/002-vault-configuration-contract/contracts/dmassist.schema.json`; require integer `version` `1`, reject unknown properties, require custom section entries to contain exactly non-empty `path` and `description`, enforce `^[a-z][a-z0-9_]*$` custom identifiers without built-in collisions, encode preparation mode constraints, and annotate defaults without applying them.
- [ ] T008 Reconcile normalized profile entities, types, defaults, and schema boundaries with the published artifact in `specs/002-vault-configuration-contract/data-model.md`.
- [ ] T009 Add future schema acceptance scenarios for valid and invalid normalized instances, mode-dependent preparation fields, custom identifiers, unknown properties, and annotation-only defaults in `specs/002-vault-configuration-contract/quickstart.md`.

**Checkpoint**: The normalized profile contract and schema are consistent; no YAML reader or runtime validator is implied.

---

## Phase 5: User Story 3 - Receive Clear Validation and Safe Path Handling (Priority: P1)

**Goal**: Specify observable failures and vault-boundary safeguards while keeping parser and filesystem implementation in Issue #4.

**Independent Test**: For each malformed profile, unavailable validation, explicit missing directory, unsafe path/symlink, or changed dependency scenario, confirm the contract requires a clear failure before dependent access or writes, rejects partial settings, and requires revalidation where applicable.

- [ ] T010 Define all-or-nothing validation, actionable error outcomes, deterministic resolution, explicit-directory requirements, safe path rules, and stale-input behavior in `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`; identify YAML parsing, duplicate-key rejection, scalar normalization, filesystem state, and symlink resolution as Issue #4 runtime responsibilities.
- [ ] T011 Align validation lifecycle states and filesystem-dependent constraints with the schema/runtime boundary in `specs/002-vault-configuration-contract/data-model.md`.
- [ ] T012 Separate future normalized-schema cases from YAML parser, scalar normalization, duplicate-key, filesystem/path-boundary, and stale-input integration scenarios in `specs/002-vault-configuration-contract/quickstart.md`; mark Issue #4 ownership explicitly.

**Checkpoint**: The feature contract clearly distinguishes JSON Schema validation from parser, vault, and operation checks.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verify traceability and consistency across the design artifacts.

- [ ] T013 Review `specs/002-vault-configuration-contract/spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/vault-configuration-contract.md`, `contracts/dmassist.schema.json`, and `quickstart.md` for requirement coverage, consistent defaults, and the Issue #3/Issue #4 boundary.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No prerequisites.
- **Foundational (Phase 2)**: Depends on Setup; establishes profile and schema decisions before story work.
- **User Stories (Phases 3–5)**: Depend on the Foundational phase. User Story 1 and the initial User Story 2 contract/schema work can proceed independently after the foundation. User Story 3 follows the schema/contract definition so runtime-only constraints remain accurately separated.
- **Polish (Phase 6)**: Depends on all desired story artifacts.

### User Story Dependencies

- **User Story 1 (P1)**: Depends only on the foundation; independently documents absent-profile discovery and preservation.
- **User Story 2 (P2)**: Depends only on the foundation; defines the profile fields and schema artifact. Its contract and schema tasks can proceed in parallel.
- **User Story 3 (P1)**: Depends on the foundation and the User Story 2 field/schema definitions; clarifies validation failures, path safety, and runtime ownership without implementing them.

### Within Each User Story

- Contract and schema artifacts should be defined before quickstart scenarios that validate them.
- Reconcile the data model after the profile/schema shape is agreed.
- Schema validation scenarios target normalized objects only; runtime integration scenarios are tracked separately for Issue #4.

### Parallel Opportunities

- T002 may run in parallel with T001 if the artifact inventory is already known; otherwise complete T001 first.
- T004 and T007 edit different files and can proceed in parallel after T003.
- T006 and T007 can proceed in parallel after T003 because they edit separate artifacts.
- T005 can proceed independently from schema authoring once User Story 1 contract semantics are agreed.
- Do not parallelize tasks that edit the same contract, data-model, or quickstart file.

## Parallel Example: User Story 2

```text
Task: T006 Specify profile fields and defaults in specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md
Task: T007 Create the normalized-profile JSON Schema in specs/002-vault-configuration-contract/contracts/dmassist.schema.json
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Setup and Foundational phases.
2. Complete User Story 1's discovery and no-migration contract.
3. Confirm its independent test scenarios require read-only outcomes and no file changes.

This MVP delivers only the existing-vault and absent-profile contract; it does not implement discovery runtime behavior.

### Incremental Delivery

1. Add User Story 1 for safe read-only discovery without migration.
2. Add User Story 2 for the profile field contract and JSON Schema artifact.
3. Add User Story 3 for complete validation outcomes and vault-boundary guarantees.
4. Complete cross-artifact consistency review.

## Notes

- Every task is an unchecked checklist item with a sequential ID and a repository-relative file path.
- `[P]` marks tasks that edit different files and have no incomplete prerequisite.
- User Story tasks use `[US1]`, `[US2]`, or `[US3]` for traceability to `spec.md`.
- The tasks define and validate design artifacts only; implementation of YAML/runtime behavior belongs to Issue #4.
