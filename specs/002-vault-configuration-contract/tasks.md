---

description: "Remaining work for the Vault Configuration Contract"
---

# Tasks: Vault Configuration Contract

**Input**: Design documents from `specs/002-vault-configuration-contract/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Scope**: The written version-1 contract, JSON Schema, data model, plan, research, and future validation scenarios already exist. These tasks resolve the preparation-default wording, verify the schema as a design artifact, update stale project-status references, and perform a final consistency review. YAML parsing, scalar normalization, runtime validator integration, filesystem operations, and runtime integration tests remain owned by Issue #4.

**Tests**: No repository test harness or runtime loader exists. Schema verification uses a temporary/local standards-compliant JSON Schema Draft 2020-12 validator and does not add a repository dependency.

## Phase 1: Setup

**Purpose**: No project or runtime setup is required for the remaining documentation and schema verification work.

---

## Phase 2: Foundational

**Purpose**: No additional foundation tasks remain; the profile shape and ownership boundaries are established.

---

## Phase 3: User Story 2 - Describe Vault-Specific Organization (Priority: P2)

**Goal**: Make preparation defaults unambiguous and verify the published normalized-profile schema.

**Independent Test**: Confirm omitted `preparation` resolves to `session_section` with heading `Preparation`; a present mapping requires `mode`, rejects `{}`, and uses the `Preparation` heading when `session_section` omits `heading`. Confirm Draft 2020-12 schema validation accepts/rejects the cases documented in `quickstart.md` and does not mutate input instances to apply defaults.

- [x] T001 [US2] Align preparation omission defaults and present-mapping requirements across `specs/002-vault-configuration-contract/spec.md`, `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`, `schemas/dmassist.schema.json`, `specs/002-vault-configuration-contract/data-model.md`, and `specs/002-vault-configuration-contract/quickstart.md`.
- [x] T002 [US2] Validate `schemas/dmassist.schema.json` against the Draft 2020-12 meta-schema and representative valid/invalid normalized cases drawn from `specs/002-vault-configuration-contract/quickstart.md`; verify defaults remain annotations and the validator leaves instances unchanged, without adding a repository/runtime dependency.

**Checkpoint**: The preparation contract is consistent and the schema artifact passes standards-compliant verification; this does not imply a YAML reader or runtime validator exists.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Keep repository-level status accurate and verify traceability across the design artifacts.

- [x] T003 [P] Update `README.md`, `docs/architecture.md`, and `docs/vault-guidance-brainstorm.md` to identify the proposed contract/schema as documented while keeping reader and runtime behavior clearly unimplemented.
- [x] T004 Review `specs/002-vault-configuration-contract/spec.md`, `specs/002-vault-configuration-contract/plan.md`, `specs/002-vault-configuration-contract/research.md`, `specs/002-vault-configuration-contract/data-model.md`, `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`, `schemas/dmassist.schema.json`, `specs/002-vault-configuration-contract/quickstart.md`, `specs/002-vault-configuration-contract/tasks.md`, `README.md`, `docs/architecture.md`, and `docs/vault-guidance-brainstorm.md` for consistent defaults, schema/runtime ownership, and proposal-versus-implementation language.

## Dependencies & Execution Order

- T001 must complete before T002 because schema verification uses the reconciled preparation behavior.
- T003 is independent of T001 and T002 because it updates project-level status references.
- T004 depends on T001, T002, and T003.

## Parallel Opportunities

- T001 and T003 may proceed in parallel because they edit distinct files.
- T002 follows T001; T004 runs after all other tasks.

## Implementation Strategy

Complete the preparation contract reconciliation, run one-off schema verification without adding project dependencies, update the repository-level documentation, then perform the cross-artifact review. The version-1 contract and schema are design artifacts only; Issue #4 remains responsible for runtime implementation.

## Notes

- Every task uses a sequential ID, required user-story label where applicable, and explicit repository-relative file path(s).
- `[P]` marks work that can proceed independently in different files.
- The tasks cover remaining design-artifact verification only; they do not implement a loader, parser, or filesystem operations.
