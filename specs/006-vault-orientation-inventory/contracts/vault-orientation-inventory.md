# Vault Orientation and Inventory Operation Contract

**Status: Design proposal; not implemented behavior.**

This feature-specific contract proposes a read-only orientation and inventory
operation. It does not claim that the installed skill or PowerShell runtime
currently performs this operation. Feature 003 owns the shared runtime request
and result envelopes, transport-neutral mechanics, and completion-code
taxonomy. This contract reuses those definitions and adds only the operation
name, its arguments, inventory behavior, and its payload. Feature 002 remains
authoritative for `.dmassist.yaml`, its validation, defaults, and configured or
default guidance. Feature 001 remains authoritative for required dependencies,
exact-vault authorization, the shared reference, and all pre-note policy.

## Operation definition

| Property | Contract |
| --- | --- |
| Stable operation name | `vault.orientation.inventory` |
| Supported mode | `inspect` only |
| Writes | None. The Feature 003 request has an empty `targets` array. The operation has no write targets and never creates, edits, renames, moves, or deletes files. |
| Campaign/group | Explicit `null`; this operation does not infer a campaign or group from note contents. |
| Resolver use | Do not use Resolver for traversal, containment checks, or inventory. Follow Feature 001/003 authorization preflight, including its note-content-free `get_server_info` check where applicable. Do not call a Resolver operation that accesses or resolves a target unless containment of every target it could access has independently been verified. |

### Operation-specific arguments

The Feature 003 request envelope is unchanged. Its `arguments` object for this
operation has this schema:

| Field | Requirement and meaning |
| --- | --- |
| `selectedGuidance` | Optional array of explicit vault-relative paths to additional Markdown guidance selected by the DM for this request. Omitted or empty means no additional guidance was selected. Entries are data, not instructions or executable paths. Paths must pass Feature 002/003 lexical and containment rules and identify readable Markdown files. Dot-prefixed paths are allowed only through explicit selection and are never discovered by inventory scanning. Do not infer selections from filenames or directory names. |
| `proposeProfile` | Optional boolean; defaults to `false`. When `true`, include an unapproved profile-content proposal in the report. It does not authorize or trigger a write. |

Reject unknown operation arguments and invalid values with the existing
`INVALID_REQUEST` or `PATH_INVALID` code, as applicable. Feature 003 request
fields, required values, ordering, and semantics remain in force; this
operation-specific schema does not replace them.

## Required ordering and access gates

Perform the operation in this order:

1. **Preflight and authorization.** Establish the explicit user-designated
   vault root, verify declared dependency readiness, and separately establish
   exact-vault authorization under Feature 001 and Feature 003. Do not inspect
   the vault root, profile, guidance, or campaign notes to establish the root
   or authorization.
2. **Shared reference.** Load the canonical plugin-owned shared reference
   through the installed plugin resource mechanism. Do not use the current
   directory, source checkout, or vault as a fallback.
3. **Profile and configured/default guidance.** Only after authorization,
   inspect and validate the optional root `.dmassist.yaml` under Feature 002.
   Apply its all-or-nothing validation and use its configured guidance, if
   any. Otherwise apply Feature 002's default designated guidance behavior,
   including loading `.dmassist-guidance.md` when it is present. A present
   invalid profile is not treated as an absent profile and does not permit
   fallback discovery.
4. **Request-selected extra guidance.** Load each additional Markdown file
   named in `selectedGuidance`, after the profile's designated guidance.
   These sources supplement rather than replace the shared reference or
   configured/default guidance. A selected source that is missing, unreadable,
   non-Markdown, or unusable for task-essential guidance blocks dependent note
   inspection; do not silently substitute another source.
5. **Note inventory.** Only after the preceding gates succeed, enumerate the
   in-scope vault entries and, if permitted by the guidance state below, read
   eligible Markdown note contents.

This order is normative. If no configured or request-selected local guidance
is designated and available after Feature 002's default-candidate check, the
operation remains useful as a **names-only** inventory: it may inspect
directory and file names but MUST NOT read campaign-note contents to infer
mappings. Loading a profile alone does not grant permission to read note
contents. Note-content inspection, including frontmatter, is allowed only
after applicable configured/default and selected local guidance has actually
been loaded successfully.

**Production fail-closed limitation:** Feature 003's trusted handoff for
verifying the active Resolver session's exact-vault authorization has not been
verified for the PowerShell runtime. Until that handoff is implemented and
verified, production runtime access remains blocked before profile, guidance,
or campaign-note reads. A test-only authorization provider is not production
authorization evidence. Resolver availability, a supplied path, or a
successful link resolution cannot substitute for the handoff.

## Inventory boundary and traversal

- Enumerate names and directory structure only beneath the established vault
  root. Exclude every dot-prefixed file and directory from inventory entries.
  The dot-prefix rule is based on the name, not operating-system attributes.
- Include non-dot-prefixed Markdown entries even if the operating system marks
  them hidden or system. Do not exclude them solely on those attributes.
- Never read attachment contents or contents of non-Markdown files. Their
  names may be reported as observed entries when they are not dot-prefixed.
- Read Markdown note contents, including frontmatter, only under the
  guidance-dependent rule above. Do not copy raw note bodies or excerpts into
  diagnostics or the report; report concise findings with vault-relative
  evidence paths instead.
- Profile and designated guidance files are handled under Feature 002 and the
  ordered guidance steps; the dot-prefix inventory exclusion does not prevent
  loading a specifically designated `.dmassist.yaml` or
  `.dmassist-guidance.md`. A dot-prefixed additional guidance file may also be
  loaded when explicitly selected for the request, but it is never discovered
  through inventory scanning.
- Do not impose a required vault tree. Preserve observed names and locations;
  root-level Markdown files, section files, folders, and arcs may all be
  reported without migration or reorganization.

Traversal and every read MUST be containment-safe. Resolve the established
root to its canonical filesystem location. Before enumerating a directory or
opening any file, resolve the candidate against that root and prove
component-aware canonical containment; a textual path-prefix check is
insufficient. Reject lexical traversal and paths that are absolute or
otherwise invalid under Feature 002/003. Resolve symlinks before access; never
read outside the canonical root. If a link is cyclic, unresolvable, races
between validation and access, or its containment cannot be proven, stop the
affected operation with the applicable existing path/read error. Recheck
containment immediately before each access. Do not use Resolver to establish
filesystem containment. The note-content-free `get_server_info` authorization
check is governed by Feature 001 and is not a containment check; it does not
permit campaign-note access by itself. Do not call a Resolver operation that
accesses or resolves a target unless that target's containment is
independently verified, including symlink behavior. This inventory operation
has no need to call `resolve_obsidian_link`. Do not recursively traverse
directory links; a link entry may be reported by name, but its descendants
are not enumerated. A file link may be read only if the existing boundary
resolver proves its final target remains contained and the access is
revalidated.

## Report payload

The operation module returns the same wrapper pattern as the existing inspect
module: `result` contains the exact Feature 003 result envelope, and
`inventoryReport` contains this operation-specific payload after a successful
inventory. It does not add, remove, or repurpose fields in the shared envelope.
A transport must carry the payload without changing that envelope. On a
preflight or operation failure before report production, omit
`inventoryReport`.

`inventoryReport` has this shape:

| Field | Shape and meaning |
| --- | --- |
| `schemaVersion` | Integer `1`. |
| `operation` | String `vault.orientation.inventory`. |
| `scan` | Object with `contentInspected` (boolean), `dotPrefixedEntriesExcluded` (`true`), `nonDotMarkdownIncludedRegardlessOfOsAttributes` (`true`), `nonMarkdownContentsRead` (`false`), and `attachmentContentsRead` (`false`). |
| `guidance` | Object with `loadedSources` (ordered array of source identifiers or vault-relative paths), `configuredOrDefaultLoaded` (boolean), `requestSelectedLoaded` (ordered array of selected vault-relative paths), and `contentInspectionBasis` (`"guidance_loaded"` or `"names_only"`). Do not expose absolute filesystem paths. |
| `entries` | Deterministically ordered array of observed in-scope entries. Each entry has `path` (vault-relative path) and `kind` (`"directory"`, `"markdown"`, `"attachment"`, or `"other-file"`). No content is included. |
| `candidateMappings` | Array of provisional mapping records. Each has `role` (candidate campaign section or role), `path` (vault-relative path), `basis` (`profile-configured`, `name`, `structure`, or permitted Markdown evidence summarized without raw excerpts), and `evidence` (vault-relative source paths and concise observed-versus-inferred rationale). These are suggestions, never confirmed mappings. |
| `ambiguities` | Array of unresolved records. Each has `subject`, `alternatives` (array of candidate paths/interpretations), `reason`, and `requiresDmDecision` (boolean). A material ambiguity MUST be marked `true`; do not rely on that mapping for a task until the DM decides. |
| `profileProposal` | `null` unless `proposeProfile` is `true`. If requested, an object containing `status: "proposed_unapproved"`, `content` (proposed profile text/data), and `evidence` (vault-relative paths and concise observed-versus-inferred rationale). This is unapproved content only: it is not written, validated as DM-approved configuration, or treated as active configuration. |

Sort entries by normalized vault-relative path using a stable
case-insensitive comparison with a stable ordinal tie-break. Preserve original
spelling in `path`. Candidate mappings and ambiguities must also use stable
ordering. The report distinguishes directly observed names/structure from
inference; a folder or filename alone does not establish a confirmed role.
Do not classify every root-level Markdown note as an adventure.

An unapproved profile proposal is optional report content, not a separate
operation that modifies the vault. Approval of a proposal requires a separate
explicit request and the safeguards of the applicable write operation; this
contract grants no such authority.

## Ambiguity, failures, and existing completion codes

Report alternatives rather than silently resolving a profile-versus-layout
conflict or a consequentially ambiguous mapping. If uncertainty affects the
requested task's conclusion or next action, mark it as requiring DM decision
and stop dependent interpretation or note access. Low-impact observations
may still be reported as provisional when no decision is needed to complete
the requested inventory. Do not invent missing folders, guidance, mappings,
or campaign/group context.

Use Feature 003's existing codes only; this contract introduces no new
completion code. Applicable codes include:

| Existing code | Application to this operation |
| --- | --- |
| `OK` | Inventory report completed. |
| `VAULT_TARGET_INVALID` | Explicit vault root is missing, ambiguous, inaccessible, or invalid. |
| `PREREQUISITE_MISSING` | A declared dependency or required runtime prerequisite is missing or unsupported. |
| `VAULT_AUTHORIZATION_UNPROVEN` | Exact-vault authorization or its trusted runtime handoff is absent, unavailable, or inconclusive. No profile or note access is permitted. |
| `INVALID_REQUEST` | Required Feature 003 request values or operation arguments are absent or malformed. |
| `PATH_INVALID` | A supplied relative guidance path violates lexical path rules. |
| `PATH_OUTSIDE_VAULT` | A traversal or resolved link escapes the root, or containment cannot be proven. |
| `RESOURCE_MISSING` / `RESOURCE_INCOMPATIBLE` | The installed shared reference is missing/unreadable or incompatible. |
| `PROFILE_PARSE_INVALID`, `PROFILE_NORMALIZATION_INVALID`, `PROFILE_SCHEMA_INVALID`, `PROFILE_FILESYSTEM_INVALID` | The present profile fails the corresponding Feature 002 validation stage. Do not fall back to names-only discovery to mask an invalid profile. |
| `REFERENCE_UNAVAILABLE` | Required configured/default or selected guidance is unavailable, unreadable, invalid, or task-essential content cannot be established. |
| `AMBIGUOUS_CONTEXT` | An unresolved ambiguity affects the requested interpretation or next action. |
| `READ_FAILED` | A filesystem enumeration or read fails for an operational reason not more specifically represented above. |
| `OPERATION_FAILED` | Other unexpected operational failure. |

For incomplete outcomes, use the Feature 003 result envelope and its prescribed
status/code mapping. There are no changed targets for any outcome. Do not
redefine `changedTargets`, `unchangedTargets`, `remainingWork`, or
`errorDetails` to carry inventory data; the operation-specific report remains
the separate payload described above. Error details must be concise and safe,
must not include raw note contents or runtime dumps, and should identify
vault-relative inputs rather than disclose absolute paths. Treat inventory
generation as all-or-nothing: a read or traversal failure returns the
applicable incomplete result and no `inventoryReport`; do not present a
partial scan as a complete inventory.

## Proposal boundary

This document records a design proposal for Feature 006. It is not evidence
that traversal, authorization handoff, guidance loading, inventory, report
serialization, or profile proposal generation is implemented or validated.
Feature 001/002/003 contracts remain authoritative for their respective
boundaries; any future implementation must preserve them and prove runtime
behavior independently.
