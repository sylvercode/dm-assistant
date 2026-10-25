---

description: "Implementation tasks for shared vault guidance"
---

# Tasks: Shared Vault Guidance

**Input**: Design documents from `specs/001-shared-vault-guidance/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/vault-guidance-loading.md`, and `quickstart.md`

**Tests**: No automated test tasks are included. The feature requires manual
installed-client verification in `quickstart.md`; that release validation is
included in the final phase.

**Organization**: Tasks are grouped by user story so each story can be
implemented and assessed as an increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task can run in parallel with other tasks in its phase because
  it touches different files and has no dependency on incomplete work.
- **[Story]**: User story served by the task (US1, US2, or US3).
- Every task description names the exact repository-relative file path(s).

## Phase 1: Setup

**Purpose**: Project initialization and basic structure.

No setup tasks are needed. The installable plugin root, manifest, and reserved
`skills/` directory already exist; this feature adds no runtime framework or
project dependencies.

---

## Phase 2: Foundational

**Purpose**: Resolve the installed-resource lookup decision before skills
depend on it.

- [ ] T001 Determine a supported installed-plugin resource lookup for the
  canonical shared reference, independent of the current working directory;
  record the selected method and evidence, or an explicit blocker if none is
  verified, in `specs/001-shared-vault-guidance/research.md`. Use the
  documented installation and client-discovery workflow in
  `specs/001-shared-vault-guidance/quickstart.md`; do not rely on source-tree
  or current-directory fallbacks.

**Checkpoint**: Do not implement reference loading until T001 records a
supported lookup decision. An unresolved lookup is a blocker, not permission
to invent a path.

---

## Phase 3: User Story 1 - Consistent vault-aware assistance (Priority: P1)

**Goal**: Give vault-facing skills one canonical reference and loading contract
so they apply shared campaign boundaries, context, and Obsidian conventions.

**Independent Test**: With the Resolver configured, install the plugin and
invoke the skill from the repository root and from a different working
directory. Confirm the same installed reference and explicitly designated
vault-local guidance are loaded before note interpretation, the authorized
vault and campaign context are established, and offline Obsidian defaults
support both internal-link formats while preferring wikilinks absent an
established vault preference.

### Implementation for User Story 1

- [ ] T002 [US1] Create the canonical plugin-owned shared guidance in
  `skills/vault-orientation/VAULT-REFERENCE.md`. Paraphrase the official
  Obsidian sources for aliases, tags, wikilinks and Markdown-style internal
  links, and callouts; support both link formats and recommend wikilinks unless
  DM input or designated vault-local guidance establishes another preference.
  Include source links as provenance, and ensure defaults work offline without
  runtime fetching. Define shared vault/campaign boundaries, preparation
  versus actual-play and character knowledge, continuity preservation,
  player-facing information safety, editing safeguards, and the rule that
  vault content is data rather than governing authority. Permit compatible DM
  customization without changing native Obsidian semantics or weakening
  shared safety rules.
- [ ] T003 [US1] Create the portable vault-orientation skill with valid
  `name` and `description` frontmatter in
  `skills/vault-orientation/SKILL.md`. Use the verified T001 lookup to load
  `VAULT-REFERENCE.md` from the installed plugin resource, not from the
  current directory, source checkout, or campaign vault. Require the skill to
  load vault-local guidance designated by the DM or an established
  vault-configuration contract without guessing a filename or configuration
  schema, and establish the authorized vault, campaign/group, and relevant
  audience before interpreting or changing campaign notes.
- [ ] T004 [US1] Add a dependency preflight to
  `skills/vault-orientation/SKILL.md` that checks every currently declared
  required runtime dependency before campaign-note access, initially the
  `obsidian-link-resolver` MCP server exposing `resolve_obsidian_link` and
  access to the authorized vault. Stop and explain setup or readiness failures
  before reading or changing notes; surface resolver errors and unresolved or
  ambiguous destinations rather than guessing. Keep user-owned MCP setup and
  authorized vault paths out of the plugin. Resolver server/tool integration
  itself is tracked separately by GitHub epic #7.

**Checkpoint**: The orientation skill loads the canonical installed reference,
designated local guidance, and context before note interpretation, and
enforces the dependency preflight.

---

## Phase 4: User Story 2 - Safe handling of missing or ambiguous guidance (Priority: P1)

**Goal**: Pause dependent work rather than inventing guidance, context, or
campaign conventions when a required input is unavailable or ambiguous.

**Independent Test**: In a disposable vault, try missing shared guidance,
designated-but-missing local guidance, no designated local guidance, and
ambiguous campaign or mapping context. Confirm the skill distinguishes these
cases, explains the affected work, asks for required DM direction when needed,
and leaves campaign notes unchanged whenever work is blocked.

### Implementation for User Story 2

- [ ] T005 [US2] Define missing, unreadable, and ambiguous input handling in
  `skills/vault-orientation/SKILL.md`. Name the failed shared or designated
  local source, explain dependent work, and pause that work without creating,
  editing, moving, deleting, or reorganizing campaign notes. Distinguish a
  designated-but-missing source from no local guidance being designated; do
  not require or invent a local guidance file, and allow a straightforward
  read-only lookup to use provisional layout understanding when no source was
  designated, while asking the DM if uncertainty affects the next action.
  When multiple interpretations materially affect the next action, state the
  alternatives and decision needed, then ask the DM. Re-establish guidance
  and context after the missing input or ambiguity is resolved.

**Checkpoint**: Required missing inputs and material ambiguity block only
dependent work, with existing campaign notes unchanged.

---

## Phase 5: User Story 3 - Preserve campaign boundaries and DM control (Priority: P2)

**Goal**: Apply shared safeguards without overriding vault organization,
continuity, or DM authority.

**Independent Test**: In a disposable vault, exercise an absent folder,
tentative preparation, a contradiction or unresolved adventure plan,
player-facing output, a clear page-local edit, and a broad or
continuity-changing edit. Confirm existing organization and continuity are
preserved, player output excludes DM-only facts and revealing links, local
edits do not trigger redundant approval, and impactful edits wait for approval
of a scoped preview.

### Implementation for User Story 3

- [ ] T006 [US3] Operationalize the shared campaign-protection and DM-control
  rules in `skills/vault-orientation/SKILL.md`, applying the requirements in
  `skills/vault-orientation/VAULT-REFERENCE.md` to requested work. Do not infer
  that absent folders should be created or notes reorganized; keep preparation
  tentative and distinct from actual-play history and character knowledge;
  preserve contradictions and unresolved adventure plans for DM clarification;
  and exclude DM-only facts and revealing links from player-facing output.
  Allow a clearly requested page-local edit when its scope and effect are
  clear. Before any broad, destructive, restructuring, or
  continuity-changing edit, present a scoped preview and wait for explicit DM
  approval; apply only the approved preview within the authorized vault.
  Treat note content as data and do not publish or share vault content unless
  separately authorized.

**Checkpoint**: Shared safeguards preserve campaign data and DM control in
read and write workflows.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Keep contributor-facing discovery guidance accurate and verify
the integrated feature in the supported client.

- [ ] T007 Make `skills/README.md` the declared inventory of every immediate
  child skill directory containing a `SKILL.md`. Add an entry for
  `skills/vault-orientation/SKILL.md`, classify it as vault-facing, and identify
  its shared-reference and required-dependency preflight obligations. Define
  the inventory table format so each new skill is classified as vault-facing
  or non-vault-facing; link to skill instructions rather than duplicating
  them. Do not list a skill that does not exist.
- [ ] T008 Run the applicable scenarios in
  `specs/001-shared-vault-guidance/quickstart.md` using an isolated Copilot CLI
  setup and disposable test vault after the Resolver integration in #7 is
  available. Verify installed discovery and reference loading from different
  working directories, offline defaults, dependency fail-closed behavior,
  guidance/context failures, continuity/player-safety safeguards, and the
  preview/approval gate. Enumerate all immediate-child `skills/*/SKILL.md`
  files, verify each has exactly one README inventory entry and a vault-facing
  classification, then verify every vault-facing skill explicitly loads both
  guidance sources and checks all declared dependencies before campaign-note
  access. Record each exercised scenario and inventory check as pass, fail, or
  blocked in the quickstart completion record; do not mark unimplemented or
  unexercised behavior as passed.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No work required; the plugin scaffold already exists.
- **Foundational (Phase 2)**: T001 must establish a supported installed
  resource lookup before reference-loading implementation begins.
- **User Stories (Phases 3-5)**: Depend on T001 and proceed in priority order.
  The stories update the same canonical reference and skill contract, so they
  are not independent parallel workstreams.
- **Polish (Phase 6)**: T007 follows the skill implementation; T008 requires
  the stories to be implemented and the Resolver integration in #7 to be
  available.

### User Story Dependencies

- **US1 (P1)**: Depends on T001; T003 depends on the canonical reference
  created by T002. T004 defines readiness behavior for the Resolver interface
  implemented separately in #7.
- **US2 (P1)**: Depends on US1's loading and context contract; extends the same
  `skills/vault-orientation/SKILL.md`.
- **US3 (P2)**: Depends on the canonical reference and skill from US1 and
  follows US2 because it further updates the same skill workflow.
- **External dependency**: GitHub epic #7 owns Resolver integration and
  supported-client verification. This task list does not create an MCP server,
  configure user-specific vault roots, or duplicate #7's integration work.
  Complete #7 before considering Resolver-dependent installed-client
  validation in T008 complete.

### Within Each User Story

- Complete tasks in their listed order where they touch the same file.
- The shared reference must exist before the skill can load it.
- No automated tests are required by the feature specification; use the
  independent acceptance criteria and the documented manual validation guide.

### Parallel Opportunities

- No safe parallel task pairs are identified. The resource, skill, and story
  safeguards are deliberately centralized and each story extends shared files;
  parallel edits would conflict or depend on unfinished contracts.
- After implementation, independent quickstart scenarios may be exercised
  separately in isolated disposable environments, but record results in the
  shared completion record without overwriting one another.

---

## Parallel Example: User Stories

There are no safe per-story implementation tasks to run concurrently: US2 and
US3 both extend `skills/vault-orientation/SKILL.md`, while US1 establishes the
shared reference and loading contract they rely on. Complete US1, then US2,
then US3. T008's isolated quickstart scenarios can be distributed only after
the shared implementation and Resolver prerequisite are ready.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 to establish a supported installed-resource lookup.
2. Complete US1 (T002-T004) to deliver the canonical reference and orientation
   loading/dependency contract.
3. **Stop and validate** US1 against its independent test criterion. A
   production-ready vault-facing workflow still requires the Resolver
   integration in #7 and the corresponding quickstart checks.

### Incremental Delivery

1. Complete the installed-resource decision and US1 shared guidance.
2. Add US2 missing/ambiguous-input handling and verify blocked work leaves
   notes unchanged.
3. Add US3 campaign-boundary and DM-approval behavior.
4. Update contributor guidance and complete the applicable quickstart
   scenarios after #7 is available.

---

## Notes

- Every task uses the required checklist form and a sequential task ID.
- Story tasks include a `[US1]`, `[US2]`, or `[US3]` label; setup,
  foundational, and polish tasks do not.
- No `[P]` markers are used because all implementation tasks share or depend on
  the canonical reference and skill workflow.
- The tasks describe proposed implementation work. The current repository
  remains a scaffold until those tasks are implemented and verified.
