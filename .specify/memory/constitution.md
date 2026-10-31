<!-- Sync Impact Report
Version change: 1.0.0 → 1.0.1
Modified sections: Development Workflow — define the PowerShell acceptance test command
Added sections: none
Removed sections: none
-->
# DM Assistant Constitution

## Core Principles

### I. Preserve the Plugin Architecture
The repository root MUST remain the installable Agent Plugins 1.0 plugin. Portable
skills MUST live in immediate child folders of `skills/`, and Copilot-specific
agents MUST live in `com.github.copilot/agents/`. Plugin metadata MUST follow the
official discovery contract; do not add legacy component-path fields or
placeholder hooks, MCP servers, or integrations. This keeps the plugin portable
and its capabilities discoverable.

### II. Keep the Campaign Vault Separate
The campaign vault is distinct from the plugin repository. Vault-facing workflows
MUST obtain the vault location from the user's workspace or explicit input and
MUST NOT assume the plugin directory is the vault. This prevents operations from
being directed at the wrong data.

### III. Preserve Campaign Continuity and User Control
Vault-facing workflows MUST preserve existing organization and user edits. They
MUST NOT infer that missing folders should be created, silently resolve
contradictions, or rewrite run adventure plans. Broad, destructive, restructuring,
or continuity-changing edits require a preview and DM approval; clearly requested
local edits do not require redundant approval. These safeguards keep campaign
history and the DM's authority intact.

### IV. Respect Character Knowledge and Player Safety
Preparation MUST remain distinct from actual play and character knowledge. Future
workflows may update character or group knowledge and world facts only from
actual-play records, or from an explicit DM judgment where the guidance allows
it. DM-only facts and revealing links MUST NOT appear in player-facing handouts.
This protects both continuity and the separation between player and DM knowledge.

### V. Distinguish Proposals from Implemented Behavior
Documentation, brainstorms, and planned capabilities MUST be treated as proposals
until implemented. Documentation MUST identify scaffold limitations and MUST NOT
describe planned behavior as available runtime behavior. This avoids misleading
contributors and users.

## Plugin and Vault Constraints

- Keep reusable workflow guidance in skills rather than duplicating it in agents.
- Add integrations only when a concrete need and an actual implementation exist.
- Keep credentials and campaign content out of the distributed plugin.
- Follow the official Plugins for GitHub Copilot and Copilot CLI plugin
  documentation when changing plugin metadata or discovery behavior.
- Preserve existing vault conventions; do not migrate or restructure a vault
  without explicit authorization.

## Development Workflow

- Check current GitHub issues for scope and dependencies before starting planned
  project work. The `epic` label tracks epics; it does not prove implementation.
- Update directly related documentation when behavior or architecture changes.
- Validate plugin discovery using the local installation steps in `README.md`.
- Run the PowerShell acceptance suite with Pester 6.2.0:
  `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`. Runtime prerequisites
  and support limitations are documented in `docs/powershell-runtime-support.md`.
- No build or lint commands are defined. Do not claim those checks were run.
- Reviews MUST verify that changes comply with this constitution and distinguish
  implemented behavior from proposals.

## Governance

This constitution governs repository design and supersedes conflicting
contributor guidance. Amendments MUST be made through a reviewed change that
explains the rationale and identifies affected guidance or implementation.
Contributors MUST check compliance during planning and review; deviations require
an explicit rationale and approval in the change.

Constitution versions use semantic versioning: MAJOR for backward-incompatible
governance changes, MINOR for new or materially expanded principles or sections,
and PATCH for clarifications and non-semantic refinements. The ratification date
records the original adoption date and MUST NOT be reset by later amendments.
The last-amended date changes whenever the constitution changes.

**Version**: 1.0.1 | **Ratified**: TODO(RATIFICATION_DATE): confirm original adoption date | **Last Amended**: 2026-10-30
