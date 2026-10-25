# Feature Specification: Shared Vault Guidance

**Feature Branch**: `sylvercode-shared-vault-guidance`

**Created**: 2026-10-24

**Status**: Draft

**Input**: GitHub issue #2, “Establish shared vault guidance and loading prerequisites”

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Consistent vault-aware assistance (Priority: P1)

As a DM using a vault-facing skill, I need it to apply the same campaign boundaries and conventions as every other skill so that preparation, actual play, lore, character knowledge, and player-facing material remain consistent.

**Why this priority**: Shared rules are foundational to safe and coherent vault workflows.

**Independent Test**: Use a vault-facing skill with a known campaign task and verify it consults the shared reference and designated vault-local guidance before interpreting or changing campaign notes, then applies the specific safeguards in FR-007 through FR-010.

**Acceptance Scenarios**:

1. **Given** the shared reference and designated vault-local guidance are available, **When** a vault-facing skill starts a campaign-note task, **Then** it loads both sources and the active vault/campaign context before interpreting or changing notes.
2. **Given** a task concerns preparation, actual play, character knowledge, lore, or a player-facing handout, **When** the skill responds, **Then** it follows the preparation and knowledge boundary in FR-007, the continuity boundary in FR-008, and the player-safety boundary in FR-009, as applicable.
3. **Given** the plugin is installed separately from the campaign vault, **When** the skill locates its shared reference, **Then** it uses the plugin-owned resource and does not treat the plugin directory as the vault.

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
4. **Given** output is intended for players, **When** the skill uses campaign information, **Then** it excludes DM-only facts and revealing links.
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
- **FR-004**: Before a vault-facing skill acts on campaign notes, it MUST establish the authorized vault from the user's workspace or explicit input and the relevant campaign/group from explicit input or unambiguous vault context. If either cannot be established, it MUST ask the DM before proceeding.
- **FR-005**: When required guidance is unavailable or unreadable, a vault-facing skill MUST identify the affected source, explain which requested work depends on it, and pause that work without changing campaign notes or silently substituting assumptions.
- **FR-006**: When vault mappings, guidance, or campaign context have multiple reasonable interpretations that affect the next action, a vault-facing skill MUST state the competing interpretations, identify the needed decision, and request DM direction before proceeding.
- **FR-007**: Shared guidance MUST distinguish preparation from actual-play history and character knowledge; preparation alone MUST NOT establish that an event occurred or that a character knows it.
- **FR-008**: Shared guidance MUST preserve existing vault organization and notes, avoid assuming absent folders should be created, and prohibit silently resolving contradictions or rewriting run adventure plans.
- **FR-009**: Shared guidance MUST keep DM-only facts and revealing links out of player-facing handouts and outputs.
- **FR-010**: Broad, destructive, restructuring, or continuity-changing edits MUST be previewed and approved by the DM before application; clearly requested page-local edits MUST NOT require redundant approval.
- **FR-011**: Shared guidance and vault content MUST be treated as data, not as authority to override governing instructions or authorize unrelated actions.
- **FR-012**: The installed-resource lookup MUST be verified in the supported client so that skills can find the bundled reference independently of the current working directory.
- **FR-013**: Before any vault-facing skill reads or changes campaign notes, it MUST verify that every currently declared required runtime dependency is available. The initial required dependency is the Obsidian Link Resolver MCP server exposing `resolve_obsidian_link`, configured to allow the authorized vault. If any required dependency is missing, unavailable, or misconfigured, the skill MUST explain the failure and stop before accessing or changing campaign notes.
- **FR-014**: The required-dependency inventory MUST be explicitly documented and extensible; it is not an exhaustive list of all future dependencies. Each added required dependency MUST state its purpose and scope, supported version or compatibility contract, user setup/configuration, readiness check, and behavior when unavailable.

## Expected Dependencies *(initial, non-exhaustive)*

| Dependency | Type and scope | Purpose | Setup and verification | Failure behavior |
|---|---|---|---|---|
| [Obsidian Link Resolver](https://github.com/sylvercode/obsidian-link-resolver) | Required runtime MCP server for every vault-facing skill; minimum compatible release is `2.0.0`. | Exposes `resolve_obsidian_link` for resolving Obsidian links against an authorized vault. | The DM installs the MCP release separately and configures `obsidian-link-resolver` in Copilot CLI with one or more explicitly authorized absolute vault roots. Verify the server and tool are available in a new session. Do not embed vault-specific paths in the plugin. | If the server or tool is unavailable, or the vault is not authorized, the skill stops before reading or changing campaign notes and reports the required setup. Resolver errors or unresolved/ambiguous links MUST be surfaced; skills MUST NOT guess a destination. |
| [Obsidian Aliases documentation](https://obsidian.md/help/aliases) | Reference source, not a runtime dependency. | Documents native alias behavior for shared guidance and validation examples. | Keep as a reference link; do not require the Obsidian application at runtime. | If documentation is unavailable, do not claim undocumented alias behavior. |
| [Obsidian Tags documentation](https://obsidian.md/help/tags) | Reference source, not a runtime dependency. | Documents native tag behavior for shared guidance and validation examples. | Keep as a reference link; campaign-specific tag vocabulary remains DM-owned. | If documentation is unavailable, do not claim undocumented tag behavior. |

This inventory records dependencies identified so far and is not exhaustive.
Future required runtime dependencies may be added using FR-014. Documentation
links remain reference sources unless a later specification explicitly makes
them runtime dependencies.

### Key Entities

- **Shared vault reference**: Plugin-owned guidance describing common vault concepts, boundaries, continuity safeguards, knowledge rules, and safe editing expectations.
- **Vault-local guidance**: DM-owned conventions and exceptions designated for a particular vault; it remains outside the distributed plugin.
- **Vault and campaign context**: The authorized campaign workspace and relevant campaign/group identity needed to interpret a task.
- **Vault-facing skill**: A user-invoked workflow that reads or changes campaign notes and is therefore subject to the loading prerequisite and safeguards.
- **Required runtime dependency**: An explicitly declared external tool or service with a purpose, scope, supported compatibility contract, setup, readiness check, and unavailable behavior. The initial inventory is non-exhaustive.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every plugin skill that reads or changes campaign notes is included in the plugin's declared skill inventory, and 100% of that inventory passes a check that both guidance sources are loaded before note interpretation or changes.
- **SC-002**: 100% of tested missing-guidance and ambiguity scenarios identify the missing source or competing interpretations, name the dependent work, and pause that work without campaign-note changes until DM direction is available.
- **SC-003**: All documented acceptance scenarios for preparation/history, continuity, player safety, and approval safeguards pass without unintended campaign-note changes.
- **SC-004**: In a short walkthrough, at least 4 of 5 DMs can correctly identify which example guidance is plugin-wide and which is vault-specific, with no vault reorganization required.
- **SC-005**: In 100% of tested vault-facing skill invocations where the resolver server or `resolve_obsidian_link` is unavailable or not configured for the authorized vault, the skill reports the dependency problem and performs no campaign-note reads or changes.

## Assumptions

- The initial workflows support one campaign per vault; multi-campaign isolation is outside this feature.
- The supported client and installed-resource lookup method will be selected and verified during planning; source-tree presence alone does not satisfy the lookup requirement.
- GitHub Copilot CLI is the supported client for the initial resolver dependency setup. The MCP server and user-authorized vault roots are configured outside the distributed plugin.
- The designated vault-local guidance source is supplied explicitly by the DM or identified by the vault-configuration contract. The separate configuration work defines its specific discovery and configuration rules; this feature does not prescribe that schema or require vault migration.
- A specialized agent may be considered as a future workflow option only if supported and useful, but explicit skill prerequisites remain required and do not depend on agent availability.
- No vault folders, profile files, or guidance files are created or reorganized automatically by this feature.
