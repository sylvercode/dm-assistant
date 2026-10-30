# DM Assistant Contributor Instructions

This repository is an Agent Plugins 1.0 plugin with locally tested PowerShell runtime foundations, not a production-ready campaign assistant. Exact-vault authorization and installed-client validation remain blocked or unverified. Check the [README](README.md) and [plugin architecture](docs/architecture.md) before changing plugin structure. Treat planned capabilities as proposals until implemented.

## Plugin Structure

- Keep portable skills in immediate child folders of `skills/`, with a `SKILL.md` in each skill folder.
- Keep Copilot-specific agents in `com.github.copilot/agents/`; keep reusable workflow guidance in skills rather than duplicating it in agents.
- The repository root is the installable plugin. Do not add legacy component-path fields to `plugin.json` or placeholder hooks, MCP servers, or integrations.
- Follow the official [Plugins for GitHub Copilot](https://docs.github.com/en/copilot/concepts/customizations/plugins) and [Creating a plugin for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating) documentation when changing plugin metadata or discovery behavior.

## Campaign Vault Boundaries

- The campaign vault is separate from this plugin. Get its location from the user's workspace or explicit input; never assume the plugin directory is the vault.
- Before changing vault-facing guidance, consult [Vault Guidance Brainstorm](docs/vault-guidance-brainstorm.md) and the relevant README section. These documents describe proposals and safeguards, not implemented runtime behavior.
- Do not infer that missing folders should be created or that existing notes should be reorganized. Preserve user changes and keep operations within the authorized vault.
- Keep preparation distinct from actual play and character knowledge. Do not silently resolve contradictions or rewrite run adventure plans. Keep DM-only facts and revealing links out of player-facing handouts.
- Ask for a preview and approval before broad, destructive, restructuring, or continuity-changing edits; clearly requested local edits do not need redundant approval.

## Project Tracking and Validation

- GitHub Issues tracks project epics with the `epic` label. Check current issues for scope and dependencies before starting planned work; do not treat the label as evidence that a capability is implemented.
- Run the PowerShell acceptance suite with Pester 6.2.0: `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`. Use only synthetic disposable vaults; the test-only authorization provider does not establish production authorization. See [runtime support and limitations](docs/powershell-runtime-support.md).
- No build or lint commands are defined. For plugin discovery checks, follow the local installation steps in the [README](README.md).
