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

- [X] T001 Verify that a consuming vault-facing skill can load the one
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
- [X] T002 Determine and document whether resolver readiness and authorization
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
designated local guidance permits only a read-only lookup limited to the
requested information, using relevant notes identified without relying on an
uncertain folder or note-role mapping. Also confirm the
installed reference is identical from multiple working directories and local
defaults cover both internal-link formats.

### Implementation for User Story 1

- [X] T003 [US1] Create the canonical plugin-owned shared guidance in
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
- [X] T004 [US1] Create the portable vault-orientation skill with valid
  `name` and `description` frontmatter in
  `skills/vault-orientation/SKILL.md`. Load `VAULT-REFERENCE.md` from this
  skill's own bundled resources using the documented per-skill resource
  mechanism, not from the current directory, source checkout, or campaign
  vault. This does not satisfy T001's separate cross-skill installed-resource
  gate; do not enable another vault-facing consumer until that gate passes.
  Implement
  the ordered preflight in FR-018, using its cross-referenced FR-003 through
  FR-014 for detailed guidance, vault, dependency, context, and ambiguity
  obligations. Require the skill to load only vault-local guidance designated
  by the DM or an established vault-configuration contract, if applicable,
  without guessing its path or schema. Make the entire ordered preflight an
  explicit fail-closed gate before any campaign-note access, including a
  default of no access whenever vault authorization is unverifiable or any
  other required preflight step fails. Follow the loading contract in
  `specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`:
  establish the authorized vault location without reading campaign notes;
  verify required dependency readiness and authorization using T002's
  note-content-free method when established; until then, fail closed whenever
  no documented exact-vault authorization signal is available. Load the shared
  reference and any designated local guidance; establish the campaign/group
  and whether output includes a handout or read-aloud section;
  then access campaign notes. Treat no designated local guidance as a valid
  state: permit a read-only lookup limited to the specific information
  requested, using relevant notes identified without relying on an uncertain
  folder or note-role mapping, only after all other checks pass. Pause if
  uncertainty affects findings or the next action, and never create or change
  notes based on provisional assumptions.

**Checkpoint**: The orientation skill encodes the ordered preflight and uses
its own bundled canonical resource. Cross-skill loading and exact-vault
authorization remain unverified gates; no runtime readiness is implied.

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
read-only lookup limited to the requested information, using relevant notes
identified without relying on an uncertain folder or note-role mapping, when
all other preflight checks pass.

### Implementation for User Story 2

- [X] T005 [US2] Define missing, unreadable, and ambiguous input handling in
  `skills/vault-orientation/SKILL.md`. Name the failed shared or designated
  local source, dependency, or context; explain dependent work; and pause it
  before campaign-note access or changes as required by FR-005 and FR-018.
  Distinguish a designated-but-missing local source from no source being
  designated. Do not require or invent a local guidance file; when none was
  designated, allow a read-only lookup limited to the specific information
  requested, using relevant notes identified without relying on an uncertain
  folder or note-role mapping, after the other preflight checks pass. Pause
  before further note access if uncertainty affects findings or the next
  action. Provisional assumptions never authorize creating or changing notes.
  For other missing required sources, identify the source and affected work,
  pause before note access, and ask the DM. State competing interpretations
  and the needed decision when ambiguity matters, as required by FR-006.
  Re-establish guidance and context after the missing input or ambiguity is
  resolved.
- [X] T006 [US2] Define the dependency-failure preflight in
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

- [X] T007 [US3] Operationalize campaign-protection and DM-control rules in
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

- [X] T008 Make `skills/README.md` the declared inventory of every immediate
  child skill directory containing a `SKILL.md`. Add an entry for
  `skills/vault-orientation/SKILL.md`, classify it as vault-facing, and
  identify its shared-reference and required-dependency preflight obligations.
  Define a table format requiring each future skill to be classified as
  vault-facing or non-vault-facing; link to skill instructions rather than
  duplicating them. Point to the authoritative dependency table in
  `specs/001-shared-vault-guidance/spec.md` rather than maintaining a divergent
  dependency list. Do not list a skill that does not exist.
- [X] T009 Document the dependency inventory maintenance rule in
  `skills/README.md` and
  `specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`.
  Require every new required runtime dependency to be added to the
  **Expected Runtime Dependencies** table in
  `specs/001-shared-vault-guidance/spec.md` with purpose, scope, compatibility,
  user setup/configuration, readiness check, authorization check when
  applicable, and unavailable behavior. Require affected vault-facing skill
  preflights and the static source audit to refer to that authoritative table;
  do not duplicate its dependency details.
- [X] T010 Perform the static inventory/source audit and record its result in
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
- [X] T011 Run the independent installed-client and disposable-vault scenarios
  in `specs/001-shared-vault-guidance/quickstart.md`. Use the README's local
  installation and discovery instructions. Validate installed discovery,
  cross-skill canonical-reference loading from multiple working directories,
  offline Obsidian defaults, bounded no-designated-guidance read-only behavior,
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
  **Deferred human validation:** Checked at the DM's request after the
  agent-run scenarios passed. The unperformed SC-004 walkthrough is tracked
  separately in [#13](https://github.com/sylvercode/dm-assistant/issues/13);
  this checkbox does not represent an SC-004 pass.
- [X] T012 Review the completed changes against every constitution MUST and
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
  resource-loading method and blocks additional consumers from relying on an
  assumed sibling path. T002 establishes safe, note-content-free dependency
  readiness and vault-authorization verification and blocks all
  campaign-note access until verified. Per the user's direction, this
  source-only orientation skill was written with fail-closed behavior while
  both gates remain unresolved.
- **User Stories (Phases 3-5)**: The current source implementation covers US1
  through US3, but the unresolved foundational gates prohibit treating it as
  runtime-ready or accessing campaign notes.
- **Polish (Phase 6)**: T008-T009 document the skill and dependency
  inventories. T010 is a static audit after all relevant source files and
  inventory entries exist. T011 runs independent scenarios and defers
  resolver-dependent scenarios until #7 is available. T012 is the final
  governance review.

### User Story Dependencies

- **US1 (P1)**: Runtime use depends on T001 and T002. T004 uses the bundled
  reference from its owning skill directory and fails closed when the exact
  authorization check is unavailable; this does not satisfy either gate.
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

1. Complete T001 and T002 before enabling campaign-note access or additional
   consuming skills. If explicitly directed to proceed with source-only
   implementation while a gate remains unresolved, preserve the blocker and
   fail closed rather than inventing a lookup or authorization mechanism.
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
- The current source implementation is validated except for SC-004. T001 and
  T002 passed, and the agent-run T011 scenarios passed (three after skill
  fixes). T011 is checked with the SC-004 human DM walkthrough deferred to
  [#13](https://github.com/sylvercode/dm-assistant/issues/13), not passed.
  See the current implementation record in `quickstart.md`.

### Current execution status

**2026-10-29 update:** T002 passes. Resolver 2.1.0 adds `get_server_info`,
which returns the configured vault roots without reading notes. Tests with a
configured root, an unconfigured root, multiple roots, and a nonexistent root
behaved as expected. The skill now requires a normalized exact match before
note access. Agent-run T011 scenarios in an isolated installed client passed
against a disposable vault: authorization, missing dependency, offline
defaults, local guidance, missing guidance, ambiguity, no-guidance lookup,
player safety, preparation vs. history, knowledge updates, local and
broad edits, and a permission-denied reference. Three scenarios failed on
their first run (S10 uncertain mapping, E04 broad edit without preview, E05
offered to proceed without the reference). Each led to a narrow skill fix and
a passing re-run. At the DM's request, T011 is now checked with the remaining
SC-004 walkthrough deferred to
[#13](https://github.com/sylvercode/dm-assistant/issues/13). SC-004 requires
five human DMs and remains unperformed, not passed. The 2026-10-26 notes below
are historical.

**DM-provided configuration check (2026-10-29):** Launched the Resolver
exactly as configured in the DM-provided `.temp\WitM-DM\.mcp.json`, without
changing the configuration or calling a note tool. `initialize` reported
version 2.1.0, and `tools/list` exposed `get_server_info`. `get_server_info`
returned one root: the repository worktree, with a `\\?\` prefix. After
normalization, this root is a parent of `.temp\WitM-DM`, not an exact match.
The skill must therefore stop before reading notes from `.temp\WitM-DM` until
the DM changes `--vault` to that folder.

**2026-10-26 update (historical):** T001 now passes through consumer-to-owner skill
activation followed by reading the owner's runtime-provided installed
resource path, verified from two working directories including one outside
the repository. T002 readiness passes, but its exact-vault authorization
method remains blocked. T011 is only partially exercised: fixture discovery,
resource lookup, and a constrained orientation preflight smoke test passed;
note-access scenarios and the human walkthrough remain untested. These results
supersede earlier unresolved-T001 status statements above. See `research.md`
and `quickstart.md`.

**Resolved T002 blocker (historical):** Readiness was verified, but a documented,
note-content-free check of the running server's exact-vault authorization is
still missing. A Resolver tool could satisfy this if it accepts an exact vault
path, checks the active startup allow-list without reading notes or resolving
links, returns an explicit authorized/not-authorized result, does not grant
access, and surfaces errors. This is a proposed capability, not an existing
tool. Once available, verify both the configured disposable vault and an
unconfigured directory, then wire the documented check into the skill before
marking T002 complete. Resolver integration remains owned by #7. Resolved on
2026-10-29 by Resolver 2.1.0's `get_server_info`.

**T011 blocker (historical):** The constrained preflight smoke test is insufficient
for completion. After T002 is resolved, run realistic DM-style workflows in the
installed client against a disposable vault, covering the documented positive,
failure, knowledge, player-safety, and editing/approval scenarios and inspecting
outputs and before/after note state. These technical scenarios may be exercised
by an agent; a live campaign or human DM is not required for every scenario.
Separately, SC-004 requires an informal walkthrough with five human DMs and at
least four correctly distinguishing plugin-wide from vault-specific guidance.
Both the remaining scenario evidence and this human walkthrough are missing.
Keep T011 open until all applicable checks are recorded, not merely one
realistic smoke test.

**Additional T011 checks completed (2026-10-26):** Full package install,
reinstall, listing, fresh-session skill discovery, and installed reference
reading passed under isolated configuration. A separate missing-reference
resource test observed the exact installed-path failure and reported dependent
work must pause, without fallback reads or campaign access. This does not
validate the authorization-gated campaign workflow; permission-denied
unreadability was not separately tested. Evidence and limits are recorded in
`quickstart.md` and `research.md`. The isolated plugin was uninstalled.

Per the user's earlier direction, source implementation proceeded before T001
or T002 passed. The vault-orientation skill loads its own bundled reference and
fails closed when exact-vault authorization cannot be verified. T001 now proves
the fixture's cross-skill loading pattern, not Resolver authorization or full
runtime readiness. No additional vault-facing consumer skill is enabled.

### Durable test conclusions (2026-10-26)

This record is self-contained: `.temp` contains disposable logs and fixtures
that may be deleted. Their paths elsewhere are historical evidence locations,
not prerequisites for understanding these results. All client tests below used
GitHub Copilot CLI 1.0.103. A pass applies only to the scope described here;
it does not imply completion of unexercised scenarios.

| Check | Observed result and conclusion |
| --- | --- |
| T001 installed cross-skill resource loading | **PASS.** Installed a two-skill fixture under an isolated `COPILOT_HOME`. The consumer activated `dm-probe-owner` through the `skill` tool; the owner read `SHARED.md` using its runtime-provided resource directory. Both a run from the fixture directory and a run from an empty directory outside the Git repository returned sentinel `VIOLET-CEDAR-9264` from the same `installed-plugins\_direct\resource-lookup-probe\skills\dm-probe-owner\SHARED.md`. Neither installed run used `--plugin-dir`, glob, shell, or an inferred sibling path. Separate local `--plugin-dir` runs also succeeded. Use owner-skill activation and its supplied resource path, not assumed sibling adjacency. |
| T002 Resolver readiness | **PASS for readiness only.** Launched the configured stdio executable with only the exact disposable vault supplied as its `--vault` root. MCP `initialize` returned server version `3.5.1`; `tools/list` exposed `resolve_obsidian_link` and `generate_obsidian_link`. No tool was called during this readiness probe. A separate fresh CLI session also exposed both tools. |
| T002 exact-vault authorization | **BLOCKED on 2026-10-26; PASS on 2026-10-29** with Resolver 2.1.0 `get_server_info` (see status above). The earlier tool catalog offered no note-content-free authorized-roots check, and no other documented runtime signal was demonstrated. |
| Orientation preflight smoke test | **PASS, constrained.** With the disposable vault explicitly named and Resolver tools visible, the actual skill reported exact-vault authorization as unverified and stopped before shared/local guidance or campaign-note reads. No `view` or Resolver calls occurred. The prompt explicitly required a preflight-only stop and Resolver calls were denied, so this is not an unconstrained behavioral acceptance test. An earlier run excluded the Resolver tools; its missing-tool report is not evidence that the server failed. |
| Explicit user-requested link resolution | **PASS, one functional case.** `resolve_obsidian_link` received `[[Svalich Woods]]`, context `7. Argynvostholt.md` within the disposable vault, and that exact vault root. It returned `status: resolved`, `target_path: Locations/Svalich Woods.md`, `is_embed: false`, and `isError: false`. The path matches `Locations\Svalich Woods.md`. No notes were modified. This test does not satisfy the pre-access, note-content-free authorization requirement. |
| T011 full package install/reinstall and discovery | **PASS.** Copied the plugin manifest, complete `skills` directory, and `com.github.copilot` components into a disposable package. Installed and reinstalled it with a new isolated `COPILOT_HOME`; listing showed `dm-assistant` v0.1.0 and installation reported one skill. A fresh session without `--plugin-dir` activated `vault-orientation`, read the installed `VAULT-REFERENCE.md`, and identified aliases, tags, internal links, and callouts. This was a non-campaign resource/discovery check. |
| T011 missing shared reference | **PASS, resource-only.** Removed `VAULT-REFERENCE.md` only from the isolated installed copy. A fresh session activated the skill and attempted its exact installed resource path; the tool returned `Path does not exist`. The response named the missing shared source and dependent campaign work, required a pause before note access, and did not read fallback copies or other files. Only `skill` and read-only `view` tools were available. This did not exercise the complete ordered campaign preflight or permission-denied unreadability. |
| T010 static inventory/source audit | **PASS.** Exactly one immediate-child skill file, `skills/vault-orientation/SKILL.md`, matches one vault-facing inventory entry. Its source includes the canonical resource, designated local guidance, declared Resolver dependency, readiness/authorization gates, and actual-play-or-permitted-DM-judgment knowledge-update rule. Frontmatter and whitespace checks passed. This is source evidence, not runtime acceptance. |
| Remaining T011 acceptance scenarios | **Superseded on 2026-10-29.** The agent-run scenarios were exercised after T002 passed; see the 2026-10-29 status above and `quickstart.md`. T011 is checked with SC-004 deferred to [#13](https://github.com/sylvercode/dm-assistant/issues/13). The human walkthrough remains unperformed, not passed. |

**Cleanup and preservation:** Both disposable plugin installations were
uninstalled using their isolated CLI homes; the final package-test plugin list
showed no installed plugins. The two-skill fixture's source files and direct
MCP probe script were removed. The repository's shared reference, existing
vault notes, live plugin settings, and live MCP configuration were not changed
by the tests. The explicit functional resolution was the only campaign-link
call; it was separately requested by the user. No note-edit scenarios ran.
