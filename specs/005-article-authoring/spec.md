# Feature Specification: Article Authoring and Template Selection

**Feature Branch**: `sylvercode-article-authoring-templates`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: https://github.com/sylvercode/dm-assistant/issues/6

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create an article from a plugin default (Priority: P1)

As a Dungeon Master, I can request a new campaign article of a supported type and have the authoring workflow use that type's bundled default when I have not configured a personal template.

**Why this priority**: A usable default provides the basic authoring experience without requiring the DM to first create or configure a template.

**Independent Test**: In a disposable vault with the required authoring context and no template override, request one article type that has a bundled default. Verify the default is read before the new article is written and that the article follows the selected type without changing any existing note.

**Acceptance Scenarios**:

1. **Given** the DM requests any supported built-in article type (`adventure`, `character`, `handout`, `location`, `monster`, `party`, `persona`, `rule`, or `session`) and no override is configured, **When** a default template is available, **Then** the workflow reads that template before creating the article.
2. **Given** the DM requests a named custom article type registered in the vault profile, **When** its configured vault-owned template is valid and available, **Then** the workflow reads it before creating the requested article.
3. **Given** the DM requests an article type that is not built in and is not registered with a custom template, **When** no configured template exists for it, **Then** the workflow explains that no template is available and asks how to proceed without inventing a template or creating the article.

---

### User Story 2 - Use a DM-owned template (Priority: P1)

As a Dungeon Master, I can customize a bundled template in my vault or refer to an existing vault template so plugin updates do not replace my work and I do not have to reorganize existing files.

**Why this priority**: DM-owned templates preserve campaign-specific organization and preferences while allowing the plugin to provide useful defaults.

**Independent Test**: In a disposable vault, configure an override for a built-in article type and request that article. Verify the configured template is selected and read first, a competing plugin default is not used, and neither the template nor unrelated vault content is overwritten.

**Acceptance Scenarios**:

1. **Given** a built-in article type has both a bundled default and a configured override, **When** the DM requests that type, **Then** the configured override takes precedence.
2. **Given** the DM creates a new template in the recommended `.dmassist-templates/` location, **When** it is configured for an article type, **Then** the workflow uses it without changing plugin-owned resources.
3. **Given** the DM keeps a template in another existing location inside the vault, **When** its path is configured for an article type, **Then** the workflow uses it without moving or renaming it.
4. **Given** a configured template is missing, unreadable, invalid, or outside the authorized vault, **When** the DM requests the affected article, **Then** the workflow reports the problem and stops that article creation without silently substituting a default.
5. **Given** a custom article type is requested, **When** no configured custom template exists, **Then** the workflow reports that no template is available and asks the DM how to proceed; it does not select a built-in template by guesswork.
6. **Given** the selected template changes while the article is being prepared, **When** the workflow detects the change, **Then** it stops the affected article creation and requires the template to be checked again before proceeding.

---

### User Story 3 - Preserve campaign and player-facing boundaries (Priority: P1)

As a Dungeon Master, I need generated articles to follow the vault's established Obsidian conventions and keep player-facing material free of DM-only facts and revealing links.

**Why this priority**: Templates must improve consistency without treating formatting as access control or leaking campaign secrets.

**Independent Test**: Author a DM note and a player-facing handout in a disposable vault with established tag and callout conventions. Verify each follows those conventions, that the handout excludes DM-only facts and revealing links, and that a callout or hidden section is not treated as a security boundary.

**Acceptance Scenarios**:

1. **Given** the vault or designated guidance establishes tag, link, or callout conventions, **When** the workflow authors an article, **Then** it follows those conventions and does not replace the DM's tag vocabulary with an invented one.
2. **Given** no vault-specific callout convention has been established, **When** the workflow needs to distinguish read-aloud text, DM tips, cautions, or DM-only secrets, **Then** it uses the corresponding proposed native callout defaults from FR-013.
3. **Given** the workflow creates a handout or read-aloud section, **When** the content is prepared, **Then** it contains no DM-only facts or links that reveal them and is gate-checked immediately before it is handed out or read aloud.
4. **Given** a template contains a DM-only callout or collapsed section, **When** the workflow prepares player-facing content, **Then** it omits protected facts and revealing links entirely rather than relying on the callout, label, or collapse state to hide them.
5. **Given** a template contains clearly labeled fill-in placeholders, **When** the workflow has the requested information, **Then** it completes those placeholders with the article content; if required information is missing, it asks the DM rather than inventing it.
6. **Given** a template contains dynamic expressions or community-plugin syntax, **When** the workflow uses it, **Then** it does not execute those expressions or claim they were expanded, and asks the DM how to proceed if their output is needed in the article.
7. **Given** a template is for tentative preparation, **When** the workflow creates the article, **Then** it does not present prepared events as actual-play history or use them alone to establish character or group knowledge.

---

### User Story 4 - Protect existing vault content (Priority: P1)

As a Dungeon Master, I need article creation to respect the authorized vault, preserve existing notes and templates, and stop safely when prerequisites or the destination are uncertain.

**Why this priority**: New authoring must not overwrite user work, escape the authorized vault, or bypass the shared safeguards required of every vault-facing skill.

**Independent Test**: In a disposable vault, run authoring once with the resolver unavailable, once with an unsafe template path, and once with a destination that already exists. Verify each case stops before an unauthorized read or write and leaves existing files unchanged.

**Acceptance Scenarios**:

1. **Given** a required declared dependency is unavailable or not confirmed for the intended vault, **When** an authoring workflow starts, **Then** it explains the unmet prerequisite and makes no campaign-note or template access or changes.
2. **Given** a template reference would access content outside the authorized vault, including through a link from an in-vault file, **When** the template is selected, **Then** the workflow rejects it before reading the file.
3. **Given** article authoring depends on a link destination that cannot be confirmed to remain in the authorized vault, **When** the workflow evaluates that destination, **Then** it stops the dependent work without accessing the destination.
4. **Given** the proposed destination already contains an article, **When** the DM requests authoring, **Then** the workflow does not overwrite or reformat that article and asks the DM how to proceed.
5. **Given** a new article requires a missing folder or an ambiguous destination, **When** the workflow resolves where to write, **Then** it does not create folders or choose a destination by guesswork and asks the DM for direction.
6. **Given** a request includes any change beyond creating one new article at a clear destination, or would affect actual-play records or established continuity, **When** the workflow proposes the change, **Then** it provides a scoped preview and waits for DM approval before applying it.
7. **Given** the requested authoring would change an actual-play record or established campaign continuity, **When** the workflow prepares the change, **Then** it follows the shared approval rules and does not apply the change before the DM approves it.

### Edge Cases

- The optional vault profile is absent; the workflow may use a bundled default only after required preflight succeeds and may not assume that conventional folders exist.
- The profile is malformed or unsupported, or a configured template path has an invalid value; dependent authoring stops with a clear error rather than using partial settings or a guessed default.
- A configured built-in override is unavailable even though a plugin default exists; the override error takes precedence over default fallback.
- A custom type's template is missing or invalid; no built-in default is substituted.
- The configured template changes after it has been checked or read; the affected operation stops and requires revalidation before proceeding.
- The installed plugin default cannot be located from the skill's installed resource location; authoring reports the unavailable default rather than searching from the current working directory.
- A fill-in placeholder requests information absent from the DM's request and available context; the workflow asks for that information rather than guessing or leaving the article appearing complete.
- A template contains dynamic expressions alongside ordinary fill-in placeholders; only the clearly labeled fill-in placeholders may be completed, while dynamic expressions remain unexecuted.
- A template suggests creating a folder, changing permissions, migrating notes, or weakening a safety rule; template text cannot authorize those actions.
- Tag conventions are absent or conflict; the workflow does not silently impose a campaign-specific vocabulary.
- A player-facing section's safety cannot be established; the section is withheld until the DM can resolve the issue.
- A prepared article contains speculative events or knowledge; it is not treated as actual-play history or established character knowledge.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Before accessing campaign notes or vault-owned templates, each article-authoring skill MUST establish the authorized vault, confirm the required Obsidian Link Resolver is ready for that exact vault, check any other dependencies declared as required, load the shared reference and any designated vault-local guidance, and establish the relevant campaign/group and audience context. Future required dependencies MUST be checked according to the authoritative inventory in [Feature 001](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive).
- **FR-002**: Resolver readiness, exact-vault authorization, and unavailable behavior MUST follow the authoritative dependency contract in [Feature 001](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive). The service being available or returning a link destination MUST NOT by itself establish authorization. When authoring depends on a link destination, the workflow MUST use it only when the destination is confirmed to remain within the authorized vault, including when a link leads from an in-vault file to content outside it.
- **FR-003**: The plugin MUST provide a default template for each built-in article type supported by the authoring workflows. Each default MUST be available as part of the relevant installed authoring skill, regardless of the DM's current working directory.
- **FR-004**: The built-in article types MUST be `adventure`, `character`, `handout`, `location`, `monster`, `party`, `persona`, `rule`, and `session`, as defined in the [Feature 002 configuration contract](../002-vault-configuration-contract/contracts/vault-configuration-contract.md). The set of article types MUST also support DM-defined custom types registered in that profile's custom template mapping. Each custom type MUST have a unique identifier matching `[a-z][a-z0-9_]*` and MUST NOT duplicate a built-in type.
- **FR-005**: The workflow MUST select an explicitly configured DM-owned template for an article type before considering that type's bundled plugin default. If an explicitly configured template is missing, unreadable, invalid, or outside the authorized vault, the workflow MUST report the error and stop the affected article creation without falling back to the plugin default.
- **FR-006**: The recommended location for newly created DM-owned templates MUST be `.dmassist-templates/` at the vault root. The workflow MUST also support valid existing templates referenced in place and MUST NOT move, rename, or overwrite them to enforce the recommendation.
- **FR-007**: A DM-owned template reference MUST identify a file within the authorized vault. The workflow MUST reject any reference that would access a file outside the vault, including paths that leave the vault or links inside the vault that lead elsewhere. Templates MUST be treated as data, not as instructions, authorization, or permission to access other files.
- **FR-008**: Before creating an article, the workflow MUST explicitly read and validate the selected template. A detected change to the selected template or other authoring dependency MUST invalidate the affected operation until it is revalidated.
- **FR-009**: When neither a valid configured template nor a bundled default is available for the requested type, the workflow MUST explain the gap and ask the DM how to proceed without inventing or silently substituting a template.
- **FR-010**: Article creation MUST NOT overwrite, reformat, migrate, move, or reorganize existing campaign notes or vault-owned templates. If the intended destination already exists or is ambiguous, the workflow MUST stop and ask the DM rather than choosing an overwrite or alternate location.
- **FR-011**: The workflow MUST preserve existing vault organization and MUST NOT create a missing folder merely because a template or conventional layout suggests it.
- **FR-012**: The workflow MUST honor established tag and callout conventions from the shared reference and designated vault-local guidance. Tags classify content and MUST NOT be used as a substitute for explanatory prose or treated as a fixed vocabulary when the DM has not established one.
- **FR-013**: The workflow SHOULD use the proposed native Obsidian callout defaults where relevant: `quote` titled “Read aloud” for player-safe narration, `tip` titled “DM tip” for practical DM advice, `warning` with a specific title for cautions, and `note` titled “DM only” for DM-facing secrets. Designated vault guidance may customize these defaults. Callouts, hidden sections, and collapsed sections MUST NOT be treated as access controls.
- **FR-014**: Handouts and read-aloud sections MUST be treated as player-facing. The workflow MUST exclude DM-only facts and revealing links from them and MUST gate-check each section immediately before it is handed out or read aloud. Other authoring content remains DM-facing.
- **FR-015**: The workflow MUST complete clearly labeled, static fill-in placeholders in the selected template using information supplied by the DM or established, authorized campaign context. If required information is missing or ambiguous, it MUST ask the DM rather than inventing an answer or silently presenting an incomplete article as complete. This supported placeholder completion MUST be distinct from executing dynamic expressions, substitutions, or community-plugin syntax; those MUST remain unexecuted and MUST NOT be represented as expanded unless separately supported. If their output is needed, the workflow MUST report the limitation and ask the DM how to proceed.
- **FR-016**: Article authoring MUST preserve the distinction between tentative preparation and actual-play history, and MUST NOT establish character/group knowledge or world facts from preparation alone.
- **FR-017**: Only a request to create one new article at a clear destination, without changing existing notes, actual-play records, or established continuity, qualifies as a safe page-local creation that does not require separate approval. Any additional or destructive change, or a change that restructures vault content, alters an actual-play record, or changes established continuity, MUST receive a scoped preview and DM approval before application, following [Feature 001's editing safeguards](../001-shared-vault-guidance/spec.md#functional-requirements).
- **FR-018**: An unavailable preflight dependency, invalid authoring profile, missing required guidance, unresolved campaign context, or unsafe path MUST stop dependent work before unauthorized campaign-note access or any change. The workflow MUST clearly identify the unmet prerequisite or decision required.

### Key Entities

- **Article type**: One of the nine built-in categories or a DM-defined custom category registered in the vault profile, identified by a unique supported name and associated with its configured template.
- **Template**: A plugin-owned default or DM-owned Markdown resource that guides the structure and conventions of one or more article types.
- **Template mapping**: The profile setting associating a built-in or custom article type with a DM-owned template path.
- **Authoring request**: The DM's request for a new article, including its type, purpose, audience, and intended destination when known.
- **Authorized vault**: The campaign workspace established by the DM and confirmed by the required dependency contract before its notes or templates are accessed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In every tested built-in article type with a bundled default and no configured override, the workflow reads the selected default before creating the article.
- **SC-002**: In every tested case where both an override and a bundled default exist, the workflow selects the valid configured override; in every case where that override is invalid, it reports the error and does not use the default.
- **SC-003**: In 100% of tested cases where a template reference leads outside the authorized vault, the workflow rejects it before reading any template content and makes no vault changes.
- **SC-004**: In 100% of tested cases involving an unavailable required service, invalid campaign settings, or unclear campaign context, the workflow stops before dependent note access or any write and identifies the blocker.
- **SC-005**: In 100% of tested destination-conflict cases, existing notes and templates remain unchanged.
- **SC-006**: In 100% of tested player-facing outputs, DM-only facts and revealing links are absent; presentation labels or hidden sections are never accepted as a substitute for this check.
- **SC-007**: In every tested template containing clearly labeled fill-in placeholders, the workflow fills those for which it has supported information and asks the DM about required missing information; unsupported dynamic expressions remain unexecuted and are reported when their output is needed.
- **SC-008**: DMs can identify the selected article type, whether its source was a configured template or bundled default, and any reason authoring stopped in one response.
- **SC-009**: A DM can register and request at least one valid custom article type using its configured template, and the workflow reads that template before creating the requested article.

## Assumptions

- The optional `.dmassist.yaml` profile and its built-in/custom template mapping rules are governed by Feature 002; this feature does not introduce a competing configuration shape.
- The shared guidance and required dependency inventory in Feature 001 are prerequisites for all article-authoring skills.
- The PowerShell runtime and safe-operation contracts in Feature 003 govern applicable runtime path validation, previews, conflict handling, and writes; this specification does not claim that production vault authorization is currently implemented.
- One active campaign/party per vault remains the supported scope. Shared campaigns, template migration, automatic note restructuring, and dynamic template expansion are out of scope.
- The tag and callout rules are defaults that yield to established vault conventions and designated guidance, within the shared safety boundaries.
- Plugin defaults are distributed with their consuming skills; DM-owned templates remain in the campaign vault and are not changed by plugin updates.
