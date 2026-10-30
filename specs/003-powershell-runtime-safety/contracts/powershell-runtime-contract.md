# PowerShell Runtime and Safe Operation Contract

**Status: Implemented in locally tested PowerShell modules; production access
and installed-client/platform qualification remain blocked or unverified.**

This contract defines a technology-neutral interface and safety boundary for
script-backed workflows. Modules live within the consuming skill; no universal
CLI, hook, or MCP integration is introduced. Static plugin installation and
discovery remain independent of PowerShell. Feature 003
owns runtime mechanics; Feature 001 owns shared guidance and pre-note policy;
Feature 002 owns profile semantics and the authoritative profile contract.

## 1. Contract boundary and transport

An operation is modeled as a structured request and structured result. Field
names, allowed values, ordering, and code meanings below are stable contract
identifiers. The future implementation may represent these structures as
PowerShell objects, JSON, or another documented format. Choosing a CLI,
command-line argument syntax, standard-output protocol, process exit-code
mapping, or other transport is deferred; none is implied here. Completion
codes are contract values, not process exit codes.

The selected PowerShell 7 runtime and dependency versions, supported
OS/runtime matrix, and provisioning guidance must be recorded for each release.
No operation installs or upgrades PowerShell or add-ons. A vault-facing
operation's declared dependencies include the authoritative Feature 001
inventory, initially `obsidian-link-resolver` 2.0.0 or later with
`resolve_obsidian_link`, plus the profile reader when profile validation is
needed. Profile validation uses the built-in `Test-Json -Schema` cmdlet, so
the supported PowerShell release must be 7.4 or later for JSON Schema Draft
2020-12 support; no separate validator module is required. Readiness
and authorization to the exact vault are separate checks.

## 2. Operation request

Every invocation receives one explicit request. No value may be inferred from
the process working directory, plugin directory, a note, a profile, or
environment-variable/home-directory expansion.

| Field | Requirement |
| --- | --- |
| `contractVersion` | Required string identifying this interface version; current value is `1`. |
| `requestId` | Required caller-generated correlation identifier. It is not an authorization token or a promise of retry/idempotency behavior. |
| `operation` | Required stable identifier registered by the consuming workflow. An operation's name, argument schema, and whether it can change established campaign facts (section 9) must be documented before release; this contract does not invent a CLI command or a universal operation catalog. |
| `vaultRoot` | Required explicit absolute path to the user-designated vault. It is never defaulted to the plugin or current directory. Authorization of this exact root is independently established before any vault read. |
| `campaignGroup` | Required context object with explicit `campaign` and `group` values, or explicit `null` for a value that the requested operation does not use. Required context may not be guessed from note content. |
| `mode` | Required enum: `inspect`, `preview`, or `apply`. `inspect` is read-only; `preview` computes and reports proposed changes without writing; `apply` may write only the requested targets and only under the safeguards below. |
| `arguments` | Required operation-specific data object, including the requested action and any content supplied for it. Its schema is defined by the registered operation. Values are data, never executable instructions or command fragments. |
| `targets` | Required array of explicit vault-relative target paths for the operation; may be empty only when the operation has no file targets. Preserve the operation's declared deterministic order. |
| `approvedPreviewId` | Required for an `apply` that falls under Feature 003 FR-011's preview-and-confirm rule; otherwise omitted. It must identify the exact, still-current preview (section 9) and cannot authorize different targets or changes. |
| `reviewedVersions` | Required with `approvedPreviewId`; otherwise omitted. The ordered per-target entries returned by the approved preview, one per target in `targets` order, each carrying that target's `observedVersion`, `replacementVersion`, and `conversionDecision` (section 9). |
| `reviewedDependencyVersions` | Required with `approvedPreviewId`; otherwise omitted. The ordered dependency entries returned by the approved preview, each carrying a dependency identity and its observed version (section 9); empty only when the preview used no dependency. |
| `declinedReviewId` | Optional; valid only with `mode: apply` and mutually exclusive with `approvedPreviewId`. Identifies a preview (`previewId`) that the DM declined or withdrew. The runtime writes nothing and returns `not completed` / `USER_CANCELLED`. |

Operation-specific input schemas must define whether each field is required,
its type, and its permitted values. Unknown operation arguments must be
rejected rather than interpreted as commands. The runtime validates `vaultRoot`
as a user-designated root; vault-relative path restrictions in section 5 apply
to `targets` and configured references, not to the absolute root input itself.

## 3. Prerequisite and pre-note handoff

Before any profile or campaign-note access, the caller/runtime must complete
these gates in order:

1. Establish the explicit vault root without reading campaign notes or
   assuming the plugin location.
2. Verify each declared runtime dependency's readiness and compatibility, and
   separately verify that it is authorized for this exact vault.
3. Load the plugin-owned shared reference. After the authorization gate, read
   the profile only as needed to determine any designated local guidance;
   load that guidance through its applicable resource/path mechanism. When no
   local guidance is designated, only a specific `inspect` lookup that does
   not depend on uncertain folder or note-role mappings may proceed (FR-023);
   any other request stops before campaign-note access with
   `AMBIGUOUS_CONTEXT`.
4. Establish the required campaign/group and player-facing output context.
5. Only after all preceding gates succeed, access campaign notes as permitted
   by the relevant Feature 001/002 contract.

The current Feature 001 contract requires a note-content-free exact-vault
authorization signal, but no such signal is established in the Feature 003
specification. **Until that signal is documented and successfully verified,
exact-vault authorization is blocked: the operation must return
`VAULT_AUTHORIZATION_UNPROVEN` and must not read the profile, guidance, or any
campaign note, and must not write or create any vault content.** Resolver
availability, a caller-supplied path, or successful link resolution is not
proof of authorization. Production preflight also accepts no authorization
assertion from request fields, paths, environment variables, configuration, or
the profile; a synthetic provider used only by the acceptance harness is
outside this contract and the installed skill and never proves that Feature
001's signal exists. A failed, missing, incompatible, or inconclusive gate
fails closed before profile or note access. Non-vault read-only assistance that is
independent of the blocked operation may remain available.

Installing or discovering the static plugin and its skills does not invoke
PowerShell or install prerequisites. A script invocation must not alter
execution policy, permissions, security software, or other operating-system
controls. Never pass paths or content to `Invoke-Expression`,
`[scriptblock]::Create`, or `-Command`/argument strings; use `-LiteralPath`
for every filesystem cmdlet.

## 4. Installed schema resource

The single canonical packaged schema location for profile-consuming work is:

`skills/vault-orientation/assets/dmassist.schema.json`

The schema belongs inside the installed consuming plugin component. A future
installed loader must locate that resource through the installed plugin/owner
skill resource mechanism, independently of the current working directory, and
validate against that loaded artifact. This path is a proposal for the future
packaged resource; Feature 002 documentation and packaging must be updated
separately. Do not copy a second schema or fall back to a repository checkout,
vault path, or current-directory path. The current source-tree schema location
does not prove that the proposed installed resource exists.

If the resource is missing, unreadable, malformed, incompatible with the
profile contract, or the required Draft 2020-12 validator is unavailable, the
profile-dependent operation stops before using profile settings. Return
`RESOURCE_MISSING`, `RESOURCE_INCOMPATIBLE`, or `PREREQUISITE_MISSING` as
applicable. Installed-client verification must show that the loader locates
and validates against this same packaged artifact from at least two different
working directories; source-tree inspection alone is insufficient.

## 5. Path validation and access

The canonical vault root is resolved from the explicit input only after the
authorization gate. For every supplied or configured vault-relative path:

1. Require a non-empty relative path using `/` separators. Reject absolute
   forms, a leading `/`, backslashes, drive or URI syntax, NUL/control
   characters, wildcard syntax, and any `.` or `..` component.
2. Do not expand variables, home-directory markers, Obsidian links, or other
   expressions. Treat paths and file content strictly as data; never
   interpolate them into a command or execute them.
3. Resolve the path against the canonical vault root, resolving existing
   path components and symbolic links, including intermediate links. Use a
   component-aware containment test, never a textual prefix test.
4. Refuse an unresolved, cyclic, inaccessible, or out-of-bound resolution
   before accessing the target. Return `PATH_OUTSIDE_VAULT` for an
   out-of-bound resolution or when containment cannot be proven (a cyclic or
   unresolvable link chain), and `READ_FAILED` when a path component is
   inaccessible. An in-vault symbolic link is allowed only after its final
   target is verified inside the vault.
5. Recheck the canonical boundary before each access and immediately before
   each write. Do not create a missing target directory or infer a replacement
   target.

If a platform cannot perform the required checks reliably, that environment
must not be claimed as supported for that operation. Path validation must not
invoke an external shell command to resolve an untrusted path.

## 6. Profile validation stages

Profile-dependent work loads `.dmassist.yaml` only at the root of the
explicitly authorized vault and follows Feature 002's authoritative contract.
These stages are distinct, ordered, and all-or-nothing:

1. **Parse:** A selected YAML reader parses the document and rejects malformed
   or unsupported syntax and duplicate mapping keys. Reader versions and
   supported syntax are release prerequisites, not schema semantics.
2. **Normalize:** Convert supported YAML string, boolean, numeric, and
   date/time scalars in string-valued fields into non-empty, locale-independent
   strings. Booleans use lowercase text; dates/timestamps use ISO 8601.
   Reject explicit nulls and collections in scalar positions. Preserve
   `version` as integer `1`; do not coerce it to a string.
3. **Schema validate:** Validate the normalized JSON-compatible object against
   the installed canonical JSON Schema using Draft 2020-12. Reject unknown
   fields, invalid types, unsupported versions, or other schema violations.
   Schema `default` annotations do not mutate or populate the instance.
4. **Resolve defaults:** Only after successful schema validation, apply the
   documented Feature 002 defaults to omitted settings without changing the
   source profile. An invalid present profile is not treated as an absent
   profile and must not fall back to discovery.
5. **Filesystem validate:** Separately resolve configured paths and check
   boundaries, existence, readability, and expected file/directory types
   when required. An explicitly configured built-in or custom section folder
   must already exist; any invalid explicit section path rejects the entire
   profile. Omitted conventional folders remain optional discovery candidates.
   Do not create folders or treat schema success as filesystem validation.

When no profile exists, follow Feature 002's read-only discovery contract.
Where multiple candidates exist, identify the most likely as inferred, state
the evidence and alternatives, and continue only while uncertainty does not
affect conclusions or the next action. Stop and ask the DM once it does.
Inferred candidates never authorize edits. For unchanged profile and
referenced state, resolution must be deterministic. If an input changes during
dependent work, stop, identify it, and require revalidation; do not retry
automatically or mix old and new inputs.

## 7. Result envelope and ordering

Every operation returns the following labeled fields in this order. The
logical field order is normative even if the eventual transport does not
preserve object-member order.

| Order | Field | Shape and meaning |
| --- | --- | --- |
| 1 | `operation` | The request's stable operation identifier. |
| 2 | `completionStatus` | Exactly `complete`, `not completed`, or `partially completed`. |
| 3 | `completionCode` | Exactly one stable code from section 8. |
| 4 | `changedTargets` | Array of vault-relative target records actually changed by this invocation; empty when none. Never include note contents. |
| 5 | `unchangedTargets` | Array of requested vault-relative targets not changed, including failed, conflicted, cancelled, or not-yet-attempted targets when applicable. |
| 6 | `remainingWork` | Array describing uncompleted requested work, in deterministic operation order; empty when no work remains. |
| 7 | `errorDetails` | Omitted only when there is no error; otherwise an object containing `code` (same value as `completionCode`), a concise safe `message`, and optional structured `details`. |

Target records contain a vault-relative path and a stable outcome such as
`written`, `deleted`, `unchanged`, `conflict`, `failed`, or `not attempted`.
Operation-specific target outcomes must be documented before release. Never
include full note text. Error messages must avoid unnecessary campaign
contents, secrets, absolute paths, and raw parser/runtime dumps. Diagnostics
remain on-device; no usage or diagnostic telemetry is sent off-device.

Status rules:

- `complete`: all requested work completed, including an already-satisfied
  read-only or no-change request.
- `not completed`: no requested target was changed and the operation did not
  complete.
- `partially completed`: at least one requested target was changed, but some
  requested work was not completed.

For a multi-target operation, `changedTargets` and `unchangedTargets` must
partition the requested targets. A target not reached after a failure is
unchanged and listed as `not attempted`; its pending work is represented in
`remainingWork`. A no-target operation uses empty arrays. In no case may an
incomplete result use `complete`.

## 8. Stable completion-code taxonomy

Codes are case-sensitive stable identifiers. User-facing messages may be
localized or refined, but a code's meaning and status mapping must not change
within contract version 1.

| Code | Allowed status | Meaning |
| --- | --- | --- |
| `OK` | `complete` | Requested work completed. |
| `NO_CHANGES` | `complete` | Request completed and no target needed changing. |
| `PREREQUISITE_MISSING` | `not completed` | Runtime, required module/dependency, or validator prerequisite is missing or unsupported. |
| `VAULT_AUTHORIZATION_UNPROVEN` | `not completed` | Exact-vault authorization is absent, unavailable, or inconclusive; no profile or campaign-note access is permitted. |
| `VAULT_TARGET_INVALID` | `not completed` | Vault root is missing, ambiguous, inaccessible, or not a valid explicit target. |
| `INVALID_REQUEST` | `not completed` | Required inputs are absent, malformed, or invalid for the registered operation. |
| `PATH_INVALID` | `not completed` | A supplied/configured relative path violates lexical path rules. |
| `PATH_OUTSIDE_VAULT` | `not completed` or `partially completed` | Canonical or symbolic-link resolution escapes the authorized vault or cannot be proven contained (a cyclic or unresolvable link chain), including at the immediate pre-write recheck. |
| `RESOURCE_MISSING` | `not completed` | Required installed plugin resource, including the canonical schema, cannot be found or read. |
| `RESOURCE_INCOMPATIBLE` | `not completed` | Loaded installed resource does not match the required contract or dialect. |
| `PROFILE_PARSE_INVALID` | `not completed` | YAML syntax is malformed/unsupported or contains duplicate mapping keys. |
| `PROFILE_NORMALIZATION_INVALID` | `not completed` | Parsed values cannot be normalized under Feature 002 rules. |
| `PROFILE_SCHEMA_INVALID` | `not completed` | Normalized profile fails the canonical JSON Schema. |
| `PROFILE_FILESYSTEM_INVALID` | `not completed` | During profile validation, a configured path escapes the vault, or a configured section folder is missing or not a folder; the entire profile is rejected (FR-020, FR-021). |
| `REFERENCE_UNAVAILABLE` | `not completed` | A configured guidance file, template, party note, or preparation location needed by the current operation is missing, unreadable, or invalid at use time (FR-023, FR-025). |
| `AMBIGUOUS_CONTEXT` | `not completed` | Uncertainty affects the conclusion or next action and requires DM direction. |
| `CONFIRMATION_REQUIRED` | `not completed` | Required preview approval for the exact proposed changes is absent or does not match. |
| `USER_CANCELLED` | `not completed` | The DM declined or withdrew a preview before apply; a stop signal during apply is `INTERRUPTED`. |
| `ENCODING_UNSAFE` | `not completed` | Text cannot be decoded reliably; no write is permitted. |
| `TARGET_CONFLICT` | `not completed` or `partially completed` | A target or dependency, including a configured reference, changed since the reviewed/validated snapshot and is now a stale input; do not overwrite or continue dependent work. |
| `READ_FAILED` | `not completed` or `partially completed` | An operational read failed; status reflects whether an earlier target changed. |
| `WRITE_FAILED` | `not completed` or `partially completed` | A write failed; use `partially completed` if an earlier target in the same operation changed. |
| `INTERRUPTED` | `not completed` or `partially completed` | Operation was interrupted; status and exact target lists reflect any earlier completed writes. |
| `OPERATION_FAILED` | `not completed` or `partially completed` | Other operational failure; status reflects whether any requested target changed. |

Where two statuses are allowed, use `partially completed` only when an earlier
target in the same operation changed; otherwise use `not completed`.

Configured-path code selection: a lexical violation is `PATH_INVALID`. During
profile validation, a configured path that escapes the vault, or a configured
section folder that is missing or not a folder, is `PROFILE_FILESYSTEM_INVALID`
(FR-020, FR-021). The existence, readability, and type of a configured
guidance file, template, party note, or preparation location are checked only
when an operation needs it, returning `REFERENCE_UNAVAILABLE` (FR-023,
FR-025). A reference verified for the current operation that then changes or
disappears before dependent work finishes is `TARGET_CONFLICT` (FR-024).

The specific cause code is retained when failure occurs after earlier writes:
for example, `WRITE_FAILED` with `partially completed`. Do not replace it with
a generic partial-success code. A release must test every applicable code and
its allowed status.

## 9. Preview, approval, and safe writes

Inspection and preview never write. A preview identifies the exact targets,
proposed operation per target, each target's reviewed `observedVersion`,
`replacementVersion`, and `conversionDecision`, and the reviewed dependency
versions, without including note content in diagnostics. A preview assesses
encoding for every target and stops with `ENCODING_UNSAFE` if any target
cannot be safely preserved. When FR-011 requires approval, `apply` must refer
to that exact preview via `approvedPreviewId`; changed inputs,
targets, proposed changes, or scope invalidate the approval. Approval does not
cover later or additional changes. Clearly requested text edits confined to
one named note do not require redundant broad-change approval.

The runtime keeps no preview state between invocations. A target's
`replacementVersion` is a fingerprint of the complete bytes that would be
written while preserving its supported encoding and original line endings.
The preview's dependency versions fingerprint every
profile, guidance file, template, configured reference, and packaged plugin
resource the runtime reads to construct the proposed change, ordered by
ordinal comparison of their vault-relative path or plugin-resource identity.
Guidance loaded only by the assistant is not fingerprinted; FR-027
re-establishment governs it. `runtimeVersion` is the installed plugin
version combined with a fingerprint of the installed runtime module files, so
a runtime change between preview and apply invalidates the approval.
`previewId` is a deterministic digest (for example SHA-256) of the canonical
serialization of `contractVersion`, `runtimeVersion`, `operation`, the
canonical `vaultRoot`, `campaignGroup`, the ordered `targets`, `arguments`,
each target's reviewed `observedVersion`, `replacementVersion`, and
`conversionDecision`, and the ordered dependency versions. `requestId` and
`mode` are not digest inputs.
Canonical serialization is the RFC 8785 JSON Canonicalization Scheme (JCS)
encoded as UTF-8: object members are sorted by UTF-16 code units at every
nesting level, array order is preserved, and no insignificant whitespace is
emitted. Implementations must not rely on hashtable or dictionary enumeration
order. Fingerprints are for change detection only and are not diagnostic
content.

An approved `apply` supplies `approvedPreviewId`, `reviewedVersions`, and
`reviewedDependencyVersions`, and the runtime checks them in this order:

1. Recompute the digest from the request's fields, the carried versions and
   conversion decisions, and the current `runtimeVersion`; if it does not
   match `approvedPreviewId`, return `CONFIRMATION_REQUIRED`.
2. If a target's or dependency's current version differs from its carried
   reviewed version, return `TARGET_CONFLICT` and identify the changed target
   or dependency without exposing its contents.
3. Rebuild each replacement from the unchanged inputs; if its fingerprint
   differs from the carried `replacementVersion`, the preview no longer
   describes the write, so return `CONFIRMATION_REQUIRED`.
A DM decline or withdrawal is reported through `declinedReviewId` and returns
`USER_CANCELLED` without writing.

Each registered operation declares whether it can change established campaign
facts. The runtime classifies multi-target, deletion, and reorganization
changes itself; approval is required when the operation declares
fact-changing effects or the change cannot be classified. A request cannot
lower the declared classification.

Before each write, revalidate the vault boundary, target identity, and
target/dependency state against the state used to construct the proposed
change: the carried reviewed versions for an approved `apply`, or otherwise
the versions read earlier in the same invocation. If any differs, refuse the
write with `TARGET_CONFLICT`, leave that
target unchanged, stop the multi-target operation, and report exact outcomes.
Rechecking must occur immediately before replacement. Implementations must
not claim stronger concurrency guarantees than their platform primitive
provides; supported platforms must pass tests that mutate a target after
preview and before the final write check.

For each individual note, prepare complete replacement content away from the
live file in a temporary file on the same filesystem, then use a
rename-class atomic replacement. Never truncate and rewrite the live file.
If the safe staging or replacement cannot be performed, fail without exposing
a partially written target. Clean up abandoned staging data when possible.
Atomicity is per note, not across a multi-note operation.

Preserve the existing encoding, line endings, and all unrelated Markdown
text and formatting exactly when preparing each replacement. Supported text
must decode strictly, without replacement characters, as BOM-marked UTF-8 or
UTF-16, or BOM-less UTF-8, and re-encoding with the detected encoding and BOM
must reproduce the original bytes. If decoding is unreliable or the source
bytes do not round-trip exactly, return `ENCODING_UNSAFE` and leave the target
unchanged. Legacy code pages and lossy conversion are unsupported; the runtime
does not convert note encodings. Assess every target before the first write;
`ENCODING_UNSAFE` always uses `not completed`.

For multi-target writes, process targets in the previewed deterministic order.
On the first failure or interruption: stop, do not attempt later targets, do
not roll back earlier completed writes, and report earlier writes as changed,
the failed and unattempted targets as unchanged, and the remaining work. The
currently failing target must remain complete and unchanged, never partially
written.

## 10. Traceability and measurable contract tests

| Contract area | Feature 003 traceability | Required verification |
| --- | --- | --- |
| Runtime support, dependency gates, no auto-install, static plugin discovery | FR-001–FR-005, FR-015, FR-027 | Test every published supported OS/runtime/dependency set; missing or unsupported prerequisites stop before vault access and do not install/upgrade anything. Plugin installation/discovery succeeds without PowerShell. |
| Explicit inputs and working-directory independence | FR-006 | Run the same request from at least two working directories; verify identical vault, campaign/group, and operation selection. Missing/ambiguous targets never fall back to plugin or current directory. |
| Exact-vault block and ordered handoff | FR-004, FR-027 | With authorization missing or inconclusive, assert `not completed` / `VAULT_AUTHORIZATION_UNPROVEN`, zero profile/note reads, zero writes. With gates passing, assert pre-note order and no note access before all checks. |
| Installed schema lookup | FR-019, FR-028 | Installed fixture locates one canonical artifact from two working directories and validates against it; missing/incompatible artifact blocks before profile use, with no checkout/vault/CWD fallback. |
| Path rules and boundary checks | FR-007, FR-021 | Reject every forbidden lexical form before access; reject traversal and symlink escapes before target access; accept only in-vault links after canonical, component-aware checks; recheck before every access. |
| Profile parse/normalize/schema/filesystem separation | FR-016–FR-025 | Independently exercise malformed YAML/duplicate keys, normalized scalar edge cases, schema-invalid profiles, absent-profile discovery, explicit missing directories, reference type/readability, shared or nested section mappings and undetermined destinations (`AMBIGUOUS_CONTEXT`), deterministic defaults, and stale dependencies. Schema defaults alone never mutate input. |
| Result structure and code taxonomy | FR-010 | Verify every result has the fields in the prescribed order, exact status vocabulary, one stable code, safe diagnostics, correct target partition, and no incomplete result marked complete. Exercise each listed code and each allowed status. |
| Read-only, approval, and content-as-data safeguards | FR-008–FR-009, FR-011, FR-014 | Inspection/preview produce zero writes; broad changes require approval of the exact current preview, while a single named-note text edit does not; a target, template, guidance, or profile change after preview makes the old approval fail with `TARGET_CONFLICT`, and a changed request, runtime version, or rebuilt replacement makes it fail with `CONFIRMATION_REQUIRED`; the same preview yields the same `previewId` across separate processes; a DM decline or withdrawal returns `USER_CANCELLED`; command-like note content and paths are never executed or wildcard-expanded; diagnostics omit note bodies and remain on-device. |
| Conflict detection, preservation, and encoding | FR-012–FR-013 | Modify a target after preview and before final write check; verify refusal and no overwrite. Verify supported UTF-8/UTF-16 bytes, line endings, and unrelated text remain intact; unsupported or undecodable text returns `ENCODING_UNSAFE` and remains unchanged. |
| Atomicity and multi-target failure | FR-026 | Inject failure/interruption during a target write and after an earlier target succeeds; verify no partial current file, no later attempts, no rollback, correct `partially completed` status, and exact changed/unchanged/remaining target lists. |

The specification and Feature 002 contract remain authoritative if a future
implementation detail differs. Any necessary change to stable fields, status
values, codes, path rules, or safety behavior requires a reviewed contract
version change. None of the proposed behavior above is evidence of an
implemented runtime.
