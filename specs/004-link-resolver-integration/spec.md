# Feature Specification: Link Resolver Integration

**Feature Branch**: Not assigned

**Created**: 2026-10-31

**Status**: Draft

**Input**: User description: Reference: https://github.com/sylvercode/dm-assistant/issues/7

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set Up the Required Resolver (Priority: P1)

As a Dungeon Master, I can install and configure the required link resolver separately from the plugin and explicitly authorize my vault so vault-facing assistance can work with links in the intended campaign.

**Why this priority**: Vault-facing skills depend on this service, and an installation that cannot be discovered or safely associated with the intended vault must not proceed to campaign notes.

**Independent Test**: Follow the published setup in a fresh supported client session and confirm that link resolution is ready for the intended vault without reading campaign notes.

**Acceptance Scenarios**:

1. **Given** the DM has configured one or more explicitly authorized absolute vault roots, **When** a fresh supported client session starts, **Then** the link-resolution service is ready for use and the setup instructions do not require putting a private vault path in the plugin.
2. **Given** the intended vault is not an exact match for an authorized root, **When** a vault-facing skill begins, **Then** it explains the authorization problem and accesses no campaign notes.

---

### User Story 2 - Stop Safely When the Resolver Is Unavailable (Priority: P1)

As a Dungeon Master, I can rely on a vault-facing skill to stop before campaign-note access when the required resolver is missing, unavailable, incompatible, or not confirmed for my vault.

**Why this priority**: Continuing without a required dependency could lead to incomplete or incorrect campaign assistance and would bypass the vault authorization boundary.

**Independent Test**: Run a vault-facing workflow with the resolver unavailable or improperly configured and verify it identifies the failed prerequisite, provides the required setup guidance, and makes no campaign-note reads or changes.

**Acceptance Scenarios**:

1. **Given** the resolver or a required tool is unavailable, **When** a vault-facing skill is requested, **Then** the skill names the unmet prerequisite, explains the setup needed, and stops before reading or changing campaign notes.
2. **Given** the resolver is available but its reported authorized roots do not exactly match the established vault, **When** a vault-facing skill performs its preflight, **Then** it fails closed without using link resolution as proof of authorization.
3. **Given** resolver settings changed after the current client session started, **When** a vault-facing skill is requested, **Then** it treats the active settings as unconfirmed, requests a fresh session and verification, and accesses no campaign notes.

---

### User Story 3 - Understand Link-Resolution Results (Priority: P2)

As a Dungeon Master, I can see whether a requested link resolved, was unresolved, had a missing subtarget, was ambiguous, or failed, without the assistant inventing a destination.

**Why this priority**: Faithful result handling prevents the assistant from presenting uncertain campaign references as established facts.

**Independent Test**: Exercise each supported result type with a disposable vault and verify the outcome and any available candidate information are conveyed accurately, with no guessed destination.

**Acceptance Scenarios**:

1. **Given** a link has one resolved destination, **When** it is resolved, **Then** the skill reports that destination without changing the note.
2. **Given** a link cannot be found, **When** it is resolved, **Then** the skill reports that it is unresolved and does not guess a destination.
3. **Given** a link's requested subtarget is missing, **When** it is resolved, **Then** the skill reports the missing subtarget and does not guess a replacement.
4. **Given** more than one destination matches a link, **When** it is resolved, **Then** the skill reports the ambiguity and available candidates without selecting one.
5. **Given** link resolution fails, **When** it is resolved, **Then** the skill reports the failure and only details defined by the Resolver contract and present in the result; it identifies unavailable details without guessing a destination.

---

### User Story 4 - Keep Setup Focused (Priority: P3)

As a Dungeon Master, I can avoid unnecessary integrations and keep future additions tied to a demonstrated campaign workflow need.

**Why this priority**: Additional integrations can complicate setup and should only be introduced when they solve a real user problem.

**Independent Test**: Review the feature's proposed integrations and verify that only the required link-resolution service is included; any other proposal has a separately documented workflow gap and approval.

**Acceptance Scenarios**:

1. **Given** no separate workflow gap has been demonstrated, **When** this feature is delivered, **Then** it introduces no additional integrations or placeholder endpoints.
2. **Given** a possible future integration is identified, **When** it is considered, **Then** it remains a separate proposal until its workflow gap and acceptance criteria are documented.

### Edge Cases

- The resolver's configured root is a parent or child of the intended vault but is not the vault itself.
- The service appears available but required capabilities or supported compatibility cannot be confirmed.
- The resolver configuration changes after the current client session starts; the stale session must not be trusted until a fresh session verifies the new settings.
- A result is incomplete, ambiguous, or reports an error.
- Additional integration opportunities arise during implementation without evidence of a concrete workflow gap.
- Setup examples could accidentally be mistaken for real vault paths or copied into distributed plugin configuration.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The DM MUST be able to install and configure the Obsidian Link Resolver separately from the plugin and authorize one or more absolute vault roots for it.
- **FR-002**: Setup guidance MUST explain how to configure and verify the service in a fresh supported client session. It MUST use placeholders for vault-specific paths and MUST NOT store or distribute a user's private vault path in plugin content or shared configuration.
- **FR-003**: Before any campaign-note access, every vault-facing skill MUST confirm that the required link-resolution service is ready and separately establish that the intended vault is authorized. Service availability alone MUST NOT be treated as authorization.
- **FR-004**: Resolver readiness and authorization MUST follow the required capabilities, supported compatibility, and exact-vault rules in Feature 001's [dependency contract](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive).
- **FR-005**: Authorization MUST be established without reading campaign-note content. The established vault MUST exactly match an authorized vault root; a parent or child root MUST NOT count as a match. Link resolution MUST NOT be used as evidence of authorization.
- **FR-006**: If the service, any required capability, its compatibility, or authorization cannot be confirmed according to the dependency contract, the vault-facing skill MUST explain the failed prerequisite and stop before campaign-note access or changes.
- **FR-007**: A skill using link resolution MUST accurately distinguish a resolved destination, an unresolved link, a missing requested subtarget, multiple possible destinations, and a resolution failure. It MUST report only details defined by the Resolver contract and present in the result; it MUST identify unavailable details without guessing a destination.
- **FR-008**: If resolver settings change after the current client session starts, a vault-facing skill MUST treat that session's settings as unconfirmed, request a fresh session and verification, and stop before campaign-note access.
- **FR-009**: This feature MUST NOT introduce integrations beyond the required link-resolution service. Any additional hook, agent, or service MUST remain a separate proposal until a concrete workflow gap and its acceptance criteria are documented.
- **FR-010**: Feature 001's dependency contract MUST be the authoritative source for the service's supported compatibility, required capabilities, readiness, authorization, and unavailable behavior. Every vault-facing skill MUST follow that same contract before campaign-note access.

### Key Entities

- **Required link-resolution service**: The separately installed service that finds destinations for Obsidian links and confirms which vault roots are authorized.
- **Authorized vault root**: An absolute vault location explicitly permitted by the DM for the resolver to use.
- **Resolution outcome**: The result of resolving a link, including a resolved destination or a distinct unresolved, missing-subtarget, ambiguous, or error state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In all four documented setup checks—fresh-session availability, required capability readiness, authorization of the intended vault, and exclusion of private vault paths from the plugin—the DM can complete setup without reading campaign notes.
- **SC-002**: Every vault-facing skill listed in the current skills inventory confirms the same required dependency and vault-authorization contract before campaign-note access.
- **SC-003**: In each of the six blocked scenarios—service unavailable, a required tool unavailable, compatibility or version unconfirmed, `get_server_info` failed or returned no usable vault list, no exact authorized-root match, and stale resolver settings in the active session—the skill explains the unmet prerequisite and stops before any campaign-note read or change.
- **SC-004**: In each of the five link-resolution outcomes—resolved, unresolved, missing subtarget, ambiguous, and error—the skill reports the correct outcome and never guesses a destination.
- **SC-005**: This feature introduces zero additional integrations; any later integration is considered only with a separately documented workflow gap and acceptance criteria.

## Assumptions

- GitHub Copilot CLI is the supported client for this integration, consistent with the existing repository support contract.
- The Obsidian Link Resolver is the required external link-resolution service. Feature 001's [dependency inventory](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive) is the authoritative source for its current minimum compatible release and required capabilities.
- Issue #7 names `2.0.0` as its minimum, but the current Feature 001 contract requires `2.1.0` or later for exact-vault authorization; this current contract is the applicable baseline.
- One or more authorized vault roots may be configured by the DM. Only an exact match for the vault established for the current task authorizes that task.
- Resolver readiness does not establish a trusted handoff to the PowerShell runtime; script-backed vault access remains blocked until that handoff is separately verified.
- Shared-campaign support and dynamic template expressions remain out of scope until separately specified.
