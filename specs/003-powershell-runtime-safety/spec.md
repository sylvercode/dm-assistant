# Feature Specification: PowerShell Runtime and Safe Operations

**Feature Branch**: `003-powershell-runtime-safety`

**Created**: 2026-10-25

**Status**: Draft

**Input**: User description: "Use issue 4 as input and create number 003 spec since 001 and 002 are in creation in another worktree."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run a Script-Backed Workflow Safely (Priority: P1)

A Dungeon Master starts a script-backed workflow and needs to know that the environment is supported before any operation touches campaign files. If the PowerShell runtime (the program that runs the workflow's scripts) or a required add-on is absent or unsupported, the workflow explains the prerequisite and stops without changing the vault.

**Why this priority**: A predictable runtime is the foundation for all later mechanical workflows. Failing closed protects campaign material and gives the user a clear next step.

**Independent Test**: Review the published supported-environment and prerequisite guidance, install the plugin without PowerShell, then run a representative operation with each documented supported environment and with a missing or unsupported prerequisite. Confirm supported runs proceed, blocked runs explain the missing prerequisite, and no blocked run changes vault files or installs or upgrades a prerequisite.

**Acceptance Scenarios**:

1. **Given** a documented supported environment with all required components, including a validator compatible with the published JSON Schema dialect when configuration is used, **When** the user starts a script-backed operation, **Then** the operation passes its prerequisite check and continues.
2. **Given** a missing or unsupported runtime or required module, **When** the user starts a script-backed operation, **Then** the user receives a specific prerequisite message, no prerequisite is installed or upgraded automatically, and no vault content is changed.
3. **Given** a blocked scripted operation, **When** the assistant can still help without the script, **Then** that independent read-only assistance remains available.
4. **Given** a new release of the script-backed workflows, **When** the project publishes its supported-environment guidance, **Then** the guidance identifies the latest stable versions selected, the exact versions and selection date, and how to obtain the runtime and each add-on; repeatability and failure behavior are checked in every supported environment, and installing the plugin itself does not require the runtime.

---

### User Story 2 - Select and Inspect the Intended Vault (Priority: P1)

A Dungeon Master needs a script-backed operation to act on the intended vault and campaign context regardless of the shell's current folder. Inspection should be read-only by default, and neither a supplied path nor a symbolic link may redirect an operation outside the authorized vault.

**Why this priority**: Selecting the correct boundary prevents accidental operations on the plugin installation, another campaign, or files outside the user's authorization.

**Independent Test**: Run a read-only operation from multiple working directories with a valid vault target, then try missing, ambiguous, traversal, and symbolic-link escape targets; confirm only the authorized vault is inspected and invalid targets are refused without changes.

**Acceptance Scenarios**:

1. **Given** a valid explicit vault and campaign/group context, **When** the user starts an operation from different working directories, **Then** the same target is selected and the results are consistent.
2. **Given** a target path that escapes the authorized vault through traversal or a symbolic link, **When** the user starts an operation, **Then** the operation is refused before accessing or changing the out-of-bound target.
3. **Given** a missing or ambiguous vault target, **When** the user starts an operation, **Then** the operation reports the issue instead of assuming the plugin directory or creating vault folders.
4. **Given** an inspection operation, **When** it completes, **Then** campaign files remain unchanged.

---

### User Story 3 - Understand Results and Control Changes (Priority: P2)

A Dungeon Master needs consistent results from mechanical operations and control over any requested file changes. The user can preview broader changes, approve them explicitly, and rely on the workflow to detect intervening edits and preserve Markdown content.

**Why this priority**: Clear outcomes and conflict-safe writes make mechanical assistance trustworthy without transferring campaign authority away from the Dungeon Master.

**Independent Test**: Exercise successful, invalid-input, and partial-failure cases; then preview a change affecting multiple notes, modify a target before applying it, and confirm the workflow refuses to overwrite that intervening edit. Verify an unapproved broad change is not applied and failure diagnostics do not include full note contents.

**Acceptance Scenarios**:

1. **Given** a completed operation, **When** its result is returned, **Then** the result follows a consistent, labeled format and order and includes the documented completion code (the value other tools use to recognize success or failure).
2. **Given** an operation that encounters an error, **When** it reports completion, **Then** it cannot present a partial outcome as full success and identifies the error clearly.
3. **Given** an inspection or a change to more than one note, any deletion or reorganization, or a change to established campaign facts beyond the specific text edit requested in one named note, **When** the operation is requested, **Then** inspection makes no changes and the edit requires a preview and explicit Dungeon Master approval.
4. **Given** a target file changed after a preview, **When** the proposed write is applied, **Then** the workflow detects the change and refuses to overwrite it.
5. **Given** an explicitly requested local edit, **When** it is applied without an intervening change, **Then** existing Markdown text, formatting, and saved character representation are preserved except for the requested change.
6. **Given** campaign content or paths that resemble executable input, **When** an operation processes them, **Then** they are treated as data and are not executed or interpolated into a command.
7. **Given** an operation that reports an error, **When** diagnostic information is recorded or shown, **Then** it omits full note contents and keeps campaign data local.

---

### User Story 4 - Validate Vault Configuration Before Use (Priority: P1)

A Dungeon Master may use an optional vault configuration profile to identify existing campaign folders and references. Script-backed workflows must load and validate that profile consistently before relying on it, and stop with an actionable error when its contents or referenced files are invalid or have changed.

**Why this priority**: The configuration contract in feature 002 depends on runtime validation to prevent malformed settings, unsafe paths, or stale references from directing later work incorrectly.

**Independent Test**: Exercise a valid profile and profiles with duplicate keys, invalid versions, unknown fields, invalid scalar values, missing configured folders, paths outside the vault, and changed references. Confirm valid profiles resolve consistently and each invalid or stale profile stops dependent work before unsafe access or writes.

**Acceptance Scenarios**:

1. **Given** no `.dmassist.yaml` exists at the authorized vault root, **When** a workflow requests configuration-dependent discovery, **Then** it follows the separate configuration contract's read-only discovery behavior and creates no profile, folder, or note.
2. **Given** a profile contains malformed or unsupported YAML, duplicate keys, an absent, invalid, or unsupported version, unknown fields, explicit nulls, or values rejected by the published profile schema, **When** a workflow loads the profile, **Then** it reports a clear validation error and does not use the profile. YAML aliases or merge keys are accepted only when supported by the selected reader and the resolved profile passes schema validation.
3. **Given** a supported YAML string, boolean, numeric, or date/time scalar is used for a string-valued setting, **When** the profile is normalized, **Then** it becomes a non-empty string using a locale-independent representation, booleans use lowercase text, dates and timestamps use ISO 8601, collection values and nulls are rejected, and the version remains integer `1`.
4. **Given** a syntactically valid profile normalizes successfully, **When** the workflow validates it, **Then** the version-1 JSON Schema is applied to the normalized profile, documented defaults are applied only for omitted settings, and schema default annotations do not mutate or fill the profile by themselves.
5. **Given** an explicitly configured built-in or custom section folder is missing, **When** the profile is validated, **Then** the entire profile is rejected without creating the folder or falling back to discovery; omitted conventional folders remain optional discovery candidates.
6. **Given** a configured profile path, party note, preparation location, or custom section path is relative to the vault, **When** its final destination is resolved, **Then** traversal and symbolic links are checked and any destination outside the authorized vault is refused before access. Shared or nested section mappings remain valid, but an unresolved classification or destination is referred to the Dungeon Master.
7. **Given** an explicitly configured guidance file or template is needed but is missing, unreadable, or invalid, **When** the workflow requests it, **Then** the workflow reports the failure and does not silently skip it or substitute another source; an absent optional default guidance candidate does not by itself invalidate the profile.
8. **Given** the same profile and referenced vault content are unchanged, **When** separate operations resolve the profile, **Then** they produce the same settings and vault boundaries.
9. **Given** the profile or a referenced guidance file, template, or path changes during an operation that depends on it, **When** the change is detected, **Then** that operation stops, reports the change, and requires revalidation before retrying without mixing old and new inputs.
10. **Given** an explicitly configured party note, preparation location, section folder, guidance file, or template is needed, **When** the workflow checks that reference, **Then** it verifies existence, readability, and the expected file or folder type and stops dependent work if the reference is invalid rather than selecting a substitute.

### Edge Cases

- The PowerShell runtime (the program that runs scripts) is installed but outside the supported versions, or a required add-on is absent or unsupported.
- The target vault is unspecified, unclear, unreadable, or points to the plugin installation rather than a user-authorized vault.
- A path uses `..` to move above the vault folder, or a link to another location (symbolic link), to resolve outside the vault.
- The starting folder changes, is unavailable, or differs from the vault and plugin locations.
- A note changes between preview and write, or a multi-note operation fails after processing only some targets.
- Markdown notes (plain-text files used for vault content) use different text encodings (saved character representations) or line endings, or contain text that resembles shell commands.
- An error report could expose campaign content by including full note text or supplied paths unnecessarily.
- The configuration profile contains YAML merge/alias syntax, duplicate keys, ambiguous date-like scalars, explicit nulls, or scalar values whose parsed types differ from their declared setting types.
- The profile is structurally valid but references a missing configured folder, unreadable guidance, or invalid template.
- A profile or referenced file changes after validation but before its dependent operation completes.
- Multiple configured section mappings overlap and a note's classification or operation destination cannot be determined from the profile.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST document the operating environments supported for script-backed workflows and the prerequisites for each one.
- **FR-002**: For each project release, the project MUST identify the latest stable PowerShell runtime and required add-ons, including `powershell-yaml` for reading YAML (a human-readable settings format) and a validator compatible with the published JSON Schema dialect. It MUST record their exact versions and the date those versions were selected.
- **FR-003**: The project MUST document how users obtain the prerequisites for supported environments without automatically installing or upgrading them during a workflow.
- **FR-004**: Before a script-backed operation runs, the system MUST verify that the required runtime and modules are available at supported versions. If a prerequisite is missing or unsupported, it MUST explain what is needed and stop that operation before any vault edits.
- **FR-005**: Installing the current plugin scaffold MUST NOT require PowerShell; only future script-backed workflows require the documented runtime.
- **FR-006**: Each operation MUST receive the vault, campaign/group, and requested operation explicitly and MUST select the same target regardless of the user's starting folder.
- **FR-007**: The system MUST check the final destination of every supplied path, including paths that use `..` or links to another location, against the user-authorized vault folder. It MUST refuse missing or unclear targets rather than assuming the plugin directory is the vault or creating unrequested folders.
- **FR-008**: Paths and campaign content MUST be treated only as data, not as instructions to run or text to combine with commands. The system MUST NOT change or bypass operating-system script-running policies, user permissions, or security software to enable an operation.
- **FR-009**: Inspection operations MUST be read-only by default.
- **FR-010**: The system MUST return results in a consistent, labeled format that other tools can read (the same named fields in each result) with a documented completion status and completion code (a value other tools can use to recognize success or failure). Errors MUST be clear, and incomplete work MUST NOT be described as fully complete.
- **FR-011**: Changes to more than one note, any deletion or reorganization, or changes to established campaign facts beyond the specific text edit requested in one named note MUST show the proposed changes and require explicit Dungeon Master approval before writing. A clearly requested text edit confined to one named note MUST NOT require redundant approval.
- **FR-012**: Before writing, the system MUST check whether each target note changed since it was read or previewed. If a target changed, the system MUST refuse to overwrite it and report the conflict.
- **FR-013**: Writes MUST preserve existing Markdown text, formatting, and text encoding (the saved representation of characters) except for the requested change.
- **FR-014**: Error reports and logs MUST avoid unnecessary campaign content and keep campaign data on the user's device.
- **FR-015**: Before script-backed operations are relied upon, the project MUST test repeatability and failure behavior in every supported environment.
- **FR-016**: The runtime MUST load the optional `.dmassist.yaml` profile only from the root of the explicitly authorized vault. If the profile is absent, dependent discovery MUST remain read-only and MUST NOT create a profile, folder, or note.
- **FR-017**: The runtime MUST reject malformed or unsupported YAML, duplicate mapping keys, an absent, invalid, or unsupported profile version, unknown fields, explicit nulls, and invalid values with a clear error before using the profile.
- **FR-018**: The runtime MUST normalize supported YAML string, boolean, numeric, and date/time scalar values for string-valued profile settings to non-empty strings using locale-independent representations; booleans MUST use lowercase text and dates or timestamps MUST use ISO 8601. It MUST reject null and collection values for string fields and preserve the profile version as integer `1`.
- **FR-019**: The runtime MUST validate the normalized version-1 profile against the published JSON Schema. It MUST apply contract defaults only to omitted settings; JSON Schema default annotations MUST NOT be treated as applying or mutating those values.
- **FR-020**: The runtime MUST require every explicitly configured built-in or custom section directory to exist and MUST reject the entire profile if one is missing. Omitted conventional default directories MUST remain optional discovery candidates; validation MUST NOT create directories or fall back from an invalid explicit mapping.
- **FR-021**: Every configured path, including party note, preparation location, section, custom section, guidance, and template paths, MUST be resolved relative to the authorized vault and checked after traversal and symbolic-link resolution. Any target outside the vault MUST be refused before access or modification.
- **FR-022**: The runtime MUST permit shared or nested section mappings without treating overlap alone as invalid. When an operation cannot determine a note's classification or destination from overlapping mappings, it MUST stop and ask the Dungeon Master.
- **FR-023**: When an explicitly configured guidance file or template is needed but is missing, unreadable, or invalid, the runtime MUST report the error and stop the dependent operation without silently skipping the source or substituting another. An absent optional default guidance candidate MUST NOT by itself invalidate the profile.
- **FR-024**: The runtime MUST resolve unchanged profile and referenced vault state deterministically. If the profile or a referenced guidance file, template, or path changes during a dependent operation, the runtime MUST stop that operation, report the change, and require revalidation before retrying; it MUST NOT automatically retry or combine old and new inputs.
- **FR-025**: Before a dependent operation uses an explicitly configured party note, preparation location, section folder, guidance file, or template, the runtime MUST verify that the target exists, is readable, and has the expected file or folder type. If the target is unavailable or invalid, it MUST report the problem and stop dependent work without silently selecting a substitute.

**Acceptance Coverage**:

- FR-001–FR-005: User Story 1, scenarios 1–4.
- FR-006–FR-009: User Story 2, scenarios 1–4.
- FR-010–FR-014: User Story 3, scenarios 1–7.
- FR-015: User Story 1, scenarios 1 and 4.
- FR-016–FR-025: User Story 4, scenarios 1–10.

**Configuration Contract Boundary**:

- Feature 002 owns the profile's field definitions, defaults, optionality, read-only discovery selection policy, machine-readable schema artifact and schema/contract consistency, custom-field semantics, and other contract behavior that does not depend on runtime or filesystem access.
- This feature owns the runtime work explicitly delegated by feature 002: YAML parsing and normalization, duplicate-key rejection, applying schema validation, verifying configured paths and referenced files, deterministic resolution, and revalidation when inputs change.
- The delegated runtime requirements correspond to feature 002 FR-010–FR-011, FR-013, FR-015–FR-017, FR-019–FR-021, and the runtime-specific boundary in FR-024, plus the schema-validation operation from FR-022. They are covered by this feature's FR-016–FR-025. Feature 002's contract and schema artifacts remain authoritative for configuration semantics outside this runtime scope.

### Key Entities

- **Supported Environment**: An operating environment with its approved runtime and required module prerequisites and provisioning guidance.
- **Operation Request**: The explicit vault, campaign/group, and operation context needed to perform one mechanical task.
- **Authorized Vault Boundary**: The user-designated vault root against which resolved targets are checked.
- **Operation Result**: A consistently ordered outcome with status, relevant results, error information, and a completion code (a value other tools use to identify success or failure).
- **Change Preview**: A description of proposed file changes against the state reviewed before an authorized write.
- **Vault Configuration Profile**: The optional `.dmassist.yaml` settings document at the authorized vault root.
- **Normalized Profile**: The settings produced after supported YAML scalars are converted to the published version-1 schema's expected types and values.
- **Configured Reference**: A vault-relative section, guidance, party, or template path whose final destination and required existence/readability are checked before use.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every environment listed as supported, users can find its exact prerequisite versions and instructions for obtaining them; installing the plugin succeeds without those prerequisites.
- **SC-002**: Users can perform the same operation from at least two different starting folders and receive results for the same explicitly selected vault.
- **SC-003**: 100% of tested attempts to reach notes outside the authorized vault are refused before those notes are read or changed.
- **SC-004**: In each of three acceptance cases—a completed request, a request blocked before any changes, and a request stopped after some work—the result states `complete`, `not completed`, or `partially completed` as appropriate and identifies any remaining work. 100% of results match their case, and none describes incomplete work as complete.
- **SC-005**: In 100% of tested edits, unrelated note text, formatting, and characters remain as originally saved; changes made after review are not overwritten; and changes across multiple notes, deletions, reorganization, or broad changes to established campaign facts are not made without approval.
- **SC-006**: At least 4 of 5 Dungeon Masters in a usability walkthrough correctly identify the next step for a missing prerequisite, invalid vault target, and operation failure from the user-facing messages.
- **SC-007**: 100% of reviewed diagnostics avoid including full note contents, and campaign data remains on the user's device.
- **SC-008**: Every supported environment passes repeatability checks showing the same read-only request returns the same result, and missing-prerequisite and operation-failure checks produce the expected message without unintended vault changes.
- **SC-009**: 100% of tested malformed YAML, duplicate-key, invalid-version, unknown-field, null, and schema-invalid profiles are rejected before their settings are used.
- **SC-010**: 100% of tested supported scalar values normalize to the specified locale-independent representation, while null and collection values for string fields and non-integer version values are rejected.
- **SC-011**: 100% of tested normalized profiles are validated against the published version-1 schema; omitted defaults follow the written contract and schema annotations alone do not alter profile values.
- **SC-012**: 100% of tested explicitly configured missing section directories reject the entire profile without creating folders or falling back to discovery, while omitted conventional directories remain optional.
- **SC-013**: 100% of tested traversal and symbolic-link escapes across section, guidance, and template paths are refused before out-of-vault access or modification; valid shared or nested mappings remain accepted, with unresolved destinations escalated to the Dungeon Master.
- **SC-014**: 100% of tested missing, unreadable, or invalid explicitly configured guidance and templates stop the dependent operation without silent omission or substitution; an absent optional default guidance candidate does not reject the profile.
- **SC-015**: 100% of tested changes to a profile or referenced guidance, template, or path during a dependent operation stop the operation and require revalidation; unchanged inputs resolve to equivalent settings and vault boundaries.
- **SC-016**: 100% of tested explicitly configured party notes, preparation locations, section folders, guidance files, and templates are checked for existence, readability, and expected file or folder type before use; invalid references stop dependent work without substitution.

## Assumptions

- This foundation serves future script-backed skills and hooks; it does not add scripts, hooks, or runtime requirements to the current empty plugin scaffold.
- The initial workflow targets one campaign/group context per vault. Shared-campaign support is deferred.
- The user designates the vault through workspace context or explicit input; the plugin installation is never a fallback vault.
- Supported operating environments and provisioning guidance are finalized during planning before any script-backed workflow is implemented.
- Inspection remains available as read-only assistance when a scripted operation is blocked by missing prerequisites.
