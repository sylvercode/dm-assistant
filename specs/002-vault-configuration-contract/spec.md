# Feature Specification: Vault Configuration Contract

**Scope boundary**: This feature defines the `.dmassist.yaml` schema and the
observable outcomes for valid, invalid, and absent configuration, including a
machine-readable JSON Schema for profile structure and value constraints. The
schema does not replace YAML parsing or runtime checks that depend on the
authorized vault and filesystem. This feature does not select or provision a
YAML parser, define a PowerShell runtime, or implement a configuration reader.
Parser selection, dependency provisioning, and reader integration belong to
Issue #4, “Establish the PowerShell runtime and safe operation contracts.”

**Feature Branch**: `sylvercode-vault-configuration-contract`

**Created**: 2026-10-25

**Status**: Draft

**Input**: User description: "Use issue #3, Define the vault configuration contract, as input; use feature number 002."

## Clarifications

### Session 2026-10-25

- Q: When a configured section folder does not exist, should the entire profile fail validation or only operations that need that folder stop? → A: Reject the entire profile until every explicitly configured section folder exists.
- Q: Should different section mappings be allowed to point to the same folder or to folders nested inside one another? → A: Allow shared and nested locations; ask the DM when an operation has an unresolved classification or destination.
- Q: Should the initial configuration format allow YAML anchors and aliases, which let one setting reuse another setting's value? → A: Allow syntax supported by the reader selected under Issue #4 when the resolved configuration passes schema validation; duplicate keys and invalid/conflicting settings remain errors.
- Q: When read-only discovery finds several plausible locations for one section, how should the assistant proceed? → A: Select the most likely candidate, report the choice, and continue read-only work.
- Q: If configuration or a referenced guidance file, template, or path changes after validation but before a dependent operation completes, what should happen? → A: Stop the affected operation, report the change, and require revalidation before retrying.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use an Existing Vault Without Migration (Priority: P1)

A Dungeon Master can use an existing campaign vault without creating a configuration file, renaming folders, moving notes, or adopting a prescribed layout. The assistant can identify likely existing sections for read-only work and make uncertainty visible rather than treating missing locations as instructions to create them.

**Why this priority**: Existing vaults must remain usable without migration; this is the core compatibility promise.

**Independent Test**: Point a read-only discovery workflow at an existing vault without `.dmassist.yaml` and verify that it reports existing locations and ambiguities without changing any files.

**Acceptance Scenarios**:

1. **Given** a vault with conventional section folders and no configuration, **When** a user requests read-only discovery, **Then** the available sections are reported and no configuration or folders are created.
2. **Given** a vault with renamed, missing, or additional sections, **When** discovery runs, **Then** it reports what it can identify and any ambiguity without claiming missing sections exist.
3. **Given** adventures stored as root-level files or folders, **When** discovery runs, **Then** it can report those candidates without requiring an `Adventures` folder or treating every root item as an adventure.
4. **Given** several plausible locations for one section, **When** read-only discovery runs, **Then** it selects the most likely candidate, reports that choice as inferred alongside the alternatives and its reason, and continues read-only work without treating the inferred choice as authorization for edits.

---

### User Story 2 - Describe Vault-Specific Organization (Priority: P2)

A Dungeon Master can provide an optional vault-local profile to identify section locations, the active group context, where session preparation belongs, custom article templates, and additional guidance. The profile describes the existing vault rather than copying campaign facts or imposing a new layout.

**Why this priority**: A clear profile reduces repeated explanation and lets future workflows use each vault's organization while preserving user-owned content.

**Independent Test**: Validate a profile with customized paths and verify that each setting resolves to the intended in-vault location while leaving notes unchanged.

**Acceptance Scenarios**:

1. **Given** a valid profile with custom section locations, **When** it is read, **Then** those locations take precedence over the documented defaults without requiring other folders to be renamed or created.
2. **Given** a valid profile with a group note, preparation location, template overrides, and guidance paths, **When** it is read, **Then** each setting is available as configuration and no lore, session history, or character knowledge is duplicated into the profile.
3. **Given** a profile without optional settings, **When** it is read, **Then** documented defaults apply and optional guidance or template overrides are not required.
4. **Given** an explicitly configured template that is missing, unreadable, or invalid, **When** a workflow requests that template, **Then** it reports the problem and does not silently substitute a default template.
5. **Given** an explicitly configured guidance file that is missing or unreadable, **When** a workflow needs that guidance, **Then** it reports the problem rather than silently proceeding without it.
6. **Given** an explicitly configured section folder does not exist, **When** the profile is validated, **Then** the entire profile is rejected with an error identifying the missing folder, and no folder is created automatically.
7. **Given** section mappings share a folder or are nested within one another, **When** the profile is validated, **Then** overlap alone does not invalidate the profile; an operation with an unresolved classification or destination asks the DM before proceeding.
8. **Given** a vault has a section outside the built-in categories, **When** the DM defines a custom section with an identifier, existing folder, and description of its use, **Then** workflows can use that description as context when identifying relevant material without treating it as executable instruction or automatic classification.
9. **Given** a DM or maintainer needs to check the profile's supported structure, **When** they use the published machine-readable schema, **Then** it describes the version-1 profile's structural and value constraints, while the written contract identifies validation that still depends on YAML parsing or vault state.

---

### User Story 3 - Receive Clear Validation and Safe Path Handling (Priority: P1)

A Dungeon Master receives an actionable error when a profile is malformed, incompatible, or points outside the authorized vault. Profile content remains data: it cannot grant destructive permissions or cause commands or other content to execute.

**Why this priority**: Reliable validation and a strict vault boundary protect campaign files and prevent unsafe guesses.

**Independent Test**: Supply malformed profiles and paths involving traversal or symbolic links that resolve outside the vault; verify each is rejected clearly before any write occurs.

**Acceptance Scenarios**:

1. **Given** malformed YAML, duplicate keys, unsupported YAML features, invalid field types, or unknown fields, **When** the profile is loaded, **Then** it fails with a clear error naming the invalid input instead of silently guessing or ignoring it.
2. **Given** a profile declaring a newer unsupported schema version, **When** it is loaded, **Then** it reports the unsupported version and does not interpret the profile using older rules.
3. **Given** a profile with a missing or invalid schema version, **When** it is loaded, **Then** it reports the version error and does not infer a version.
4. **Given** a configured relative path that traverses outside the vault or a path whose symbolic link resolves outside it, **When** the path is resolved, **Then** it is rejected before access or modification outside the vault.
5. **Given** configuration or referenced guidance containing command-like text or a request to bypass safeguards, **When** a workflow reads it, **Then** the content is treated as data and does not execute commands, authorize destructive actions, or override approval requirements.
6. **Given** a workflow cannot validate the profile, **When** the user requests an operation that depends on its settings, **Then** the workflow explains that validation is unavailable and does not proceed using unvalidated settings or silently install or substitute a dependency.
7. **Given** two workflows read the same profile against unchanged vault contents, **When** each resolves its settings and paths, **Then** both report identical settings and vault boundaries.
8. **Given** validated configuration or a referenced guidance file, template, or path changes during a dependent operation, **When** the change is detected, **Then** the affected operation stops, reports the change, and requires revalidation before retrying without silently mixing old and new inputs.

## Edge Cases

- A configured section, guidance file, group note, or template does not exist or is unreadable.
- Two existing locations plausibly match one section, or configured locations overlap.
- A path is valid as text but resolves through a symbolic link outside the authorized vault.
- YAML uses aliases or merge keys, contains duplicate mapping keys, or has scalar values whose parsed types differ from the schema field types.
- A profile uses an absent, invalid, or newer schema version.
- The vault has no conventional folders, or has root-level adventure material and unrelated root notes.
- The optional default guidance file is absent; this must not make an otherwise unconfigured vault unusable.
- A configured template override fails validation; article creation must stop rather than silently use a different template.
- Configuration or a referenced guidance file, template, or path changes after validation: stop the affected operation, report the change, and require revalidation before retrying.
- The machine-readable schema is missing, invalid, or inconsistent with the written version-1 contract; it cannot be used as a complete substitute for the contract or runtime validation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST define `.dmassist.yaml` as an optional configuration file located at the root of the explicitly authorized campaign vault, not in the plugin installation.
- **FR-002**: The configuration contract MUST define a schema version and a supported initial version. A missing, invalid, or newer unsupported version MUST produce a clear validation error; the system MUST NOT silently reinterpret unsupported configuration.
- **FR-003**: The contract MUST define configurable paths for Adventures, Lore, Monsters Stats, Rules, Sessions, and Handouts, with defaults of `Adventures`, `Lore`, `Monsters Stats`, `Rules`, `Sessions`, and `Handouts`, respectively. The defaults MUST be candidates, not a requirement to create folders or migrate notes.
- **FR-004**: The contract MUST allow root-level adventure candidates to be discovered without treating every root item as an adventure or requiring an Adventures folder.
- **FR-005**: The contract MUST support one active campaign/group context per vault, including a reference to the group's note. Shared-campaign selection and campaign-state duplication in configuration are out of scope.
- **FR-006**: The contract MUST allow preparation to be associated either with a section titled `Preparation` in a session note or with a separate preparation location. Its default MUST keep preparation distinct from recorded session outcomes.
- **FR-007**: The contract MUST allow optional vault-relative paths to designated Markdown guidance and optional per-article-type template overrides. An absent default guidance file MUST be treated as optional; an explicitly configured but unavailable guidance file or template MUST be reported rather than silently ignored or substituted.
- **FR-008**: The contract MUST document defaults and optional fields so a vault can omit settings it does not customize.
- **FR-009**: When `.dmassist.yaml` is absent, the system MUST support read-only discovery and report identified locations and ambiguities without creating configuration, folders, or notes.
- **FR-010**: The configuration contract MUST define expected field types and validation outcomes. Duplicate YAML mapping keys MUST be rejected during parsing; unknown fields, unsupported schema versions, invalid values, and explicit nulls MUST produce clear errors. YAML syntax supported by the reader chosen for implementation may be used if the resulting configuration passes schema validation; unsupported or malformed syntax MUST stop profile loading. For string-valued fields, YAML string, boolean, numeric, and date/time scalar values MUST resolve to non-empty strings using locale-independent representations; booleans MUST use lowercase text and dates and timestamps MUST use ISO 8601. Explicit nulls and collection values MUST be rejected. The version field MUST remain the integer `1`.
- **FR-011**: Every configured path MUST be relative to the authorized vault, and its fully resolved target—including symbolic-link resolution—MUST remain within that vault before it is accessed or modified.
- **FR-012**: Configuration, templates, and guidance MUST be treated as data, MUST NOT execute commands or expressions, and MUST NOT grant permissions or weaken safeguards for destructive or continuity-changing edits.
- **FR-013**: A workflow MUST clearly report when it cannot validate the profile and MUST NOT continue using unvalidated settings. Runtime selection and dependency handling are outside this feature's scope.
- **FR-014**: The contract MUST keep machine-readable settings separate from campaign lore, session history, and character knowledge, and MUST NOT require migration, restructuring, or reformatting of existing vault content.
- **FR-015**: Any workflow reading the same profile against the same vault state MUST resolve identical settings and path boundaries.
- **FR-016**: Every explicitly configured section folder MUST exist. A missing explicitly configured section folder MUST cause rejection of the entire profile, without creating the folder or falling back to discovery. Missing conventional default folders that were not explicitly configured remain optional discovery candidates.
- **FR-017**: Section mappings MAY share locations or be nested. Overlap MUST NOT invalidate an otherwise valid profile or classify every note under a mapped location automatically. An operation with an unresolved classification or destination MUST ask the DM before proceeding.
- **FR-018**: When unconfigured discovery finds multiple plausible locations for a section, it MUST select the most likely candidate and continue read-only work, while reporting the selection as inferred, its reason, and the alternatives. An inferred discovery selection MUST NOT authorize edits or override explicitly configured mappings. This read-only selection policy does not resolve ambiguous destinations or classifications within overlapping configured mappings.
- **FR-019**: If configuration or a referenced guidance file, template, or path changes after validation during a dependent operation, the affected operation MUST stop, report the change, and require revalidation before retrying. It MUST NOT automatically retry or silently combine old and new settings, and MUST continue to enforce the vault boundary before access.
- **FR-020**: The contract MUST allow optional custom sections, each with a stable identifier, a vault-relative existing directory path, and a non-empty description of the section's intended use. Descriptions MUST be treated as data that can inform classification, not as instructions, authorization, or proof that every note in the folder belongs to that section. Custom section paths MUST follow the same boundary, existence, overlap, and whole-profile validation rules as explicitly configured built-in sections.
- **FR-021**: The contract MUST allow optional named custom article-template overrides for DM-specific article types beyond the built-in types. Each custom type MUST map to one vault-relative Markdown template path, use a valid identifier that does not duplicate a built-in type, and follow the same path-boundary and missing/unreadable/invalid-template error behavior as built-in overrides. Custom template content MUST remain data and MUST NOT execute or grant permissions.
- **FR-022**: The feature MUST provide a machine-readable JSON Schema for version 1 of `.dmassist.yaml`, distributed with the configuration contract. The schema MUST validate the normalized profile structure and define its structural and value constraints, including allowed properties, required values, field types, enums, identifier patterns, and conditional preparation settings. It MUST reject unknown properties and include applicable defaults as JSON Schema annotations, without implying that schema validation applies them.
- **FR-023**: The JSON Schema MUST be consistent with the written version-1 contract and serve as the machine-readable definition of constraints expressible over the normalized profile structure. The written contract MUST remain authoritative for defaults and observable behavior not encoded by the schema.
- **FR-024**: The JSON Schema MUST NOT be presented as parsing YAML or as validating duplicate YAML keys, reader-specific syntax, scalar normalization, vault-relative path resolution, filesystem existence or readability, symbolic-link boundaries, or changes to inputs during an operation. Those requirements remain separate runtime obligations; Issue #4 owns YAML reading, normalization to the schema's input structure, validator integration, and filesystem-dependent checks.

### Key Entities

- **Vault profile**: Optional, versioned settings associated with one authorized campaign vault.
- **Section mapping**: A configurable vault-relative location for a campaign content category, with a documented conventional default.
- **Custom section**: An optional user-defined category with an identifier, existing vault-relative directory, and description to help future workflows understand its intended content.
- **Campaign/group context**: The single active group's note reference used to scope future workflows without storing the group's knowledge in configuration.
- **Preparation location**: The configured way to keep tentative session preparation distinct from actual-play records.
- **Guidance path**: An optional in-vault Markdown source designated for vault-specific instructions.
- **Template override**: An optional mapping from an article type to a DM-owned, vault-relative template.
- **Custom template type**: A DM-defined article type identifier mapped to a vault-owned template for article needs outside the built-in template catalog.
- **Machine-readable profile schema**: A versioned artifact describing the structural and value constraints of the normalized version-1 profile, complementing rather than replacing the written contract and runtime checks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A vault with no configuration can complete read-only discovery with zero created or modified files.
- **SC-002**: 100% of fields in the supported profile schema have a documented accepted value type, default or required status, and invalid-value outcome.
- **SC-003**: All validation cases for malformed YAML, duplicate keys, unknown fields, unsupported schema versions, invalid types, traversal, and out-of-vault symbolic links produce an explicit error before any out-of-vault access or write.
- **SC-004**: Existing vaults can use their current organization without renaming folders, moving notes, or changing campaign-content formats.
- **SC-005**: In every test where profile validation is unavailable, the workflow reports that it cannot validate the profile and makes no decision using unvalidated settings.
- **SC-006**: Every structural and value constraint expressible against the normalized version-1 profile has a corresponding schema validation case, and all cases produce the outcomes defined by the written contract without treating parser or filesystem checks as schema validation.

## Assumptions

- `.dmassist.yaml` is the sole configuration file for this contract and remains optional.
- Initial workflows target one campaign and one active group per vault; multiple campaigns sharing one vault are deferred.
- Conventional section names and meanings follow the repository README; existing vault organization takes precedence when a profile maps different locations.
- The optional root-level `.dmassist-guidance.md` is the default designated guidance candidate, but its absence is not an error unless a path is explicitly configured.
- Preparation defaults to a section titled `Preparation` in the session note; a separate preparation location can be selected when desired.
- Unknown fields are rejected so misspelled or ambiguous settings are not silently ignored. YAML syntax support follows the reader selected during runtime implementation.
- A JSON Schema artifact validates the structure and value constraints of the normalized profile; YAML parsing, scalar normalization, and checks requiring access to the authorized vault remain outside its scope.
- Configuration and path validation do not authorize any content edits; existing approval and continuity safeguards remain in force.
- The YAML reader, runtime, dependency versions, and provisioning are owned by Issue #4; this feature defines only the configuration schema and externally observable validation behavior.
