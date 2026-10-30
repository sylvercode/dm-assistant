# Feature 003 Validation Guide

**Status: Future implementation validation plan — no PowerShell runtime,
profile loader, or automated vault operation is implemented by this guide.**

Use this guide when implementing and validating Feature 003. Its scenarios
describe expected behavior, not commands that can be run against the current
plugin. The current repository is a static Agent Plugins 1.0 scaffold. Do not
use a real campaign vault for these checks: all test profiles, notes, paths,
and campaign/group names must be synthetic and disposable.

## Prerequisites and scope

Before testing a future script-backed operation:

- Confirm the release documents the supported Windows, macOS, and Linux
  combinations, exact PowerShell 7 (`pwsh`) and add-on versions, selection
  date, and how to obtain prerequisites. Do not install or upgrade them as
  part of a workflow test.
- Use only a release-supported environment with the declared runtime and
  operation-specific modules available. Profile tests require the selected
  YAML reader and a JSON Schema Draft 2020-12 validator.
- Use an isolated synthetic vault fixture with a disposable outside-boundary
  directory. Include only invented data; take before/after inventories or
  byte snapshots to verify that blocked and read-only scenarios do not write.
- Test the exact-vault dependency gate. The initial Feature 001 dependency is
  `obsidian-link-resolver` 2.0.0 or later with `resolve_obsidian_link`;
  readiness and authorization for the exact vault are separate checks. The
  note-content-free authorization signal is not yet defined. Until it is
  documented and verifiable, tests of the production preflight must expect a
  `VAULT_AUTHORIZATION_UNPROVEN` block before profile, guidance, or
  campaign-note access. Scenarios below that reach profile, path, preview, or
  write behavior run in an "authorized synthetic fixture" through the
  test-only authorization provider that only the harness injects. That
  provider never proves that Feature 001's signal exists and must not be
  present in, or reachable from, the installed skill.

The eventual transport, operation names, and test-runner commands have not
been selected. The criteria below are executable acceptance criteria for a
future harness; they are not shell commands or a proposed universal CLI.

## Verify the installed plugin and packaged schema

Use only the current repository-documented local plugin installation steps.
With GitHub Copilot CLI installed, from the repository root:

```shell
copilot plugin install .
copilot plugin list
```

Confirm the plugin is listed as `dm-assistant`. In a new interactive session,
check component discovery with `/agent` and `/skills list`; `vault-orientation`
should be listed. These checks verify static plugin installation and discovery
only. They do not prove that a PowerShell runtime, scripts, profile loader, or
vault authorization gate exists.

The Feature 003 contract names one future canonical packaged schema location:
`skills/vault-orientation/assets/dmassist.schema.json`. The current scaffold
does not yet contain that packaged asset, so this check is a future
implementation/packaging acceptance test, not a claim that the current
installation has passed it.

For the future installed-client test:

1. Reinstall the local plugin after packaging changes, then use an installed
   fixture and the owner-skill resource mechanism to locate the schema at the
   canonical path. Do not use the source checkout, vault, or current working
   directory as a fallback.
2. Launch equivalent profile-validation requests with the process starting in
   two different working directories, neither being the plugin directory or
   the synthetic vault. Both must identify/load the same installed artifact
   and produce the same validation outcome for identical input.
3. Demonstrate that this artifact is actually used: a valid synthetic
   version-1 profile passes the installed Draft 2020-12 validation, while an
   otherwise identical profile with a schema-invalid value is rejected as
   `PROFILE_SCHEMA_INVALID`. Record the artifact identity (for example,
   digest) in test evidence; do not emit profile or note contents.
4. In a separate fixture, remove or make the installed artifact unavailable,
   then verify profile-dependent work stops with `RESOURCE_MISSING` before
   profile settings are used. An incompatible artifact must stop with
   `RESOURCE_INCOMPATIBLE`. Neither case may fall back to a checkout, vault,
   or current-directory copy.

Source-tree presence alone is insufficient evidence. The test passes only
when the installed consumer loads and validates against its one packaged
canonical artifact from both starting directories.

## Representative acceptance scenarios

Each scenario should capture the structured result, target inventory, and
relevant synthetic fixture state. Results use the Feature 003 contract fields
in order: `operation`, `completionStatus`, `completionCode`, `changedTargets`,
`unchangedTargets`, `remainingWork`, and `errorDetails` when present. Do not
record full note contents in diagnostics.

| Area | Synthetic setup and action | Expected result |
| --- | --- | --- |
| Runtime/dependency/authentication gate | Exercise a missing or unsupported runtime/module, a missing or incompatible declared dependency, and an unavailable or inconclusive exact-vault authorization signal separately. Attempt a vault-facing operation in each case. | Each attempt is `not completed`, with `PREREQUISITE_MISSING` for runtime/module/dependency readiness failures or `VAULT_AUTHORIZATION_UNPROVEN` for exact-vault authorization failure. No profile, guidance, or campaign-note access; no writes; no prerequisite auto-install or upgrade. Resolver/tool presence alone never proves exact-vault authorization. |
| Profile parse and normalization | In the authorized synthetic fixture, test a valid profile plus malformed YAML, duplicate mapping keys, unsupported/invalid version, unknown field, explicit null, collection in a string field, and supported boolean/numeric/date-time scalars in string-valued fields. | Invalid YAML/duplicate keys return `PROFILE_PARSE_INVALID`; normalization failures return `PROFILE_NORMALIZATION_INVALID`. Valid supported scalars normalize to non-empty locale-independent strings, booleans lowercase, dates/timestamps ISO 8601, and version remains integer `1`. Invalid profile settings are never used. |
| Schema and defaults | Validate the normalized valid profile against the installed canonical schema. Also test a schema-invalid normalized profile and omitted settings. | Valid normalized profile passes the canonical Draft 2020-12 artifact. Invalid profile returns `PROFILE_SCHEMA_INVALID`. Apply only Feature 002's contract defaults for omitted values; schema `default` annotations do not mutate or populate the source profile. |
| Filesystem/reference validation | Test explicitly configured section folders that exist and are missing, plus required configured guidance/template/party/preparation references with wrong type, unreadable, or missing states. Also test omitted conventional folders. | Explicit invalid section directory rejects the entire profile with `PROFILE_FILESYSTEM_INVALID`; invalid required reference returns `REFERENCE_UNAVAILABLE`. No directory is created, no discovery fallback or source substitution occurs. Omitted conventional folders remain optional discovery candidates. |
| Traversal and symlink boundaries | Use synthetic relative paths containing `..`, `.`, backslashes, absolute/drive/URI forms, wildcards, or control characters. Add an intermediate or leaf symlink that resolves outside the synthetic vault, and a symlink that resolves within it. | Invalid lexical paths return `PATH_INVALID`; canonical escapes return `PATH_OUTSIDE_VAULT`, before outside target access. Valid in-vault symlink is allowed only after canonical component-aware containment checks. Repeat boundary checks before each access and immediately before writes; never rely on a string-prefix test. |
| Inferred read-only discovery | Omit `.dmassist.yaml` and provide multiple plausible synthetic section locations. Request a read-only lookup whose conclusion does not depend on uncertain mappings, then separately request work where uncertainty changes the conclusion or next action. | No profile, folder, or note is created. For the first request, report the most likely candidate as inferred, with reason and alternatives, and continue read-only. For the second, stop for DM direction with `AMBIGUOUS_CONTEXT`. An inferred candidate never authorizes edits. |
| Read-only inspect | Request inspection of a valid synthetic target after all applicable pre-note gates pass; compare fixture bytes and inventory before and after. | Result is `complete` / `OK` or `NO_CHANGES` as appropriate; no target changes. It reports stable labeled fields and does not include full note content in error details. |
| Preview and approval | Request a change affecting multiple synthetic notes (or deletion, reorganization, or a broad established-fact change). Inspect the preview, attempt apply without approval, then approve only that exact current preview and apply. Change a target or proposed scope and attempt to reuse the old approval. | Preview writes nothing. Missing, stale, or mismatched approval returns `not completed` / `CONFIRMATION_REQUIRED` and changes nothing. Approval applies only the exact preview; changed inputs, targets, scope, or proposed effect require a new preview and approval. |
| Write-time conflict | Preview a synthetic target, modify it externally after review, then request apply; separately arrange a change between an earlier check and the immediate pre-write check. | The target is not overwritten. Return `not completed` / `TARGET_CONFLICT` when nothing earlier changed, or `partially completed` with `TARGET_CONFLICT` if an earlier target in the same ordered operation was already written. List conflict and later unattempted targets as unchanged and report remaining work. |
| Atomic interruption | Inject a failure/interruption while replacing one synthetic note, and in a multi-note run inject it after an earlier note has completed. | The in-progress note is either fully unchanged or fully replaced, never partially written. Stop at first failure; preserve earlier completed changes, do not roll back, and do not attempt later notes. Use `INTERRUPTED` with `not completed` if no target changed or `partially completed` if earlier targets changed. Report exact changed/unchanged targets and remaining work. |
| Encoding conversion warning | Use synthetic, reliably decodable text whose encoding or line endings cannot be safely preserved. First request the write without conversion acknowledgement, then submit a subsequent request that explicitly acknowledges the warning. | First request returns `not completed` / `ENCODING_CONVERSION_WARNING` with no write. Only after explicit acknowledgement may the write convert to UTF-8 without BOM and LF; unrelated text remains intact. |
| Undecodable content | Use a synthetic note with bytes that cannot be reliably decoded. Request an edit. | Return `not completed` / `ENCODING_UNSAFE`; leave the target byte-for-byte unchanged and do not attempt conversion or write. |
| Multi-note first failure | Prepare at least three synthetic targets in deterministic order. Allow the first target to succeed, force the second to fail, and observe the third. Repeat with the first target failing. | Stop on the first failure; do not attempt later targets and do not undo earlier successful writes. With an earlier successful target, status is `partially completed`; with no successful target, `not completed`. Preserve the specific cause code (for example `WRITE_FAILED`), list changed and unchanged targets exactly, mark later targets `not attempted`, and report remaining work. |

Across all scenarios, verify that inputs are treated as data rather than
commands, there is no telemetry, diagnostics remain on-device, and no
incomplete operation is reported as `complete`. For multi-target writes,
changed and unchanged targets must partition the requested targets in the
documented deterministic order.

## Completion criteria and caveats

Feature 003 is not validated by these written scenarios alone. Before claiming
an implementation is ready, run the future harness in every published
supported environment, verify installed-client resource lookup, and retain
sanitized results for the cases above. Also confirm that the installed plugin
either excludes `tests/` or gains no authorization bypass from it, and that
production preflight still returns `VAULT_AUTHORIZATION_UNPROVEN` when no
harness provider is supplied. Do not claim stronger concurrency
guarantees than the tested filesystem replacement primitives provide. Record
sanitized evidence in the "Verification evidence" section of
`docs/powershell-runtime-support.md`; this quickstart remains a guide only.

The exact runtime/add-on versions, supported platform matrix, installed
resource-loading implementation, runtime transport, operation catalog, and
test-harness commands remain implementation decisions. This guide deliberately
does not invent commands for them. Exact-vault authorization also remains a
blocking contract dependency until Feature 001 defines a note-content-free
signal.
