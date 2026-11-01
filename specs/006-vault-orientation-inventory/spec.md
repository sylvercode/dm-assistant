# Feature Specification: Read-Only Vault Orientation and Inventory

**Feature Branch**: `006-vault-orientation-inventory`

**Created**: 2026-11-01

**Status**: Draft

**Input**: GitHub issue [#8](https://github.com/sylvercode/dm-assistant/issues/8), “Implement read-only vault orientation and inventory”

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Safely orient to a campaign vault (Priority: P1)

As a Dungeon Master, I need the assistant to establish the intended vault and load the applicable guidance and required dependencies before inspecting campaign notes, so that the inventory is limited to the authorized campaign and does not bypass safeguards.

**Why this priority**: An inventory is useful only when it is scoped to the correct vault and follows the same access boundaries as other vault-facing work.

**Independent Test**: Start an orientation request with a disposable vault and verify that the assistant establishes the vault, checks prerequisites, loads guidance, and does not inspect campaign notes until those steps succeed.

**Acceptance Scenarios**:

1. **Given** a vault has been identified and all declared required dependencies are available and authorized for it, **When** the DM requests orientation, **Then** the assistant loads the shared reference and any designated local profile before inspecting campaign notes.
2. **Given** the vault, a required dependency, or required guidance cannot be established, **When** orientation begins, **Then** the assistant explains the blocker and stops before reading campaign notes.
3. **Given** a required link-resolution service is available but its authorization or required target-containment safeguards cannot be confirmed, **When** orientation is requested, **Then** the assistant stops before campaign-note access or link resolution.
4. **Given** a profile has been designated for the requested task but is unavailable or invalid, **When** orientation begins, **Then** the assistant explains the profile problem and does not read campaign notes that depend on it.

---

### User Story 2 - Understand an existing vault layout (Priority: P1)

As a Dungeon Master, I need a read-only inventory to identify likely campaign sections and meaningful uncertainty in my existing organization, so that I can orient the assistant without reorganizing my vault.

**Why this priority**: Vaults differ in structure, and a useful orientation must describe what is present rather than impose a prescribed layout.

**Independent Test**: Use disposable vaults with representative layouts and verify the inventory accurately reports likely mappings, avoids unsupported classifications, and leaves every file unchanged.

**Acceptance Scenarios**:

1. **Given** an adventure is represented by a root-level Markdown file and there is no Adventures folder, **When** the inventory runs, **Then** it may identify the file as a possible adventure without treating every root-level note as an adventure.
2. **Given** adventures are represented by folders, individual files, or both, **When** the inventory runs, **Then** it reports the observed structure without requiring a migration or a particular layout.
3. **Given** the vault uses renamed folders or additional Lore sections, **When** the inventory runs, **Then** it reports candidate mappings and preserves the existing names and organization.
4. **Given** more than one plausible mapping could affect the requested task, **When** the inventory encounters that ambiguity, **Then** it describes the alternatives and asks the DM to decide before relying on a mapping.
5. **Given** a profile is absent, **When** the DM requests straightforward read-only orientation, **Then** the assistant can report observable candidate mappings without requiring the DM to create a profile first.
6. **Given** an existing profile conflicts with the organization observed during inventory, **When** the conflict affects the requested task, **Then** the assistant identifies both interpretations and asks the DM before relying on either.

---

### User Story 3 - Review proposed mappings without losing control (Priority: P2)

As a Dungeon Master, I need proposed mappings or profile content presented for my review, so that I can confirm how the assistant should interpret my vault without unsolicited edits.

**Why this priority**: A proposed profile can make future orientation more consistent, but only the DM can confirm that inferred meanings match campaign intent.

**Independent Test**: Request a profile proposal from a vault without a profile, then verify that the proposal is reviewable and no profile or campaign file is written unless the DM separately approves that change.

**Acceptance Scenarios**:

1. **Given** the inventory identifies candidate mappings, **When** the DM asks for a profile proposal, **Then** the assistant presents the proposed content and the evidence or uncertainty behind its mappings without writing it.
2. **Given** the DM has not explicitly approved a profile change, **When** orientation or proposal generation completes, **Then** the vault remains unchanged.
3. **Given** the DM explicitly approves a profile change, **When** that separate change is carried out, **Then** only the approved profile content is written and no vault folders or campaign notes are reorganized or altered.

### Edge Cases

- The intended vault location is missing, unclear, or different from the plugin installation directory.
- A declared required dependency is unavailable, reports an incompatible or unconfirmed state, or cannot establish authorization for the exact vault.
- A designated profile is missing, unreadable, invalid, incomplete, or conflicts with observed organization.
- A mapping is plausible based on a folder name but is contradicted by its contents or by another plausible interpretation.
- An adventure is stored as a single file, at the vault root, or in one or more folders; the vault may also contain unrelated root-level notes.
- A vault contains renamed sections, additional Lore subsections, or no conventional section folders.
- Inspection is requested for a task whose outcome depends on an unresolved mapping.
- A proposed profile is declined or left unapproved.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The orientation workflow MUST obtain the target vault from the user's workspace or explicit input and MUST NOT treat the plugin installation directory as the campaign vault.
- **FR-002**: Before accessing campaign notes, the workflow MUST establish the target vault, verify every currently declared required dependency and its applicable authorization, load the plugin-owned shared reference, and load any designated vault-local profile. It MUST stop and identify the unmet prerequisite if any required step fails.
- **FR-003**: The workflow MUST follow the required dependency-readiness and vault-authorization rules established by Feature 001. It MUST NOT treat service availability or successful link resolution as proof of authorization.
- **FR-004**: If the link-resolution service is needed, its authorized vault MUST exactly match the target vault, and its supported behavior MUST prevent link resolution from reaching content outside that vault. If either condition cannot be confirmed, the workflow MUST stop before using the service.
- **FR-005**: The orientation inventory MUST be read-only: it MUST NOT create, modify, move, rename, or delete campaign files, folders, or profile content.
- **FR-006**: The inventory MUST report observed organization and candidate section mappings without requiring the vault to follow a prescribed folder layout or be migrated.
- **FR-007**: The inventory MUST support identifying adventures represented by root-level files, individual files within sections, and folders or arcs, while not classifying every root-level note as an adventure.
- **FR-008**: The inventory MUST allow renamed sections and additional Lore sections to be reported as candidate mappings without changing their names or locations.
- **FR-009**: When no profile is designated, the workflow MUST support straightforward read-only discovery. It MUST report uncertain mappings as provisional and MUST pause before relying on an ambiguity that affects the task.
- **FR-010**: If a profile designated for the requested task is unavailable, unreadable, invalid, or incomplete, the workflow MUST identify the issue and stop before reading campaign notes that depend on it. It MUST NOT silently substitute a guessed profile or mapping.
- **FR-011**: The workflow MUST offer proposed mappings or profile content for DM review and MUST distinguish proposals from confirmed mappings.
- **FR-012**: The workflow MUST NOT write or update a profile unless the DM explicitly approves that specific change. Any approved profile write MUST be limited to the reviewed content and MUST NOT reorganize the vault or alter campaign notes.
- **FR-013**: If the profile conflicts with the organization observed during inventory, the workflow MUST identify both interpretations and ask the DM before relying on either interpretation for the requested task.

### Key Entities

- **Target vault**: The campaign workspace explicitly established for the current orientation request.
- **Vault profile**: Optional DM-designated guidance that records campaign context or says which existing folders or notes serve particular purposes.
- **Candidate mapping**: A suggested connection between an observed vault location or content pattern and a campaign section or role, not yet confirmed by the DM.
- **Orientation inventory**: A read-only report of the vault's observed organization, suggested mappings, and relevant uncertainties.
- **Link-resolution service**: The separately installed service that finds the destinations of links in Obsidian notes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In all five prerequisite-failure checks—unclear target vault, unavailable required dependency, unconfirmed vault authorization, unavailable shared reference, and a designated profile that is missing, unreadable, invalid, or incomplete—the workflow identifies the blocker and stops before reading any campaign note that depends on it.
- **SC-002**: Across six sample layouts—root-level adventures with an unrelated root note, single-file adventures, folder-based arcs, a mix of files and folders, renamed sections, and additional Lore sections—the inventory identifies the observed organization in all six and never labels the unrelated root note as an adventure.
- **SC-003**: In every read-only inventory check, the count of campaign files, folders, and profile content created, modified, moved, renamed, or deleted is zero.
- **SC-004**: In all three ambiguity checks—a renamed section with multiple plausible roles, a profile that conflicts with observed organization, and multiple plausible mappings for the requested task—the workflow states the alternatives and does not rely on one before DM direction.
- **SC-005**: In an informal walkthrough with five DMs, at least four correctly identify which parts of a proposed profile are observed and which are inferred; all five can decline the proposal without any vault changes.

## Assumptions

- The Obsidian Link Resolver, a separately installed service for finding destinations of Obsidian note links, and any other dependencies declared as required by Feature 001 remain prerequisites for vault-facing note access; orientation does not weaken those requirements.
- A missing profile is not itself a failure when the requested orientation can be completed through straightforward, read-only discovery.
- A profile proposal is separate from the inventory. Approval authorizes only the specific reviewed profile change, not restructuring or unrelated campaign edits.
- The initial orientation targets one explicitly established campaign vault; interpreting multiple campaigns within a shared vault is outside this feature unless separately specified.
- The inventory reports candidate mappings and material ambiguities; it does not claim that a folder or note role is confirmed solely from its name.
