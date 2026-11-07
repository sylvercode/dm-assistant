# Implementation Plan: Article Authoring and Template Selection

**Branch**: `005-article-authoring` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-article-authoring/spec.md`

## Summary

Deliver one vault-facing `article-authoring` skill with a bundled Markdown
default for each of the nine built-in article types. Reuse Feature 002's
`.dmassist.yaml` template mappings, selecting a valid DM-owned override before
the skill-owned default and stopping on any invalid configured override. Follow
the shared preflight, path-containment, change-detection, player-safety, and
safe-write contracts. Production vault access remains fail-closed until the
trusted authorization handoff is verified; do not invoke Resolver link
resolution until target containment, including symlinks, is verified.

## Technical Context

**Language/Version**: GitHub Copilot skill instructions and templates in
Markdown; existing script-backed operations use PowerShell 7.6.9 (7.4+ minimum).

**Primary Dependencies**: Agent Plugins 1.0 discovery; Obsidian Link Resolver
MCP API 2.1.0 or later with `get_server_info` and `resolve_obsidian_link`;
Feature 001 shared vault guidance; Feature 002 profile/schema contract; Feature
003 structured PowerShell runtime and safe-operation contract.

**Storage**: DM-owned templates and campaign articles are Markdown files in the
explicitly authorized Obsidian vault. Built-in defaults are bundled resources
of the authoring skill. The optional `.dmassist.yaml` profile remains at the
vault root.

**Testing**: Add Feature 005 Pester coverage in
`tests/powershell/ArticleAuthoring.Tests.ps1` for installed template
packaging, profile/template path validation, consumed-input freshness, and
safe-operation integration, using synthetic disposable vaults and the
test-only authorization provider where needed. Keep skill-level client
scenarios (selection, user-visible outcomes, and player-safety decisions) in
`quickstart.md` for supported installed-client evaluation. Run the existing
Pester 6.2.0 suite with
`pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`; do not infer
installed-client or production authorization evidence from local tests.

**Target Platform**: GitHub Copilot CLI Agent Plugins 1.0. PowerShell runtime
support is locally tested on Windows; cross-platform support is not established.

**Project Type**: Agent Plugins 1.0 repository with portable skills and shared
PowerShell runtime modules.

**Performance Goals**: No numeric latency or throughput goal is specified.
The supported operation is one DM-requested article at a time; correctness,
fail-closed behavior, and preservation of existing content take precedence.

**Constraints**: Keep each skill as an immediate child of `skills/` and list it
in `skills/README.md`. Do not assume the plugin is the campaign vault, create
missing folders, overwrite existing notes, execute template expressions, or
infer authorization from profile data, Resolver availability, or test-only
authorization. Treat invalid/stale dependencies as blockers. Production
script-backed vault access remains fail-closed until a trusted active-session
authorization handoff is verified; Resolver link resolution remains blocked
until upstream target-containment protection is verified.

**Scale/Scope**: One active campaign/party per vault; nine built-in article
types plus profile-registered custom types. One article creation is the
operation boundary. Shared campaigns, template migration, automatic vault
reorganization, and dynamic template expansion are out of scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Plan alignment |
|---|---|---|
| I. Preserve the Plugin Architecture | PASS | Add one immediate-child portable skill and bundled resources; do not add placeholder integrations or legacy manifest fields. |
| II. Keep the Campaign Vault Separate | PASS | Resolve DM-owned templates and articles only within the explicitly authorized vault; bundle defaults with the plugin skill. |
| III. Preserve Campaign Continuity and User Control | PASS | Do not overwrite or restructure existing content; require preview and approval for changes beyond safe page-local creation. |
| IV. Respect Character Knowledge and Player Safety | PASS | Keep preparation distinct from actual play and omit DM-only facts and revealing links from player-facing output. |
| V. Distinguish Proposals from Implemented Behavior | PASS | Keep planning artifacts explicit about blocked production authorization and unverified client/runtime evidence. |

**Gate result**: PASS for planning and design. This does not authorize
production vault access or writes; the implementation gates above remain
mandatory.

## Project Structure

### Documentation (this feature)

```text
specs/005-article-authoring/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── article-authoring-contract.md
└── tasks.md
```

`tasks.md` is produced by `/speckit-tasks`, not by this planning workflow.

### Source Code (repository root)

```text
skills/
├── README.md
├── article-authoring/
│   ├── SKILL.md
│   └── templates/
│       ├── adventure.md
│       ├── character.md
│       ├── handout.md
│       ├── location.md
│       ├── monster.md
│       ├── party.md
│       ├── persona.md
│       ├── rule.md
│       └── session.md
└── vault-orientation/
    ├── SKILL.md
    ├── assets/
    └── scripts/

tests/
└── powershell/
    ├── Invoke-Tests.ps1
    └── ArticleAuthoring.Tests.ps1
```

**Structure Decision**: Use one `article-authoring` skill to own all built-in
defaults and shared authoring guidance. Extend the existing PowerShell
acceptance harness only for runtime-backed behaviors; keep tests on synthetic
disposable vaults. Any added runtime code must remain within the existing
`skills/vault-orientation/scripts/` component boundary unless a later design
demonstrates that the authoring skill needs a separate, skill-owned operation
module. Pester tests verify packaging and runtime-backed behavior; evaluate
skill-level content and response behavior separately in the supported client.

## Constitution Check (Post-Design)

| Principle | Result | Design evidence |
|---|---|---|
| I. Preserve the Plugin Architecture | PASS | One portable skill; no new manifest component paths or placeholder integrations. |
| II. Keep the Campaign Vault Separate | PASS | Bundled defaults are plugin resources; overrides and articles remain vault-owned. |
| III. Preserve Campaign Continuity and User Control | PASS | Existing-note conflicts stop; broader or continuity-changing edits require preview and approval. |
| IV. Respect Character Knowledge and Player Safety | PASS | Player-facing checks and preparation/history boundaries are part of the contract. |
| V. Distinguish Proposals from Implemented Behavior | PASS | Research and quickstart distinguish design, synthetic runtime evidence, and installed-client verification. |

**Post-design gate result**: PASS with the same mandatory production
authorization and Resolver target-containment gates. No constitution
violations require a complexity justification.
