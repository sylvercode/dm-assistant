# Feature Specification: PowerShell Runtime and Safe Operations

**Feature Branch**: `003-powershell-runtime-safety`

**Created**: 2026-10-25

**Status**: Draft

**Input**: User description: "Spec 001 and 002 are completed. Check if this influences current spec 003."

## Clarifications

### Session 2026-10-25

- Q: If a multi-note operation fails after changing some notes, what should the workflow do? → A: Stop on the first failure, preserve changes already made, and report exactly which notes changed and which did not.
- Q: How should a Dungeon Master approve a proposed change that affects multiple notes, deletes or reorganizes notes, or broadly changes established campaign facts? → A: Show a preview, then require clear confirmation for that specific preview; approval does not cover other changes.
- Q: Which operating systems must future script-backed workflows support? → A: Windows, macOS, and Linux where the required PowerShell runtime and add-ons are available.
- Q: May script-backed workflows send usage or diagnostic telemetry off the user's device? → A: No; do not send usage or diagnostic telemetry off-device.
- Q: What information should every script-backed operation return so another workflow can reliably interpret its outcome? → A: Return the operation, completion status and code, changed and unchanged targets, remaining work, and any error details.
- Q: How should workflow behavior reconcile uncertain folder mappings when no vault profile exists? → A: Continue read-only using the most likely candidate, label it as inferred, and stop if uncertainty affects conclusions or the next action.

### Session 2026-10-28

- Q: If a workflow is interrupted while writing one note, how should it protect that note? → A: Prevent partial contents in the note being written; retain earlier completed changes and report exact outcomes.
- Q: How should consuming tools distinguish operations that stop because they are blocked, invalid, conflicted, cancelled, or failed? → A: Keep the three progress statuses (`complete`, `not completed`, and `partially completed`) and use stable completion codes to distinguish the specific outcome.
- Q: What should happen if another process changes a note after the workflow checks it but just before the workflow writes its proposed change? → A: Recheck at write time and refuse to replace a note whose contents changed since review.
- Q: What should happen if a note uses a text encoding or line-ending pattern the workflow cannot safely preserve? → A: Convert reliably decodable text to UTF-8 without a BOM and LF line endings, warning before writing; if text cannot be decoded reliably, stop without writing.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run a Script-Backed Workflow Safely (Priority: P1)

A Dungeon Master starts a script-backed workflow and needs to know that the environment and declared dependencies are ready before any operation reads or changes campaign files. If the PowerShell runtime (the program that runs the workflow's scripts), a required add-on, the Obsidian Link Resolver, or authorization for the exact vault is missing or unsupported, the workflow explains the prerequisite and stops before note access.

**Why this priority**: A predictable runtime is the foundation for all later mechanical workflows. Failing closed protects campaign material and gives the user a clear next step.

**Independent Test**: Review the published supported-environment and prerequisite guidance, install the plugin without PowerShell, then run a representative operation with each documented supported environment and with a missing or unsupported runtime, module, declared dependency, or exact-vault authorization. Confirm supported runs proceed, blocked runs explain the missing prerequisite and do not read or change notes, and no prerequisite is installed or upgraded automatically.

**Acceptance Scenarios**:

1. **Given** Windows, macOS, or Linux with all required components, including a validator compatible with the published JSON Schema dialect when configuration is used, **When** the user starts a script-backed operation, **Then** the platform is supported and the operation passes its prerequisite check. A platform where the required components cannot be supported reliably is explicitly identified as unsupported.
2. **Given** a missing or unsupported runtime, required module, declared runtime dependency, or exact-vault authorization, **When** the user starts a script-backed operation, **Then** the user receives a specific prerequisite message, no campaign notes are read or changed, and no prerequisite is installed or upgraded automatically.
3. **Given** a blocked scripted operation, **When** the assistant can still help without the script, **Then** that independent read-only assistance remains available.
4. **Given** a new release of the script-backed workflows, **When** the project publishes its supported-environment guidance, **Then** the guidance identifies the latest stable versions selected, the exact versions and selection date, and how to obtain the runtime and each add-on; repeatability and failure behavior are checked in every supported environment, and installing the plugin itself does not require the runtime.
5. **Given** a vault-facing skill invokes a script-backed operation, **When** the operation would access campaign notes, **Then** the skill first completes the ordered pre-note checks from feature 001, including loading the bundled shared reference, any designated vault-local guidance, and the relevant campaign/group context.

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
5. **Given** a vault-facing operation requires the Obsidian Link Resolver, **When** the active session lacks compatible `obsidian-link-resolver` version `2.0.0` or later, the `resolve_obsidian_link` tool, or a note-content-free signal that the exact vault is authorized, **Then** the operation stops before accessing campaign notes; tool availability alone does not establish vault authorization.
6. **Given** an operation loads a plugin-owned shared resource or profile-validation artifact, **When** the plugin is installed and the process starts in a different working directory, **Then** the resource is located through the installed plugin resource mechanism rather than a source checkout, vault path, or current-directory assumption.

---

### User Story 3 - Understand Results and Control Changes (Priority: P2)

A Dungeon Master needs consistent results from mechanical operations and control over any requested file changes. The user can preview broader changes, approve them explicitly, and rely on the workflow to detect intervening edits and preserve Markdown content.

**Why this priority**: Clear outcomes and conflict-safe writes make mechanical assistance trustworthy without transferring campaign authority away from the Dungeon Master.

**Independent Test**: Exercise successful, invalid-input, and partial-failure cases; then preview a change affecting multiple notes, modify a target before applying it, and confirm the workflow refuses to overwrite that intervening edit. Verify an unapproved broad change is not applied and failure diagnostics do not include full note contents.

**Acceptance Scenarios**:

1. **Given** a completed operation, **When** its result is returned, **Then** it uses the same labeled fields and order as other results and identifies the operation, completion status and code, changed targets, unchanged targets, remaining work, and any error details.
2. **Given** an operation that encounters an error, **When** it reports completion, **Then** it cannot present a partial outcome as full success and identifies the error clearly.
3. **Given** an inspection or a change to more than one note, any deletion or reorganization, or a change to established campaign facts beyond the specific text edit requested in one named note, **When** the operation is requested, **Then** inspection makes no changes and the edit requires showing the proposed changes and receiving the Dungeon Master's explicit confirmation for that exact preview before writing.
4. **Given** a target file changed after a preview, including after an earlier pre-write check, **When** the proposed write is applied, **Then** the workflow rechecks the target immediately before writing, detects the change, and refuses to overwrite it.
5. **Given** an explicitly requested local edit, **When** it is applied without an intervening change, **Then** existing Markdown text, formatting, and saved character representation are preserved except for the requested change; if the existing encoding or line endings cannot be safely preserved, the workflow warns before writing and converts reliably decodable text to UTF-8 without a BOM and LF line endings. If the text cannot be decoded reliably, it stops without writing.
6. **Given** campaign content or paths that resemble executable input, **When** an operation processes them, **Then** they are treated as data and are not executed or interpolated into a command.
7. **Given** an operation that reports an error, **When** diagnostic information is recorded or shown, **Then** it omits unnecessary campaign content and remains on the user's device; the workflow sends no usage or diagnostic telemetry off-device.
8. **Given** a multi-note operation fails after changing one or more notes, **When** the failure occurs, **Then** the operation stops without attempting remaining notes or undoing completed changes, prevents partial contents in the note being written, identifies exactly which notes changed and which did not, and reports partial completion.

---

### User Story 4 - Validate Vault Configuration Before Use (Priority: P1)

A Dungeon Master may use an optional vault configuration profile to identify existing campaign folders and references. Script-backed workflows must load and validate that profile consistently before relying on it, and stop with an actionable error when its contents or referenced files are invalid or have changed.

**Why this priority**: The configuration contract in feature 002 depends on runtime validation to prevent malformed settings, unsafe paths, or stale references from directing later work incorrectly.

**Independent Test**: Exercise a valid profile and profiles with duplicate keys, invalid versions, unknown fields, invalid scalar values, missing configured folders, paths outside the vault, and changed references. Confirm valid profiles resolve consistently and each invalid or stale profile stops dependent work before unsafe access or writes.

**Acceptance Scenarios**:

1. **Given** no `.dmassist.yaml` exists at the authorized vault root, **When** a workflow requests configuration-dependent discovery, **Then** it follows the separate configuration contract's read-only discovery behavior and creates no profile, folder, or note.
2. **Given** no profile exists and more than one section location is plausible, **When** read-only discovery runs, **Then** it selects the most likely candidate, reports that choice as inferred with alternatives and reason, and continues only while the uncertainty does not affect conclusions or the next action.
3. **Given** a profile contains malformed or unsupported YAML, duplicate keys, an absent, invalid, or unsupported version, unknown fields, explicit nulls, or values rejected by the published profile schema, **When** a workflow loads the profile, **Then** it reports a clear validation error and does not use the profile. YAML aliases or merge keys are accepted only when supported by the selected reader and the resolved profile passes schema validation.
4. **Given** a supported YAML string, boolean, numeric, or date/time scalar is used for a string-valued setting, **When** the profile is normalized, **Then** it becomes a non-empty string using a locale-independent representation, booleans use lowercase text, dates and timestamps use ISO 8601, collection values and nulls are rejected, and the version remains integer `1`.
5. **Given** a syntactically valid profile normalizes successfully, **When** the workflow validates it, **Then** the version-1 JSON Schema is applied to the normalized profile, documented defaults are applied only for omitted settings, and schema default annotations do not mutate or fill the profile by themselves.
6. **Given** an explicitly configured built-in or custom section folder is missing, **When** the profile is validated, **Then** the entire profile is rejected without creating the folder or falling back to discovery; omitted conventional folders remain optional discovery candidates.
7. **Given** a configured profile path, party note, preparation location, or custom section path is relative to the vault, **When** its final destination is resolved, **Then** traversal and symbolic links are checked and any destination outside the authorized vault is refused before access. Shared or nested section mappings remain valid, but an unresolved classification or destination is referred to the Dungeon Master.
8. **Given** an explicitly configured guidance file or template is needed but is missing, unreadable, or invalid, **When** the workflow requests it, **Then** the workflow reports the failure and does not silently skip it or substitute another source; an absent optional default guidance candidate does not by itself invalidate the profile.
9. **Given** the same profile and referenced vault content are unchanged, **When** separate operations resolve the profile, **Then** they produce the same settings and vault boundaries.
10. **Given** the profile or a referenced guidance file, template, or path changes during an operation that depends on it, **When** the change is detected, **Then** that operation stops, reports the change, and requires revalidation before retrying without mixing old and new inputs.
11. **Given** an explicitly configured party note, preparation location, section folder, guidance file, or template is needed, **When** the workflow checks that reference, **Then** it verifies existence, readability, and the expected file or folder type and stops dependent work if the reference is invalid rather than selecting a substitute.

### Edge Cases

- The PowerShell runtime (the program that runs scripts) is installed but outside the supported versions, or a required add-on is absent or unsupported.
- The target vault is unspecified, unclear, unreadable, or points to the plugin installation rather than a user-authorized vault.
- A configured path is absolute, uses a backslash, drive or URI syntax, contains a wildcard or control character, or includes `.` or `..` path components.
- A path uses a symbolic link to resolve outside the vault, or a link inside the vault is valid but must still be checked against the canonical vault boundary.
- The starting folder changes, is unavailable, or differs from the vault and plugin locations.
- A note changes between preview and write, or a multi-note operation fails after processing only some targets.
- Another process changes a note after a pre-write check but before the proposed write is applied.
- A multi-note write fails after at least one successful change; completed changes must be reported accurately and must not be silently undone.
- The process is interrupted while writing one note; that note must not be left partially written, and prior completed note changes remain intact.
- Markdown notes (plain-text files used for vault content) use unsupported text encodings (saved character representations) or line endings, contain text that cannot be decoded reliably, or contain text that resembles shell commands.
- An error report could expose campaign content by including full note text or supplied paths unnecessarily.
- The configuration profile contains YAML merge/alias syntax, duplicate keys, ambiguous date-like scalars, explicit nulls, or scalar values whose parsed types differ from their declared setting types.
- The profile is structurally valid but references a missing configured folder, unreadable designated guidance, or invalid template.
- The Obsidian Link Resolver is available but the authorized-vault roots do not include the exact established vault, or exact-vault authorization cannot be checked without reading note content.
- The bundled schema is missing from the installed plugin, differs from the published Draft 2020-12 artifact, or cannot be loaded from a non-default working directory.
- A profile or referenced file changes after validation but before its dependent operation completes.
- Multiple configured section mappings overlap and a note's classification or operation destination cannot be determined from the profile.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST support Windows, macOS, and Linux for script-backed workflows when required prerequisites are available and can be supported reliably. It MUST document the supported operating environments and prerequisites for each; any excluded environment MUST be identified as unsupported.
- **FR-002**: For each project release, the project MUST identify the latest stable PowerShell runtime and the prerequisite add-ons needed by script-backed workflows, and record their exact versions and selection date.
- **FR-003**: The project MUST document how users obtain the prerequisites for supported environments without automatically installing or upgrading them during a workflow.
- **FR-004**: Before a script-backed operation runs, the system MUST verify that the required runtime and modules are available at supported versions. Before a vault-facing operation accesses campaign notes, the invoking skill MUST complete the ordered pre-note checks and verify every declared dependency for readiness and authorization to the exact vault, as defined by feature 001. The initial dependency includes `obsidian-link-resolver` version `2.0.0` or later with `resolve_obsidian_link`; server or tool availability alone MUST NOT be treated as proof that the exact vault is authorized. If a prerequisite or authorization check is missing, incompatible, or inconclusive, the operation MUST explain what is needed and stop before reading or changing campaign notes. Until feature 001 defines a documented note-content-free authorization signal, all vault-facing scripted operations are expected to stop at that authorization gate.
- **FR-005**: Installing the current plugin scaffold MUST NOT require PowerShell; only future script-backed workflows require the documented runtime.
- **FR-006**: Each operation MUST receive the vault, campaign/group, and requested operation explicitly and MUST select the same target regardless of the user's starting folder.
- **FR-007**: The system MUST check every supplied or configured path against the user-authorized vault. Configured paths MUST use `/` separators and MUST be relative; the system MUST reject absolute paths, leading `/`, backslashes, drive or URI syntax, NUL/control characters, wildcards, and `.` or `..` path components. It MUST NOT expand environment variables, home directories, Obsidian links, or other path expressions. Before access, it MUST resolve each path to its final location, including symbolic links, and verify that location stays inside the authorized vault using folder-boundary-aware checks (not simple string prefix checks). Symbolic links that still resolve inside the vault are allowed. It MUST refuse missing or unclear vault targets rather than assuming the plugin directory is the vault or creating unrequested folders.
- **FR-008**: Paths and campaign content MUST be treated only as data, not as instructions to run or text to combine with commands. The system MUST NOT change or bypass operating-system script-running policies, user permissions, or security software to enable an operation.
- **FR-009**: Inspection operations MUST be read-only by default.
- **FR-010**: The system MUST return results in a consistent, labeled format that other tools can read, using the same fields and order for every operation: operation, completion status, completion code, changed targets, unchanged targets, remaining work, and error details when present. Completion status MUST use `complete`, `not completed`, or `partially completed`; stable completion codes MUST distinguish why work did not complete, including prerequisite blocks, invalid input, conflicts, cancellations, and operational failures. Errors MUST be clear, and incomplete work MUST NOT be described as fully complete.
- **FR-011**: Changes to more than one note, any deletion or reorganization, or changes to established campaign facts beyond the specific text edit requested in one named note MUST show the proposed changes and require explicit Dungeon Master confirmation for that exact preview before writing. A clearly requested text edit confined to one named note MUST NOT require redundant approval. Approval of one preview MUST NOT authorize other or later changes.
- **FR-012**: Immediately before applying each write, the system MUST check whether its target note changed since it was read or previewed. If a target changed, including after an earlier pre-write check, the system MUST refuse to overwrite it and report the conflict.
- **FR-013**: Writes MUST preserve existing Markdown text, formatting, and text encoding (the saved representation of characters) except for the requested change when the encoding and line endings can be safely preserved. If they cannot be safely preserved, the workflow MUST warn before writing and convert reliably decodable text to UTF-8 without a byte-order mark and LF line endings. If the text cannot be decoded reliably, the workflow MUST stop without writing.
- **FR-014**: Error reports and logs MUST avoid unnecessary campaign content and remain on the user's device. Script-backed workflows MUST NOT send usage or diagnostic telemetry off-device.
- **FR-015**: Before script-backed operations are relied upon, the project MUST test repeatability and failure behavior in every supported environment.
- **FR-016**: The runtime MUST load the optional `.dmassist.yaml` profile only from the root of the explicitly authorized vault. If the profile is absent, dependent discovery MUST follow the feature 002 read-only discovery contract and MUST NOT create a profile, folder, or note. If a profile is present but invalid, the runtime MUST report the error rather than falling back to unconfigured discovery for profile-dependent work.
- **FR-017**: The runtime MUST reject malformed or unsupported YAML, duplicate mapping keys, an absent, invalid, or unsupported profile version, unknown fields, explicit nulls, and invalid values with a clear error before using the profile. YAML aliases and merge keys MAY be used only when supported by the selected reader and the resolved profile passes schema validation.
- **FR-018**: The runtime MUST normalize supported YAML string, boolean, numeric, and date/time scalar values for string-valued profile settings to non-empty strings using locale-independent representations; booleans MUST use lowercase text and dates or timestamps MUST use ISO 8601. It MUST reject null and collection values for string fields and preserve the profile version as integer `1`.
- **FR-019**: The runtime MUST validate the normalized version-1 profile against the published profile-validation artifact from feature 002. It MUST apply contract defaults only to omitted settings; validation metadata defaults MUST NOT be treated as applying or mutating those values.
- **FR-020**: The runtime MUST require every explicitly configured built-in or custom section directory to exist and MUST reject the entire profile if one is missing. Omitted conventional default directories MUST remain optional discovery candidates; validation MUST NOT create directories or fall back from an invalid explicit mapping.
- **FR-021**: Every configured path, including party note, preparation location, section, custom section, guidance, and template paths, MUST be resolved relative to the authorized vault and checked after canonicalization and symbolic-link resolution using a component-aware boundary check. Any target outside the vault MUST be refused before access or modification; symbolic links resolving within the vault are allowed. The boundary MUST be rechecked before every access.
- **FR-022**: The runtime MUST permit shared or nested section mappings without treating overlap alone as invalid. When an operation cannot determine a note's classification or destination from overlapping mappings, it MUST stop and ask the Dungeon Master.
- **FR-023**: When an explicitly configured or DM-designated guidance file is needed but is missing, unreadable, or invalid, the runtime MUST report the error and stop dependent work before campaign-note access without silently skipping or substituting the source. When no local guidance is designated, its absence MUST NOT invalidate the profile; after other pre-note checks pass, only a specific, read-only lookup that does not rely on uncertain folder or note-role mappings may proceed, as specified by feature 001. An explicitly configured template that is missing, unreadable, or invalid MUST stop article creation without substituting a plugin default; if neither an override nor a plugin default exists, the workflow MUST report that no template is available and ask the DM how to proceed.
- **FR-024**: The runtime MUST resolve unchanged profile and referenced vault state deterministically. If the profile or a referenced guidance file, template, or path changes during a dependent operation, the runtime MUST stop that operation, report the change, and require revalidation before retrying; it MUST NOT automatically retry or combine old and new inputs.
- **FR-025**: Before a dependent operation uses an explicitly configured party note, preparation location, section folder, guidance file, or template, the runtime MUST verify that the target exists, is readable, and has the expected file or folder type. If the target is unavailable or invalid, it MUST report the problem and stop dependent work without silently selecting a substitute.
- **FR-026**: If a multi-note write fails after one or more notes have been changed, the operation MUST stop without attempting remaining notes or automatically undoing completed changes. An interruption MUST NOT leave the note being written partially changed. The operation MUST report partial completion and identify exactly which notes changed and which did not.
- **FR-027**: Every vault-facing skill that invokes a script-backed operation affecting campaign material MUST complete the ordered pre-note sequence defined by feature 001 before note access: establish the authorized vault; verify readiness and exact-vault authorization for every declared dependency; load the plugin-owned shared reference and any designated local guidance; establish campaign/group and player-facing output context; then access only relevant notes. An absent, unreadable, or inconclusive prerequisite MUST stop dependent work before note access. Script execution MUST NOT be treated as proof that the assistant loaded shared guidance.
- **FR-028**: The runtime MUST load the published profile-validation artifact through its installed plugin resource location, independently of the current working directory. It MUST verify that the installed workflow loads the same artifact that defines the active profile contract; a source-tree, vault, or current-directory path MUST NOT be used as fallback.

**Acceptance Coverage**:

- FR-001–FR-005: User Story 1, scenarios 1–4.
- FR-006–FR-007 and FR-009: User Story 2, scenarios 1–6.
- FR-008: User Story 3, scenario 6.
- FR-010–FR-014 and FR-026: User Story 3, scenarios 1–8.
- FR-015: User Story 1, scenarios 1 and 4.
- FR-016–FR-025: User Story 4, scenarios 1–11.
- FR-027–FR-028: User Stories 1 and 2, scenario 5 and 6.

**Configuration Contract Boundary**:

- Feature 002 owns the profile's field definitions, defaults, optionality, read-only discovery selection policy, machine-readable schema artifact and schema/contract consistency, custom-field semantics, and other contract behavior that does not depend on runtime or filesystem access.
- This feature owns the runtime work explicitly delegated by feature 002: YAML parsing and normalization, duplicate-key rejection, applying schema validation, verifying configured paths and referenced files, deterministic resolution, and revalidation when inputs change.
- The delegated runtime requirements correspond to feature 002 FR-010–FR-011, FR-013, FR-015–FR-017, FR-019–FR-021, and the runtime-specific boundary in FR-024, plus the schema-validation operation from FR-022. They are covered by this feature's FR-016–FR-025. Feature 002's contract and schema artifacts remain authoritative for configuration semantics outside this runtime scope.
- Feature 001 owns the shared reference content, skill inventory, and pre-note workflow policy. This feature owns the runtime dependency and authorization checks and requires script-backed callers to follow that pre-note sequence; scripts do not prove that the assistant loaded the reference.

### Key Entities

- **Supported Environment**: An operating environment with its approved runtime and required module prerequisites and provisioning guidance.
- **Operation Request**: The explicit vault, campaign/group, and operation context needed to perform one mechanical task.
- **Authorized Vault Boundary**: The user-designated vault root against which resolved targets are checked.
- **Operation Result**: A consistently ordered outcome with the operation, completion status and code, changed and unchanged targets, remaining work, and error details when present.
- **Change Preview**: A description of proposed file changes against the state reviewed before an authorized write.
- **Vault Configuration Profile**: The optional `.dmassist.yaml` settings document at the authorized vault root.
- **Normalized Profile**: The settings produced after supported YAML scalars are converted to the published version-1 schema's expected types and values.
- **Configured Reference**: A vault-relative section, guidance, party, or template path whose final destination and required existence/readability are checked before use.
- **Declared Runtime Dependency**: A dependency in feature 001's authoritative inventory that must be ready and authorized for the exact vault before a vault-facing workflow reads campaign notes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every environment listed as supported, users can find its exact prerequisite versions and instructions for obtaining them; installing the plugin succeeds without those prerequisites.
- **SC-002**: Users can perform the same operation from at least two different starting folders and receive results for the same explicitly selected vault.
- **SC-003**: 100% of tested attempts to reach notes outside the authorized vault are refused before those notes are read or changed.
- **SC-004**: In each acceptance case—a completed request, a request blocked before any changes, invalid input, a conflict, cancellation, an operational failure, and a request stopped after some work—the result states `complete`, `not completed`, or `partially completed` as appropriate, uses a stable completion code that distinguishes the reason, and identifies any remaining work. 100% of results match their case, and none describes incomplete work as complete.
- **SC-005**: In 100% of tested edits, unrelated note text and formatting remain as originally saved when the source format can be safely preserved; when conversion is needed, reliably decoded text is converted only after a warning and uses UTF-8 without a byte-order mark and LF line endings, while undecodable text is left unchanged. Changes made after review, including immediately before a write, are not overwritten; changes across multiple notes, deletions, reorganization, or broad changes to established campaign facts are not made unless the Dungeon Master confirms the exact preview shown for that change.
- **SC-006**: At least 4 of 5 Dungeon Masters in a usability walkthrough correctly identify the next step for a missing prerequisite, invalid vault target, and operation failure from the user-facing messages.
- **SC-007**: 100% of reviewed diagnostics avoid including full note contents and remain on the user's device; no usage or diagnostic telemetry is sent off-device.
- **SC-008**: Every supported environment passes repeatability checks showing the same read-only request returns the same result, and missing-prerequisite and operation-failure checks produce the expected message without unintended vault changes.
- **SC-009**: 100% of tested malformed YAML, duplicate-key, invalid-version, unknown-field, null, and schema-invalid profiles are rejected before their settings are used.
- **SC-010**: 100% of tested supported scalar values normalize to the specified locale-independent representation, while null and collection values for string fields and non-integer version values are rejected.
- **SC-011**: 100% of tested normalized profiles are validated against the published version-1 profile-validation artifact; omitted defaults follow the written contract and validation metadata alone does not alter profile values.
- **SC-012**: 100% of tested explicitly configured missing section directories reject the entire profile without creating folders or falling back to discovery, while omitted conventional directories remain optional.
- **SC-013**: 100% of tested traversal and symbolic-link escapes across section, guidance, and template paths are refused before out-of-vault access or modification; valid shared or nested mappings remain accepted, with unresolved destinations escalated to the Dungeon Master.
- **SC-014**: 100% of tested missing, unreadable, or invalid explicitly configured guidance and templates stop the dependent operation without silent omission or substitution; an absent optional default guidance candidate does not reject the profile.
- **SC-015**: 100% of tested changes to a profile or referenced guidance, template, or path during a dependent operation stop the operation and require revalidation; unchanged inputs resolve to equivalent settings and vault boundaries.
- **SC-016**: 100% of tested explicitly configured party notes, preparation locations, section folders, guidance files, and templates are checked for existence, readability, and expected file or folder type before use; invalid references stop dependent work without substitution.
- **SC-017**: In 100% of tested vault-facing skill invocations, campaign notes are not accessed unless every dependency in feature 001's authoritative inventory is ready and authorized for the exact vault and the ordered pre-note checks have succeeded; resolver presence alone never counts as proof of vault authorization.
- **SC-018**: 100% of tested configured paths containing an absolute form, unsupported separator, drive or URI syntax, control character, wildcard, or `.`/`..` component are rejected before access; valid in-vault symbolic links are accepted only after canonical, component-aware boundary verification.
- **SC-019**: The installed workflow loads the same published profile-validation artifact from at least two different working directories, and missing or incompatible packaged validation data stops profile-dependent work before settings are used.
- **SC-020**: In 100% of tested multi-note failures or interruptions during a note write, the operation stops at the first failed write, leaves prior successful writes intact, does not leave the note being written partially changed, does not attempt later notes or rollback, and reports exact changed and unchanged note sets.

## Assumptions

- This foundation serves future script-backed skills and hooks; it does not add scripts, hooks, or runtime requirements to the current empty plugin scaffold.
- The initial workflow targets one campaign/group context per vault. Shared-campaign support is deferred.
- The user designates the vault through workspace context or explicit input; the plugin installation is never a fallback vault.
- Supported operating environments and provisioning guidance are finalized during planning before any script-backed workflow is implemented.
- Inspection remains available as read-only assistance when a scripted operation is blocked by missing prerequisites.
- Until feature 001 defines and delivers a note-content-free exact-vault authorization signal, vault-facing scripted operations are expected to stop before campaign-note access and report that authorization could not be proven.
