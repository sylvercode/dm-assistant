# Implementation Plan: Vault Configuration Contract

**Branch**: `sylvercode-vault-configuration-contract` | **Date**: 2026-10-25 | **Spec**: `specs/002-vault-configuration-contract/spec.md`

**Input**: Feature specification from `specs/002-vault-configuration-contract/spec.md`

## Summary

Define an optional, versioned `.dmassist.yaml` contract for one authorized
campaign vault, including conventional section defaults, active group context,
preparation location, guidance paths, template overrides, strict YAML
validation, and vault-contained path resolution. Ship both the written
configuration contract and a machine-readable JSON Schema for the normalized
version-1 profile. The profile describes user-owned organization and must not
migrate or duplicate campaign content. The JSON Schema validates structural
and value constraints; it does not parse YAML, apply defaults, or check
filesystem state. This feature does not select or provision a YAML reader or
implement a runtime loader; parser selection, scalar normalization, JSON
Schema validator integration, and filesystem-dependent checks belong to
Issue #4, “Establish the PowerShell runtime and safe operation contracts.”

## Technical Context

**Language/Version**: N/A for this design-only schema feature. Runtime language
and version are owned by Issue #4.

**Primary Dependencies**: JSON Schema Draft 2020-12 is the dialect for the
machine-readable version-1 profile schema. This is a contract-artifact choice,
not a runtime dependency selection. Issue #4 will select and record the YAML
reader, scalar-normalization behavior, validator implementation, and runtime
dependencies.

**Storage**: `.dmassist.yaml` and referenced Markdown/files in the authorized
vault; plugin-owned defaults remain in the installed plugin. No campaign data
is copied into the profile.

**Testing**: No repository build, test, or lint commands exist in this
scaffold. As a design-artifact verification, validate the schema against the
Draft 2020-12 meta-schema and representative valid/invalid normalized-profile
instances from `quickstart.md` using a standards-compliant validator. This
one-off verification does not add a repository/runtime dependency or imply a
loader exists. Treat YAML parsing, duplicate-key detection, scalar
normalization, validator integration, and path-boundary behavior as future
runtime/integration work owned by Issue #4.

**Target Platform**: Not specified for the schema. Runtime platform support is
owned by Issue #4.

**Project Type**: Agent Plugins 1.0 documentation-and-metadata scaffold; this
feature's deliverables are the proposed user-facing configuration contract,
machine-readable profile schema, and validation outcomes, not a reader or
runtime implementation.

**Performance Goals**: No numeric performance target. Configuration resolution
must be deterministic for unchanged vault and profile state.

**Constraints**: Vault location must come from explicit user/workspace context.
Every configured path is vault-relative and its resolved target must remain
within the vault. No folder creation, migration, content execution, silent
fallback, or permission broadening. Explicitly configured section folders must
exist; overlapping mappings remain valid but do not determine note
classification. The JSON Schema validates normalized profile structure and
values; its `default` annotations document defaults but do not apply them.
YAML parsing, duplicate-key rejection, scalar normalization, filesystem
existence and boundary validation, and stale-input handling remain Issue #4
runtime responsibilities. Every future profile/discovery workflow must follow
the Spec 001 vault-facing preflight: establish the authorized vault and verify
required dependency readiness (initially `obsidian-link-resolver`/
`resolve_obsidian_link` and `get_server_info` at version 2.1.0 or later) and
vault authorization separately before profile-dependent or campaign-note
access; profile contents cannot establish or expand authorization. A present
default guidance candidate that is
unreadable, invalid, or unavailable blocks dependent interpretation or note
work rather than being silently skipped.
Stop and revalidate when the profile, referenced guidance or template, or a
relevant path changes during a dependent operation.

**Scale/Scope**: One active campaign/party per vault; six conventional section
mappings, optional custom sections with descriptions, preparation, guidance,
and per-article template settings. Shared-campaign selection and
campaign-state storage are out of scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
| --- | --- | --- |
| Preserve the plugin architecture | Do not add placeholder plugin components or change the root plugin layout for a design-only feature. | PASS |
| Keep the campaign vault separate | Resolve the vault only from explicit context; keep the profile and campaign content in the vault. | PASS |
| Preserve continuity and user control | Do not migrate/restructure content; inferred discovery is read-only; edits remain subject to approval safeguards. | PASS |
| Respect character knowledge and player safety | Keep preparation distinct from actual play; keep player handouts separate from DM-only content. | PASS |
| Distinguish proposals from implemented behavior | Label all planned loader/runtime behavior as a contract proposal; no existing runtime capability is claimed. | PASS |

No constitution violations require justification.

## Project Structure

### Documentation (this feature)

```text
repository-root/
├── skills/vault-orientation/assets/
│   └── dmassist.schema.json   # moved from schemas/ by Feature 003 T015
└── specs/002-vault-configuration-contract/
    ├── plan.md
    ├── research.md
    ├── data-model.md
    ├── quickstart.md
    └── contracts/
        └── vault-configuration-contract.md
```

### Source Code (repository root)

```text
No source code is added by Feature 002. Feature 003 implements the loader and
validation modules under skills/vault-orientation/scripts/ with a synthetic
acceptance harness under tests/powershell/. Production access and installed
client/platform qualification remain blocked or unverified.
```

**Structure Decision**: Keep this phase within the feature's specification
directory. It defines the configuration interface and validation expectations
with a written contract and a Draft 2020-12 schema artifact, without adding a
skill, script, hook, integration, or reader implementation to the empty
scaffold. Schema validation operates on the normalized profile structure;
parser selection and runtime work are explicitly deferred to Issue #4.

**Schema resource location**: The canonical schema now lives at
`skills/vault-orientation/assets/dmassist.schema.json`, packaged with its
consuming skill. Feature 003 (Issue #4, task T015) moved it there from the
provisional repository-root path `schemas/dmassist.schema.json`, which no
longer exists, and its installed resource lookup locates it independently of
the working directory. The original planning rationale follows: the
repository-root path was a source location for this design artifact, not a
confirmed installed-plugin resource path. Agent Plugins 1.0 documents recognized
component locations and resources bundled with skills, but does not establish
that an arbitrary root-level schema directory will be included or discoverable
after installation. Issue #4 must choose the final location alongside the
skill/runtime component that consumes the schema and verify that the installed
plugin includes it and that the loader can locate and use it.

## Complexity Tracking

No constitution violations.
