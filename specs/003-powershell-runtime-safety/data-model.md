# Data Model: PowerShell Runtime and Safe Operations

## Status and scope

**Proposed future contract—not implemented behavior.** The repository is an
Agent Plugins 1.0 scaffold; it contains no PowerShell operation runtime or
profile loader. The entities and states below describe the intended contracts
for future script-backed workflows. They do not prescribe a persistence
format, script API, or installed-resource lookup implementation.

Feature 003 owns runtime prerequisite checks, safe operation execution,
profile parsing and validation delegated by Feature 002, path/reference
checks, conflict-safe writes, and consistent results. Feature 001 remains
authoritative for shared guidance, the dependency inventory, and the ordered
vault-facing pre-note policy. Feature 002 remains authoritative for profile
fields, defaults, discovery policy, schema semantics, and vault-configuration
behavior outside the runtime boundary. Nothing in this model grants access or
write authority.

## Entities and fields

### Supported runtime environment

The approved combination of operating system, PowerShell runtime, and
prerequisite add-ons for a release.

| Field | Meaning and constraint |
| --- | --- |
| `operatingSystem` | Windows, macOS, or Linux, limited to combinations verified for that release. Unsupported combinations are identified as unsupported. |
| `runtimeName`, `runtimeVersion` | PowerShell (`pwsh`) and the exact supported version. The version is selected and recorded per release, not inferred from a floating minimum. |
| `addOns[]` | Required add-on identities and exact versions, including any YAML reader and Draft 2020-12 validator needed by the operation. |
| `selectionDate` | Date those prerequisite versions were selected for the release. |
| `provisioningGuidance` | User-facing acquisition/setup guidance. A workflow checks prerequisites but does not install or upgrade them. |

Plugin discovery and installation are independent of this entity: installing
the static plugin must not require PowerShell or run scripts.

### Operation request

One explicitly scoped request to inspect or change campaign material.

| Field | Meaning and constraint |
| --- | --- |
| `operationId` | Identity for correlating the request and its result; not a vault permission. |
| `operation` | Requested operation name and scope. Input is data, never executable text. |
| `vaultInput` | User workspace or explicit vault selection. It must not be inferred from the plugin location or process current directory. |
| `campaignGroup` | Explicit or unambiguous campaign/group context, consistent with the one-campaign/group-per-vault assumption. |
| `targets[]` | Requested note or configuration references, interpreted relative to the authorized vault where applicable. |
| `requestedChange` | Requested content effect. Clearly requested edits to one named note may proceed without redundant approval; broader, destructive, restructuring, multi-note, or continuity-changing work requires approval of its exact preview. |
| `mode` | Read-only inspection or requested mutation. Inspection is read-only. |

The same explicit request and unchanged inputs must select the same target
regardless of the starting working directory.

### Authorized vault boundary

The canonical root established from the user's workspace or explicit input,
against which all vault paths and dependency authorization are evaluated.

| Field | Meaning and constraint |
| --- | --- |
| `selectedRoot` | User-designated vault root; plugin installation is never a fallback. |
| `canonicalRoot` | Canonicalized root used for path-containment checks. |
| `established` | Whether the requested vault can be identified without reading campaign notes. |
| `authorizationState` | Whether the exact established vault is proven authorized by a note-content-free signal; tool/server presence alone is insufficient. |

An unresolved root or unproven authorization blocks campaign-note access. The
vault root may be inspected only as permitted by the preflight; it does not
authorize access to any path outside its canonical boundary.

### Declared runtime dependency and preflight evidence

One entry in Feature 001's authoritative, extensible dependency inventory, and
the operation-scoped evidence that it is ready and authorized for the exact
vault.

| Field | Meaning and constraint |
| --- | --- |
| `dependencyId` | Inventory identity; do not maintain a divergent Feature 003 inventory. |
| `purpose`, `scope` | Dependency capability and the vault-facing skills/operations that require it, as documented in Feature 001. |
| `requiredInterface`, `compatibleVersion` | Required capability and compatible release. Initially, `obsidian-link-resolver` version 2.0.0 or later exposing `resolve_obsidian_link`. |
| `readinessState` | `ready`, `missing`, `incompatible`, or `unknown`, based on the documented readiness check. |
| `vaultAuthorizationState` | `authorized`, `not authorized`, or `unknown` for this exact canonical vault, established separately from readiness. |
| `evidence` | Non-content-bearing check result and timestamp/context sufficient to show which vault and dependency were checked; never campaign note contents. |

Each dependency must be ready and separately authorized before campaign-note
access. `unknown` is not success. Do not resolve a campaign link to establish
authorization.

### Guidance and campaign context

Pre-note inputs required by Feature 001 for interpreting a vault-facing task.

| Field | Meaning and constraint |
| --- | --- |
| `sharedReferenceState` | Whether the canonical plugin-owned reference was loaded from the installed plugin resource, not from the source checkout, vault, or current directory. |
| `profileDesignationState` | Whether a local guidance source is designated, absent by valid no-designation, or designated but missing/unreadable/invalid. The profile is a control input, not a campaign note. |
| `localGuidanceReference` | DM-designated or contract-designated vault-local guidance path, if any; never guessed. |
| `campaignGroup` | Relevant campaign/group established from explicit input or unambiguous designated context. |
| `playerFacingSections` | Whether requested output contains handout/read-aloud sections; only those sections are player-facing. |
| `contextVersion` | Operation-local identity/version of the inputs used to establish context; a changed vault, profile, guidance, campaign, or group invalidates dependent work. |

Preflight order is: establish the authorized vault without campaign-note
access; check every declared dependency for readiness and exact-vault
authorization; load the canonical shared reference and inspect only the
profile/control input needed to identify designated local guidance; load that
guidance when designated; establish campaign/group and output-section
context; then access only relevant campaign notes. An absent local-guidance
designation is valid and distinct from a designated source that is missing or
unreadable. A missing designated source blocks dependent work. If no local
guidance is designated, Feature 001 permits only a specific read-only lookup
that does not rely on uncertain folder or note-role mappings; stop if
uncertainty affects findings or the next action. Changes to vault, dependency,
guidance, campaign, or group require re-establishing the applicable checks.

The current contract does not define a note-content-free signal proving that
the exact vault is an authorized resolver root. Until Feature 001 defines and
delivers that signal, a vault-facing scripted operation must stop at this
preflight gate before campaign-note access.

### Vault configuration profile and validation snapshot

The optional `.dmassist.yaml` at the authorized vault root, its normalized
profile object, and the operation-local proof that the profile and references
were valid when used.

| Field | Meaning and constraint |
| --- | --- |
| `profilePath` | Fixed root-relative `.dmassist.yaml`; never resolved from the plugin or current directory. |
| `presenceState` | `absent` or `present`. Absence allows only Feature 002's read-only discovery behavior; it does not authorize creating a profile or folders. |
| `rawVersionSnapshot` | Operation-local identity of the source profile bytes observed during loading, used to detect subsequent changes. |
| `parseState` | `not applicable`, `parsed`, or a specific parse failure, including malformed/unsupported YAML and duplicate mapping keys. |
| `normalizedProfile` | Parsed values after supported string, boolean, numeric, and date/time scalars in string-valued fields are normalized to non-empty locale-independent strings; booleans are lowercase and dates/timestamps ISO 8601. Nulls and collection values in string fields are rejected; `version` remains integer `1`. |
| `schemaArtifactIdentity` | Identity/version of the installed canonical Feature 002 validation artifact (Draft 2020-12) loaded independently of the current directory. Missing, incompatible, or unavailable artifact blocks dependent work; there is no source-tree fallback. |
| `schemaState` | `not applicable`, `valid`, or `invalid`, after validation of the normalized object against that artifact. |
| `effectiveSettings` | Settings after Feature 002 contract defaults are applied only for omitted values. Schema `default` annotations do not insert or mutate profile values. |
| `referenceSnapshots[]` | The path, expected file/directory kind, canonical target, existence/readability result, and observed version for each reference needed by the operation. |
| `validationState` | `absent`, `validating`, `valid`, `invalid`, `unavailable`, or `stale`. |

Feature 003 owns YAML parsing, duplicate-key rejection, normalization,
application of the published schema, runtime filesystem checks, deterministic
resolution, and change detection. Feature 002 owns the schema and all profile
semantics, including effective defaults and absent-profile discovery. A
present invalid profile is rejected as a whole; do not use partial settings
or fall back to discovery for profile-dependent work.

An explicitly configured built-in or custom section directory must exist and
pass boundary checks or the whole profile is invalid. Omitted conventional
folders remain optional discovery candidates. Party, preparation, guidance,
section, and template references must be checked for canonical in-vault
containment and expected kind before use; each must exist and be readable
when required. Do not create missing folders, skip a designated input, or
substitute a different reference. Shared/nested section mappings are valid;
unresolved classification or destination requires DM direction. Profile text,
notes, guidance, templates, and paths are untrusted data, never commands,
permissions, or authority to expand the request.

Before each access, resolve existing path components including symbolic
links, canonicalize target and vault root, and perform a component-aware
containment check. Reject absolute paths, leading `/`, backslashes, drive or
URI syntax, control characters, wildcards, and `.` or `..` components. Do not
expand environment variables, home directories, Obsidian links, or path
expressions. Recheck near every access; path-based checks cannot eliminate
every race if another process replaces a link between check and use.

If the profile or a referenced input/path changes during dependent work,
transition that work to `stale`, stop it, identify the changed dependency
without exposing note contents, and require revalidation before retrying.
Never auto-retry or combine old and new inputs. Unaffected work may continue
only when it does not depend on the changed input.

### Note version snapshot

An operation-local snapshot of the exact target note state reviewed before a
proposed write. It is not a lock or permission to write.

| Field | Meaning and constraint |
| --- | --- |
| `targetPath` | Vault-relative path plus canonical in-vault target identity. |
| `observedVersion` | Exact byte-content fingerprint and available file identity/metadata recorded when the note is read or previewed. Content fingerprints are for conflict detection only and are not diagnostic content. |
| `encoding` | Detected source encoding and whether it can be safely round-tripped. |
| `lineEndings` | Observed line-ending pattern and whether it can be safely preserved. |
| `replacementVersion` | Identity of the proposed replacement derived from the reviewed snapshot and requested edit. |
| `conversionDecision` | `preserve`, `warn-and-convert`, or `undecodable-no-write`. Conversion target is UTF-8 without BOM and LF. |
| `writeState` | `not started`, `prepared`, `rechecked`, `replaced`, `conflict`, or `failed`. |

Immediately before each write, re-resolve and check the boundary, then compare
the target with the version captured when it was read/reviewed. If it changed,
refuse replacement and report a conflict; do not overwrite or automatically
retry. A warning and the conversion decision must precede writing whenever
encoding or line endings cannot be safely preserved. Reliably decodable text
may then be converted to UTF-8 without BOM and LF. If decoding is unreliable,
do not write that file.

### Change preview

The exact proposed edit and the target versions against which it was reviewed.

| Field | Meaning and constraint |
| --- | --- |
| `previewId` | Identity for the exact preview presented for approval. |
| `targets[]` | Exact target paths and their reviewed `observedVersion` values. |
| `proposedEffects[]` | Human-reviewable description or diff of intended changes, including any requested conversion. |
| `scopeClass` | Single named-note text edit, multi-note, deletion, reorganization, or broader established-fact change. |
| `approvalState` | `not required`, `awaiting`, `approved`, `declined`, or `expired/stale`. |

Only the exact approved preview may be applied. Approval does not authorize
later edits or different targets. Any material change in target version,
content, or proposed effect invalidates the preview and requires a new review
and, where required, approval. Clearly requested edits confined to one named
note do not need redundant approval, but still require conflict checks and
safe replacement.

### Operation result

The stable, consistently ordered outcome contract returned by every operation.

| Field | Meaning and constraint |
| --- | --- |
| `operation` | Operation name/scope matching the request. |
| `completionStatus` | Exactly `complete`, `not completed`, or `partially completed`. |
| `completionCode` | Stable, nonlocalized machine-readable outcome code; consumers must not parse prose. |
| `changedTargets[]` | Exact targets successfully changed by this operation. |
| `unchangedTargets[]` | Exact intended targets not changed, including conflicts, blocked targets, and work not attempted. |
| `remainingWork[]` | Remaining actions or decisions needed to complete the request. |
| `errorDetails` | Optional concise actionable category/message and safe diagnostic context; omit full campaign content and unnecessary sensitive paths. |

Statuses describe progress, while codes distinguish causes. The stable code
vocabulary and required status mapping are defined once in
[the runtime interface contract](contracts/powershell-runtime-contract.md#8-stable-completion-code-taxonomy);
this model does not define a competing code set. Implementations must preserve
those meanings, and new codes require a compatible interface-contract
revision.

`complete` means all requested work completed, including successful
read-only work. `not completed` means none of the requested work completed.
`partially completed` means some but not all requested work completed. In a
multi-target request, any completed target followed by a failure yields
`partially completed`, not success.

Diagnostics and logs remain on the user's device, exclude unnecessary
campaign content, and send no usage or diagnostic telemetry off-device.

## Relationships

- An operation request establishes one authorized vault boundary and one
  campaign/group context. All target and configured paths are scoped to that
  boundary; neither profile contents nor dependency readiness grant access.
- Each vault-facing operation depends on the ordered preflight evidence and
  on the Feature 001 inventory. Every declared dependency has independent
  readiness and exact-vault authorization state.
- A vault has zero or one root profile. A present profile is parsed and
  normalized, validated against Feature 002's canonical artifact, and
  resolved without changing the source. It may reference vault-owned files
  that become operation dependencies when used.
- Each operation's validation snapshot records the profile and referenced
  input versions on which its effective settings depend. A detected change
  invalidates only dependent work, which must stop and be revalidated.
- A change preview binds exact target versions to an exact proposed effect.
  Applicable approval authorizes only that preview.
- Each note write consumes one note version snapshot and produces either a
  complete atomic replacement or no replacement. A multi-note operation is
  a sequence of per-note replacements, not one batch transaction.
- The result reports the exact relation between requested targets, changed
  targets, unchanged targets, and remaining work; it does not imply rollback
  or global transactionality.

## Validation and invariants

1. **Runtime readiness:** verify the supported `pwsh` runtime and operation's
   required add-ons before execution. Report unsupported environments; never
   install or upgrade prerequisites automatically.
2. **Exact-vault preflight:** apply Feature 001's ordered pre-note checks.
   The resolver tool's presence proves readiness only, not authorization for
   the exact vault. Until the note-content-free authorization signal exists,
   stop before campaign-note access.
3. **Input and data safety:** treat paths, profile values, notes, guidance,
   and templates as data. Do not execute, interpolate into commands, or allow
   them to weaken operating-system policy, user permissions, approvals, or
   vault boundaries.
4. **Profile validation:** parse YAML with duplicate-key rejection, normalize
   supported typed scalars, and validate the normalized object against the
   installed canonical Feature 002 Draft 2020-12 artifact. Reject unsupported
   YAML, missing/invalid/unsupported version, unknown fields, nulls,
   invalid values, and schema errors before using settings. Do not use
   validation defaults to mutate/fill the profile; apply only Feature 002's
   contract defaults for omitted values.
5. **All-or-nothing configured profile:** any profile-wide schema or required
   configured-section path error rejects the entire profile. Do not use
   partial settings, create directories, or fall back to discovery.
6. **Reference and path validity:** before each access, verify existence,
   readability, expected file/directory type when required, and canonical
   component-aware containment within the authorized vault. In-vault
   symbolic links are permitted; escapes and unresolved targets are refused.
7. **Staleness:** check that the profile and referenced inputs remain the
   validated versions before dependent use. On change, stop and revalidate;
   never mix old and new inputs or silently retry.
8. **Approval and continuity:** require explicit approval for the exact
   preview when scope is multi-note, destructive, restructuring, or
   continuity-changing. Preserve unrelated note content; do not silently
   resolve contradictions or rewrite run adventure plans.
9. **Per-file atomicity:** stage replacement bytes on the target filesystem,
   recheck the target's observed version immediately before replacement, and
   replace using a rename-class atomic operation. Never truncate and rewrite
   the live target. If staging or replacement fails, do not expose partial
   contents in that target; report the failure.
10. **Encoding and line endings:** preserve original representation when
    safely round-trippable. Otherwise warn before writing and convert only
    reliably decodable content to UTF-8 without BOM and LF. Undecodable
    content is unchanged and not written.
11. **Multi-note semantics:** process targets in a deterministic order.
    Stop at first failure; preserve earlier completed writes, do not attempt
    later targets, and do not roll back. Report exact changed and unchanged
    target sets, remaining work, and partial completion where any requested
    work succeeded but the operation did not fully complete.
12. **Stable result contract:** every result has the same labeled fields and
    order. Status is one of the three defined values; stable codes distinguish
    prerequisite blocks, invalid input, conflicts, cancellations, and
    operational failures. Do not claim incomplete work is complete.
13. **Local diagnostics:** avoid full note contents and unnecessary
    campaign-sensitive data in errors/logs; keep diagnostics on-device and
    send no telemetry off-device.

Per-file atomic replacement and the immediate pre-write version check reduce
partial-write and lost-update risks, but do not guarantee isolation from every
concurrent filesystem actor. In particular, path-based APIs cannot eliminate
all check/use races. On a replacement conflict or filesystem failure, report
the outcome rather than silently retrying.

## State transitions

### Vault-facing operation lifecycle

| State | Entry condition | Transition |
| --- | --- | --- |
| `requested` | Explicit operation request received. | Check runtime prerequisites; no campaign-note access. |
| `runtime_checked` | Runtime and required add-ons verified. | Establish the user-designated vault and canonical boundary; otherwise `blocked`. |
| `vault_established` | Vault root identified without campaign-note access. | Verify every declared dependency's readiness and exact-vault authorization; any missing, incompatible, unauthorized, or unknown result is `blocked`. |
| `dependencies_verified` | All dependencies ready and authorized for this exact vault. | Load installed shared reference; inspect only profile/control input required to determine local-guidance designation. |
| `loading_guidance` | Shared reference available and profile designation resolved. | Load designated local guidance; missing/unreadable/invalid designated source is `blocked`. No designation is valid. |
| `context_established` | Required guidance state is known. | Establish campaign/group and handout/read-aloud context. If missing or ambiguous in a way that affects the next action, `blocked` pending DM direction. |
| `ready` | Ordered pre-note checks succeeded. | Access relevant campaign notes and perform requested read-only or change work. Re-run applicable preflight if vault, dependency, guidance, campaign, or group changes. |
| `previewed` | Proposed change preview is ready. | If approval is required, wait for approval of the exact preview; otherwise proceed to snapshot/recheck. |
| `awaiting_approval` | Approval-required preview presented. | Exact approval proceeds; decline/cancel makes no proposed changes; changed inputs expire the preview and require revalidation/re-preview. |
| `writing` | Approval requirements met and target snapshot captured. | For each target, recheck boundary and exact version immediately before atomic replacement. A mismatch is `conflict`; replacement failure is `failed`; do not attempt subsequent targets. |
| `complete` | All requested work completed. | Emit `complete` with `OK`, or `NO_CHANGES` when no target needed changing. |
| `blocked` | Runtime, vault, dependency, guidance, context, profile, or required reference cannot be safely established. | Stop dependent work before campaign-note access where preflight has not completed; report code, next step, unchanged targets, and remaining work. |
| `invalid` | Input/profile fails validation. | Do not use partial or invalid settings; report `not completed` with the applicable stable code. |
| `stale` | A profile or referenced dependency changes during dependent work. | Stop affected work, report `TARGET_CONFLICT`, require revalidation before retry. |
| `conflict` | A note differs from the version reviewed when the immediate pre-write check runs. | Refuse that replacement; do not retry automatically. Prior completed target writes remain. |
| `failed` | An operational error or interruption prevents the next safe step. | Preserve prior completed target writes; ensure the current note is not partially replaced; stop later targets and report exact outcomes. |
| `cancelled` | User cancels before or during work. | Do not start further writes. Preserve completed writes; report `not completed` if none completed, otherwise `partially completed`. |

The terminal result status is derived from actual progress, not the state name:
all requested work done is `complete`; no requested work done is `not
completed`; some but not all is `partially completed`. A multi-note operation
that fails after one or more successful replacements is partial and is never
rolled back.

### Profile lifecycle

| State | Transition and behavior |
| --- | --- |
| `absent` | After the required preflight, use only Feature 002's read-only discovery behavior. Do not create a profile, folder, or note. |
| `present` → `parsing` | Read `.dmassist.yaml` only from the established vault root after dependency readiness/authorization checks. Capture the source version. |
| `parsing` → `invalid` | Malformed/unsupported YAML, duplicate keys, invalid or unsupported version, unknown fields, nulls, or normalization errors reject the profile before settings are used. |
| `parsing` → `normalizing` | Normalize supported scalar types under Feature 002's locale-independent rules; preserve version as integer `1`. |
| `normalizing` → `schema_validating` | Load the canonical installed schema artifact independently of current working directory and validate the normalized profile. Missing/incompatible artifact yields `unavailable`; validation errors yield `invalid`. |
| `schema_validating` → `resolving` | On a valid schema instance, apply Feature 002's omitted-property defaults without mutating the source profile and validate explicitly configured paths/references against live vault state. |
| `resolving` → `valid` | Required configured section folders and needed references pass type, existence/readability, and canonical-boundary checks. Capture dependency versions for the operation. |
| `valid` → `stale` | A profile, referenced file, or path target changes during dependent work. Stop affected work and require full applicable revalidation. |
| `stale` → `parsing` | Only after an explicit retry/revalidation; do not combine the old snapshot with new values. |

`invalid`, `unavailable`, and `stale` are not discovery-fallback states for a
present profile. Discovery is reserved for an absent profile.

## Open issue

Feature 001 has not yet defined and delivered note-content-free evidence that
the exact established vault is among the resolver's authorized roots. Until
that contract exists and can be verified, vault-facing scripted operations
must stop before campaign-note access; resolver availability alone is
insufficient.
