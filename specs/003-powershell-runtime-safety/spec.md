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

1. **Given** a documented supported environment with all required components, **When** the user starts a script-backed operation, **Then** the operation passes its prerequisite check and continues.
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

### Edge Cases

- The PowerShell runtime (the program that runs scripts) is installed but outside the supported versions, or a required add-on is absent or unsupported.
- The target vault is unspecified, unclear, unreadable, or points to the plugin installation rather than a user-authorized vault.
- A path uses `..` to move above the vault folder, or a link to another location (symbolic link), to resolve outside the vault.
- The starting folder changes, is unavailable, or differs from the vault and plugin locations.
- A note changes between preview and write, or a multi-note operation fails after processing only some targets.
- Markdown notes (plain-text files used for vault content) use different text encodings (saved character representations) or line endings, or contain text that resembles shell commands.
- An error report could expose campaign content by including full note text or supplied paths unnecessarily.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST document the operating environments supported for script-backed workflows and the prerequisites for each one.
- **FR-002**: For each project release, the project MUST identify the latest stable PowerShell runtime and required add-ons, including `powershell-yaml` for reading YAML (a human-readable settings format). It MUST record their exact versions and the date those versions were selected.
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

**Acceptance Coverage**:

- FR-001–FR-005: User Story 1, scenarios 1–4.
- FR-006–FR-009: User Story 2, scenarios 1–4.
- FR-010–FR-014: User Story 3, scenarios 1–7.
- FR-015: User Story 1, scenarios 1 and 4.

### Key Entities

- **Supported Environment**: An operating environment with its approved runtime and required module prerequisites and provisioning guidance.
- **Operation Request**: The explicit vault, campaign/group, and operation context needed to perform one mechanical task.
- **Authorized Vault Boundary**: The user-designated vault root against which resolved targets are checked.
- **Operation Result**: A consistently ordered outcome with status, relevant results, error information, and a completion code (a value other tools use to identify success or failure).
- **Change Preview**: A description of proposed file changes against the state reviewed before an authorized write.

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

## Assumptions

- This foundation serves future script-backed skills and hooks; it does not add scripts, hooks, or runtime requirements to the current empty plugin scaffold.
- The initial workflow targets one campaign/group context per vault. Shared-campaign support is deferred.
- The user designates the vault through workspace context or explicit input; the plugin installation is never a fallback vault.
- Supported operating environments and provisioning guidance are finalized during planning before any script-backed workflow is implemented.
- Inspection remains available as read-only assistance when a scripted operation is blocked by missing prerequisites.
