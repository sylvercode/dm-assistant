# Implementation Plan: Link Resolver Integration

**Branch**: `copilot/speckit-specify` | **Date**: 2026-10-31 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-link-resolver-integration/spec.md`

## Summary

Document and validate the separately installed Obsidian Link Resolver integration for GitHub Copilot CLI. Follow Feature 001's authoritative dependency contract: API baseline 2.1.0 or later, both required MCP tools available, exact authorization through `get_server_info`, verified target containment (including symlinks) before link resolution, and the complete ordered pre-note gates before content-reading calls. Provide Copilot CLI-specific setup guidance with placeholder vault paths; do not add another integration or claim that script-backed access is enabled.

## Technical Context

**Language/Version**: Markdown documentation and portable skill instructions; no new runtime language or version is required.

**Primary Dependencies**: Obsidian Link Resolver MCP API baseline 2.1.0+ (`resolve_obsidian_link`, `get_server_info`), with separately verified canonical target containment before any link-resolution call; GitHub Copilot CLI MCP configuration.

**Storage**: No new storage. Vault roots remain user-configured in the user's MCP client configuration.

**Testing**: Static skill inventory/source audit; review setup examples for private-path placeholders; fresh Copilot CLI session checks for server readiness and exact-vault authorization; all five link-result outcomes and six blocked-access scenarios; plugin discovery validated by following the README's local installation steps in the supported client; and installed-resource lookup verified from the repository root and another working directory. Record plugin-discovery and installed-resource evidence separately from Resolver readiness and authorization. Run `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1` with Pester 6.2.0 and record the result.

**Target Platform**: GitHub Copilot CLI. Do not infer platform support for script-backed vault access from this integration; that runtime remains fail-closed pending its separate authorization handoff verification.

**Project Type**: Agent Plugins 1.0 plugin documentation and portable skill guidance.

**Performance Goals**: No quantitative latency or throughput target is specified; link resolution is an interactive local MCP workflow.

**Constraints**: Keep private vault paths and campaign content out of plugin/shared configuration; do not use link resolution as authorization evidence; require exact-vault authorization before note access; do not add integrations beyond the resolver; distinguish documented proposals from verified runtime behavior.

**Scale/Scope**: One or more DM-authorized vault roots for a local Copilot CLI session; all listed vault-facing skills must follow the common dependency contract. No multi-user service or shared-campaign capability is in scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle or constraint | Plan compliance |
|---|---|
| Preserve plugin architecture | Pass. Keep portable guidance in immediate-child skill folders and use existing plugin discovery/configuration conventions; no legacy manifest fields or placeholder integrations. |
| Keep campaign vault separate | Pass. User supplies and configures vault roots; repository examples use placeholders and do not contain private vault paths. |
| Preserve continuity and user control | Pass. Resolver outcomes do not authorize note changes; unresolved and ambiguous links are surfaced without guessing. |
| Respect character knowledge and player safety | Pass. No campaign facts or player-facing content are generated as part of this dependency integration. |
| Distinguish proposals from implemented behavior | Pass. Document installed-client evidence separately from local/runtime tests; keep PowerShell access blocked until its handoff is verified. |
| Issue scope and dependency | Pass. Issue #7 is the feature source and is blocked by #2; its historical 2.0.0 minimum is superseded by Feature 001's current 2.1.0 contract. |

**Gate result**: PASS. No constitution exception or complexity justification is required.

## Project Structure

### Documentation (this feature)

```text
specs/004-link-resolver-integration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── resolver-mcp-contract.md
```

### Relevant repository surfaces

```text
README.md
docs/architecture.md
docs/powershell-runtime-support.md
skills/README.md
skills/vault-orientation/SKILL.md
skills/vault-orientation/assets/runtime-dependencies.json
specs/001-shared-vault-guidance/spec.md
tests/powershell/
```

**Structure Decision**: This is a plugin-guidance and external MCP dependency feature, not a new application or service. Keep the durable interface contract and validation guide under this feature's `specs/` directory. Update the existing README, skill inventory, consuming skill, and packaged dependency projection only where implementation work identifies drift from Feature 001. Add no server, hook, endpoint, or placeholder plugin component. Use the existing synthetic Pester suite for any runtime changes and an installed Copilot CLI session for client-level verification.

## Constitution Check (Post-Design)

| Review | Result |
|---|---|
| Design artifacts describe only the required resolver integration | PASS |
| Feature 001 remains authoritative for dependency and authorization behavior | PASS |
| Client-specific setup does not reuse incompatible VS Code MCP configuration | PASS |
| No private vault path, campaign content, or unsupported production claim is introduced | PASS |
| Script-backed runtime remains fail-closed until separately verified | PASS |

**Post-design gate result**: PASS. No constitution exception or complexity justification is required.

## Complexity Tracking

No constitution violations.
