# Research: Link Resolver Integration

## Decision: Follow Feature 001's dependency contract without modification

**Decision**: Require the Resolver API baseline 2.1.0 or later and both `resolve_obsidian_link` and `get_server_info`; configure one or more explicitly authorized vault roots with `--vault`; establish authorization only by requiring a returned canonical `vaults[].path` to exactly match the task's established vault after Feature 001's normalization. Complete the full ordered pre-note sequence before any operation that can read target content. Before `resolve_obsidian_link`, require verified upstream canonical target containment (including symlinks), and pass the exact matched root as `vault_root`. Resolver 2.1.0 can follow file symlinks outside an authorized root while reading heading or block targets; no release with a verified fix is confirmed here, so resolution remains blocked until that guarantee is established.

**Rationale**: Feature 001 is the authoritative dependency contract and the upstream Resolver 2.1.0 release added server information needed for exact-vault authorization. Upstream source documents the running version and canonical startup roots in `get_server_info`; the resolver canonicalizes and deduplicates configured roots. Review identified that this root authorization is not sufficient to confine target reads through symlinks, so link resolution also requires a verified upstream target-containment guarantee.

**Alternatives considered**:
- Retain issue #7's historical 2.0.0 minimum: rejected because that release predates `get_server_info` and cannot satisfy the current authorization contract.
- Use `resolve_obsidian_link` to infer authorization: rejected because successful resolution is not proof that the task's intended vault is authorized.
- Change Feature 001's path normalization or dependency contract: rejected because the upstream canonical-path behavior agrees with its current rules.

**Sources**:
- [Feature 001, FR-013/FR-014 and Expected Runtime Dependencies](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive)
- [Resolver v2.1.0 release](https://github.com/sylvercode/obsidian-link-resolver/releases/tag/v2.1.0)
- Upstream `crates/obsidian-link-resolver-mcp/src/mcp.rs`, including tool registration, `ServerInfo`, `ConfiguredVault`, and startup vault canonicalization.
- Upstream [Obsidian Link Resolver README](https://github.com/sylvercode/obsidian-link-resolver)

## Decision: Write setup guidance for Copilot CLI's MCP configuration

**Decision**: Describe Copilot CLI configuration, not the upstream README's VS Code or Claude Desktop examples. Use supported Copilot CLI user configuration (`~/.copilot/mcp-config.json`) or repository MCP configuration (`.mcp.json` / `.github/mcp.json`), with the CLI's `"type": "local"` server format and placeholder vault paths. Explain that a fresh session is needed to verify active tools and authorization.

**Rationale**: Official Copilot CLI documentation says VS Code's `.vscode/mcp.json` is not read by Copilot CLI and that its `servers` schema is unsupported. CLI inspection (`copilot mcp get` / `/mcp show`) exposes status and tools but not the server's semantic version; `get_server_info` is the authoritative live version source as well as the no-note-content authorization check.

**Alternatives considered**:
- Copy the upstream VS Code `.vscode/mcp.json` example: rejected because Copilot CLI does not consume that file/schema.
- Treat CLI server status as sufficient version confirmation: rejected because it reports status and available tools, not semantic version.
- Put a real user's vault path in the plugin or shared example: rejected by the privacy and vault-boundary requirements; use a placeholder in setup guidance.

**Sources**:
- GitHub Docs, `content/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers.md` (user and repository config files, local server schema, verification commands, and VS Code config incompatibility).
- GitHub Docs, Copilot CLI command reference (`copilot mcp` and `--additional-mcp-config`).
- [Copilot CLI installation guidance](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli)

## Decision: Keep validation claims bounded to their evidence

**Decision**: Use static inventory/source checks and synthetic tests for local behavior, then separately verify the actual installed Copilot CLI setup in a fresh session. Do not treat copied-package tests, source inspection, or the PowerShell harness's test-only authorization provider as production authorization evidence. Keep script-backed vault access blocked pending the separate active-session handoff verification.

**Rationale**: Repository documentation explicitly distinguishes synthetic local acceptance coverage from installed-client verification, and the PowerShell runtime cannot yet consume a verified handoff from the active Resolver session.

**Alternatives considered**:
- Treat source-level config examples or a disposable copied plugin as installed-client verification: rejected because neither tests actual client discovery.
- Enable script-backed access based solely on resolver readiness: rejected because readiness does not establish trusted authorization for the selected vault.

**Sources**:
- [README project status and vault-facing workflow](../../README.md)
- [Plugin architecture](../../docs/architecture.md)
- [PowerShell runtime support and limitations](../../docs/powershell-runtime-support.md)
