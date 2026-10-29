# Implementation Plan: PowerShell Runtime and Safe Operations

**Branch**: `003-powershell-runtime-safety` | **Date**: 2026-10-28 | **Spec**: `specs/003-powershell-runtime-safety/spec.md`

**Input**: Feature specification from `specs/003-powershell-runtime-safety/spec.md`, scoped by GitHub issue [#4](https://github.com/sylvercode/dm-assistant/issues/4).

## Summary

Define implementable, testable contracts for future PowerShell-backed vault
operations without adding a runtime to the current Agent Plugins 1.0 scaffold.
The design covers supported runtime prerequisites, explicit operation inputs
and structured results, the Feature 001 pre-note and exact-vault authorization
gate, Feature 002 profile parsing/normalization/schema validation, installed
plugin resource discovery, vault-contained paths, and preview/conflict-safe
atomic note writes. The canonical profile schema will be packaged with its
current consuming skill at `skills/vault-orientation/assets/dmassist.schema.json`;
Feature 002 remains authoritative for its meaning and constraints.

The plan's gates are **design readiness gates**, not claims that these runtime
capabilities exist. Until Feature 001 supplies a note-content-free signal
proving authorization for the exact vault, every vault-facing operation stops
before campaign-note access.

## Technical Context

**Language/Version**: PowerShell 7 (`pwsh`) for future script-backed skills.
The exact stable release and per-OS support matrix are selected, dated, and
recorded when the dependency set is validated for implementation.

**Primary Dependencies**: `powershell-yaml` for YAML parsing and
normalization; a Draft 2020-12 JSON Schema validator, with `JsonSchema.Net`
as the researched candidate. The selected exact versions and selection date
must be recorded alongside release support guidance. The required
`obsidian-link-resolver` dependency remains governed by Feature 001's
authoritative inventory and requires separate exact-vault authorization.

**Storage**: User-owned `.dmassist.yaml`, Markdown notes, and references stay
in the explicitly authorized campaign vault. The profile-validation schema
is a plugin-owned skill asset at
`skills/vault-orientation/assets/dmassist.schema.json`; it is not campaign
data. Per-note temporary write files, if used, must be created on the target
filesystem and removed after successful replacement or a handled failure.

**Testing**: No repository test/build/lint commands are defined. The design
validation guide specifies synthetic disposable-vault cases, PowerShell
checks in each claimed supported environment, and installed Copilot CLI
plugin/resource checks from multiple working directories. Schema tests cover
valid and invalid normalized profiles; runtime acceptance tests cover
preflight blocking, path containment, deterministic results, safe writes,
interruption, conflicts, and partial completion. This planning phase adds no
test runner or implementation claim.

**Target Platform**: GitHub Copilot CLI Agent Plugin installed on Windows,
macOS, and Linux only where the selected PowerShell runtime and required
modules are supported and verified. Unsupported combinations must be
documented; installation and discovery of the static plugin must not require
PowerShell.

**Project Type**: Agent Plugins 1.0 documentation-and-metadata scaffold.
Feature 003 delivers design artifacts only; future scripts and bundled
resources belong to an actual skill component, not a new root-level
runtime/integration or placeholder plugin component.

**Performance Goals**: No numeric latency or throughput target is specified.
Future tests must confirm deterministic operation and bounded failure
behavior for the supported test fixtures; performance limits remain a
planning/implementation decision if measured workloads require them.

**Constraints**: Follow the feature 001 pre-note ordering and authoritative
dependency inventory; never treat resolver availability as proof of
authorization. Feature 002 owns profile semantics, defaults, and schema
constraints; Feature 003 owns parser/normalizer/validator integration and
filesystem checks. Never use the plugin directory as the vault, execute
paths/content, bypass OS controls, install dependencies automatically,
send off-device telemetry, or use a source-checkout/current-directory
fallback for packaged resources. Writes must recheck the target immediately
before replacement, avoid leaving a partially written note, preserve
round-trippable text, warn before documented conversion, and stop on
undecodable content. Multi-note work stops at the first failure without
rollback.

**Scale/Scope**: One campaign/group context per vault; profile, operation,
and per-note result semantics are bounded by Feature 003. Shared-campaign
selection and campaign-state storage remain out of scope. The spec defines
no maximum vault size, batch size, or operation duration; do not imply
unmeasured capacity guarantees.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
| --- | --- | --- |
| Preserve the plugin architecture | Keep the current root plugin layout; package future scripts/resources within an actual skill; add no placeholder integration or agent. | PASS |
| Keep the campaign vault separate | Obtain the vault from explicit/workspace context; store only user configuration and campaign data in the vault; keep schema/runtime resources in the plugin. | PASS |
| Preserve continuity and user control | Preserve existing organization and edits; require scoped previews for broad changes; refuse uncertain or conflicting writes. | PASS |
| Respect character knowledge and player safety | Maintain preparation/actual-play distinction and the Feature 001 player-facing checks. | PASS |
| Distinguish proposals from implemented behavior | Label all runtime, schema packaging, and validation behavior as proposed until installed-client and runtime validation succeeds. | PASS |

No constitution violations require justification.

## Project Structure

### Documentation (this feature)

```text
specs/003-powershell-runtime-safety/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── powershell-runtime-contract.md
```

### Source Code (repository root)

```text
No runtime source is added in this planning phase.

Future consumer component selected by this plan:
skills/
└── vault-orientation/
    ├── SKILL.md
    ├── VAULT-REFERENCE.md
    ├── assets/
    │   └── dmassist.schema.json
    └── scripts/
        └── [future PowerShell operations, introduced only with an implementation task]
```

**Structure Decision**: Keep Feature 003's deliverables in its spec directory.
The current repository has no PowerShell scripts, runtime loader, or test
suite, so this phase adds no code or plugin component. For the future
consumer, keep the canonical Feature 002 schema with the existing
`vault-orientation` skill rather than relying on a free-standing root schema
directory or sibling-skill traversal. Reconcile Feature 002's schema
references and the architecture/README documentation to this packaged
location when the implementation tasks move/package the artifact; preserve
one canonical schema rather than maintaining a second copy.

## Complexity Tracking

No constitution violations.
