# Feature Specification: Link Resolver Integration

**Feature Branch**: Not assigned

**Created**: 2026-10-31

**Status**: Draft

**Input**: User description: Reference: https://github.com/sylvercode/dm-assistant/issues/7

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set Up the Required Resolver (Priority: P1)

As a Dungeon Master, I can install and configure the required link resolver separately from the plugin and explicitly authorize my vault so vault-facing assistance can work with links in the intended campaign.

**Why this priority**: Vault-facing skills depend on this service, and an installation that cannot be discovered or safely associated with the intended vault must not proceed to campaign notes.

**Independent Test**: Follow the published setup in a clean Copilot CLI session, confirm the resolver and its required tools are available, and confirm the intended vault is explicitly authorized without reading campaign notes.

**Acceptance Scenarios**:

1. **Given** the DM has configured one or more explicitly authorized absolute vault roots, **When** a fresh supported client session starts, **Then** the required resolver tools are discoverable and the setup instructions do not require putting a private vault path in the plugin.
2. **Given** the intended vault is not an exact match for an authorized root, **When** a vault-facing skill begins, **Then** it explains the authorization problem and accesses no campaign notes.

---

### User Story 2 - Stop Safely When the Resolver Is Unavailable (Priority: P1)

As a Dungeon Master, I can rely on a vault-facing skill to stop before campaign-note access when the required resolver is missing, unavailable, incompatible, or not confirmed for my vault.

**Why this priority**: Continuing without a required dependency could lead to incomplete or incorrect campaign assistance and would bypass the vault authorization boundary.

**Independent Test**: Run a vault-facing workflow with the resolver unavailable or improperly configured and verify it identifies the failed prerequisite, provides the required setup guidance, and makes no campaign-note reads or changes.

**Acceptance Scenarios**:

1. **Given** the resolver or a required tool is unavailable, **When** a vault-facing skill is requested, **Then** the skill names the unmet prerequisite, explains the setup needed, and stops before reading or changing campaign notes.
2. **Given** the resolver is available but its reported authorized roots do not exactly match the established vault, **When** a vault-facing skill performs its preflight, **Then** it fails closed without using link resolution as proof of authorization.

---

### User Story 3 - Understand Link-Resolution Results (Priority: P2)

As a Dungeon Master, I can see whether a requested link resolved, was unresolved, had a missing subtarget, was ambiguous, or failed, without the assistant inventing a destination.

**Why this priority**: Faithful result handling prevents the assistant from presenting uncertain campaign references as established facts.

**Independent Test**: Exercise each supported result type with a disposable vault and verify the outcome and any available candidate information are conveyed accurately, with no guessed destination.

**Acceptance Scenarios**:

1. **Given** a link has one resolved destination, **When** it is resolved, **Then** the skill reports that destination without changing the note.
2. **Given** a link is unresolved, has a missing subtarget, is ambiguous, or returns an error, **When** it is resolved, **Then** the skill reports that specific outcome and available details, and does not guess a destination.

### Edge Cases

- The resolver's configured root is a parent or child of the intended vault but is not the vault itself.
- A tool is listed as available but the resolver version is missing, malformed, or incompatible.
- The resolver configuration changes after the current client session starts, so the active session does not reflect the new setup.
- Resolver output is missing, malformed, ambiguous, or reports an error.
- Additional integration opportunities arise during implementation without evidence of a concrete workflow gap.
- Setup examples could accidentally be mistaken for real vault paths or copied into distributed plugin configuration.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The DM MUST be able to install and configure the Obsidian Link Resolver separately from the plugin, for the supported Copilot CLI client, with one or more explicitly authorized absolute vault roots.
- **FR-002**: Setup guidance MUST explain how to configure and verify the resolver in a fresh supported client session. It MUST use placeholders for vault-specific paths and MUST NOT store or distribute a user's private vault path in plugin content or shared configuration.
- **FR-003**: Before any campaign-note access, every vault-facing skill MUST check the declared required-dependency inventory for resolver readiness and separately establish that the intended vault is explicitly authorized. Readiness or tool availability alone MUST NOT be treated as authorization.
- **FR-004**: The required resolver MUST be compatible with version `2.1.0` or later and expose `resolve_obsidian_link` and `get_server_info` in the active supported client session. The version and tools MUST be verified as part of readiness.
- **FR-005**: Authorization MUST be established without reading campaign-note content. The established vault MUST exactly match a reported authorized vault root; a parent or child root MUST NOT count as a match. Link resolution MUST NOT be used as evidence of authorization.
- **FR-006**: If the resolver or any declared required tool is missing, unavailable, incompatible, malformed, or not confirmed for the intended vault, the vault-facing skill MUST explain the failed prerequisite and stop before campaign-note access or changes.
- **FR-007**: A skill using link resolution MUST accurately distinguish resolved, unresolved, missing-subtarget, ambiguous, and error outcomes, and convey available result details without guessing a destination.
- **FR-008**: Validation MUST cover resolver discovery in a fresh supported client session, authorized-vault boundaries, each specified resolution outcome, and absence of campaign-note reads or changes when the dependency is unavailable.
- **FR-009**: Additional hooks, agents, MCP servers, or other integrations MUST remain optional unless a separate, demonstrated workflow gap justifies them. No placeholder endpoints or unsupported integration assumptions may be introduced.
- **FR-010**: The required dependency declaration MUST remain consistent with the shared dependency-readiness contract established by Feature 001 and MUST be checked by every vault-facing skill before campaign-note access.

### Key Entities

- **Required resolver dependency**: The separately installed link-resolution service, its supported compatibility level, required capabilities, setup, readiness check, and failure behavior.
- **Authorized vault root**: An absolute vault location explicitly permitted by the DM for the resolver to use.
- **Resolution outcome**: The result of resolving a link, including a resolved destination or a distinct unresolved, missing-subtarget, ambiguous, or error state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of fresh-session setup checks, the supported client exposes the compatible resolver and both required tools without any user-specific vault path being included in the plugin.
- **SC-002**: A static audit finds that 100% of vault-facing skills check all declared required dependencies and establish vault authorization before any campaign-note access.
- **SC-003**: In 100% of tested missing, unavailable, incompatible, or unauthorized dependency scenarios, no campaign notes are read or changed before the skill stops.
- **SC-004**: In 100% of tested link-resolution cases, the skill preserves the distinction among the five required outcomes and never invents a destination.
- **SC-005**: The setup documentation and validation introduce zero placeholder integration endpoints or undocumented assumptions about additional integrations.

## Assumptions

- GitHub Copilot CLI is the supported client for this integration, consistent with the existing repository support contract.
- Feature 001 defines the shared dependency-readiness contract, while this feature specifies user setup, installed-client verification, and resolver-result behavior.
- Issue #7 names `2.0.0` as its minimum, but the current Feature 001 contract and vault-orientation guidance require `2.1.0` or later to support note-content-free exact-vault authorization through `get_server_info`; this current contract is the applicable baseline.
- One or more authorized vault roots may be configured by the DM. Only an exact match for the vault established for the current task authorizes that task.
- Resolver readiness does not establish a trusted handoff to the PowerShell runtime; script-backed vault access remains blocked until that handoff is separately verified.
- Shared-campaign support and dynamic template expressions remain out of scope until separately specified.
