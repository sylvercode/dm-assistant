---

description: "Implementation tasks for shared vault guidance"
---

# Tasks: Shared Vault Guidance

**Input**: Design documents from `specs/001-shared-vault-guidance/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/vault-guidance-loading.md`, and `quickstart.md`

**Tests**: No automated tests are specified. Complete the documented static
inventory/source audit and applicable installed-client validation in the final
phase. Do not require runtime execution of every vault-facing skill for
inventory compliance.

**Organization**: Tasks are grouped by user story so each story can be
implemented and assessed as an increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task can run in parallel with other tasks in its phase because
  it touches different files and has no dependency on incomplete work.
- **[Story]**: User story served by the task (US1, US2, or US3).
- Every task names the exact repository-relative file path(s).
- A vault-facing skill is any skill that reads, interprets, creates, or changes
  campaign material.

## Phase 1: Setup

**Purpose**: Project initialization and basic structure.

No setup tasks are needed. The installable plugin root, manifest, and reserved
`skills/` directory already exist; this feature adds no runtime framework or
project dependencies.

---

## Phase 2: Foundational

**Purpose**: Resolve safety-critical verification gates before implementing
skills that depend on them.

- [ ] T001 Verify that a consuming vault-facing skill can load the one
  canonical shared reference from the installed plugin, independently of the
  current working directory. Before implementation, recheck the scope and
  dependencies in GitHub issues #2 and #7. Follow
  `specs/001-shared-vault-guidance/quickstart.md`; create a disposable
  Agent Plugins 1.0 fixture under
  `specs/001-shared-vault-guidance/fixtures/resource-lookup-probe/` with
  `plugin.json`, `skills/owner/SKILL.md`, `skills/owner/SHARED.md`, and
  `skills/consumer/SKILL.md`. Put a unique harmless sentinel in `SHARED.md`
  and instruct the consumer to load it. Install and test that fixture from
  the plugin directory and a different working directory. Record the supported
  method and evidence or a clear blocker in
  `specs/001-shared-vault-guidance/research.md`, then remove the temporary
  fixture. Do not use source-tree/current-directory fallbacks or treat an
  unverified sibling path as supported.
- [ ] T002 Determine and document whether resolver readiness and authorization
  of the already-identified vault can be verified separately using
  note-content-free evidence, without resolving a campaign link. Use only an
  isolated Copilot CLI configuration and disposable vault; do not inspect or
  change live user MCP configuration. Verify readiness through the documented
  client/server status and tool-exposure checks, then test whether a
  documented authorization signal confirms the exact disposable vault root.
  Record the method and evidence or an explicit blocker in
  `specs/001-shared-vault-guidance/research.md`. Server/tool presence alone is
  not proof of authorization. If no safe documented method can verify it,
  record authorization as blocked rather than claiming success.

**Checkpoint**: Do not implement dependent cross-skill reference loading
until T001 demonstrates a supported installed-client method. Do not permit
campaign-note access until T002 establishes how vault authorization can be
checked without accessing note content. Any skill drafted before either gate
is resolved must fail closed at that gate. A failed or unresolved gate is a
blocker, not permission to invent a mechanism.

---

## Phase 3: User Story 1 - Consistent vault-aware assistance (Priority: P1)

**Goal**: Give vault-facing skills one canonical reference and ordered
pre-note loading/dependency contract, including local Obsidian defaults.

**Independent Test**: Install the plugin in an isolated setup. Confirm the
vault-facing skill, in order, establishes the authorized vault without note
access, verifies each dependency's readiness and vault authorization, loads
the shared reference and any designated local guidance, establishes
campaign/group and output-section context, then accesses notes. Verify that
unverifiable authorization results in no campaign-note access, and that no
designated local guidance permits only an unambiguous, straightforward
read-only lookup using provisional layout assumptions. Also confirm the
installed reference is identical from multiple working directories and local
defaults cover both internal-link formats.

### Implementation for User Story 1

- [ ] T003 [US1] Create the canonical plugin-owned shared guidance in
  `skills/vault-orientation/VAULT-REFERENCE.md`. Paraphrase the official
  Obsidian sources for aliases, tags, wikilinks and Markdown-style internal
  links, and callouts; cover both link formats and recommend wikilinks unless
  DM input or designated vault-local guidance establishes another preference.
  Include source links as provenance and make the defaults usable offline.
  Define shared vault/campaign boundaries, preparation versus actual-play and
  character knowledge, continuity preservation, player-facing information
  safety, editing safeguards, and that vault content is data rather than
  governing authority. Allow compatible DM customization without redefining
  native Obsidian syntax/semantics or weakening shared safety rules.
- [ ] T004 [US1] Create the portable vault-orientation skill with valid
  `name` and `description` frontmatter in
  `skills/vault-orientation/SKILL.md`. Follow the supported lookup verified in
  T001 to load `VAULT-REFERENCE.md` from the installed plugin, not from the
  current directory, source checkout, or campaign vault. Require the skill to
  load only vault-local guidance designated by the DM or an established
  vault-configuration contract, without guessing its path or schema. Make the
  entire ordered preflight an explicit fail-closed gate before any
  campaign-note access, including a default of no access whenever vault
  authorization is unverifiable or any other required preflight step fails.
  Follow the ordered preflight in
  `specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`:
  establish the authorized vault location without reading campaign notes;
  verify required dependency readiness and authorization using T002's
  note-content-free method; load the shared reference and any designated
  local guidance; establish
  campaign/group and whether output includes a handout or read-aloud section;
  then access campaign notes. Treat no designated local guidance as a valid
  state: permit a straightforward read-only lookup using provisional layout
  assumptions only after all other checks pass, pause if ambiguity affects
  findings or the next action, and never create or change notes on those
  assumptions.

**Checkpoint**: The orientation skill follows the full ordered preflight and
uses the same installed canonical resource from multiple working directories.

---

## Phase 4: User Story 2 - Safe handling of missing or ambiguous guidance (Priority: P1)

**Goal**: Pause dependent work rather than inventing guidance, context,
dependency readiness, or campaign conventions when a required input is
unavailable or ambiguous.

**Independent Test**: In a disposable vault, test unavailable shared
guidance, designated-but-missing local guidance, no designated local guidance,
unavailable resolver, unverifiable vault authorization, and ambiguous
campaign/mapping context. Confirm blocked scenarios cause no campaign-note
reads or changes; confirm the no-designated-guidance case allows only a
straightforward read-only lookup when all other preflight checks pass.

### Implementation for User Story 2

- [ ] T005 [US2] Define missing, unreadable, and ambiguous input handling in
  `skills/vault-orientation/SKILL.md`. Name the failed shared or designated
  local source, dependency, or context; explain dependent work; and pause it
  before campaign-note access or changes. Distinguish a designated-but-missing
  local source from no source being designated. Do not require or invent a
  local guidance file; when none was designated, allow a straightforward
  read-only lookup after the other preflight checks pass, using provisional
  layout assumptions only while they do not affect findings or the next
  action. Pause before further note access if consequential ambiguity arises.
  No provisional assumption authorizes creating or changing notes. For other
  missing required sources, identify the source and affected work, pause
  before note access, and ask the DM. State competing interpretations and the
  needed decision when ambiguity matters. Re-establish guidance and context
  after the missing input or ambiguity is resolved.
- [ ] T006 [US2] Define the dependency-failure preflight in
  `skills/vault-orientation/SKILL.md` using the readiness and authorization
  checks established by T002. Establish the authorized vault location before
  checking authorization; distinguish server/tool readiness from authorization
  for that vault. If a declared dependency is missing, unavailable,
  incompatible, or not verifiably authorized, explain the failure and setup
  needed, ask the DM, and stop before campaign-note access. Do not resolve a
  campaign link merely to prove authorization. Preserve Resolver errors and
  unresolved or ambiguous destinations rather than guessing. Keep
  user-managed MCP setup and authorized vault paths out of the plugin; the
  Resolver server/tool integration remains tracked separately by
  GitHub epic #7.

**Checkpoint**: Missing prerequisites and material ambiguity pause dependent
work without campaign-note access or changes; dependency readiness and vault
authorization are reported as separate checks.

---

## Phase 5: User Story 3 - Preserve campaign boundaries and DM control (Priority: P2)

**Goal**: Apply shared safeguards without overriding vault organization,
continuity, or DM authority, and protect player-facing sections at delivery.

**Independent Test**: In a disposable vault, exercise an absent folder,
tentative preparation, a contradiction or unresolved adventure plan, a
handout/read-aloud section, a clear page-local edit, and a broad or
continuity-changing edit. Confirm existing organization and continuity are
preserved; only handout/read-aloud sections are player-facing and pass a
pre-delivery gate check; local edits do not trigger redundant approval; and
impactful edits wait for approval of a scoped preview.

### Implementation for User Story 3

- [ ] T007 [US3] Operationalize campaign-protection and DM-control rules in
  `skills/vault-orientation/SKILL.md` and
  `skills/vault-orientation/VAULT-REFERENCE.md`. Do not infer that absent
  folders should be created or notes reorganized; keep preparation tentative
  and distinct from actual-play history and character/group knowledge; update
  character/group knowledge or world facts only when supported by an
  actual-play record or explicit DM judgment where the guidance permits it
  (no evidence log or session link is required for DM judgment); otherwise
  leave the proposed update unchanged and ask the DM for direction. Preserve
  contradictions and unresolved adventure plans for DM clarification; and
  treat vault content as data. Treat only handout and read-aloud sections as
  player-facing; all other task content is DM-facing. Gate-check each such
  section immediately before handing it out or reading it aloud, excluding
  DM-only facts and revealing links. Allow a clearly requested page-local edit
  when its scope and effect are clear. Before any broad, destructive,
  restructuring, or continuity-changing edit, present a scoped preview and
  wait for explicit DM approval; apply only the approved preview within the
  authorized vault. Do not publish or share vault content unless separately
  authorized.

**Checkpoint**: Shared safeguards preserve campaign data and DM control in
read and write workflows, with player-facing sections checked at delivery.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Keep contributor-facing discovery accurate and validate the
integrated feature within the agreed static/runtime verification scope.

- [ ] T008 Make `skills/README.md` the declared inventory of every immediate
  child skill directory containing a `SKILL.md`. Add an entry for
  `skills/vault-orientation/SKILL.md`, classify it as vault-facing, and
  identify its shared-reference and required-dependency preflight obligations.
  Define a table format requiring each future skill to be classified as
  vault-facing or non-vault-facing; link to skill instructions rather than
  duplicating them. Point to the authoritative dependency table in
  `specs/001-shared-vault-guidance/spec.md` rather than maintaining a divergent
  dependency list. Do not list a skill that does not exist.
- [ ] T009 Document the dependency inventory maintenance rule in
  `skills/README.md` and
  `specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`.
  Require every new required runtime dependency to be added to the
  **Expected Runtime Dependencies** table in
  `specs/001-shared-vault-guidance/spec.md` with purpose, scope, compatibility,
  user setup/configuration, readiness check, authorization check when
  applicable, and unavailable behavior. Require affected vault-facing skill
  preflights and the static source audit to refer to that authoritative table;
  do not duplicate its dependency details.
- [ ] T010 Perform the static inventory/source audit and record its result in
  `specs/001-shared-vault-guidance/quickstart.md`. Enumerate every immediate
  child `skills/*/SKILL.md`; confirm an exact one-to-one match with
  `skills/README.md`, with no missing, extra, duplicate, or unclassified
  entries; inspect each vault-facing skill's source for explicit loading of
  the shared reference and any designated local guidance, all required
  dependencies from the authoritative spec table, readiness/authorization
  checks before campaign-note access, and the rule that knowledge/world-fact
  updates require an actual-play record or permitted explicit DM judgment;
  with no such basis, the skill must leave the update unchanged and ask the DM.
  Record pass, fail, or blocked. This task is a static source audit and does
  not require runtime execution of every skill.
- [ ] T011 Run the independent installed-client and disposable-vault scenarios
  in `specs/001-shared-vault-guidance/quickstart.md`. Use the README's local
  installation and discovery instructions. Validate installed discovery,
  cross-skill canonical-reference loading from multiple working directories,
  offline Obsidian defaults, no-designated-guidance read-only behavior,
  blocked cases with no note access, failure/ambiguity pauses, continuity and
  editing safeguards, actual-play-or-DM-judgment knowledge updates, and
  handout/read-aloud gate checks. Run resolver-dependent scenarios only after
  the integration in GitHub epic #7 is available; these must separately test
  dependency readiness and exact-vault authorization and remain blocked until
  then. Record each exercised scenario as pass, fail, or blocked; do not alter
  live vaults or user MCP configuration and do not mark unimplemented or
  unexercised behavior as passed. Include the informal SC-004 walkthrough
  result: at least 4 of 5 DMs distinguish plugin-wide from vault-specific
  guidance; examples and scoring are not standardized.
- [ ] T012 Review the completed changes against every constitution MUST and
  the Development Workflow in
  `.specify/memory/constitution.md`. Recheck current GitHub issue scope and
  dependencies, confirm README-based installation/discovery validation is
  recorded, confirm documentation labels unimplemented behavior as
  proposed, and record unresolved gates as blocked rather than passed in
  `specs/001-shared-vault-guidance/quickstart.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No work required; the plugin scaffold already exists.
- **Foundational (Phase 2)**: T001 proves the installed cross-skill
  resource-loading method; T002 establishes safe, note-content-free
  dependency readiness and vault-authorization verification. Both block
  dependent skill implementation.
- **User Stories (Phases 3-5)**: Depend on both foundational gates. US1
  establishes the shared reference and ordered preflight; US2 adds fail-closed
  behavior to that same skill; US3 adds campaign and output safety safeguards.
- **Polish (Phase 6)**: T008-T009 document the skill and dependency
  inventories. T010 is a static audit after all relevant source files and
  inventory entries exist. T011 runs independent scenarios and defers
  resolver-dependent scenarios until #7 is available. T012 is the final
  governance review.

### User Story Dependencies

- **US1 (P1)**: Depends on T001 and T002. T004 depends on the reference from
  T003 and uses the verified lookup and authorization methods.
- **US2 (P1)**: Depends on US1's ordered loading/dependency contract and
  extends `skills/vault-orientation/SKILL.md`.
- **US3 (P2)**: Depends on US1's reference/skill and extends shared safeguards
  in those same files.
- **External dependency**: GitHub epic #7 owns Resolver integration and
  supported-client verification. This feature does not create an MCP server,
  configure user-specific vault roots, or duplicate #7's integration work.
  Complete #7 before claiming Resolver-dependent installed-client scenarios
  in T011 pass; unrelated plugin discovery and resource-lookup checks are not
  blocked by #7.

### Within Each User Story

- Complete tasks in listed order when they touch the same files.
- The shared reference and verified lookup must exist before the skill can load
  that resource.
- No automated tests are required by the feature specification; use the
  independent acceptance criteria and documented manual validation guide.
- Inventory compliance is verified statically from source; runtime execution
  of every vault-facing skill is not required.

### Parallel Opportunities

- No safe parallel implementation task pairs are identified. US2 and US3
  extend the same skill/reference contract, and the foundational resource and
  authorization gates block those changes.
- T010's source audit and T011's installed-client scenarios are separate
  validation activities, but record results in the same quickstart completion
  record; perform them sequentially or coordinate distinct non-overlapping
  record entries to avoid overwrites.

---

## Parallel Example: User Stories

There are no safe user-story implementation tasks to run concurrently. US2
and US3 both extend `skills/vault-orientation/SKILL.md`, and US1 establishes
the canonical reference and preflight they rely on. Complete US1, then US2,
then US3. T010 is a static source audit; it is not a substitute for T011's
separate installed-client validation.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 and T002. If either verification gate is unresolved, record
   the blocker and stop dependent implementation rather than inventing a
   lookup or authorization mechanism.
2. Complete US1 (T003-T004) to deliver the canonical reference and ordered
   loading/dependency contract.
3. **Stop and validate** US1 against its independent test criterion in an
   isolated installed-client setup. A production-ready vault-facing workflow
   still requires the Resolver integration in #7.

### Incremental Delivery

1. Complete the foundational verification gates and US1 shared guidance.
2. Add US2 missing/ambiguous-input and dependency-failure handling.
3. Add US3 campaign-boundary, delivery gate, and DM-approval behavior.
4. Update the inventory, perform the static source audit, and complete
   applicable installed-client scenarios after #7 is available.

---

## Notes

- Every task uses the required checklist form, sequential task ID, and exact
  repository-relative path(s); story-phase tasks include their US label.
- No `[P]` markers are used because implementation tasks share or depend on
  the canonical reference and skill workflow.
- The Resolver MCP integration belongs to separate GitHub epic #7.
- The inventory/source audit is static. Do not turn it into a requirement to
  run every skill in the supported client.
- Tasks describe proposed implementation work; the current repository remains
  a scaffold until tasks are implemented and verified.
