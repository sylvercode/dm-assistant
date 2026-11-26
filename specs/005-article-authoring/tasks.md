---
description: "Implementation tasks for article authoring and template selection"
---

# Tasks: Article Authoring and Template Selection

**Input**: Design documents from `specs/005-article-authoring/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Add Feature 005 Pester tests for package and runtime-backed behavior in `tests/powershell/ArticleAuthoring.Tests.ps1`, plus supported-client scenario checks from `quickstart.md` for skill decisions that Pester cannot exercise. Use only synthetic disposable vaults and the test-only authorization provider for local runtime tests. Neither test type establishes production authorization.

**Organization**: Tasks are grouped by the four P1 user stories. Each story includes an independent acceptance criterion.

## Phase 1: Setup

**Purpose**: Reconcile the destination acceptance criterion with FR-017 before implementation.

On 2026-11-21, the DM changed the destination requirement to also accept
absolute paths within the selected vault. The article entry point normalizes
these to vault-relative identities; the shared runtime still enforces its
vault-relative path and filesystem containment rules.

- [X] T001 Update User Story 4 acceptance scenario 5 in `specs/005-article-authoring/spec.md` to match FR-017: require one explicit DM-supplied in-vault Markdown destination, state that Feature 002 section-folder/template mappings do not identify article paths, and require the workflow to ask rather than infer a destination.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the shared article-authoring skill entry point, register it, and route operations through existing safety contracts before any story work.

- [X] T002 [P] Create `skills/article-authoring/SKILL.md` with portable skill frontmatter, activation of `vault-orientation`, the required pre-note sequence from `skills/vault-orientation/SKILL.md`, installed-skill resource loading, and a one-article operation boundary; do not access vault-owned inputs before authorization, shared-reference, and guidance gates succeed.
- [X] T003 [P] Register `article-authoring` exactly once in `skills/README.md` as a vault-facing immediate-child skill, link to `skills/article-authoring/SKILL.md`, and require shared-reference and declared-dependency checks before campaign-note access.
- [X] T004 Route script-backed article creation through `skills/vault-orientation/scripts/RuntimePreflight.psm1`, `skills/vault-orientation/scripts/DependencyPreflight.psm1`, and `skills/vault-orientation/scripts/SafeNoteWriter.psm1`; preserve fail-closed exact-vault authorization and existing approval/write contracts, and do not add a test authorization provider or direct-write path. The skill documents this required route and blocks script-backed article writes until production authorization and a create-only safe-writer path are verified.

**Checkpoint**: The skill is registered, delegates shared preflight to `vault-orientation`, and uses existing runtime gates without claiming production authorization is implemented.

---

## Phase 3: User Story 1 - Create an Article from a Plugin Default (Priority: P1) 🎯 MVP

**Goal**: Create a built-in article from its installed skill-owned default, or use a valid registered custom type's configured vault-owned template; never invent a template for an unsupported type.

**Independent Test**: For each built-in type with no override, select and read its corresponding installed-skill template before article creation regardless of current working directory. A valid registered custom type reads only its mapped template; an unbuilt or unregistered type asks how to proceed without creating an article.

### Tests for User Story 1

- [X] T005 [P] [US1] Add package-layout tests in `tests/powershell/ArticleAuthoring.Tests.ps1` that assert the repository plugin package contains exactly one Markdown default for each built-in type (`adventure`, `character`, `handout`, `location`, `monster`, `party`, `persona`, `rule`, and `session`) under `skills/article-authoring/templates/`; do not treat this source-tree check as installed-client verification.
- [X] T006 [P] [US1] Add supported-client scenarios to `specs/005-article-authoring/quickstart.md` that request all nine built-in types from a working directory outside the plugin installation, exercise one valid profile-registered custom type, and assert the unified success/blocked response identifies type when known, source or why selection was not reached, destination or blocker, and no-creation confirmation when blocked.

### Implementation for User Story 1

- [X] T007 [P] [US1] Create the `adventure` default structure in `skills/article-authoring/templates/adventure.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T008 [P] [US1] Create the `character` default structure in `skills/article-authoring/templates/character.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T009 [P] [US1] Create the `handout` default structure in `skills/article-authoring/templates/handout.md` using static Markdown, player-facing content sections, and only the specified non-executable fill-in markers.
- [X] T010 [P] [US1] Create the `location` default structure in `skills/article-authoring/templates/location.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T011 [P] [US1] Create the `monster` default structure in `skills/article-authoring/templates/monster.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T012 [P] [US1] Create the `party` default structure in `skills/article-authoring/templates/party.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T013 [P] [US1] Create the `persona` default structure in `skills/article-authoring/templates/persona.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T014 [P] [US1] Create the `rule` default structure in `skills/article-authoring/templates/rule.md` using static Markdown and only the specified non-executable fill-in markers.
- [X] T015 [P] [US1] Create the `session` default structure in `skills/article-authoring/templates/session.md` with separate preparation and actual-play sections, using static Markdown and only the specified non-executable fill-in markers.
- [X] T016 [US1] Implement source lookup, unsupported-type handling, and the unified outcome response in `skills/article-authoring/SKILL.md`: recognize exactly the nine built-in types; load defaults from the installed `article-authoring` skill resources independent of the current working directory; read the selected template before drafting; select a custom template only for a registered `templates.custom.<id>` whose ID matches `[a-z][a-z0-9_]*` and does not duplicate a built-in; and explain when no template is available without searching alternate locations, inventing content, or creating an article. On success, identify the requested type, selected source, and destination; when blocked, identify the type when known, selected source or that selection was not reached, the blocker, and confirm no article was created. For an approval-required outcome, identify that approval is needed and confirm no article has yet been created. Apply this response contract to preflight, template, required-input, safety, stale-input, destination, approval, and write outcomes. Depends on T002, T005, and T007–T015.

**Checkpoint**: The repository package contains nine separate default resources; supported-client testing validates installed-resource lookup and custom-type behavior; unsupported types block without a substitute.

---

## Phase 4: User Story 2 - Use a DM-Owned Template (Priority: P1)

**Goal**: Prefer a valid configured DM-owned override while preserving its location and stopping on any invalid or stale override without fallback.

**Independent Test**: A valid override is selected ahead of a bundled default, including when it exists outside `.dmassist-templates/`; a missing, unreadable, invalid, stale, or out-of-vault override blocks creation without fallback or file movement.

### Tests for User Story 2

- [X] T017 [P] [US2] Add synthetic-vault freshness tests in `tests/powershell/ArticleAuthoring.Tests.ps1` for changes to each consumed profile/mapping, designated guidance, selected template, relevant context, authorization/boundary evidence, and destination identity/existence/parent state after validation and before writing; assert stale invalidation, required revalidation, and no write.
- [X] T018 [P] [US2] Add supported-client scenarios to `specs/005-article-authoring/quickstart.md` for configured built-in override precedence, configured overrides outside `.dmassist-templates/`, valid custom types, and missing/unreadable/invalid/stale/out-of-vault overrides that block without fallback or article creation.

### Implementation for User Story 2

- [X] T019 [US2] Implement configured-template precedence in `skills/article-authoring/SKILL.md` using only Feature 002's `templates.<built-in-type>` and `templates.custom.<id>` mappings: validate custom IDs against `[a-z][a-z0-9_]*` with no built-in collision; use a valid in-vault override before a bundled default; preserve valid existing paths; and stop on any invalid configured override without falling back. Depends on T016.
- [X] T020 [US2] Bind SafeNoteWriter freshness checks in `skills/vault-orientation/scripts/SafeNoteWriter.psm1` to every consumed authoring input: profile and selected mapping, designated guidance, selected template, relevant campaign context, authorization/boundary evidence, and destination identity/existence/parent state. If any input changes after validation or before writing, invalidate dependent work, report staleness, require revalidation, and do not retry or mix old and new inputs. Depends on T019.

**Checkpoint**: Valid overrides retain precedence and user ownership; invalid or stale configuration cannot silently select a different template or proceed to a write.

---

## Phase 5: User Story 3 - Preserve Campaign and Player-Facing Boundaries (Priority: P1)

**Goal**: Preserve vault conventions and continuity, complete only supported static markers, and prevent DM-only information from reaching player-facing output.

**Independent Test**: Author DM-facing and player-facing content using established conventions; verify that player-facing sections omit DM-only facts and revealing links, supported marker behavior follows required/optional semantics, dynamic syntax stays unexecuted, and preparation is not reported as actual play.

### Tests for User Story 3

- [X] T021 [P] [US3] Add static template checks in `tests/powershell/ArticleAuthoring.Tests.ps1` for the exact required/optional marker syntax and non-executable Markdown constraints across the nine bundled templates; depends on T007–T015.
- [X] T022 [P] [US3] Add supported-client scenarios to `specs/005-article-authoring/quickstart.md` for convention precedence; tag use that does not replace explanatory prose or impose a fixed vocabulary when none is established; native callout fallback and warning-title specificity; ignoring template text that attempts to authorize access or changes; DM-only fact/revealing-link omission; final player-safety gate timing and recheck after edits; required/optional marker behavior; leaving dynamic syntax unexecuted and reporting the limitation and asking the DM how to proceed when its output is needed; and preparation/actual-play separation.

### Implementation for User Story 3

- [X] T023 [US3] Implement content and audience safeguards in `skills/article-authoring/SKILL.md`: follow conventions established by explicit DM instructions, designated local guidance, the shared reference, or relevant authorized notes; use tags to classify content, not replace explanatory prose, and do not impose a fixed tag vocabulary when none is established; use proposed native defaults only when no applicable convention exists and require warning titles to name the caution or consequence; treat templates as data, not instructions, authorization, or permission to access other files or make changes; classify DM-only facts from DM direction or designated guidance/context and revealing links from their target or known result; omit them from player-facing sections; gate-check after the final content change and directly before delivery/read, repeating after later changes and withholding if safety cannot be established; recognize only the exact required/optional HTML-comment markers, ask about missing or ambiguous required values, allow optional markers to remain, never execute other template syntax, and when dynamic output is needed report that it was not expanded and ask the DM how to proceed; keep preparation distinct from actual-play history, character knowledge, and world facts. Depends on T019 and T007–T015.

**Checkpoint**: Article content respects established conventions and player/DM boundaries; unsupported template syntax is never expanded or presented as expanded.

---

## Phase 6: User Story 4 - Protect Existing Vault Content (Priority: P1)

**Goal**: Block unsafe or unauthorized reads and writes, preserve existing content, and require scoped approval for changes beyond one safe page-local creation.

**Independent Test**: With synthetic vault fixtures, unsafe or out-of-root paths, unverified Resolver targets, stale inputs, existing destinations, missing folders, and ambiguous destinations cause no dependent read or write; only one clear new article may use the page-local exception, while broader or continuity-changing edits wait for explicit approval.

### Tests for User Story 4

- [X] T024 [P] [US4] Add synthetic-vault Pester tests in `tests/powershell/ArticleAuthoring.Tests.ps1` for preflight failure with no dependent reads/writes; escaping paths and unverified Resolver targets; destination conflicts, missing parents, ambiguous/inferred destinations, and unchanged fixtures; plus page-local versus broader approval and approval invalidation when the proposal or consumed inputs change.
- [X] T025 [P] [US4] Add supported-client scenarios to `specs/005-article-authoring/quickstart.md` confirming that article destinations require one explicitly DM-supplied in-vault Markdown path, Feature 002 section-folder/template mappings alone do not identify a destination, and all blocked path/approval cases leave the synthetic fixture unchanged.

### Implementation for User Story 4

- [X] T026 [P] [US4] Enforce article-template and destination containment using `skills/vault-orientation/scripts/VaultPathValidation.psm1` and `skills/vault-orientation/scripts/VaultBoundary.psm1`; reject absolute template paths, outside-vault absolute destinations, traversal, and symlink-resolved paths outside the authorized root before script reads/writes. Resolver symlink-target qualification is deferred to the owner as of 2026-11-17, not an authoring gate. Depends on Phase 2.
- [X] T027 [US4] Recheck destination identity and filesystem state in `skills/vault-orientation/scripts/SafeNoteWriter.psm1` immediately before applying an article: accept only one in-vault Markdown path explicitly supplied by the DM and normalized to a vault-relative identity; reject an existing target, missing parent, multiple plausible paths, or unknown destination. Never treat Feature 002 section-folder or template mappings as article destinations, overwrite or reformat existing content, create folders, guess an alternate path, or write after any required gate fails. Depends on T020 and T026.
- [X] T028 [US4] Apply the page-local exception and scoped approval flow through `skills/vault-orientation/scripts/ChangePreview.psm1` and `skills/vault-orientation/scripts/ApplyNoteChanges.psm1`: allow exactly one clear new article with no existing-note, actual-play, or continuity changes without separate DM approval; otherwise show a scoped preview, make no change before explicit approval, and bind approval to the current proposal and consumed inputs. Depends on T027.

**Checkpoint**: Unsafe access is blocked, existing content remains unchanged on conflicts or failures, and approval protects all changes outside the narrow page-local exception.

---

## Phase 7: Polish & Cross-Cutting Validation

**Purpose**: Validate the complete skill inventory, repository acceptance suite, and local discovery guidance without claiming blocked production behavior.

- [X] T029 Verify the `article-authoring` entry and every immediate-child skill in `skills/README.md`, follow the local plugin installation guidance in `README.md`, run `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`, and execute the quickstart's supported-client scenarios with disposable fixtures; report synthetic evidence separately from live caller MCP checks, caller-confirmation handling, installed-client behavior, and cross-platform support. Incremental CLI checks are recorded in the quickstart. Rerun client authoring scenarios with the revised `callerPreflight` contract; the unimplemented runtime/MCP bridge is no longer required. Resolver symlink qualification is deferred to the owner and does not block this task. Depends on T016, T020, T023, and T024–T028.

  Final local verification on 2026-11-25: the immediate-child inventory is
  confirmed, local plugin installation guidance was reviewed, and the complete
  Pester suite passed with 417 tests passing and 5 file-symbolic-link tests
  skipped for missing Windows Developer Mode/elevation. The installed-client
  scenarios and cross-platform qualification exercised in this work are
  accepted for T029 and recorded in [quickstart.md](quickstart.md). Residual
  synthetic scenarios are deferred to issue #17; cross-client, production
  authorization, and cross-platform qualification are deferred to issue #18.
  Do not infer production authorization or complete platform coverage from
  the passing suite.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; reconciles the destination acceptance criterion with FR-017.
- **Foundational (Phase 2)**: Depends on Setup; blocks all user-story work.
- **User Stories (Phases 3–6)**: Depend on Setup and the foundational skill, inventory, and safe-operation integration.
- **Polish (Phase 7)**: Depends on all four user stories.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Phase 2. It creates the default templates and initial source-selection flow.
- **User Story 2 (P1)**: Follows User Story 1 because it extends the same skill flow and adds override freshness handling.
- **User Story 3 (P1)**: Follows User Story 2 because it completes the same skill instructions with content and audience safeguards.
- **User Story 4 (P1)**: Path-containment work can start after Phase 2; destination rechecks depend on T020's freshness binding, and approval work depends on destination validation.

### Within Each User Story

- T005 and T006 can be prepared before the US1 implementation; T007–T015 create distinct template files and may run in parallel.
- T016 follows T002, T005, and T007–T015.
- T017 and T018 define US2 validation; T019 follows US1 template selection and T020 follows T019.
- T021 and T022 define US3 validation; T023 follows T019 and the bundled-template tasks.
- T024 and T025 define US4 validation. T026 can start after Phase 2; T027 depends on T020 and T026; T028 depends on T027.
- Preserve the shared safe-write and authorization contracts; do not add a bypass to make a story appear independently complete.

### Parallel Opportunities

- T002 and T003 can run in parallel after T001 because they change separate files.
- T005 and T006 can proceed in parallel with T007–T015 because they update tests/guidance while each template task creates a separate file.
- T007–T015 can run in parallel because each creates a distinct template file.
- T017 and T018, T021 and T022, and T024 and T025 can run in parallel within their respective story phases because each pair updates separate test/guidance files.
- T026 can start after Phase 2; complete T027 after T020 and T026, then T028.

---

## Parallel Examples

### User Story 1

```text
After Phase 2, the package and client test guidance can be prepared in parallel with the nine independent template files:

Task: T005 Package-layout tests in tests/powershell/ArticleAuthoring.Tests.ps1
Task: T006 Supported-client scenarios in specs/005-article-authoring/quickstart.md
Task: T007 skills/article-authoring/templates/adventure.md
Task: T008 skills/article-authoring/templates/character.md
Task: T009 skills/article-authoring/templates/handout.md
Task: T010 skills/article-authoring/templates/location.md
Task: T011 skills/article-authoring/templates/monster.md
Task: T012 skills/article-authoring/templates/party.md
Task: T013 skills/article-authoring/templates/persona.md
Task: T014 skills/article-authoring/templates/rule.md
Task: T015 skills/article-authoring/templates/session.md
```

### User Story 2

```text
After User Story 1, define runtime and client checks in parallel; implement the skill flow before binding its consumed inputs:

Task: T017 Freshness tests in tests/powershell/ArticleAuthoring.Tests.ps1
Task: T018 Override scenarios in specs/005-article-authoring/quickstart.md
```

### User Story 3

```text
After User Story 2, prepare static/runtime checks and client scenarios in parallel before completing the shared authoring safeguards:

Task: T021 Static template checks in tests/powershell/ArticleAuthoring.Tests.ps1
Task: T022 Supported-client boundary scenarios in specs/005-article-authoring/quickstart.md
```

### User Story 4

```text
After Phase 2, path-containment work can proceed independently; prepare the synthetic and client checks in parallel:

Task: T024 Safe-operation tests in tests/powershell/ArticleAuthoring.Tests.ps1
Task: T025 Destination and approval scenarios in specs/005-article-authoring/quickstart.md
Task: T026 Path containment in skills/vault-orientation/scripts/VaultPathValidation.psm1 and skills/vault-orientation/scripts/VaultBoundary.psm1
```

---

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases, including explicit destination clarification and shared preflight/runtime wiring.
2. Complete User Story 1 and validate all nine built-in resource files, installed-client working-directory behavior, and registered custom-type selection.
3. Require live exact-vault checks by the calling skill and explicit `callerPreflight` on script requests; do not claim installed-client or platform qualification from synthetic tests.

### Incremental Delivery

1. Add User Story 1 for bundled defaults and registered custom types.
2. Add User Story 2 for DM-owned override precedence and stale-input rejection.
3. Add User Story 3 for marker semantics, convention preservation, and player-safety checks.
4. Add User Story 4 for containment, existing-content preservation, and approval-bound writes.
5. Run the existing acceptance suite and plugin discovery procedure; report all evidence limits explicitly.

---

## Notes

- `[P]` tasks are limited to independent file changes with no incomplete prerequisite.
- Every user-story task uses the matching `[US1]`–`[US4]` label.
- Feature 005 adds Pester tests for package/runtime-backed behavior and supported-client scenarios for skill decisions; neither may be reported as production authorization evidence.
- The task list's source-resource tests do not establish installed-client behavior; the quickstart scenarios must be run separately when a supported client is available.
- Existing synthetic tests do not establish production authorization or installed-client behavior.
- Copilot owns live MCP checks; PowerShell consumes explicit vault-scoped caller confirmation and enforces filesystem/write safeguards, not independently authenticated MCP authorization.
- Resolver symlink-target containment qualification and any future configurable external-target policy are deferred to the vault owner, not release gates. This does not relax PowerShell containment.
