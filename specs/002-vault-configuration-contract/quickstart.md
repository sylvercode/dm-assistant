# Vault Configuration Contract: Future Validation Guide

**Status: Design-only.** This guide describes how a future implementation
should be prepared and validated. The repository is an empty Agent Plugins 1.0
scaffold: it has no vault-profile loader, discovery workflow, runtime scripts,
or test suite. Nothing in this guide is currently runnable, and the contract
must not be treated as implemented behavior.

## Before implementation

1. Use an isolated fixture vault, not the plugin directory or a real campaign
   vault. The authorized vault must come from explicit workspace context or
   user input; no test should infer it from the plugin installation.
2. Use the version-1 schema and validation rules defined in the
   [configuration contract](contracts/vault-configuration-contract.md) as the
   implementation target. No additional contract decisions are pending in this
   guide.
3. This feature does not select a parser or runtime. Issue #4 owns reader
   selection, PowerShell/module versions, platform support, provisioning, and
   executable runtime tests. There is no current loader or command to run.
4. Use the scenarios below as schema acceptance coverage. Once Issue #4
   provides a reader, run them as integration tests and add the test command
   alongside that implementation.

## Scenario setup and expected outcomes

Use deterministic fixture contents and assert both the result and the absence
of unauthorized changes. These scenarios map to the measurable outcomes in
the [spec](spec.md) and the detailed rules in the
[configuration contract](contracts/vault-configuration-contract.md); they
summarize test intent rather than restating the schema.

| Scenario | Fixture/action | Deterministic expected outcome |
| --- | --- | --- |
| Valid profile resolution | In the fixture vault, create `.dmassist.yaml` using the version-1 schema defined in the configuration contract. Create each explicitly mapped built-in and custom section directory. Include a custom section with a purpose description, a custom template type, and, if tested, existing party, preparation, guidance, and template references. Resolve twice against the unchanged fixture. | Validation succeeds; configured mappings, custom-section descriptions, and custom template types are available to workflows, omitted built-in settings resolve only to documented defaults/candidates, and both resolutions return identical settings and canonical in-vault boundaries. No note content or vault structure changes. |
| Unconfigured, read-only discovery | Remove the profile. Provide conventional folders plus root-level adventure candidates and unrelated root content; request discovery only. | Discovery reports existing evidence and missing sections, does not call every root item an adventure, and creates or modifies no file, folder, or profile. |
| YAML reader/schema integration | With the reader selected under Issue #4, test its supported YAML syntax and scalar conversion, along with duplicate keys, unknown fields, invalid mapping shapes, explicit nulls, empty values, and malformed input. | Reader-supported syntax is parsed according to its documented behavior; the resulting profile is accepted only if it satisfies this schema. Duplicate keys, unknown fields, parser errors, nulls, empty values, and invalid field values fail clearly before dependent work. No partial settings or fallback discovery; no files change. |
| Missing, invalid, or unsupported version | Test a missing version, a non-integer/invalid version, and a syntactically valid newer unsupported version. | Each profile is rejected with a version-specific error. The newer profile is not interpreted under version-1 rules, and no dependent operation proceeds. |
| Vault boundary, including symlink | Test a traversal/absolute path and a vault-local symlink whose resolved target is outside the authorized root. Also include a symlink resolving within the root as a control case. | Escaping paths are rejected before outside-target access or modification; the in-vault symlink is accepted only if all other checks pass. A textual path prefix is not sufficient proof of containment. |
| Missing explicitly configured section folder | Configure one section to a non-existent path while other configured paths are valid. | The entire profile is rejected and identifies the missing mapping. No folder is created, no partial profile is used, and no discovery fallback replaces the rejected setting. Omitted conventional defaults remain optional candidates. |
| Custom section identification | Configure a custom section with a valid identifier, existing in-vault path, and concise description of its use. Then test an invalid identifier and a missing description. | A valid section is available by identifier, and its description is used only as classification context; it does not automatically classify every contained note or grant permission. Invalid identifiers, missing/extra fields, or a missing explicitly mapped folder reject the profile with a clear error. |
| Custom template type | Register a custom template identifier under `templates.custom`, then request an article of that type. Test a duplicate built-in identifier and a missing or unreadable custom template. | A valid custom type selects its configured vault template. Invalid or conflicting identifiers fail validation; an unavailable template stops the dependent operation, with no silent fallback to a built-in plugin template. |
| Optional versus explicitly configured missing guidance/template | First omit guidance and template overrides and omit the optional default guidance file. Then separately configure a missing guidance path and a missing template override and request the dependent operation. | Absence of the optional default guidance candidate does not invalidate the profile. An explicitly configured unavailable guidance file stops work that requires it; an explicitly configured unavailable template stops that article operation and is not silently replaced. A plugin default is eligible only when no override was explicitly configured and that default exists. |
| Overlapping section mappings | Map two section keys to the same directory, then test nested directories. Request a task whose note classification or destination cannot be determined from the request and evidence. | Both profiles pass overlap validation. The unresolved operation pauses for DM clarification and makes no write; overlap does not imply that every contained note belongs to either section. |
| Ambiguous unconfigured discovery | Create two plausible candidates for one section. Test a clearly stronger candidate, then an equal-evidence tie. | Discovery selects the strongest candidate and reports that the choice is inferred, its evidence/reason, and the alternatives. For equal evidence, it uses the contract's stable lexicographic path tie-break and reports the tie. It continues read-only; the inference does not authorize edits. |
| Stale state requires revalidation | Validate a profile, then change the profile or a referenced guidance/template file or path before a dependent operation completes. | The affected operation stops, identifies the changed dependency, and requires revalidation before retry. It does not automatically retry, mix old and new inputs, or write using stale state; it rechecks the vault boundary before further access. |

## Coverage and implementation handoff

- The no-profile and mutation assertions cover **SC-001** and the preservation
  promise in **SC-004**.
- The accepted/rejected field, YAML, version, path, dependency, and state-change
  cases provide implementation coverage for **SC-002**, **SC-003**, and
  **SC-005**.
- Keep preparation separate from actual-play outcomes and keep player-facing
  handouts free of DM-only facts as independent workflow safeguards; a passing
  configuration test does not authorize content edits or disclosure.
- Issue #4 must supply the reader/runtime test command, fixtures, and supported
  runtime/dependency record. Until then, these are schema-level expected
  outcomes, not evidence that a reader or runtime behavior has passed.

See [plan](plan.md), [research](research.md), and [data model](data-model.md)
for the proposed runtime and design details. See the repository
[README](../../README.md) and [architecture](../../docs/architecture.md) for
the current scaffold boundaries: neither provides a configuration runtime.
