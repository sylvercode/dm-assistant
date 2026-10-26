# Implementation Plan: Shared Vault Guidance

**Branch**: `sylvercode-shared-vault-guidance` | **Date**: 2026-10-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-shared-vault-guidance/spec.md`

## Summary

Create one canonical, plugin-owned shared vault reference and a vault-orientation skill that follows the defined prerequisite sequence before accessing campaign notes. A vault-facing skill is any workflow that reads, interprets, creates, or changes campaign material. The sequence is to establish the authorized vault without reading notes, verify each required dependency is available and authorized for that vault, load the shared reference and any designated vault-local guidance, establish campaign/group context and identify any handout or read-aloud section, then access campaign notes. No designated local guidance is a valid state; after other preflight checks, a lookup limited to the specific information requested may read relevant notes identified without relying on an uncertain folder or note-role mapping. It remains read-only, and consequential ambiguity pauses further access. Knowledge/world-fact updates require an actual-play record or explicit DM judgment where permitted. Only handout and read-aloud sections are player-facing; gate-check each for DM-only facts and revealing links immediately before delivery. All other task content is DM-facing. The reference will include local, paraphrased defaults for Obsidian aliases, tags, wikilinks and Markdown-style internal links, and callouts, without runtime fetching. Prefer wikilinks unless an established vault preference overrides that default. DM-designated guidance may customize defaults while preserving Obsidian syntax/semantics and shared safety requirements. Validate the resource lookup in the installed GitHub Copilot CLI plugin from multiple working directories, including a consuming skill loading the canonical reference. Current documentation does not guarantee cross-skill filesystem lookup, so this remains an empirical blocker before dependent implementation. Inventory compliance is verified by static inventory/source audit; runtime execution of every vault-facing skill is not required.

## Technical Context

**Language/Version**: Markdown for plugin guidance and portable skill instructions; PowerShell is the repository's script environment, but this feature adds no runtime scripts.

**Primary Dependencies**: Agent Plugins 1.0 fixed plugin layout; GitHub Copilot CLI as the supported client for installed-resource validation and MCP readiness checks; Obsidian Link Resolver MCP server v2.0.0 or later, installed/configured by the user with explicitly authorized vault roots. GitHub epic #7 separately owns Resolver integration. This is the initial, non-exhaustive runtime dependency inventory. Establish the intended vault location before checking dependency authorization; server/tool presence is not proof that the vault is authorized. Official Obsidian documentation for Aliases, Tags, Internal links (wikilink and Markdown-style formats), and Callouts provides source references for paraphrased guidance but is not fetched at runtime.

**Storage**: Plugin-owned Markdown resources in the plugin installation; campaign Markdown and DM-owned guidance remain in the user's separate Obsidian vault.

**Testing**: Establish the authorized vault location without reading campaign notes, then separately verify resolver readiness/tool exposure and authorization for that vault using documented, note-content-free evidence; do not resolve a campaign link merely to prove authorization. If no safe documented method can prove authorization, record the check as blocked rather than claiming success. Use a disposable two-skill plugin fixture to test cross-skill reference loading from multiple working directories and remove the fixture after recording evidence. Enumerate every immediate-child `skills/*/SKILL.md`, compare it one-to-one with `skills/README.md`, and inspect every vault-facing skill's declared source preflight, dependency-table coverage, and knowledge-update basis. This inventory/source audit is static; it does not require runtime execution of every vault-facing skill. Run plugin discovery and resource-lookup checks independently; defer resolver-dependent installed-client scenarios until GitHub epic #7 is available. In installed-client validation, test offline Obsidian defaults, both internal-link formats, wikilink default and established-preference override, DM customization, resolver outcomes, fail-closed dependency behavior, designated-missing and no-designated-guidance cases, consequential ambiguity, actual-play-or-DM-judgment updates, continuity, information safety, and approval scenarios in a disposable vault. SC-004 uses an informal short walkthrough with at least 4 of 5 DMs; examples and scoring are not standardized. The repository currently defines no automated test or lint commands.

**Target Platform**: GitHub Copilot CLI with Agent Plugins 1.0 plugin installation.

**Project Type**: Installable Agent Plugins 1.0 documentation-and-skill scaffold.

**Performance Goals**: No latency or throughput target; load the required guidance before note interpretation or changes.

**Constraints**: The plugin root remains installable; portable skills must be immediate children of `skills/`; `skills/README.md` is the declared inventory of every immediate-child skill containing `SKILL.md`, with each classified as vault-facing or non-vault-facing. Validate inventory completeness and each vault-facing source preflight through a static inventory/source audit; do not require runtime execution of every skill. The **Expected Runtime Dependencies** table in `spec.md` is the authoritative, extensible, non-exhaustive inventory. Use one canonical shared reference rather than duplicating it; do not treat the plugin directory as the vault; never distribute user-specific vault paths; establish the authorized vault before checking dependency authorization; resolver readiness and authorization are distinct, and a missing or unverifiably authorized dependency blocks campaign-note access. No designated local guidance is valid; after all other pre-note checks, it permits a lookup limited to the specific information requested, using relevant notes identified without relying on an uncertain folder or note-role mapping. That lookup is read-only; consequential ambiguity pauses and provisional assumptions never authorize writes. Knowledge/world-fact updates require an actual-play record or explicit DM judgment where permitted. Only handout/read-aloud sections are player-facing and require a pre-delivery gate check; all other task content is DM-facing. Current docs do not guarantee cross-skill resource lookup, so the installed lookup remains an empirical gate and blocker before dependent implementation. Official Obsidian help pages are citations/source material, not runtime dependencies; support both internal-link formats and prefer wikilinks unless an established vault preference overrides that default; no vault migration, automatic folder creation, or configuration schema is introduced. DM-customizable guidance cannot redefine Obsidian-native syntax or weaken shared safety requirements.

**Scale/Scope**: Initial support is one campaign per vault. Include every implemented vault-facing skill in the explicit loading inventory; the current scaffold has no implemented skills.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
|---|---|---|
| Preserve the Plugin Architecture | Keep the repository root as the Agent Plugins 1.0 plugin; skills go in immediate child folders under `skills/`; add no legacy metadata, placeholder hooks, servers, or integrations. | PASS |
| Keep the Campaign Vault Separate | Obtain vault location from workspace or explicit input; never use the plugin installation as the vault. | PASS |
| Preserve Campaign Continuity and User Control | Preserve organization and edits; do not create missing folders by assumption, resolve contradictions silently, or rewrite run plans; gate broad changes on preview and DM approval. | PASS |
| Respect Character Knowledge and Player Safety | Separate preparation, actual play, and character knowledge; update character/group knowledge or world facts only from actual-play records or explicit DM judgment where permitted; treat only handout/read-aloud sections as player-facing and gate-check them immediately before delivery for DM-only facts and revealing links. | PASS |
| Follow the Development Workflow | Check current GitHub issues for scope/dependencies before implementation, validate installed plugin discovery using README instructions, and review changes for constitution compliance and proposal-vs-implementation accuracy. | PASS — T001 rechecks issues/dependencies; T011 uses README installation/discovery validation; T012 performs the final compliance review. |
| Distinguish Proposals from Implemented Behavior | Mark future behavior as planned until implemented and verified. | PASS |

No constitution violations are identified. T001 and T002 remain prerequisite
verification gates; unresolved results block dependent implementation rather
than permitting an assumed lookup or authorization method.

### Post-design re-evaluation

The design artifacts retain the same PASS results: they define proposed
guidance and validation contracts without adding plugin metadata, runtime
integrations, a vault configuration schema, or permission to modify the
campaign vault. Principle IV is enforced by FR-007/FR-019 and the knowledge
update scenario: preparation alone is insufficient, and each update requires
an actual-play record or explicit DM judgment where permitted. The
installed-resource mechanism and note-content-free authorization evidence
remain explicit implementation verification gates, not assumed capabilities.
If either cannot be demonstrated, dependent note access remains fail-closed.
The no-designated-local-guidance case permits only straightforward read-only
lookup after all other pre-note checks; consequential layout ambiguity pauses
that lookup, and provisional assumptions never authorize writes.

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

**Loading gate**: T001 must prove the canonical reference can be loaded by a
consuming vault-facing skill from an installed plugin independently of the
current working directory. The known per-skill base-directory mechanism
supports a skill's own resources only. Do not replace the single canonical
reference with undocumented sibling-path assumptions or silently duplicate
content if the gate fails; record a blocker and settle a supported packaging
approach before dependent implementation.

## Complexity Tracking

No constitution violations require justification.
