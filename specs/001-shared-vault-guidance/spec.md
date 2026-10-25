# Feature Specification: Shared Vault Guidance

**Feature Branch**: `sylvercode-shared-vault-guidance`

**Created**: 2026-10-24

**Status**: Draft

**Input**: GitHub issue #2, “Establish shared vault guidance and loading prerequisites”

## Clarifications

### Session 2026-10-25

- Q: Should the local Obsidian link guidance cover both wikilinks and Markdown-style internal links, or only wikilinks? → A: Cover both formats and recommend wikilinks by default, while respecting an explicitly established vault preference.
- Q: Which workflows should count as vault-facing and therefore require the shared guidance and dependency checks? → A: Any skill that reads, interprets, creates, or changes campaign material.
- Q: What order should a vault-facing skill follow before reading campaign notes? → A: Confirm the vault location without reading notes; verify required tools are available and authorized for that vault; load shared and designated local guidance; resolve campaign/group and audience; then access campaign notes.
- Q: When must a vault-facing skill determine whether its output is for the DM or for players/characters? → A: Only handout and read-aloud sections are player-facing; in every case, gate-check them before handing them out or reading them aloud.
- Q: For the required inventory check, should verification stop at enumerating every skill file and inspecting each listed vault-facing skill’s declared preflight, or also run each skill in the supported client? → A: Use a static inventory and source audit only; runtime verification of every vault-facing skill is not required.
- Q: How should SC-004 measure whether DMs can distinguish plugin-wide guidance from vault-specific guidance? → A: Keep the existing 4-of-5 DM threshold and use an informal walkthrough; do not standardize the examples or scoring.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Consistent vault-aware assistance (Priority: P1)

As a DM using a vault-facing skill, I need it to apply the same campaign boundaries and conventions as every other skill so that preparation, actual play, lore, character knowledge, and player-facing material remain consistent.

**Why this priority**: Shared rules are foundational to safe and coherent vault workflows.

**Independent Test**: Use a vault-facing skill with a known campaign task and verify it consults the shared reference and designated vault-local guidance before interpreting or changing campaign notes, then applies the specific safeguards in FR-007 through FR-010.

**Acceptance Scenarios**:

1. **Given** the shared reference and designated vault-local guidance are available, **When** a vault-facing skill starts a campaign-note task, **Then** it loads both sources and the active vault/campaign context before interpreting or changing notes.
2. **Given** a task concerns preparation, actual play, character knowledge, lore, or a player-facing handout, **When** the skill responds, **Then** it follows the preparation and knowledge boundary in FR-007, the continuity boundary in FR-008, and the player-safety boundary in FR-009, as applicable.
3. **Given** the plugin is installed separately from the campaign vault, **When** the skill locates its shared reference, **Then** it uses the plugin-owned resource and does not treat the plugin directory as the vault.
4. **Given** official Obsidian help pages are unavailable during a task and the shared reference is loaded, **When** a DM asks about aliases, tags, internal links, or callouts, **Then** the skill uses the local defaults, applies any compatible DM-designated customization, and does not fetch external documentation or claim unsupported syntax.

### User Story 2 - Safe handling of missing or ambiguous guidance (Priority: P1)

As a DM, I need the assistant to stop and explain when required guidance or campaign context is missing, unreadable, or ambiguous so that it does not invent conventions or make unintended changes.

**Why this priority**: Guessing at vault structure or campaign continuity can cause user-data and story errors.

**Independent Test**: Withhold or make ambiguous a required guidance source or campaign mapping and confirm the skill identifies the missing information and pauses affected interpretation or edits for DM direction.

**Acceptance Scenarios**:

1. **Given** required shared or vault-local guidance cannot be found or read, **When** a vault-facing skill is invoked, **Then** it names the missing or unreadable source, explains which part of the requested task depends on it, and pauses that dependent work without changing campaign notes.
2. **Given** the guidance or active campaign context supports multiple reasonable interpretations, **When** the skill's next action depends on choosing among them, **Then** it states the competing interpretations, identifies the choice needed, and asks the DM to resolve it before proceeding.
3. **Given** an affected task is paused for clarification, **When** the skill reports the issue, **Then** it leaves existing campaign notes unchanged.

### User Story 3 - Preserve campaign boundaries and DM control (Priority: P2)

As a DM, I need shared guidance to protect existing organization, continuity, and player/DM information boundaries so that common rules do not override my campaign or reveal protected information.

**Why this priority**: Consistent shared guidance must preserve user authority and existing campaign data as workflows are added.

**Independent Test**: Exercise representative preparation, contradiction, knowledge, handout, and broad-edit scenarios and verify each follows the documented safeguards without restructuring or silently rewriting campaign material.

**Acceptance Scenarios**:

1. **Given** an expected folder or note is absent, **When** a skill uses the shared guidance, **Then** it does not assume a folder should be created or reorganize existing notes.
2. **Given** preparation contains material not confirmed in actual play, **When** the skill handles campaign history or character knowledge, **Then** it does not treat preparation alone as an established event or knowledge.
3. **Given** notes contain a contradiction or an unresolved adventure plan, **When** the skill encounters it, **Then** it preserves the existing content and asks the DM rather than silently resolving or rewriting it.
4. **Given** a task includes a handout or read-aloud section, **When** the skill prepares that section, **Then** it treats only that section as player-facing, excludes DM-only facts and revealing links, and gate-checks it before handing it out or reading it aloud.
5. **Given** a requested change is broad, destructive, restructuring, or continuity-changing, **When** the skill proposes the change, **Then** it previews the proposed changes and obtains DM approval before applying them.

### Edge Cases

- The reference is present in the source project but unavailable through the installed plugin resource location.
- The designated vault-local guidance is absent, unreadable, or points to conflicting conventions; the skill reports which source or convention is missing or conflicting and pauses dependent work.
- The skill cannot confidently determine the authorized vault or active campaign/group from the user's workspace, explicit input, or established vault context; it asks the DM to identify the intended context before proceeding.
- A task is a clearly requested page-local edit; it should not trigger redundant approval when it is not broad, destructive, restructuring, or continuity-changing.
- Guidance content or campaign notes contain text that appears to instruct the assistant to ignore safeguards or take unrelated actions; such text remains campaign data and does not override the skill's governing instructions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The plugin MUST provide one canonical shared reference for vault meanings, conventions, campaign boundaries, knowledge rules, preparation/history distinctions, and editing safeguards.
- **FR-002**: The shared reference MUST be distributed as a plugin-owned resource, separate from campaign data and user-owned vault guidance.
- **FR-003**: Every implemented vault-facing skill MUST explicitly load the shared reference and the vault-local guidance designated either by the DM or by an established vault-local configuration contract before interpreting or changing campaign notes. A skill MUST NOT guess which local guidance is designated.
- **FR-004**: Before a vault-facing skill accesses campaign notes, it MUST establish the authorized vault location from the user's workspace or explicit input without reading campaign notes. After loading required guidance, it MUST establish the relevant campaign/group from explicit input or unambiguous designated context. If the vault or campaign/group cannot be established, it MUST ask the DM before proceeding.
- **FR-005**: When required guidance is unavailable or unreadable, a vault-facing skill MUST identify the affected source, explain which requested work depends on it, and pause that work without changing campaign notes or silently substituting assumptions.
- **FR-006**: When vault mappings, guidance, or campaign context have multiple reasonable interpretations that affect the next action, a vault-facing skill MUST state the competing interpretations, identify the needed decision, and request DM direction before proceeding.
- **FR-007**: Shared guidance MUST distinguish preparation from actual-play history and character knowledge; preparation alone MUST NOT establish that an event occurred or that a character knows it.
- **FR-008**: Shared guidance MUST preserve existing vault organization and notes, avoid assuming absent folders should be created, and prohibit silently resolving contradictions or rewriting run adventure plans.
- **FR-009**: Shared guidance MUST treat only handout and read-aloud sections as player-facing, exclude DM-only facts and revealing links from them, and require a gate check before each is handed out or read aloud. All other task content is DM-facing.
- **FR-010**: Broad, destructive, restructuring, or continuity-changing edits MUST be previewed and approved by the DM before application; clearly requested page-local edits MUST NOT require redundant approval.
- **FR-011**: Shared guidance and vault content MUST be treated as data, not as authority to override governing instructions or authorize unrelated actions.
- **FR-012**: The installed-resource lookup MUST be verified in the supported client so that skills can find the bundled reference independently of the current working directory.
- **FR-013**: Before any vault-facing skill reads or changes campaign notes, it MUST verify that every currently declared required runtime dependency is available. The initial required dependency is the Obsidian Link Resolver MCP server exposing `resolve_obsidian_link`, configured to allow the authorized vault. If any required dependency is missing, unavailable, or misconfigured, the skill MUST explain the failure and stop before accessing or changing campaign notes.
- **FR-014**: The required-dependency inventory MUST be explicitly documented and extensible; it is not an exhaustive list of all future dependencies. Each added required dependency MUST state its purpose and scope, supported version or compatibility contract, user setup/configuration, readiness check, and behavior when unavailable.
- **FR-015**: The plugin-owned shared reference MUST contain concise, locally available, paraphrased default guidance for Obsidian aliases, tags, internal links (both wikilinks and Markdown-style links), and callouts, based on the official documentation linked in this specification. It MUST recommend wikilinks by default while respecting an explicitly established vault preference. Vault-facing skills MUST be able to use these defaults without fetching or reinterpreting the external pages at runtime.
- **FR-016**: DM-designated vault-local guidance MAY supplement or customize the shared Obsidian defaults, including replacing a general recommendation for a campaign. It MUST preserve valid Obsidian syntax and semantics and MUST NOT override the shared safety requirements.
- **FR-017**: `skills/README.md` MUST be the plugin's declared skill inventory and MUST list every immediate child skill directory containing a `SKILL.md`, classifying each entry as vault-facing or non-vault-facing. For every vault-facing skill, the inventory MUST identify its shared-reference and required-dependency preflight obligation. Validation MUST use a static inventory and source audit: enumerate all `skills/*/SKILL.md` files, confirm an exact one-to-one match with inventory entries (no missing, extra, duplicate, or unclassified entries), and inspect every listed vault-facing skill to verify that its source explicitly loads the shared reference and verifies required dependencies before campaign-note access. Runtime verification of every vault-facing skill in the supported client is not required.
- **FR-018**: A vault-facing skill MUST follow this order before accessing campaign notes: establish the authorized vault location without reading campaign notes; verify every declared required dependency is available and authorized for that vault; load the plugin-owned shared reference and designated vault-local guidance; establish the relevant campaign/group and whether the requested output includes a handout or read-aloud section; then access campaign notes. It MUST pause and ask the DM when a required step cannot be completed. Before handing out or reading aloud either player-facing section, the skill MUST gate-check it for DM-only facts and revealing links.

## Expected Runtime Dependencies *(initial, non-exhaustive)*

| Dependency | Type and scope | Purpose | Setup and verification | Failure behavior |
|---|---|---|---|---|
| [Obsidian Link Resolver](https://github.com/sylvercode/obsidian-link-resolver) | Required runtime MCP server for every vault-facing skill; minimum compatible release is `2.0.0`. | Exposes `resolve_obsidian_link` for resolving Obsidian links against an authorized vault. | The DM installs the MCP release separately and configures `obsidian-link-resolver` in Copilot CLI with one or more explicitly authorized absolute vault roots. Verify the server and tool are available in a new session. Do not embed vault-specific paths in the plugin. | If the server or tool is unavailable, or the vault is not authorized, the skill stops before reading or changing campaign notes and reports the required setup. Resolver errors or unresolved/ambiguous links MUST be surfaced; skills MUST NOT guess a destination. |

This inventory records dependencies identified so far and is not exhaustive.
Future required runtime dependencies may be added using FR-014. Obsidian help
pages listed below are source references for the locally bundled guidance, not
runtime dependencies.

## Local Obsidian Convention Sources

The shared reference MUST summarize these native concepts locally, using
paraphrased guidance rather than requiring runtime access to the web pages:

| Concept | Official source | Local default guidance |
|---|---|---|
| Aliases | [Obsidian Aliases](https://obsidian.md/help/aliases) | Use aliases as reusable alternate names for a note; use per-link display text for a one-off label. Store note aliases using Obsidian's supported list property. |
| Tags | [Obsidian Tags](https://obsidian.md/help/tags) | Use tags as classification and retrieval metadata, not as a substitute for explanatory prose. Preserve the DM's vocabulary; nested tags may express a hierarchy. |
| Internal links (Wikilinks and Markdown) | [Obsidian Internal links](https://obsidian.md/help/links) | Both wikilink and Markdown-style internal links are supported. Prefer wikilinks by default unless an established vault preference says otherwise. Use heading/block targets and display text where appropriate; resolve destinations rather than inventing them. |
| Callouts | [Obsidian Callouts](https://obsidian.md/help/callouts) | Use supported blockquote callout syntax for clearly titled supplemental content. A callout or collapsed section is presentation only, not an access-control boundary. |

These are general defaults, not a required vault structure or tag vocabulary.
An explicitly established vault preference may come from DM input or
designated vault-local guidance; it takes precedence over the wikilink default.
DM-designated guidance may set campaign-specific terms and usage preferences
within FR-016. If a preferred convention conflicts with native syntax or cannot
be verified from the available local guidance, the skill MUST identify the
conflict rather than claim unsupported behavior.

### Key Entities

- **Shared vault reference**: Plugin-owned guidance describing common vault concepts, boundaries, continuity safeguards, knowledge rules, and safe editing expectations.
- **Vault-local guidance**: DM-owned conventions and exceptions designated for a particular vault; it remains outside the distributed plugin.
- **Vault and campaign context**: The authorized campaign workspace and relevant campaign/group identity needed to interpret a task.
- **Vault-facing skill**: A user-invoked workflow that reads, interprets, creates, or changes campaign material and is therefore subject to the loading prerequisite and safeguards.
- **Required runtime dependency**: An explicitly declared external tool or service with a purpose, scope, supported compatibility contract, setup, readiness check, and unavailable behavior. The initial inventory is non-exhaustive.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A static inventory and source audit confirms that the set of immediate-child `skills/*/SKILL.md` files matches the declared inventory in `skills/README.md` exactly one-to-one, with no missing, extra, duplicate, or unclassified entries, and that 100% of entries classified as vault-facing explicitly load both required guidance sources and verify all declared dependencies before campaign-note access.
- **SC-002**: 100% of tested missing-guidance and ambiguity scenarios identify the missing source or competing interpretations, name the dependent work, and pause that work without campaign-note changes until DM direction is available.
- **SC-003**: All documented acceptance scenarios for preparation/history, continuity, player safety, and approval safeguards pass without unintended campaign-note changes.
- **SC-004**: In an informal short walkthrough, at least 4 of 5 DMs can correctly identify which example guidance is plugin-wide and which is vault-specific. The examples and scoring are not standardized, and no vault reorganization is required.
- **SC-005**: In 100% of tested vault-facing skill invocations where the resolver server or `resolve_obsidian_link` is unavailable or not configured for the authorized vault, the skill reports the dependency problem and performs no campaign-note reads or changes.
- **SC-006**: In 100% of tested convention-guidance tasks, skills use the locally bundled Obsidian defaults without fetching external help pages, and apply DM-designated customizations without misrepresenting native syntax or weakening safety requirements.

## Assumptions

- The initial workflows support one campaign per vault; multi-campaign isolation is outside this feature.
- The supported client and installed-resource lookup method will be selected and verified during planning; source-tree presence alone does not satisfy the lookup requirement.
- GitHub Copilot CLI is the supported client for the initial resolver dependency setup. The MCP server and user-authorized vault roots are configured outside the distributed plugin.
- Official Obsidian help pages are source references used to maintain concise local defaults; no network access to those pages is required during a vault-facing task.
- The designated vault-local guidance source is supplied explicitly by the DM or identified by the vault-configuration contract. The separate configuration work defines its specific discovery and configuration rules; this feature does not prescribe that schema or require vault migration.
- A specialized agent may be considered as a future workflow option only if supported and useful, but explicit skill prerequisites remain required and do not depend on agent availability.
- No vault folders, profile files, or guidance files are created or reorganized automatically by this feature.
