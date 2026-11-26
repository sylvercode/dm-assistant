# Feature Specification: Read-Only Vault Orientation and Inventory

**Feature Branch**: `006-vault-orientation-inventory`

**Created**: 2026-11-01

**Status**: Draft

**Input**: GitHub issue [#8](https://github.com/sylvercode/dm-assistant/issues/8), “Implement read-only vault orientation and inventory”

## Clarifications

### Session 2026-11-01

- Q: Which files and content may the read-only inventory inspect to infer campaign mappings? → A: Inspect folder and file names plus Markdown note contents, including frontmatter; skip dot-prefixed files and folders, attachments, and non-Markdown file contents.
- Q: How should the workflow handle the root profile and additional local guidance? → A: Load `.dmassist.yaml` and its designated guidance according to Feature 002; load other Markdown guidance only when the DM selects it for this request.
- Q: What should make additional DM-selected Markdown guidance invalid or incomplete enough to block note access? → A: Require readable Markdown; block only if task-essential guidance is missing or unusable.
- Q: How should the inventory identify hidden or system files and folders that it must skip? → A: Skip only dot-prefixed entries.
- Q: Should guidance designated by `.dmassist.yaml` count as selected, with request-level selection required only for additional guidance? → A: Yes; preserve Feature 002 guidance designation behavior and require request-level selection only for additional guidance.
- Q: When no local guidance is designated, may inventory read Markdown note contents to infer mappings? → A: No; enumerate folder and file names only and require designated guidance before reading note contents for mappings.
- Q: May the DM explicitly select a dot-prefixed Markdown file as additional guidance? → A: Yes; load it only as explicitly selected guidance and never discover it by scanning.

### Session 2026-11-08: Planning refinement

- Q: Should attachment filenames appear as inventory items? → A: No; omit them.
- Q: How should attachments be distinguished from other non-Markdown files? → A: Omit all non-Markdown filenames from inventory items rather than relying on an incomplete extension-based attachment list.
- Q: How should a skipped explicitly selected non-Markdown guidance file be identified? → A: By its position in the request, without repeating its filename.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Safely orient to a campaign vault (Priority: P1)

As a Dungeon Master, I need the assistant to establish the intended vault and load the applicable guidance and required dependencies before inspecting campaign notes, so that the inventory is limited to the authorized campaign and does not bypass safeguards.

**Why this priority**: An inventory is useful only when it is scoped to the correct vault and follows the same access boundaries as other vault-facing work.

**Independent Test**: Start an orientation request with a disposable vault and verify that the assistant establishes the vault, checks prerequisites, loads guidance, and does not inspect campaign notes until those steps succeed.

**Acceptance Scenarios**:

1. **Given** a vault has been identified and all declared required dependencies are available and authorized for it, **When** the DM requests orientation, **Then** the assistant loads the shared reference and any designated local profile before inspecting campaign notes.
2. **Given** the vault, a required dependency, or required guidance cannot be established, **When** orientation begins, **Then** the assistant explains the blocker and stops before reading campaign notes.
3. **Given** a required link-resolution service is available but exact-vault authorization cannot be confirmed, **When** orientation is requested, **Then** the assistant stops before campaign-note access or link resolution. Resolver symlink-target qualification is delegated to the vault owner; PowerShell access still requires its own vault containment checks.
4. **Given** task-essential additional Markdown guidance has been selected for the requested task but is unavailable, unreadable, or has no usable content, **When** orientation begins, **Then** the assistant explains the guidance problem and does not read campaign notes that depend on it.
5. **Given** selected additional guidance is readable and has usable content but says nothing about some locations in the requested task's scope, **When** orientation begins, **Then** the assistant proceeds, treats those locations as unguided, and reports their mappings as provisional rather than blocking.
6. **Given** the DM selects a guidance file, without marking it optional, whose only content is frontmatter, whitespace, or headings without text, **When** orientation begins, **Then** the assistant reports that the selected guidance has no usable content and stops before reading campaign notes that depend on it.
7. **Given** the DM marks a selected guidance file as optional and that file is unavailable, unreadable, or has no usable content, **When** orientation begins, **Then** the assistant reports the problem, skips that guidance, and continues without blocking.

---

### User Story 2 - Understand an existing vault layout (Priority: P1)

As a Dungeon Master, I need a read-only inventory to identify likely campaign sections and meaningful uncertainty in my existing organization, so that I can orient the assistant without reorganizing my vault.

**Why this priority**: Vaults differ in structure, and a useful orientation must describe what is present rather than impose a prescribed layout.

**Independent Test**: Use disposable vaults with representative layouts and verify the inventory accurately reports likely mappings, avoids unsupported classifications, and leaves every file unchanged.

**Acceptance Scenarios**:

1. **Given** an adventure is represented by a root-level Markdown file and there is no Adventures folder, **When** the inventory runs, **Then** it may identify the file as a possible adventure without treating every root-level note as an adventure.
2. **Given** adventures are represented by folders, individual files, or both, **When** the inventory runs, **Then** it reports the observed structure without requiring a migration or a particular layout.
3. **Given** the vault uses renamed folders or additional Lore sections, **When** the inventory runs, **Then** it reports candidate mappings and preserves the existing names and organization.
4. **Given** more than one plausible mapping would change which notes the requested task reads, which mapping a task result is based on, or what a proposed profile would record, **When** the inventory encounters that ambiguity, **Then** it describes the alternatives and asks the DM to decide before relying on a mapping.
5. **Given** no additional Markdown guidance is selected for the current request, **When** the DM requests straightforward read-only orientation, **Then** the assistant can report provisional candidate mappings based on observed folder and Markdown file names, but does not treat any file as guidance because of its name and does not require the DM to create a file first.
6. **Given** an existing profile conflicts with the organization observed during inventory, **When** the conflict affects the requested task, **Then** the assistant identifies both interpretations and asks the DM before relying on either.
7. **Given** applicable configured or request-selected local guidance has been loaded and a vault contains Markdown notes, dot-prefixed files and folders, attachments, and other non-Markdown files, **When** the inventory runs, **Then** it may inspect eligible folder and Markdown file names and Markdown note contents, including frontmatter, but does not report dot-prefixed inventory entries or non-Markdown filenames, except the fixed profile identity when needed, or read attachment or other non-Markdown contents.
8. **Given** a vault contains dot-prefixed entries and non-dot-prefixed Markdown notes marked hidden or system by the operating system, **When** the inventory runs, **Then** it skips the dot-prefixed entries and does not exclude the Markdown notes solely because of their operating-system attributes.
9. **Given** no configured or request-selected local guidance is available, **When** the inventory runs, **Then** it reports candidate mappings from eligible folder and Markdown file names only and does not read Markdown note contents.
10. **Given** the DM explicitly selects a dot-prefixed Markdown file as additional guidance, **When** the guidance preflight runs, **Then** it may load that file as guidance but does not discover it by enumerating inventory entries.
11. **Given** a folder has two plausible roles but the DM requested only an orientation inventory, **When** the inventory runs, **Then** it reports both alternatives as unresolved and completes without pausing, because no task result depends on choosing one.

---

### User Story 3 - Review proposed mappings without losing control (Priority: P2)

As a Dungeon Master, I need proposed mappings or profile content presented for my review, so that I can confirm how the assistant should interpret my vault without unsolicited edits.

**Why this priority**: A proposed profile can make future orientation more consistent, but only the DM can confirm that inferred meanings match campaign intent.

**Independent Test**: Request and decline a profile proposal from a disposable vault, then verify that the proposal is reviewable and neither inventory nor proposal generation changes any file. Applying a profile change is outside this feature and requires a separately scoped future operation.

**Acceptance Scenarios**:

1. **Given** the inventory identifies candidate mappings, **When** the DM asks for a profile proposal, **Then** the assistant presents the proposed content and the evidence or uncertainty behind its mappings without writing it.
2. **Given** the DM has not explicitly approved a profile change, **When** orientation or proposal generation completes, **Then** the vault remains unchanged.
3. **Given** the DM explicitly approves a profile change, **When** this inventory feature completes, **Then** it still makes no change; any later application is performed only by a separately scoped, profile-specific operation that previews and applies the exact approved content without reorganizing folders or altering campaign notes.
4. **Given** a candidate mapping has an unresolved task-relevant ambiguity, **When** the DM asks for a profile proposal, **Then** the proposal presents the alternatives as unresolved and does not record either one as a confirmed mapping.

### Edge Cases

- The intended vault location is missing, unclear, or different from the plugin installation directory.
- A declared required dependency is unavailable, reports an incompatible or unconfirmed state, or cannot establish authorization for the exact vault.
- The optional root profile is missing or invalid; selected additional Markdown guidance is missing, unreadable, incomplete for the requested task, or conflicts with observed organization.
- A mapping is plausible based on a folder name but is contradicted by its contents or by another plausible interpretation.
- An adventure is stored as a single file, at the vault root, or in one or more folders; the vault may also contain unrelated root-level notes.
- A vault contains renamed sections, additional Lore subsections, or no conventional section folders.
- Inspection is requested for a task whose outcome depends on an unresolved mapping, versus an orientation-only request where the same ambiguity is only informational.
- Selected guidance contains only frontmatter or headings, is marked optional by the DM, or is usable but silent about part of the task scope.
- A proposed profile is declined or left unapproved.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The orientation workflow MUST obtain the target vault from the user's workspace or explicit input and MUST NOT treat the plugin installation directory as the campaign vault.
- **FR-002**: Before accessing campaign notes, the workflow MUST establish the target vault, verify every currently declared required dependency and its applicable authorization, load the plugin-owned shared reference, and follow Feature 002 for loading the optional root `.dmassist.yaml` profile and its designated guidance. It MUST load additional vault-local Markdown guidance only when the DM explicitly names or selects it for the current request. It MUST stop and identify the unmet prerequisite if any required step fails.
- **FR-003**: The workflow MUST follow the required dependency-readiness and vault-authorization rules established by Feature 001. It MUST NOT treat service availability or successful link resolution as proof of authorization.
- **FR-004**: If the link-resolution service is needed, its authorized vault MUST exactly match the target vault, and its supported behavior MUST prevent link resolution from reaching content outside that vault. If either condition cannot be confirmed, the workflow MUST stop before using the service.
- **FR-005**: The orientation inventory MUST be read-only: it MUST NOT create, modify, move, rename, or delete campaign files, folders, or profile content.
- **FR-006**: The inventory MUST report observed organization and candidate section mappings without requiring the vault to follow a prescribed folder layout or be migrated.
- **FR-007**: The inventory MUST support identifying adventures represented by root-level files, individual files within sections, and folders or arcs, while not classifying every root-level note as an adventure.
- **FR-008**: The inventory MUST allow renamed sections and additional Lore sections to be reported as candidate mappings without changing their names or locations.
- **FR-009**: When no configured or request-selected local guidance is available, the workflow MUST support read-only discovery using eligible folder and Markdown file names only; it MUST NOT read campaign-note contents to infer mappings. Names MAY support provisional candidate mappings, but a file MUST NOT be treated as guidance, and no guidance content may be assumed, because of its name. The workflow MUST report uncertain mappings as provisional and MUST pause for DM direction before relying on a task-relevant ambiguity (FR-015). Feature 002 continues to govern the optional root profile and its designated guidance.
- **FR-010**: If task-essential additional Markdown guidance explicitly selected by the DM for the requested task is unavailable, unreadable as Markdown, or has no usable content (FR-016), the workflow MUST identify the issue and stop before reading campaign notes that depend on it. Selected guidance the DM marked optional MUST instead be reported and skipped without blocking (FR-016). It MUST NOT silently substitute guessed guidance or mappings. A fixed schema is not required. Usable guidance that is silent about part of the task scope does not block the task; those locations MUST be treated as unguided, and their mappings MUST be reported as provisional. The optional root profile and its designated guidance MUST follow Feature 002 validation and failure behavior.
- **FR-011**: The workflow MUST offer proposed mappings or profile content for DM review and MUST distinguish proposals from confirmed mappings. For each proposed mapping, it MUST indicate whether the mapping is observed (directly stated by loaded guidance or the profile) or inferred (derived from names or note contents).
- **FR-012**: Feature 006 MUST NOT write or update a profile; neither inventory nor proposal generation writes anything. Any profile write is outside this feature and requires a separately scoped, profile-specific operation that applies only the exact content the DM explicitly approved after reviewing it, and MUST NOT reorganize the vault or alter campaign notes.
- **FR-013**: If the profile conflicts with the organization observed during inventory and the conflict is task-relevant (FR-015), the workflow MUST identify both interpretations and ask the DM before relying on either interpretation. A conflict that is not task-relevant MUST be reported without pausing.
- **FR-014**: The inventory MUST inspect eligible folder and Markdown file names to identify candidate mappings. It MAY inspect Markdown note contents, including frontmatter, only after applicable configured or request-selected local guidance has been loaded. It MUST NOT enumerate or inspect dot-prefixed entries as inventory items, report any non-Markdown filename (including attachments) in the inventory report, or read attachment or other non-Markdown file contents. The fixed `.dmassist.yaml` identity may be reported for profile preflight or a proposal target. A dot-prefixed Markdown file explicitly selected as additional guidance may be loaded as guidance, but MUST NOT be discovered by inventory scanning. The inventory MUST NOT exclude an otherwise eligible non-dot-prefixed entry solely because the operating system marks it hidden or system.
- **FR-015**: An ambiguity or profile conflict is **task-relevant** when choosing between its alternatives would change at least one of: (a) which notes or locations the requested task reads or includes in scope, (b) the mapping on which a task result is based, or (c) the content of a proposed profile. Any other ambiguity is **informational**: it MUST be reported as unresolved, but it MUST NOT pause the workflow. For an orientation-only request, reporting the alternatives is the result, so its ambiguities are informational. For a profile proposal, every ambiguity that affects proposed content is task-relevant and MUST be presented as unresolved rather than resolved by the assistant.
- **FR-016**: DM-selected additional guidance is **task-essential** for the current request unless the DM marks it as optional. It has **usable content** when it is readable Markdown containing at least one non-empty line of body text outside frontmatter and headings. Selected task-essential guidance that is missing, unreadable, or lacks usable content MUST block access to campaign notes that depend on it. Selected optional guidance with the same problem MUST be reported, then skipped without blocking.
- **FR-017**: A candidate mapping MUST be supported by an explicit profile or loaded-guidance assignment; an exact, case-insensitive complete path component from the conventional section vocabulary `Adventures`, `Lore`, `Monsters Stats`, `Rules`, `Sessions`, or `Handouts`, or (under `Lore`) `Player`, `Locations`, `Cosmology`, or `Persona`; an exact, case-insensitive whole-word basename token `Adventure`, `Adventures`, `Arc`, or `Arcs`; or permitted note-content evidence that explicitly labels a role in frontmatter or self-identifies the role in the body. Explicit profile or guidance assignments are `observed`; conventional names, entry-name tokens, and note-content evidence are `inferred`. General thematic resemblance alone MUST NOT produce a candidate mapping. A name-derived mapping MUST remain provisional and uncertain; where evidence supports multiple plausible roles, the workflow MUST report the alternatives rather than select one. Entries without qualifying role evidence remain observed entries without a candidate mapping.

### Key Entities

- **Target vault**: The campaign workspace explicitly established for the current orientation request.
- **Vault profile**: The optional root `.dmassist.yaml` configuration, validated and loaded under Feature 002; it may record campaign context and mappings for existing folders or notes.
- **Additional local guidance**: Markdown guidance beyond the optional root profile and its Feature 002-designated guidance, loaded only when the DM explicitly selects it for the current request.
- **Candidate mapping**: A suggested connection between an observed vault location or content pattern and a campaign section or role, not yet confirmed by the DM. Each candidate is either observed (stated by loaded guidance or the profile) or inferred (derived from names or note contents).
- **Task-relevant ambiguity**: An unresolved choice between mappings or interpretations that would change the task's scope, result basis, or proposed profile content; it requires DM direction before reliance. Other ambiguities are informational and reported only.
- **Orientation inventory**: A read-only report of the vault's observed organization, suggested mappings, and relevant uncertainties.
- **Link-resolution service**: The separately installed service that finds the destinations of links in Obsidian notes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In prerequisite-failure checks—unclear target vault, unavailable required dependency, unconfirmed vault authorization, unavailable shared reference, an invalid root profile when required by Feature 002, or selected task-essential additional guidance that is unavailable, unreadable, or has no usable content—the workflow identifies the blocker and stops before reading any campaign note that depends on it. In the corresponding non-blocking checks—selected optional guidance with no usable content, and usable guidance that is silent about part of the task scope—the workflow reports the condition and continues.
- **SC-002**: Across the six fixtures and expected entries/candidate mappings in `quickstart.md`—root-level adventures with an unrelated root note, single-file adventures, folder-based arcs, a mix of files and folders, renamed sections, and additional Lore sections—the inventory matches each fixture's expected observations and evidence-based candidate mappings, and never labels the unrelated root note or an entry without qualifying role evidence as an adventure.
- **SC-003**: In every read-only inventory check, the count of campaign files, folders, and profile content created, modified, moved, renamed, or deleted is zero.
- **SC-004**: In all three task-relevant ambiguity checks—a renamed section with multiple plausible roles that changes the notes a task reads, a profile that conflicts with observed organization for the requested task, and multiple plausible mappings affecting a proposed profile—the workflow states the alternatives and does not rely on one before DM direction. In an informational-ambiguity check during an orientation-only request, the workflow reports the alternatives and completes without pausing.
- **SC-005**: In a walkthrough, five DMs each review the same proposed profile containing at least six mappings, including at least two observed and two inferred mappings. At least four of the five DMs correctly classify every mapping as observed or inferred, and all five can decline the proposal without any vault changes.
- **SC-006**: In inventory checks containing dot-prefixed entries, non-dot-prefixed files marked hidden or system by the operating system, attachments, and other non-Markdown files, the workflow skips dot-prefixed inventory entries, reports no non-Markdown filenames other than the fixed profile identity, does not exclude otherwise eligible non-dot-prefixed entries solely because of operating-system attributes, and does not inspect attachment or other non-Markdown file contents. When no local guidance is designated, it reads no campaign-note contents; when designated guidance is loaded, it may inspect Markdown contents, including frontmatter.

## Assumptions

- The Obsidian Link Resolver, a separately installed service for finding destinations of Obsidian note links, and any other dependencies declared as required by Feature 001 remain prerequisites for vault-facing note access; orientation does not weaken those requirements.
- A missing `.dmassist.yaml` profile is not itself a failure when the requested orientation can be completed through read-only, name-based discovery, as specified by Feature 002. Additional Markdown guidance is not inferred from filenames and is loaded only when selected for the current request; an explicitly selected dot-prefixed guidance file is allowed but is not an inventory entry. Without configured or selected local guidance, discovery does not read campaign-note contents.
- A profile proposal is separate from the inventory. Approval authorizes only the specific reviewed profile change, not restructuring or unrelated campaign edits.
- The initial orientation targets one explicitly established campaign vault; interpreting multiple campaigns within a shared vault is outside this feature unless separately specified.
- The inventory reports candidate mappings and material ambiguities; it does not claim that a folder or note role is confirmed solely from its name.
- DM-selected additional guidance is treated as task-essential by default because the DM chose it for this request; the DM can mark a selection optional. The usable-content threshold is intentionally minimal so that free-form guidance is accepted without a schema.
