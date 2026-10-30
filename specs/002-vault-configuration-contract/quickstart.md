# Vault Configuration Contract: Future Validation Guide

**Status: Feature 002 design-validation guide.** This feature defines the
version-1 profile contract and schema, not its runtime. Feature 003 now
implements a loader, validator, reference checks, and read-only discovery with
synthetic acceptance tests. See its
[validation guide](../003-powershell-runtime-safety/quickstart.md) for the
runner and remaining installed-client, platform, and authorization limitations.

## Scope and setup

The canonical schema artifact,
[`skills/vault-orientation/assets/dmassist.schema.json`](../../skills/vault-orientation/assets/dmassist.schema.json), declares
JSON Schema Draft 2020-12 and accepts a normalized JSON-compatible
version-1 profile, not YAML text. The profile's `version: 1` is its
application-level format version, not the schema dialect. Use the written
[configuration contract](contracts/vault-configuration-contract.md) as the
reference for behavior not expressible in JSON Schema.

When a future schema validation harness exists:

1. Validate constructed normalized JSON instances against the shipped schema.
   Do not treat a YAML fixture as direct schema input.
2. Keep fixtures isolated from the plugin installation and any real campaign
   vault. Schema scenarios must not access or modify filesystem paths.
3. Assert both the validation result and, where relevant, that validation has
   not mutated the input instance.
4. Do not invent a current command or runner. Issue #4 owns parser/runtime
   selection, provisioning, and integration test commands.

## Future JSON Schema validation scenarios

These are schema-level cases over normalized objects. For each invalid case,
expect rejection under the published schema; exact validator wording is
implementation-specific.

| Scenario | Normalized instance / assertion | Expected schema outcome |
| --- | --- | --- |
| Minimal valid profile | `{"version": 1}` | Accept. Omitted optional properties remain omitted in the instance. |
| Valid customized profile | Include valid built-in section overrides, a `sections.custom` entry with `path` and non-empty `description`, `party.note`, a valid preparation configuration, `guidance.path`, built-in template overrides, and a `templates.custom` entry. | Accept the normalized profile without inspecting or resolving any path. |
| Required and version constraints | Try `{}`, `{"version": 2}`, `{"version": 1.5}`, `{"version": "1"}`, `{"version": null}`, and a boolean version. | Reject a missing, unsupported, non-integer, or wrong-type version; only numeric integer `1` is valid. |
| Unknown fields at each object boundary | Add an unsupported property at the root and separately within `sections`, a custom section definition, `party`, `preparation`, `guidance`, `templates`, or a custom template map where that object is closed. | Reject each added property. Unknown-property rejection must not be tested only at the root. |
| Custom identifiers and required fields | Test valid custom IDs matching `^[a-z][a-z0-9_]*$`; invalid uppercase, leading digit, hyphen, and empty IDs; built-in section/template name collisions; custom section entries missing either `path` or `description`; and entries with extra fields. | Accept valid new IDs and exact custom section definitions. Reject invalid/colliding IDs, missing required members, and extra members. |
| Custom template values | Test valid custom template IDs mapped to non-empty strings, plus invalid IDs, built-in collisions, empty values, nulls, and non-string normalized values. | Accept valid mappings; reject invalid names and values. No file is opened. |
| Preparation mode conditions | Check `session_section` with no `path` and optional valid `heading`; reject it with `path`. Check `separate_folder` with required `path` and no `heading`; reject missing `path` or present `heading`. Also test a missing or unsupported `mode`, and an empty `preparation` object. | Accept only the declared mode-specific shapes. Omitting the entire `preparation` property receives the effective default at runtime; a present mapping must include `mode`, so `{}` is invalid and does not request that default. |
| Null, empty, type, and shape constraints | Put null, an empty string, a number, boolean, array, or object in representative string-valued locations; put null or the wrong JSON shape in mapping-valued locations. Test `sections: {}` and `templates: {}` as valid empty mappings. | Reject nulls, empty strings, wrong scalar types, and invalid mapping shapes. Accept empty `sections` and `templates` objects as specified. |
| Default annotations are not applied | Inspect schema `default` annotations for built-in section defaults, `sections.custom`, the omitted `preparation` object and its heading, `templates`, and `templates.custom`. Validate instances omitting those properties, then compare the instances before and after validation. | Confirm annotations match the written contract. Validation accepts otherwise valid omissions but does not insert defaults or mutate the instance. In particular, the `preparation` annotation describes the effective default when that property is omitted; it does not permit an empty present mapping. The contract/runtime—not the schema validator—determines effective defaults and optional candidates. |
| Schema/contract consistency | Compare each schema property, required member, type, enum, pattern, unknown-property rule, preparation conditional, and default annotation with the corresponding version-1 contract rule. Include the built-in name exclusions for custom IDs. | Report any mismatch as a schema/contract defect; schema acceptance alone does not replace contract behavior. Do not extend this comparison to YAML parsing or filesystem checks. |

Coverage should account for every structural and value constraint expressible
over the normalized profile, as required by **SC-006**. In particular,
schema tests can establish that path fields are non-empty strings; they cannot
establish that a path is safe, exists, is readable, or remains within a vault.

## Separate Issue #4 integration scenarios

The following are not JSON Schema test cases. Issue #4 owns the future reader,
scalar-normalization layer, validator integration, runtime, and associated
integration tests. These scenarios must remain separate from validation of
normalized JSON instances:

| Responsibility | Future integration scenario | Expected outcome |
| --- | --- | --- |
| YAML parser and syntax | Exercise supported YAML syntax with the reader selected under Issue #4; separately test malformed or unsupported syntax. | Reader behavior follows its documented support; parser failures stop profile loading before dependent work. |
| Scalar normalization | Feed YAML string, boolean, numeric, and date/time scalars in string-valued fields; test locale-independent conversion, lowercase boolean text, ISO 8601 dates/timestamps, explicit nulls, collections, and integer `version: 1`. | Normalize supported scalar values to the contract's required strings before schema validation. Reject explicit nulls and collections in scalar positions; preserve `version` as integer `1`. |
| Duplicate YAML keys | Provide duplicate mapping keys at relevant levels, including cases a parser might otherwise overwrite during object construction. | Detect and reject duplicates during parsing; JSON Schema cannot detect keys already discarded by the parser. |
| Filesystem, vault boundaries, and paths | In an explicitly authorized isolated fixture vault, test configured directory/file existence and readability, invalid relative/absolute/traversal paths, and symbolic links resolving inside and outside the vault. | Enforce existence and component-aware canonical vault containment before access; reject escapes. These are runtime checks, not schema assertions. |
| Stale inputs | Change the profile, a referenced guidance/template input, or a relevant path after validation and before a dependent operation completes. | Stop affected work, identify the change, and require revalidation before retry. Do not mix old and new inputs or proceed on stale validation. |
| Vault-facing preflight | Attempt profile-dependent work or campaign-note access before establishing the vault and separately verifying required dependency readiness and vault authorization, including readiness of `obsidian-link-resolver`/`resolve_obsidian_link` and explicit authorization of the intended vault. Also try to use profile contents to establish or expand authorization. | Block profile and campaign-note access until the Spec 001 preflight succeeds. Treat dependency readiness and vault authorization as distinct checks; never derive or expand authorization from `.dmassist.yaml`. |
| Default guidance candidate unavailable | With no explicit `guidance.path`, provide an absent `.dmassist-guidance.md`, then separately provide a present but unreadable/invalid candidate or make its availability impossible to establish. Request work that depends on vault-local guidance. | Absence alone is optional. If unreadable/invalid or availability cannot be established for dependent work, report the failure and pause dependent interpretation or note work before campaign-note access; do not silently skip the candidate. |

Issue #4 also owns defining the future fixture format and executable test
command. No parser, validator dependency, runtime version, or command is
prescribed here. Profile and discovery workflows must enforce the Spec 001
preflight, including the initial resolver dependency; `.dmassist.yaml` cannot
establish or expand vault or dependency authorization.

## Design safeguards

Future integration coverage must preserve read-only discovery when no profile
is present and must not create or reorganize vault content. Keep preparation
separate from actual-play outcomes, do not silently resolve contradictions or
rewrite run adventure plans, and keep DM-only facts and revealing links out of
player-facing handouts. A passing schema validation is not authorization to
access a path or perform an edit.

See [spec](spec.md), [research](research.md), and [data model](data-model.md)
for feature scope and ownership. The repository
[README](../../README.md) and [architecture](../../docs/architecture.md)
describe the current scaffold; neither provides a configuration runtime.
