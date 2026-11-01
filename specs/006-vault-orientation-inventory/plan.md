# Implementation Plan: Read-Only Vault Orientation and Inventory

**Branch**: `006-vault-orientation-inventory` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-vault-orientation-inventory/spec.md`

## Summary

Add a read-only vault inventory operation to the existing `vault-orientation`
skill and PowerShell runtime. The operation must run after the established
vault, dependency, authorization, shared-reference, and profile/guidance
preflights; enumerate only the explicitly authorized vault; and report
observed names, provisional mappings, uncertainties, and optionally an
unapproved profile proposal. Reuse Feature 001's pre-note rules, Feature 002's
profile and configured/default guidance semantics, and Feature 003's safe
runtime boundary, request/result envelope, and completion codes. Without
applicable local guidance, enumerate names only and do not read campaign-note
contents.

## Technical Context

**Language/Version**: PowerShell 7.6.9 (`pwsh`), using the Feature 003 selected runtime.

**Primary Dependencies**: Obsidian Link Resolver 2.1.0 or later with
`resolve_obsidian_link` and `get_server_info` as declared by Feature 001;
`powershell-yaml` 0.4.12 for the optional `.dmassist.yaml` profile; the
installed skill's shared reference and schema.

**Storage**: No new storage. Vault data and the optional `.dmassist.yaml`
remain user-owned files; inventory, mapping evidence, and proposals are
request-scoped and not persisted.

**Testing**: Pester 6.2.0 with synthetic disposable vaults through
`pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`. The test harness's
authorization provider is test-only and does not establish production
authorization. Installed-client and production authorization handoff checks
remain separate.

**Target Platform**: Windows is the current candidate environment with
PowerShell 7.6.9 and `powershell-yaml` 0.4.12; it is not qualified for
production script-backed vault access. macOS/Linux are unsupported and
unverified.

**Project Type**: Agent Plugins 1.0 plugin with an existing portable skill and
PowerShell runtime modules.

**Performance Goals**: No latency, throughput, or vault-size target is defined
by the specification. Do not claim a threshold or introduce an arbitrary
limit; keep traversal deterministic and avoid opening excluded file types.

**Constraints**: One explicitly established vault per request; exact-vault
authorization and all declared dependency checks precede vault reads. Use
existing boundary APIs for path resolution and byte access; do not use
Resolver for local traversal or containment. Skip dot-prefixed entries,
include non-dot-prefixed Markdown regardless of OS Hidden/System attributes,
never open attachment or non-Markdown contents, and read Markdown content
only after applicable configured/default or request-selected local guidance
has loaded. Without guidance, names only. Do not enumerate dot-prefixed
entries; explicit dot-prefixed guidance selections are allowed outside
inventory scanning. Inventory and profile proposals never write.

**Scale/Scope**: One vault and one on-demand request at a time; no persistent
index, cache, or cross-run mapping state. Vault file-count and concurrency
assumptions are not quantified by the feature.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle or constraint | Status | Plan evidence |
| --- | --- | --- |
| Preserve plugin architecture | PASS | Add behavior only within the existing immediate-child `skills/vault-orientation/` skill and its modules; do not add plugin manifest paths, placeholder hooks, MCP servers, or integrations. |
| Keep campaign vault separate | PASS | Require the explicit workspace/user vault and existing exact-vault preflight; never infer it from the plugin or working directory. |
| Preserve continuity and user control | PASS | Inventory is read-only; profile proposals remain unapproved and are never written by this operation; preserve organization and report ambiguity. |
| Respect character knowledge and player safety | PASS / N/A | This feature does not update knowledge, produce player-facing handouts, or change actual-play records. |
| Distinguish proposals from implemented behavior | PASS | Design artifacts and skill guidance must identify the operation as unavailable until implemented and validated; runtime access remains fail-closed until authorization handoff is verified. |
| Plugin and vault constraints | PASS | No credentials or campaign content in the plugin; tests use synthetic disposable vaults and test-only authorization. |

No pre-design gate violations found. No complexity-tracking exceptions are
required.

## Design Decisions

1. Register `vault.orientation.inventory` as an `inspect`-only operation with
   no write targets. Reuse the shared request/result contract; return the
   inventory payload alongside the existing result envelope following the
   current inspection-module wrapper pattern. Extend operation-specific
   argument validation to accept the ordered string-array guidance selection
   without changing the shared envelope or existing scalar validation.
2. Keep Feature 002 authoritative: load `.dmassist.yaml` when present and
   follow its validation and configured/default guidance behavior. Accept
   extra Markdown guidance only through explicit per-request selection.
3. If no applicable local guidance is loaded, allow name-based directory/file
   inventory but read no campaign-note contents. When configured/default or
   selected guidance is loaded, Markdown content including frontmatter may be
   inspected. Never open dot-prefixed entries, attachments, or other
   non-Markdown contents.
4. Reuse Feature 003's canonical boundary resolver and safe target-read APIs
   for selected guidance and eligible Markdown notes. Enumeration must not
   traverse dot-prefixed entries or follow directory links; explicitly
   selected dot-prefixed guidance is loaded separately. Each path access must
   be revalidated and proven contained.
5. Separate observations, provisional candidates, ambiguities, and an
   optional unapproved profile proposal. Do not persist mappings, silently
   choose consequential alternatives, or expose raw note content in the
   report or diagnostics.
6. Preserve the existing production block: until a trusted active-session
   authorization handoff is verified, no production script-backed profile,
   guidance, or note read is allowed. Synthetic Pester authorization is
   evidence only for local logic.

## Project Structure

### Documentation (this feature)

```text
specs/006-vault-orientation-inventory/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── vault-orientation-inventory.md
└── tasks.md              # Created by /speckit-tasks, not by this plan
```

### Source Code (repository root)

```text
skills/
└── vault-orientation/
    ├── SKILL.md
    └── scripts/
        ├── OperationRequest.psm1
        ├── RuntimeContract.psm1
        ├── VaultBoundary.psm1
        ├── VaultConfiguration.psm1
        ├── VaultInspection.psm1
        └── VaultInventory.psm1       # New read-only operation module

tests/
└── powershell/
    ├── TestHarness.psm1
    ├── Invoke-Tests.ps1
    └── VaultOrientationInventory.Tests.ps1  # New focused acceptance tests
```

**Structure Decision**: Extend the existing plugin skill/runtime layout rather
than introducing a new project or transport. The inventory module and Pester
tests are new; operation registration/request validation and the skill
workflow are integrated with existing modules. Only update the shared runtime
contract or completion-code taxonomy if implementation demonstrates a
necessary compatible contract extension.

## Constitution Check (Post-Design)

| Principle or constraint | Status | Design evidence |
| --- | --- | --- |
| Preserve plugin architecture | PASS | No new plugin component or manifest discovery behavior; portable skill remains under `skills/vault-orientation/`. |
| Keep campaign vault separate | PASS | Explicit root and exact-vault authorization remain mandatory; profile content cannot establish authorization. |
| Preserve continuity and user control | PASS | No writes, no inferred persistence, no unresolved mapping reliance, and profile proposal remains unapproved. |
| Respect character knowledge and player safety | PASS / N/A | The report is DM-facing orientation only and does not update character/group knowledge. |
| Distinguish proposals from implemented behavior | PASS | Contract and quickstart are marked as proposals; no implementation claim is made. |
| Test and runtime limitations | PASS | Synthetic disposable vault validation is separate from production authorization and installed-client verification. |

No post-design gate violations found.

## Complexity Tracking

No constitution violations or unjustified architectural complexity.
