---
description: "Implementation tasks for article authoring and template selection"
---

# Tasks: Article Authoring and Template Selection

**Input**: Design documents from `specs/005-article-authoring/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Add Feature 005 Pester tests for package and runtime-backed behavior in `tests/powershell/ArticleAuthoring.Tests.ps1`, plus supported-client scenario checks from `quickstart.md` for skill decisions that Pester cannot exercise. Use only synthetic disposable vaults and the test-only authorization provider for local runtime tests. Neither test type establishes production authorization.

**Organization**: Tasks are grouped by the four P1 user stories. Each story includes an independent acceptance criterion.

## Phase 1: Setup

**Purpose**: Resolve the prerequisite design ordering issue before implementation.

- [ ] T001 Align the pre-note sequence in `specs/005-article-authoring/spec.md`, `specs/005-article-authoring/contracts/article-authoring-contract.md`, `specs/005-article-authoring/data-model.md`, and `specs/005-article-authoring/quickstart.md` with `specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md` and `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`: establish and authorize the vault, load the shared reference, then permit only the profile read needed to identify designated local guidance; load that guidance and establish task context before campaign-note or selected-template access.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the shared article-authoring skill entry point, register it, and route operations through existing safety contracts before any story work.

- [ ] T002 [P] Create `skills/article-authoring/SKILL.md` with the portable skill frontmatter, activation of `vault-orientation`, the corrected ordering from T001, installed-skill resource loading, and a one-article operation boundary; do not access vault-owned inputs before the required authorization and guidance gates succeed.
- [ ] T003 [P] Register `article-authoring` exactly once in `skills/README.md` as a vault-facing immediate-child skill, link to `skills/article-authoring/SKILL.md`, and require the shared reference and every declared dependency to be checked before campaign-note access.
- [ ] T004 Route script-backed article creation through `skills/vault-orientation/scripts/RuntimePreflight.psm1`, `skills/vault-orientation/scripts/DependencyPreflight.psm1`, and `skills/vault-orientation/scripts/SafeNoteWriter.psm1`; preserve fail-closed exact-vault authorization and existing approval/write contracts, and do not add a test authorization provider or direct-write path.

**Checkpoint**: The skill is registered, activates the shared preflight in the correct order, and uses existing runtime gates without claiming production authorization is implemented.

---

## Phase 3: User Story 1 - Create an Article from a Plugin Default (Priority: P1) 🎯 MVP

**Goal**: Create a built-in article from its installed skill-owned default, or use a valid registered custom type's configured vault-owned template; never invent a template for an unsupported type.

**Independent Test**: For each built-in type with no override, select and read its corresponding installed-skill template before article creation regardless of current working directory. A valid registered custom type reads only its mapped template; an unbuilt or unregistered type asks how to proceed without creating an article.

### Implementation for User Story 1

- [ ] T005 [P] [US1] Create the `adventure` article structure in `skills/article-authoring/templates/adventure.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T006 [P] [US1] Create the `character` article structure in `skills/article-authoring/templates/character.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T007 [P] [US1] Create the `handout` article structure in `skills/article-authoring/templates/handout.md` using static Markdown, player-facing content sections, and only the specified non-executable fill-in markers.
- [ ] T008 [P] [US1] Create the `location` article structure in `skills/article-authoring/templates/location.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T009 [P] [US1] Create the `monster` article structure in `skills/article-authoring/templates/monster.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T010 [P] [US1] Create the `party` article structure in `skills/article-authoring/templates/party.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T011 [P] [US1] Create the `persona` article structure in `skills/article-authoring/templates/persona.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T012 [P] [US1] Create the `rule` article structure in `skills/article-authoring/templates/rule.md` using static Markdown and only the specified non-executable fill-in markers.
- [ ] T013 [P] [US1] Create the `session` article structure in `skills/article-authoring/templates/session.md` with separate preparation and actual-play sections, using static Markdown and only the specified non-executable fill-in markers.
- [ ] T014 [US1] Implement source lookup and unsupported-type handling in `skills/article-authoring/SKILL.md`: recognize exactly the nine built-in types; load each default from the installed `article-authoring` skill's resources independent of the current directory; read it before drafting; select a custom template only for a registered `templates.custom.<id>` whose ID matches `[a-z][a-z0-9_]*` and does not duplicate a built-in; and explain when no template is available without searching alternate locations, inventing content, or creating an article.
- [ ] T015 [US1] Add Pester coverage in `tests/powershell/ArticleAuthoring.Tests.ps1` that verifies the installed skill package contains exactly one Markdown default for each of the nine built-in type names, checks static skill instructions identify installed `article-authoring` skill resources and require the type, selected source or reason selection was not reached, destination on success or blocker and no-creation confirmation, and exercises valid custom profile mapping through the existing profile contract; record actual installed-client working-directory and one-response checks separately in `specs/005-article-authoring/quickstart.md`.

**Checkpoint**: Built-in defaults and valid registered custom templates are selected from their intended sources before drafting; unsupported types block without a substitute.

---

## Phase 4: User Story 2 - Use a DM-Owned Template (Priority: P1)

**Goal**: Prefer a valid configured DM-owned override while preserving its location and stopping on any invalid or stale override without fallback.

**Independent Test**: A valid override is selected ahead of a bundled default, including when it exists outside `.dmassist-templates/`; a missing, unreadable, invalid, stale, or out-of-vault override blocks creation without fallback or file movement.

### Implementation for User Story 2

- [ ] T016 [US2] Implement configured-template precedence in `skills/article-authoring/SKILL.md` using Feature 002's existing `templates.<built-in-type>` and `templates.custom.<id>` mappings: accept custom IDs matching `[a-z][a-z0-9_]*` that do not duplicate a built-in; use a valid in-vault override before a built-in default; support valid existing paths without moving or renaming them; and stop with a clear blocked outcome for any invalid configured override without falling back.
- [ ] T017 [US2] Bind freshness checks in `skills/vault-orientation/scripts/SafeNoteWriter.psm1` to every consumed authoring input: profile and selected mapping, designated guidance, selected template, relevant campaign context, authorization/boundary evidence, and destination identity/existence/parent state. If any consumed input changes after validation or before writing, invalidate dependent work, report staleness, require revalidation, and do not retry or mix old and new inputs.
- [ ] T018 [US2] Add synthetic-vault Pester coverage in `tests/powershell/ArticleAuthoring.Tests.ps1` for Feature 002 mapping/reference validation and dependency-change detection: valid configured paths, missing/unreadable/out-of-vault references, custom identifier validation, and changes to consumed profile, guidance, template, context, authorization/boundary, and destination inputs. Add configured-versus-bundled selection and no-fallback workflow checks to the supported-client scenarios in `specs/005-article-authoring/quickstart.md`.

**Checkpoint**: Configured overrides retain precedence and user ownership; invalid or stale configuration cannot silently select a different template or proceed to a write.

---

## Phase 5: User Story 3 - Preserve Campaign and Player-Facing Boundaries (Priority: P1)

**Goal**: Preserve vault conventions and continuity, complete only supported static markers, and prevent DM-only information from reaching player-facing output.

**Independent Test**: Author DM-facing and player-facing content using established conventions; verify that player-facing sections omit DM-only facts and revealing links, supported marker behavior follows required/optional semantics, dynamic syntax stays unexecuted, and preparation is not reported as actual play.

### Implementation for User Story 3

- [ ] T019 [US3] Implement content and audience safeguards in `skills/article-authoring/SKILL.md`: follow conventions established by explicit DM instructions, designated local guidance, the shared reference, or relevant authorized notes; use proposed native defaults only when no applicable convention exists, with warning titles naming the caution or consequence; identify DM-only facts from DM direction or designated guidance/context and links as revealing when their target or known result exposes those facts; gate-check after the final content change and directly before delivery/read, repeat after any later change, and withhold when safety cannot be established; recognize only the exact required/optional HTML-comment markers, ask about missing or ambiguous required values, allow optional markers to remain, never execute other template syntax, and keep preparation distinct from actual-play history, character knowledge, and world facts.
- [ ] T020 [US3] Add Pester checks in `tests/powershell/ArticleAuthoring.Tests.ps1` for the static marker syntax and template content constraints, and add supported-client scenarios to `specs/005-article-authoring/quickstart.md` verifying convention use, final player-facing gate timing, DM-only fact/link omission, marker completion/retention, dynamic-syntax non-execution, preparation/history separation, and the one-response type/source-or-not-reached/destination-or-blocker/no-creation contract; report client behavior as unverified unless actually run.

**Checkpoint**: Article content respects established conventions and player/DM boundaries; unsupported template syntax is never expanded or presented as expanded.

---

## Phase 6: User Story 4 - Protect Existing Vault Content (Priority: P1)

**Goal**: Block unsafe or unauthorized reads and writes, preserve existing content, and require scoped approval for changes beyond one safe page-local creation.

**Independent Test**: With synthetic vault fixtures, unsafe or out-of-root paths, unverified Resolver targets, stale inputs, existing destinations, missing folders, and ambiguous destinations cause no dependent read or write; only one clear new article may use the page-local exception, while broader or continuity-changing edits wait for explicit approval.

### Implementation for User Story 4

- [ ] T021 [P] [US4] Enforce article-template and destination containment using `skills/vault-orientation/scripts/VaultPathValidation.psm1` and `skills/vault-orientation/scripts/VaultBoundary.psm1`; reject absolute, traversal, and symlink-resolved paths outside the authorized root before reading or writing, and do not call `resolve_obsidian_link` until its target-containment gate is verified.
- [ ] T022 [US4] Recheck destination identity and filesystem state in `skills/vault-orientation/scripts/SafeNoteWriter.psm1` immediately before applying an article: accept only one vault-relative Markdown path explicitly supplied by the DM; reject an existing target, missing parent, multiple plausible paths, or unknown destination. Never treat Feature 002 section-folder or template mappings as article destinations, overwrite or reformat existing content, create folders, guess an alternate path, or write after any required gate fails.
- [ ] T023 [US4] Apply the page-local exception and scoped approval flow through `skills/vault-orientation/scripts/ChangePreview.psm1` and `skills/vault-orientation/scripts/ApplyNoteChanges.psm1`: allow exactly one clear new article with no existing-note, actual-play, or continuity changes without separate DM approval; otherwise show a scoped preview, make no change before explicit approval, and bind approval to the current proposal and consumed inputs.
- [ ] T024 [US4] Add synthetic-vault Pester coverage in `tests/powershell/ArticleAuthoring.Tests.ps1` for dependency/preflight failures with no dependent reads or writes; escaping paths and unverified Resolver targets; destination conflicts, missing parents, and ambiguous destinations with unchanged fixtures; and page-local versus broader approval, including approval invalidation when the proposal or consumed inputs change.

**Checkpoint**: Unsafe access is blocked, existing content remains unchanged on conflicts or failures, and approval protects all changes outside the narrow page-local exception.

---

## Phase 7: Polish & Cross-Cutting Validation

**Purpose**: Validate the complete skill inventory, repository acceptance suite, and local discovery guidance without claiming blocked production behavior.

- [ ] T025 Verify the `article-authoring` entry and every immediate-child skill in `skills/README.md`, follow the local plugin installation guidance in `README.md`, run `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`, and execute the quickstart's supported-client scenarios when that client is available; report synthetic test evidence separately from installed-client behavior, production authorization, Resolver target containment, and cross-platform support.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; resolves the profile/guidance ordering before implementation.
- **Foundational (Phase 2)**: Depends on Setup; blocks all user-story work.
- **User Stories (Phases 3–6)**: Depend on the foundational skill, inventory, and safe-operation integration.
- **Polish (Phase 7)**: Depends on all four user stories.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Phase 2. It creates the default templates and initial source-selection flow.
- **User Story 2 (P1)**: Follows User Story 1 because it extends the same skill flow and adds override freshness handling.
- **User Story 3 (P1)**: Follows User Story 2 because it completes the same skill instructions with content and audience safeguards.
- **User Story 4 (P1)**: Starts after Phase 2 and can proceed in parallel with User Story 1's template-file work; T022's write freshness check also depends on T017's operation binding.

### Within Each User Story

- T005–T013 create distinct template files and may run in parallel.
- T014 follows the foundational skill entry point and can be developed alongside the independent template files; T015 verifies the packaged templates after they exist.
- T016 follows T014; T017 follows T016's selected-input behavior; T018 verifies both.
- T019 follows T016 and T017 so selected-template freshness is in place while content safeguards are added; T020 validates the templates and skill behavior.
- T021 may proceed after Phase 2 in parallel with User Story 1's template-file work. T022 depends on T017 and T021; T023 depends on T022; T024 verifies the completed safe-operation behavior.
- Preserve the shared safe-write and authorization contracts; do not add a bypass to make a story appear independently complete.

### Parallel Opportunities

- T002 and T003 can run in parallel after T001 because they change separate files.
- T005–T013 can run in parallel because each creates a distinct template file.
- T014 can proceed in parallel with T005–T013 after T002.
- T021 can start after Phase 2; complete T022 after T017 and T021, then T023 and T024.
- User Story 4 can proceed in parallel with User Story 1's template-file work after the foundation, but integrate its safe-write changes before final validation.

---

## Parallel Example: User Story 1

```text
After Phase 2, work on these independent files in parallel:

Task: T005 Create skills/article-authoring/templates/adventure.md
Task: T006 Create skills/article-authoring/templates/character.md
Task: T007 Create skills/article-authoring/templates/handout.md
Task: T008 Create skills/article-authoring/templates/location.md
Task: T009 Create skills/article-authoring/templates/monster.md
Task: T010 Create skills/article-authoring/templates/party.md
Task: T011 Create skills/article-authoring/templates/persona.md
Task: T012 Create skills/article-authoring/templates/rule.md
Task: T013 Create skills/article-authoring/templates/session.md
```

---

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases, including correction of the profile/guidance pre-note ordering.
2. Complete User Story 1 and validate all built-in template lookups plus registered custom-type behavior.
3. Treat this as a design/skill MVP only: production article writes remain unavailable until trusted exact-vault authorization is verified.

### Incremental Delivery

1. Add User Story 1 for bundled defaults and registered custom types.
2. Add User Story 2 for DM-owned override precedence and stale-template rejection.
3. Add User Story 3 for marker semantics, convention preservation, and player-safety checks.
4. Add User Story 4 for containment, existing-content preservation, and approval-bound writes.
5. Run the existing acceptance suite and plugin discovery procedure; report all evidence limits explicitly.

---

## Notes

- `[P]` tasks are limited to independent file changes with no incomplete prerequisite.
- Every user-story task uses the matching `[US1]`–`[US4]` label.
- Feature 005 adds Pester tests for package/runtime-backed behavior and supported-client scenarios for skill decisions; neither may be reported as production authorization evidence.
- Existing synthetic tests do not establish production authorization or installed-client behavior.
- The production authorization handoff and Resolver target-containment property remain release gates, not implementation assumptions.
