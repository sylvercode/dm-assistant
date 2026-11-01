---
description: "Implementation tasks for Link Resolver Integration"
---

# Tasks: Link Resolver Integration

**Input**: Design documents from `specs/004-link-resolver-integration/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/resolver-mcp-contract.md`, and `quickstart.md`.

**Organization**: Tasks are grouped by user story so the setup, safe-stop behavior, result handling, and bounded integration scope can be implemented and validated incrementally.

## Phase 1: Setup

**Purpose**: The repository already has the plugin structure and runtime foundation; no new application scaffolding or dependencies are needed.

No setup tasks.

---

## Phase 2: Foundational Dependency Contract

**Purpose**: Keep the packaged dependency projection aligned before implementing story-specific setup and workflows.

- [X] T001 Compare `skills/vault-orientation/assets/runtime-dependencies.json` with the authoritative dependency table in `specs/001-shared-vault-guidance/spec.md`; correct any drift while preserving Resolver 2.1.0+, both required tools, and the explicit fail-closed authorization boundary.

**Checkpoint**: The shared dependency inventory is the single source of truth for every user story.

---

## Phase 3: User Story 1 - Set Up the Required Resolver (Priority: P1) 🎯 MVP

**Goal**: Give the DM Copilot CLI-specific setup guidance for separately installing and configuring the Resolver without exposing private vault paths.

**Independent Test**: Follow the setup in a fresh supported Copilot CLI session and confirm Resolver 2.1.0+, both required tools, and an exact authorization match for a disposable vault without reading campaign notes.

### Implementation for User Story 1

- [X] T002 [P] [US1] Add user-facing setup instructions to `README.md` for installing the Resolver separately, configuring Copilot CLI's supported local MCP format with placeholder `--vault` roots, starting a fresh session, and verifying both required tools; do not use VS Code `.vscode/mcp.json` syntax.
- [X] T003 [P] [US1] Update `docs/architecture.md` to document the Resolver as an externally installed dependency, keep its user-specific configuration outside the plugin, and distinguish installed-client evidence from local runtime tests.
- [X] T004 [P] [US1] Update `skills/vault-orientation/SKILL.md` to link the Resolver setup guidance and require the fresh-session readiness and authorization preflight before campaign-note access; do not imply that this verifies the PowerShell runtime handoff.
- [X] T005 [US1] Follow the fresh-session setup scenario in `specs/004-link-resolver-integration/quickstart.md` with a disposable vault; verify the reported version is at least 2.1.0, both tools are exposed, the exact normalized root matches, and no note content is read.

**Checkpoint**: The DM can configure and verify the external Resolver for the intended vault without putting private paths in plugin content or reading campaign notes.

---

## Phase 4: User Story 2 - Stop Safely When the Resolver Is Unavailable (Priority: P1)

**Goal**: Ensure missing, incompatible, stale, incomplete, or unauthorized Resolver state blocks all campaign-note access and changes.

**Independent Test**: For each blocked scenario in the quickstart, confirm the skill identifies the unmet prerequisite and stops before campaign-note reads or changes.

### Implementation for User Story 2

- [X] T006 [US2] Update `skills/vault-orientation/SKILL.md` to identify the failed prerequisite and stop before campaign-note access when the server or either tool is unavailable, compatibility or `get_server_info` is unconfirmed, no exact vault-root match exists, or Resolver settings changed after session startup; preserve the blocked PowerShell handoff.
- [X] T007 [P] [US2] Run the unavailable-service, missing-tool, unconfirmed-version, invalid-server-info, non-exact-root, and stale-session scenarios from `specs/004-link-resolver-integration/quickstart.md` using a disposable vault separate from T009; confirm no campaign-note reads or changes occur. In fresh CLI sessions against the empty test vault: disabled the Resolver for unavailable-service; excluded `get_server_info` for missing-tool; used a session-scoped synthetic MCP server that returned no confirmable version/root for unconfirmed-version and an MCP error for invalid-server-info; verified exact-root rejection against live Resolver 2.1.0 information for a separately specified test root; and supplied a confirmed post-start root-change condition for stale-session, which the skill rejected pending restart. No note content was read or changed; only the test `.mcp.json` was present and its hash remained unchanged.

**Checkpoint**: Every failed preflight scenario stops safely and directs the DM to the missing setup or fresh-session verification.

---

## Phase 5: User Story 3 - Understand Link-Resolution Results (Priority: P2)

**Goal**: Report Resolver results faithfully without inventing destinations or changing notes.

**Independent Test**: Exercise every documented result with a disposable vault; confirm the correct outcome and available candidate details are reported, with no guessed destination or note modification.

### Implementation for User Story 3

- [X] T008 [US3] Enumerate resolver-using skills from `skills/README.md` and update each corresponding `skills/<skill-name>/SKILL.md` to distinguish resolved, unresolved, missing-subtarget, ambiguous, and error results; report only details explicitly present in the upstream Resolver contract, state when details are unavailable, never select an ambiguous candidate or invent a replacement, and leave notes unchanged.
- [X] T009 [P] [US3] Run the five outcome scenarios in `specs/004-link-resolver-integration/quickstart.md` against a disposable vault separate from T007 and the upstream Resolver contract; verify faithful reporting, no guessed destination, and no note changes without inventing MCP payload fields.

**Checkpoint**: Each supported result type is communicated distinctly and uncertainty remains explicit.

---

## Phase 6: User Story 4 - Keep Setup Focused (Priority: P3)

**Goal**: Deliver only the required link-resolution integration and keep future additions as separate proposals until justified.

**Independent Test**: Review the plugin manifest and integration documentation; confirm no additional integration or placeholder is introduced and any future integration requires a documented workflow gap and acceptance criteria.

### Implementation for User Story 4

- [X] T010 [US4] Audit `plugin.json`, `skills/`, `com.github.copilot/agents/`, `docs/architecture.md`, and `specs/004-link-resolver-integration/` to verify the repository remains an Agent Plugins 1.0 plugin, `plugin.json` follows the official discovery contract without legacy component-path fields, portable skills are in immediate child folders of `skills/`, Copilot-specific agents are under `com.github.copilot/agents/`, and no integration placeholder or integration beyond the Resolver is added; correct any conflicting feature documentation.
- [X] T011 [US4] Verify the future-integration boundary in `specs/004-link-resolver-integration/spec.md`, `specs/004-link-resolver-integration/contracts/resolver-mcp-contract.md`, and `docs/architecture.md`: any additional integration remains a separate proposal until its concrete workflow gap and acceptance criteria are documented.

**Checkpoint**: The delivered feature adds no integration beyond the required Resolver.

---

## Phase 7: Polish and Cross-Cutting Validation

**Purpose**: Verify shared skill compliance, plugin discovery, and evidence boundaries across the completed stories.

- [X] T012 Run the static skill inventory and source audit using `skills/README.md` and every immediate-child `skills/*/SKILL.md`; confirm each vault-facing skill preserves Feature 001's full ordered preflight—establish the authorized vault, verify required dependencies, load shared and designated local guidance, establish campaign/group context and apply player-facing gates—before campaign-note access, and each skill that invokes link resolution preserves the five outcomes and reports only contract-defined details.
- [X] T013 Scan plugin-distributed files and shared setup examples—including `plugin.json`, `skills/**`, `com.github.copilot/agents/**`, `docs/**`, and feature specifications—for machine-specific vault paths; confirm examples use placeholders, keep findings sanitized without reproducing suspected private paths, and distinguish static checks, synthetic results, and installed-client verification.
- [X] T014 Follow the README's local plugin loading steps in the supported Copilot CLI session and verify plugin discovery; verify that the runtime resource lookup finds the same bundled reference from the repository root and another working directory. Record plugin-discovery and resource-lookup evidence separately from static checks, synthetic tests, and Resolver authorization evidence. Plugin and `vault-orientation` skill discovery succeeded from both working directories. User-provided Copilot CLI screenshots show `VAULT-REFERENCE.md` (94 lines) read from the repository root and from a session launched in the temp directory; plugin discovery and resource access are separate from Resolver authorization evidence.
- [X] T015 Run the PowerShell acceptance suite with Pester 6.2.0 using `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`; record the result and do not report the suite as passing if it was not run. Result: 359 passed, 0 failed, 5 skipped (Windows symbolic-link privilege limitations).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No work; the plugin structure and runtime foundation already exist.
- **Foundational (Phase 2)**: T001 must complete before story implementation so every story uses the authoritative dependency projection.
- **User Stories (Phases 3–6)**: Depend on T001. User Story 2 and User Story 3 both modify resolver-using skill guidance after User Story 1; complete T004, then T006, then T008 in that order to avoid conflicting edits. User Story 4's audit follows the shared documentation updates.
- **Polish (Phase 7)**: Depends on the desired user stories being complete. Complete T012 and address any findings before T013; complete T014 after documentation updates and the final privacy scan; then run T015 and record its result.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after T001; implementation tasks T002–T004 touch separate files and can proceed in parallel. T005 validates the completed setup instructions and skill preflight.
- **User Story 2 (P1)**: Starts after T004 because it extends the same skill guidance; T007 follows T006.
- **User Story 3 (P2)**: Starts after T006 because it further updates resolver-using skill guidance; T009 follows T008.
- **User Story 4 (P3)**: Starts after the setup documentation in T003 and is finalized after the story changes.

### Parallel Opportunities

- T002, T003, and T004 can run in parallel after T001 because they modify different files.
- T005 can begin after T002 and T004 are complete.
- T007 and T009 can run in parallel after their respective skill updates when each uses its own disposable vault.
- Run T012–T015 sequentially after all story work. Address T012 findings before T013's final privacy/evidence scan; then validate plugin discovery and installed-resource lookup against the finalized documentation, followed by the PowerShell acceptance suite.

---

## Parallel Example: User Story 1

```text
After T001, run these separate-file documentation tasks in parallel:
Task: T002 - Update Resolver setup guidance in README.md
Task: T003 - Update Resolver configuration boundary in docs/architecture.md
Task: T004 - Update the consuming skill preflight in skills/vault-orientation/SKILL.md
Then run T005 to validate the completed instructions in a fresh Copilot CLI session.
```

## Implementation Strategy

### MVP First (User Story 1)

1. Complete T001 to align the packaged dependency projection.
2. Complete User Story 1 setup documentation and preflight guidance (T002–T004).
3. Run T005 with a disposable vault and fresh Copilot CLI session.
4. Stop and validate that the setup is usable, private paths are absent from plugin content, and no campaign notes were read.

### Incremental Delivery

1. Deliver the P1 setup instructions and verify fresh-session readiness (User Story 1).
2. Add and verify fail-closed behavior for dependency and authorization failures (User Story 2).
3. Validate faithful handling of each Resolver outcome (User Story 3).
4. Audit the bounded integration scope and future proposal policy (User Story 4).
5. Complete the shared inventory/source and privacy/evidence audits.

## Notes

- `[P]` marks tasks that touch different files and have no unfinished prerequisite.
- Every user-story task carries its corresponding `[US#]` label.
- Exact Resolver MCP payload schemas remain delegated to the upstream Resolver contract; do not invent them in implementation.
- Keep script-backed vault access blocked until its active-session authorization handoff is separately verified.
- The feature specification does not request TDD or new automated test suites; the tasks use its independent acceptance scenarios and the existing validation guide.
