# Implementation Plan: Vault Configuration Contract

**Branch**: `002-vault-configuration-contract` | **Date**: 2026-10-25 | **Spec**: `specs/002-vault-configuration-contract/spec.md`

**Input**: Feature specification from `specs/002-vault-configuration-contract/spec.md`

## Summary

Define an optional, versioned `.dmassist.yaml` contract for one authorized
campaign vault, including conventional section defaults, active group context,
preparation location, guidance paths, template overrides, strict YAML
validation, and vault-contained path resolution. The profile describes
user-owned organization and must not migrate or duplicate campaign content.
This feature defines the schema and observable validation behavior only. It
does not select or provision a YAML reader or implement a runtime loader;
parser selection, dependency provisioning, and reader integration belong to
Issue #4, “Establish the PowerShell runtime and safe operation contracts.”

## Technical Context

**Language/Version**: N/A for this design-only schema feature. Runtime language
and version are owned by Issue #4.

**Primary Dependencies**: None selected by this feature. The runtime
implementation under Issue #4 will select and record parser dependencies.
Schema validation requirements are documented here independently of the
implementation.

**Storage**: `.dmassist.yaml` and referenced Markdown/files in the authorized
vault; plugin-owned defaults remain in the installed plugin. No campaign data
is copied into the profile.

**Testing**: No build, test, or lint commands exist in this scaffold. This plan
defines schema-level acceptance scenarios; the reader/runtime implementation
must add executable parser, schema-validation, and path-boundary tests.

**Target Platform**: Not specified for the schema. Runtime platform support is
owned by Issue #4.

**Project Type**: Agent Plugins 1.0 documentation-and-metadata scaffold; this
feature's deliverable is the proposed user-facing configuration schema and
validation outcomes, not a reader or runtime implementation.

**Performance Goals**: No numeric performance target. Configuration resolution
must be deterministic for unchanged vault and profile state.

**Constraints**: Vault location must come from explicit user/workspace context.
Every configured path is vault-relative and its resolved target must remain
within the vault. No folder creation, migration, content execution, silent
fallback, or permission broadening. Explicitly configured section folders must
exist; overlapping mappings remain valid but do not determine note
classification. Stop and revalidate when the profile, referenced guidance or
template, or a relevant path changes during a dependent operation. Reader and
runtime mechanics are specified by Issue #4.

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
specs/002-vault-configuration-contract/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── vault-configuration-contract.md
```

### Source Code (repository root)

```text
No source code is added by this planning phase. If implemented later, scripts
and reusable guidance belong with an actual skill under skills/<skill-name>/;
the repository currently has no runtime loader or test suite.
```

**Structure Decision**: Keep this phase within the feature's specification
directory. It defines the configuration interface and validation expectations
without adding a skill, script, hook, integration, or reader implementation to
the empty scaffold. Parser selection and runtime work are explicitly deferred
to Issue #4.

## Complexity Tracking

No constitution violations.
