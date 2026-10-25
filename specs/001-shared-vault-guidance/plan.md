# Implementation Plan: Shared Vault Guidance

**Branch**: `sylvercode-shared-vault-guidance` | **Date**: 2026-10-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-shared-vault-guidance/spec.md`

## Summary

Create one canonical, plugin-owned shared vault reference and a vault-orientation skill that loads it alongside DM-designated vault-local guidance before handling campaign notes. The shared reference will include local, paraphrased defaults for Obsidian aliases, tags, internal links (both wikilinks and Markdown-style links), and callouts, so a skill does not need to fetch or reinterpret official help pages at runtime. Prefer wikilinks unless DM input or designated vault-local guidance establishes another vault preference. DM-designated guidance may supplement or customize these defaults for a campaign while preserving Obsidian syntax/semantics and shared safety requirements. Every vault-facing skill must explicitly follow the same loading and context-resolution contract. Validate the packaged resource lookup in the installed GitHub Copilot CLI plugin, independently of the current working directory; do not assume source-tree paths are valid after installation.

## Technical Context

**Language/Version**: Markdown for plugin guidance and portable skill instructions; PowerShell is the repository's script environment, but this feature adds no runtime scripts.

**Primary Dependencies**: Agent Plugins 1.0 fixed plugin layout; GitHub Copilot CLI as the supported client for installed-resource validation; Obsidian Link Resolver MCP server v2.0.0 or later, installed/configured by the user with explicitly authorized vault roots. This is the initial, non-exhaustive runtime dependency inventory. Official Obsidian documentation for Aliases, Tags, Internal links (wikilink and Markdown-style formats), and Callouts provides source references for paraphrased guidance but is not fetched at runtime.

**Storage**: Plugin-owned Markdown resources in the plugin installation; campaign Markdown and DM-owned guidance remain in the user's separate Obsidian vault.

**Testing**: Configure the resolver separately using Copilot CLI's user-managed MCP settings and explicit authorized vault root(s); verify with `copilot mcp list`/`copilot mcp get` and tool discovery in a new session. Then manually validate installed-plugin discovery, loading from different working directories, offline use of locally bundled Obsidian convention defaults, both internal-link formats, wikilink default and established-vault-preference override, DM customization without semantic/safety violations, resolver outcomes, unavailable-dependency fail-closed behavior, and the spec's missing/ambiguous-guidance scenarios. The repository currently defines no automated test or lint commands.

**Target Platform**: GitHub Copilot CLI with Agent Plugins 1.0 plugin installation.

**Project Type**: Installable Agent Plugins 1.0 documentation-and-skill scaffold.

**Performance Goals**: No latency or throughput target; load the required guidance before note interpretation or changes.

**Constraints**: The plugin root remains installable; portable skills must be immediate children of `skills/`; use one canonical shared reference rather than duplicating it; do not treat the plugin directory as the vault; never distribute user-specific vault paths; the resolver is configured separately by the user and is required before every vault-facing skill; official Obsidian help pages are citations/source material, not runtime dependencies; support both Obsidian internal-link formats and prefer wikilinks unless DM input or designated local guidance establishes a vault preference; no vault migration, automatic folder creation, or configuration schema is introduced. DM-customizable guidance cannot redefine Obsidian-native syntax or weaken shared safety requirements. The required-dependency inventory is extensible and non-exhaustive.

**Scale/Scope**: Initial support is one campaign per vault. Include every implemented vault-facing skill in the explicit loading inventory; the current scaffold has no implemented skills.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
|---|---|---|
| Preserve the Plugin Architecture | Keep the repository root as the Agent Plugins 1.0 plugin; skills go in immediate child folders under `skills/`; add no legacy metadata, placeholder hooks, servers, or integrations. | PASS |
| Keep the Campaign Vault Separate | Obtain vault location from workspace or explicit input; never use the plugin installation as the vault. | PASS |
| Preserve Campaign Continuity and User Control | Preserve organization and edits; do not create missing folders by assumption, resolve contradictions silently, or rewrite run plans; gate broad changes on preview and DM approval. | PASS |
| Respect Character Knowledge and Player Safety | Separate preparation, actual play, and character knowledge; keep DM-only facts and revealing links out of player-facing output. | PASS |
| Distinguish Proposals from Implemented Behavior | Mark future behavior as planned until implemented and verified. | PASS |

No constitution violations are identified.

### Post-design re-evaluation

The design artifacts retain the same PASS results: they define proposed
guidance and validation contracts without adding plugin metadata, runtime
integrations, a vault configuration schema, or permission to modify the
campaign vault. The installed-resource mechanism remains an explicit
implementation verification gate, not an assumed capability.

## Project Structure

### Documentation (this feature)

```text
specs/001-shared-vault-guidance/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── vault-guidance-loading.md
└── tasks.md                 # Created by /speckit-tasks, not this plan
```

### Plugin resources (planned implementation layout)

```text
plugin root/
├── plugin.json
└── skills/
    ├── vault-orientation/
    │   ├── SKILL.md
    │   └── VAULT-REFERENCE.md  # Includes paraphrased Obsidian convention defaults and source links
    └── <each vault-facing skill>/
        └── SKILL.md         # Explicitly loads the canonical reference
```

**Structure Decision**: Keep the shared reference with the portable vault-orientation skill under the fixed `skills/` plugin directory, as recommended in the vault-guidance brainstorm. Other vault-facing skills must explicitly load that one canonical resource. The precise installed-path resolution must be proven with the supported Copilot CLI before relying on it; public documentation confirms discovery of files in a skill's own directory, but does not fully specify cross-skill relative-path resolution.

## Complexity Tracking

No constitution violations require justification.
