# Implementation Plan: PowerShell Runtime and Safe Operations

**Branch**: `003-powershell-runtime-safety` | **Date**: 2026-10-29 | **Spec**: `specs/003-powershell-runtime-safety/spec.md`

**Input**: Feature specification from `specs/003-powershell-runtime-safety/spec.md`, scoped by GitHub issue [#4](https://github.com/sylvercode/dm-assistant/issues/4).

## Summary

Define implementable, testable contracts for PowerShell-backed vault
operations in the Agent Plugins 1.0 scaffold. The design covers supported runtime prerequisites, explicit operation inputs
and structured results, the Feature 001 pre-note and exact-vault authorization
gate, Feature 002 profile parsing/normalization/schema validation, installed
plugin resource discovery, vault-contained paths, and preview/conflict-safe
atomic note writes. The canonical profile schema will be packaged with its
current consuming skill at `skills/vault-orientation/assets/dmassist.schema.json`;
Feature 002 remains authoritative for its meaning and constraints.

The runtime modules now exist with local synthetic coverage. Feature 001
defines the note-content-free `get_server_info` signal, but the PowerShell
runtime cannot verify a trusted handoff from the active session. Script-backed
vault access therefore remains blocked. Acceptance uses two tiers:
production-gate tests that expect a readiness or authorization block, and
downstream tests that use a harness-injected, test-only authorization provider.
The test provider never establishes a production handoff. Issue
[#7](https://github.com/sylvercode/dm-assistant/issues/7) tracks Resolver
integration; task T047 tracks the remaining runtime handoff.

## Technical Context

**Language/Version**: PowerShell 7 (`pwsh`) for future script-backed skills.
The exact stable release and per-OS support matrix are selected, dated, and
recorded in `docs/powershell-runtime-support.md` when the dependency set is
validated for implementation (T001). Selection criteria: the latest stable
PowerShell 7 release at selection time; an OS/runtime/add-on combination is
listed as supported only after it passes the prerequisite, repeatability,
and failure checks and can reliably perform the path-resolution,
atomic-replace, and encoding checks the contract requires; every other
combination is documented as unsupported. Workflows never install or upgrade
prerequisites.

**Primary Dependencies**: `powershell-yaml` for YAML parsing and
normalization; the built-in `Test-Json -Schema` cmdlet (PowerShell 7.4 or
later, backed by `JsonSchema.Net`) as the Draft 2020-12 validator, so no
separate validator module is required. The selected exact versions and
selection date must be recorded alongside release support guidance. The required
`obsidian-link-resolver` dependency remains governed by Feature 001's
authoritative inventory and requires separate exact-vault authorization.
Test-only: Pester 6, whose `*.Tests.ps1` convention the task list already
follows, pinned to an exact version in T002. It is never a prerequisite for plugin installation or a DM's
workflow, and its exact version and supported PowerShell versions are
confirmed when selected.

**Storage**: User-owned `.dmassist.yaml`, Markdown notes, and references stay
in the explicitly authorized campaign vault. The profile-validation schema
is a plugin-owned skill asset at
`skills/vault-orientation/assets/dmassist.schema.json`; it is not campaign
data. Per-note temporary write files, if used, must be created on the target
filesystem and removed after successful replacement or a handled failure.
Test fixtures are invented, disposable data under `tests/powershell/`, and
sanitized verification evidence lives in `docs/powershell-runtime-support.md`;
neither contains campaign content.

**Testing**: The PowerShell acceptance harness under `tests/powershell/`
(T002) uses only synthetic, disposable vault fixtures, in two tiers:

1. **Production-gate tests** run the real preflight with no authorization
   provider. They expect `PREREQUISITE_MISSING` for unconfirmed readiness or,
   with readiness simulated, `VAULT_AUTHORIZATION_UNPROVEN` before any profile,
   guidance, or note access and before any write (T008).
2. **Downstream tests** (profile parse/normalize/schema, path containment,
   preview, safe write, conflict, interruption, partial completion) reach
   their behavior through a test-only authorization provider that only the
   harness injects through an explicit parameter. It is never discoverable by
   production code, appears in no skill, and does not prove that the runtime
   can verify Feature 001's signal.

Schema tests cover valid and invalid normalized profiles. A static audit of
`skills/vault-orientation/scripts/` rejects dynamic execution, non-literal
path parameters, network APIs, and any reference to `tests/` (T034). Runs in
every claimed supported environment, installed Copilot CLI plugin/resource
checks from multiple working directories, and the check that the installed
plugin excludes `tests/` or gains no authorization bypass from it (T046) are
recorded as sanitized evidence in `docs/powershell-runtime-support.md`.
The Pester 6.2.0 runner now exists at `tests/powershell/Invoke-Tests.ps1`;
`AGENTS.md` documents its command, and constitution 1.0.1 records the matching
Development Workflow amendment. No build or lint command is defined.

**Target Platform**: GitHub Copilot CLI Agent Plugin installed on Windows,
macOS, and Linux only where the selected PowerShell runtime and required
modules are supported and verified. Unsupported combinations must be
documented; installation and discovery of the static plugin must not require
PowerShell.

**Project Type**: Agent Plugins 1.0 plugin with locally tested runtime
foundations. Scripts and bundled
resources belong to an actual skill component, not a new root-level
runtime/integration or placeholder plugin component. The
`tests/powershell/` harness and `docs/powershell-runtime-support.md` are
repository-level development and support artifacts, not plugin components.

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
supported round-trippable text exactly, and stop on unsupported or
undecodable content. Note encodings are never converted. Multi-note work stops at the first failure without
rollback. Use `-LiteralPath` for every filesystem cmdlet and never pass paths
or content to `Invoke-Expression`, `[scriptblock]::Create`, or
`-Command`/argument strings (contract section 3; audited by T034). The
test-only authorization provider is injected only by the test harness;
production preflight never discovers or accepts a provider from a path,
environment variable, or configuration, and production modules never
reference `tests/`.

**Scale/Scope**: One campaign/group context per vault; profile, operation,
and per-note result semantics are bounded by Feature 003. Shared-campaign
selection and campaign-state storage remain out of scope. The spec defines
no maximum vault size, batch size, or operation duration; do not imply
unmeasured capacity guarantees.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
| --- | --- | --- |
| I. Preserve the plugin architecture | Keep the current root plugin layout; package future scripts/resources within an actual skill; add no placeholder integration or agent. The `tests/powershell/` harness and support document are repository-level, add no `plugin.json` field or plugin component, and T046 verifies the installed plugin excludes `tests/` or gains no authorization bypass from it. | PASS |
| II. Keep the campaign vault separate | Obtain the vault from explicit/workspace context; store only user configuration and campaign data in the vault; keep schema/runtime resources in the plugin. Fixtures and evidence are invented and sanitized, never campaign content. | PASS |
| III. Preserve continuity and user control | Preserve existing organization and edits; require scoped previews for broad changes; refuse uncertain or conflicting writes. | PASS |
| IV. Respect character knowledge and player safety | Maintain preparation/actual-play distinction and the Feature 001 player-facing checks. | PASS |
| V. Distinguish proposals from implemented behavior | Identify locally implemented runtime and packaging separately from unverified installed-client and production behavior; claim no check ran until it does. | PASS |
| Plugin and Vault Constraints | Keep reusable guidance in skills, add no integration without an implementation, keep credentials and campaign content out of the distributed plugin, and do not restructure a vault without authorization. | PASS |
| Development Workflow | Pester 6.2.0 acceptance runner documented in `AGENTS.md`; the separate constitution 1.0.1 PATCH records the matching test command. No build or lint command exists. | PASS |

Post-design re-check (2026-10-29, after the Phase 1 artifacts and task list):
all gates still pass. The task list adds no placeholder component, and the
one follow-up, the Development Workflow wording, is tracked in T044. No
constitution violations require justification.

## Project Structure

### Documentation (this feature)

```text
specs/003-powershell-runtime-safety/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/
│   └── requirements.md
└── contracts/
    └── powershell-runtime-contract.md
```

### Source Code (repository root)

```text
Implemented layout (production vault access remains authorization-gated):
skills/
└── vault-orientation/                  # installed plugin component
    ├── SKILL.md
    ├── VAULT-REFERENCE.md
    ├── assets/
    │   └── dmassist.schema.json        # moved from schemas/ by T015
    └── scripts/                        # PowerShell modules, T003-T041

tests/
└── powershell/                         # synthetic acceptance harness, T002-T035

docs/
└── powershell-runtime-support.md       # support matrix and evidence, T001
```

**Structure Decision**: Keep design artifacts in the spec directory and runtime
modules in the existing skill. Keep the canonical Feature 002 schema with the
existing
`vault-orientation` skill rather than relying on a free-standing root schema
directory or sibling-skill traversal. Reconcile Feature 002's schema
references and the architecture/README documentation to this packaged
location when the implementation tasks move/package the artifact (T015);
preserve one canonical schema rather than maintaining a second copy. Keep the
acceptance harness and its test-only authorization provider in
`tests/powershell/`, outside every skill, and keep the support matrix and
verification evidence in `docs/powershell-runtime-support.md`. Neither is a
plugin component and neither adds a `plugin.json` field. Because the
repository root is the installable plugin, production modules must never
reference `tests/`, and T046 verifies the installed plugin excludes it or
gains no authorization bypass from it.

## Complexity Tracking

No constitution violations.
