# Implementation Plan: Read-Only Vault Orientation and Inventory

**Branch**: `sylvercode-vault-orientation-inventory` | **Date**: 2026-11-01 | **Updated**: 2026-11-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-vault-orientation-inventory/spec.md`

**Integration update:** Historical references below to an always-blocked
authorization handoff are superseded by Feature 003's caller-confirmation
contract: the caller performs live MCP checks, while PowerShell checks the
root-scoped confirmation and filesystem safeguards without authenticating MCP.
Installed-client and production qualification remain unverified.

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
contents. The inventory entry point returns an unapproved proposal, never a
write. Define the boundary for a separately approved profile write, but do
not implement that writer in this feature: no profile-specific operation is
currently registered.

## Technical Context

**Language/Version**: Stable PowerShell 7.6.9 or later (`pwsh`), Core edition.

**Primary Dependencies**: Obsidian Link Resolver 2.1.0 or later with
`resolve_obsidian_link` and `get_server_info` as declared by Feature 001;
`powershell-yaml` 0.4.12 for the optional `.dmassist.yaml` profile; the
installed skill's shared reference and schema.

**Storage**: No new storage. Vault data and the optional `.dmassist.yaml`
remain user-owned files; inventory, mapping evidence, DM-directed selections,
and proposals are request-scoped and not persisted.

**Testing**: Pester 6.2.0 with synthetic disposable vaults through
`pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1`. The test harness's
authorization provider is test-only and does not establish production
authorization. Also run the static skill inventory/source audit, the README
local plugin-discovery checks, and the five-DM SC-005 walkthrough.
Installed-client and production authorization handoff checks remain separate.

**Target Platform**: Windows is the current candidate environment with
stable PowerShell 7.6.9 or later and `powershell-yaml` 0.4.12; it is not qualified for
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
Resolver for local traversal or containment. Exclude dot-prefixed entries as
inventory items and include non-dot-prefixed Markdown regardless of OS
Hidden/System attributes. Report only eligible directory and Markdown names,
omitting all non-Markdown filenames, including attachments. Inventory never
opens attachment or other non-Markdown contents and reads Markdown note content
only after applicable local guidance has loaded. Without guidance, inventory
is names-only. The separately loaded
Feature 002 profile and explicitly selected dot-prefixed guidance are not
inventory items. Inventory and profile proposals never write.

**Scale/Scope**: One vault and one on-demand request at a time; no persistent
index, cache, or cross-run mapping state. Vault file-count and concurrency
assumptions are not quantified by the feature.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle or constraint | Status | Plan evidence |
| --- | --- | --- |
| Preserve plugin architecture | PASS | Add behavior only within the existing immediate-child `skills/vault-orientation/` skill and its modules; do not add plugin manifest paths, placeholder hooks, MCP servers, or integrations. |
| Keep campaign vault separate | PASS | Require the explicit workspace/user vault and existing exact-vault preflight; never infer it from the plugin or working directory. |
| Preserve continuity and user control | PASS (feature scope) | Inventory is read-only; profile proposals remain unapproved and are never written by this workflow. The existing generic-editor limitation is recorded separately below. |
| Respect character knowledge and player safety | PASS / N/A | This feature does not update knowledge, produce player-facing handouts, or change actual-play records. |
| Distinguish proposals from implemented behavior | PASS | Design artifacts and skill guidance must identify the operation as unavailable until implemented and validated; runtime access remains fail-closed until authorization handoff is verified. |
| Plugin and vault constraints | PASS | No credentials or campaign content in the plugin; tests use synthetic disposable vaults and test-only authorization. |
| Development workflow | PASS | Validate using the Pester 6.2.0 acceptance runner, the static skill inventory/source audit, and the README's local plugin-discovery steps; record installed-client and authorization limitations separately. |

No pre-design gate violations were found within this feature's read-only
scope. The existing generic-editor limitation is outside that scope and is
not represented as runtime-wide enforcement. No complexity-tracking
exceptions are required.

## Design Decisions

1. Register `vault.orientation.inventory` as an `inspect`-only, read-only
   operation with minimum and maximum target counts of zero, no required
   campaign/group, and `RequiresMappings=false`. The latter permits
   mapping-independent names-only orientation; it does not permit
   guidance-dependent note reads or treating inferred mappings as confirmed.
   Use `scripts\Invoke-DmInventory.ps1` as the assistant-facing entry point. It
   accepts one JSON input object, constructs the fixed runtime request, and
   invokes the internal `Invoke-DmInventory -Request $request` exported by
   `VaultInventory.psm1`. The existing registry validates operations but is
   not a dispatcher. The entry point rejects any other operation or mode,
   uses the established preflight, and always returns
   `{ result, inventoryReport }`; the shared result envelope is unchanged.
2. Keep Feature 002 authoritative for `.dmassist.yaml` and configured/default
   guidance. Additional guidance is an ordered `selectedGuidance` array of
   explicit relative paths; the `optionalGuidance` subset records which
   selections the DM marked optional. Validate and normalize both arrays
   without weakening existing scalar validation. Missing, unreadable, or
   unusable essential selections block dependent reads; equivalent optional
   failures are reported and skipped. Usable guidance that is silent about
   part of the task does not block; affected mappings remain provisional.
   Identify optional skipped selections by their original request position,
   not by echoing a non-Markdown filename. A lexical or containment violation
   remains an error, even for an optional selection. Before reusing
   `Get-DmPreNoteContext`, extend its shared
   guidance-validation and dependency-snapshot read paths so configured or
   default guidance is verified as Markdown before any content or fingerprint
   read. The current helper calls `Test-DmProfileReference` before that
   extension check. Preserve valid existing operations and add regression
   coverage for the shared helper.
3. If no applicable local guidance successfully loads, enumerate names only
   and read no campaign-note contents. Otherwise eligible Markdown content,
   including frontmatter, may be inspected after the required sources load.
   Inventory enumeration excludes dot-prefixed entries and reports only
   eligible directory and Markdown names; attachment and all other
   non-Markdown filenames are omitted from the report and their contents are
   never opened; the fixed profile identity is a separate exception.
   Feature 002-designated files and explicitly selected dot-prefixed Markdown
   guidance are loaded separately, not discovered by scanning.
4. Reuse Feature 003's canonical boundary resolver and safe target-read APIs
   for selected guidance and eligible Markdown notes. Enumeration must not
   traverse dot-prefixed entries or follow directory links. Each access must be
   revalidated and proven contained; optional guidance is not an exception.
   For an inventory file link, require both its visible name and its resolved
   in-vault target to be eligible Markdown with no dot-prefixed components in
   the target's vault-relative path before reporting or opening it.
5. Separate observed entries from candidate mappings and label each mapping
   `observed` or `inferred` using FR-011's definitions and apply FR-017's
   explicit evidence threshold; thematic resemblance alone does not produce a
   candidate. Use one shared set of evidence-basis values across the contract
   and data model. Report informational alternatives without pausing
   orientation; when unresolved alternatives affect the requested proposal,
   return them with `AMBIGUOUS_CONTEXT` and no finalized profile content.
   Accept explicit DM-directed choices only in a fresh request, validate them
   against the newly observed alternatives, and never treat them as write
   approval.
6. Preserve the inventory's no-write boundary. A profile proposal has state
   `drafted-unapproved`, is returned for review only, and does not become
   active configuration. For an existing profile, preserve unrelated values
   and comments and make proposed differences clear; if that cannot be done,
   report the limitation instead of finalizing a destructive replacement.
   A separate future profile operation must preview the exact target and
   replacement, obtain a later-message approval, then revalidate and apply
   that exact change. This feature defines those requirements but does not
   implement that operation or call it. The caller must not substitute a
   generic note-edit operation or direct file write for that boundary.
7. Preserve the existing production block: until a trusted active-session
   authorization handoff is verified, no production script-backed profile,
   guidance, or note read is allowed. Synthetic Pester authorization is
   evidence only for local logic.

## Call and Approval Boundaries

1. The assistant follows Feature 001's own dependency, exact-vault, and
   shared-reference sequence; a script reporting a loaded reference is not
   proof that the assistant loaded it. After collecting the DM's explicit
   guidance selections, optionality, proposal intent, and any mapping
   decisions, the assistant sends the JSON input defined in the
   [operation contract](contracts/vault-orientation-inventory.md) to
   `scripts\Invoke-DmInventory.ps1`, including the completed live checks in
   `callerPreflight`. The entry point constructs the Feature 003 request with
   operation `vault.orientation.inventory`, `mode: inspect`, explicit null
   campaign and group, and `targets: []`. No preview or approval fields belong
   to an inventory request.
2. The entry point validates the input, constructs the runtime request, and
   invokes `Invoke-DmInventory`, which runs the established
   runtime/request/dependency/authorization/root preflight before loading the
   shared reference, Feature 002 profile/guidance, and request-selected
   guidance in order. `Get-DmPreNoteContext` reports guidance state and
   versions rather than returning its text; when inventory interprets that
   guidance, it must read through the safe boundary and bind the read to the
   validated dependency snapshot. Capture and recheck the versions of selected
   guidance and note-content evidence before returning; a changed dependency
   invalidates the report. It reads permitted inventory inputs and returns a
   shared result plus the report. No registered dispatcher or installed
   transport is assumed.
3. A complete orientation returns `OK`. An ambiguity affecting a requested
   proposal returns `AMBIGUOUS_CONTEXT` with the successfully collected
   inventory and unresolved alternatives, not a finalized profile. An I/O,
   preflight, boundary, guidance, or proposal-generation failure returns no
   inventory report and an explicit failure.
   For a separate downstream task, the caller applies FR-015 to the reported
   alternatives and obtains DM direction before relying on an affected mapping.
4. A DM's mapping selection may be passed in `mappingDecisions` to a new
   proposal request only as an explicit choice of a currently reported
   alternative. Its identifiers bind the reported alternatives and their
   relevant evidence, not user authorization. A stale or mismatched
   selection cannot silently choose a mapping; report the current situation
   and request direction. A mapping decision is neither profile-write
   intent nor approval.
5. The DM may request a separately scoped profile change after reviewing a
   proposal. The future writer must present the exact replacement and target
   as a preview before asking for a later-message approval. Proposal generation,
   a mapping decision, an instruction to prepare a write, and possession of a
   preview identifier do not by themselves authorize apply. Decline,
   withdrawal, stale approval, or an unsupported writer causes no write.
   Existing preview/apply APIs are not sufficient for a missing profile:
   their current change plan requires an existing file, and no registered
   profile-specific write operation exists. Existing previews contain replacement
   fingerprints, not the replacement text; a future caller must present the
   exact bytes represented by that fingerprint for review. The future
   contract must define safe create versus replace, exact reviewed bytes,
   profile validation, containment, and target/dependency/runtime
   revalidation before it can be implemented or advertised. It must also
   respect the unresolved production authorization handoff and any
   applicable Feature 003 write-safety gates.

**Existing runtime limitation, outside this feature's scope:** The registered
`note.replace-text` operation can technically edit an existing
`.dmassist.yaml`: it does not restrict targets to Markdown, and a single
ordinary edit does not require the Feature 003 approval fields or validate the
replacement against the profile schema. Production script-backed access
currently fails closed at authorization. The DM chose to document this
limitation rather than add a generic-writer guard in this feature. Inventory
and its caller must not use that operation or direct file writes to change a
profile, but this workflow rule is not a runtime-wide enforcement guarantee.
Separately scoped remediation is needed before claiming other generic callers
cannot bypass profile-specific approval and validation.

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
        ├── Invoke-DmInventory.ps1  # Assistant-facing JSON entry point
        ├── OperationRequest.psm1
        ├── RuntimeContract.psm1
        ├── VaultBoundary.psm1
        ├── VaultConfiguration.psm1
        ├── VaultInspection.psm1
        └── VaultInventory.psm1       # New read-only operation module

tests/
└── powershell/
    ├── TestHarness.psm1
    ├── TestHarness.Tests.ps1             # New no-follow fixture snapshot tests
    ├── Invoke-Tests.ps1
    ├── ProfileFilesystem.Tests.ps1       # Shared guidance-read regression coverage
    ├── ProfileState.Tests.ps1            # Shared pre-note regression coverage
    └── VaultOrientationInventory.Tests.ps1  # New focused acceptance tests
```

**Structure Decision**: Extend the existing plugin skill/runtime layout rather
than introducing a new project or transport. The inventory module and Pester
tests are new; operation registration/request validation and the skill
workflow are integrated with existing modules. The assistant-facing
invocation boundary is `Invoke-DmInventory.ps1`; it constructs and dispatches
the internal runtime request. `VaultInventory.psm1` exports
`Invoke-DmInventory -Request $request` for that internal call, while
registration remains validation metadata rather than dispatch. Only update the
shared runtime contract or completion-code taxonomy if implementation
demonstrates a necessary compatible contract extension.

The current `tasks.md` incorporates these call/approval boundaries, the
FR-015/FR-016 refinements, and the decision to omit non-Markdown inventory
items. It includes the shared guidance-read guard and regression coverage,
README discovery check, and five-DM SC-005 walkthrough. Regenerate the task
list if these requirements or plan constraints change before implementation.

## Constitution Check (Post-Design)

| Principle or constraint | Status | Design evidence |
| --- | --- | --- |
| Preserve plugin architecture | PASS | No new plugin component or manifest discovery behavior; portable skill remains under `skills/vault-orientation/`. |
| Keep campaign vault separate | PASS | Explicit root and exact-vault authorization remain mandatory; profile content cannot establish authorization. |
| Preserve continuity and user control | PASS (feature scope) | Inventory never writes; DM mapping choices and the unapproved proposal cannot authorize the separately scoped future write. The existing generic-editor bypass remains outside this feature. |
| Respect character knowledge and player safety | PASS / N/A | The report is DM-facing orientation only and does not update character/group knowledge. |
| Distinguish proposals from implemented behavior | PASS | Contract and quickstart are marked as proposals; no implementation claim is made. |
| Test and runtime limitations | PASS | The plan includes the Pester suite, static skill audit, README local discovery, and the five-DM walkthrough; synthetic authorization remains separate from production authorization and installed-client verification. |

No post-design gate violations were found within this feature's read-only
scope. The separately documented generic-editor bypass remains unresolved.

## Complexity Tracking

No constitution violations or unjustified architectural complexity.
