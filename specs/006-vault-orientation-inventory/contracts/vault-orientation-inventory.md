# Vault Orientation and Inventory Operation Contract

**Status: Locally implemented, with installed-client and production qualification
unverified.** Profile writing remains a proposal.

This feature-specific contract proposes a read-only orientation and inventory
operation. Feature 003 owns the shared runtime request
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
| User-facing entry point | `skills/vault-orientation/scripts/Invoke-DmInventory.ps1`. The caller sends one JSON object on standard input; the script builds the fixed runtime request and invokes the internal module. The skill must not ask the assistant to inspect or import internal modules. |
| Runtime operation | `Invoke-DmInventory -Request $request`, exported by `VaultInventory.psm1`. The operation registry supplies validation metadata; it is not a dispatcher. Callers must use the user-facing entry point rather than dispatching this runtime function directly. |
| Supported mode | `inspect` only. The entry point rejects any other operation or mode. |
| Writes and targets | None. `targets` is the required empty array `[]`; the operation never creates, edits, renames, moves, or deletes files. |
| Registration | `FactChanging=false`, `ChangeKind=read`, `MinTargets=0`, `MaxTargets=0`, `RequiresMappings=false`, and `RequiresCampaignGroup=false`. This permits names-only orientation without local guidance; it does not permit reading note contents without guidance or relying on an unresolved mapping. |
| Campaign/group | `campaignGroup` is required with both `campaign` and `group` explicitly `null`. Neither is inferred from notes. |
| Resolver use | Do not use Resolver for traversal, containment checks, or inventory. Follow Feature 001/003 authorization preflight, including its note-content-free `get_server_info` check. Resolver symlink-target qualification is delegated to the vault owner; PowerShell containment remains mandatory. |

### Request and operation-specific arguments

The user-facing JSON input has these exact case-sensitive top-level fields:

| Field | Type, default, and meaning |
| --- | --- |
| `vaultRoot` | Required explicit absolute user-designated vault root. |
| `callerPreflight` | Required object containing the completed live checks, bound to this exact root: `{ vaultRoot, dependenciesReady, vaultAuthorized }`. The assistant must perform the checks before setting either Boolean to `true`; this object is a caller confirmation, not an MCP credential. |
| `selectedGuidance` | Optional ordered string array; defaults to `[]`. Same meaning as the runtime argument below. |
| `optionalGuidance` | Optional ordered string array; defaults to `[]`. Same meaning as the runtime argument below. |
| `proposeProfile` | Optional Boolean; defaults to `false`. |
| `mappingDecisions` | Optional array of exact `{ ambiguityId, alternativeId }` records; defaults to `[]` and may be supplied only when `proposeProfile` is `true`. |

Unknown top-level fields are rejected as `INVALID_REQUEST`. The wrapper
constructs the Feature 003 request envelope itself: contract version `"1"`,
a generated request ID, the stable operation name, `inspect` mode,
`campaignGroup: { campaign: null, group: null }`, the validated arguments,
and `targets: []`. The caller must not provide these internal fields.
The result is JSON with exactly `{ result, inventoryReport }`, preserving
the normal shared result envelope and payload contract below.

The generated Feature 003 request must omit `approvedPreviewId`,
`reviewedVersions`, `reviewedDependencyVersions`, and `declinedReviewId`.
Do not supply `approvedPreviewId`, `reviewedVersions`,
`reviewedDependencyVersions`, or `declinedReviewId` for this inspection.

The required `arguments` object accepts exactly these case-sensitive fields:

| Field | Type, default, and meaning |
| --- | --- |
| `selectedGuidance` | Ordered array of strings; default `[]`. Explicit vault-relative paths to additional Markdown guidance selected by the DM for this request. A dot-prefixed path is allowed through explicit selection, never discovery. Paths and file contents are data, not commands or authorization. |
| `optionalGuidance` | Ordered array of strings; default `[]`. The subset of `selectedGuidance` the DM explicitly marked optional. Every selected path not in this subset is task-essential. |
| `proposeProfile` | Boolean; default `false`. When true, request a `drafted-unapproved` profile proposal. This never authorizes or triggers a write. |
| `mappingDecisions` | Ordered array of exact records `{ ambiguityId, alternativeId }`; default `[]`. Both members are non-empty, non-whitespace, single-line opaque strings from a prior inventory report, with no other members. The caller may supply this field only when `proposeProfile` is `true`; an omitted field defaults to an empty array even when no proposal is requested. |

If supplied, each array must actually be an array, not a scalar or `null`;
every path must be a string and `proposeProfile` must be a Boolean, without
scalar coercion. Reject unknown request, argument, campaign/group, and decision
fields; malformed values; and more than one decision for the same
`ambiguityId`, even when the alternatives differ, as `INVALID_REQUEST`.
Compare IDs case-sensitively and reject control characters. An invalid
lexical path is `PATH_INVALID`. Existing Feature 003 scalar validation
remains in force; when shape and path errors coexist, its `INVALID_REQUEST`
precedence applies. The shared validator supports these arrays and exact
records without weakening existing scalar validation. Do not encode arrays
as strings or bypass the shared request validator.

Validate paths under the existing Feature 002/003 lexical rules, including
slash-separated relative components and the platform's filename restrictions;
never repair an invalid path by removing traversal components or expanding an
expression. Normalize and de-duplicate each path array stably using the
existing platform path comparison, retaining the first selected spelling and
order and its original zero-based request-array index. On Windows this
comparison is ordinal case-insensitive. After this normalization, every
optional path must match a selected path, otherwise return
`INVALID_REQUEST`. Distinct lexical aliases of the same file cannot make an
essential or Feature 002-designated source optional. Resolve and recheck
containment separately; lexical de-duplication is not proof of containment.

`mappingDecisions` carry only explicit DM direction relayed by the caller,
not inferred preferences. They are scoped to this request, are never
persisted, and are neither a profile-write request nor approval. Revalidate
every decision against a fresh scan as described below.

### Concrete invocation

The assistant resolves the script from the installed `vault-orientation`
skill's resource directory, not from the source checkout or vault. The live
Resolver checks must actually pass for the exact root before the confirmation
is supplied. This synthetic Windows example demonstrates the small input
contract; it does not authorize or access a real vault.

```powershell
$inventoryInput = [ordered]@{
    vaultRoot = 'C:\Synthetic Vaults\Oakvale'
    callerPreflight = [ordered]@{
        vaultRoot = 'C:\Synthetic Vaults\Oakvale'
        dependenciesReady = $true
        vaultAuthorized = $true
    }
    selectedGuidance = @('Guidance/Conventions.md', '.dm-extra-guidance.md')
    optionalGuidance = @('.dm-extra-guidance.md')
    proposeProfile = $true
}

$json = ConvertTo-Json -InputObject $inventoryInput -Depth 10 -Compress
$outcome = $json | pwsh -NoProfile -File '<installed skill resource>\scripts\Invoke-DmInventory.ps1' |
    ConvertFrom-Json
$result = $outcome.result
$report = $outcome.inventoryReport
```

In a subsequent request, the caller may supply a decision record with the
exact `ambiguityId` and `alternativeId` the DM explicitly chose from the
report. It must not choose an alternative by array position or infer approval.

## Required caller and entry-point order

1. **Caller:** Obtain the vault root from the workspace or explicit DM input
   without reading vault content. Follow Feature 001's own dependency and
   exact-vault authorization checks, then load the bundled shared reference
   independently before using campaign observations. A script reporting a
   loaded reference is not proof the assistant loaded it. Collect only the
   DM's explicit guidance selections, optionality, proposal request, and any
   mapping decisions. Supply the completed live checks in `callerPreflight`,
   then send the JSON input defined above to the shipped
   `Invoke-DmInventory.ps1` entry point. Do not construct the Feature 003
   request or import internal modules as the assistant-facing call boundary.
2. **Entry point and preflight:** The script constructs the fixed Feature 003
   request and invokes the internal runtime operation. Reject a different
   operation or mode without vault access. Run the established preflight in
   order: runtime prerequisites; request shape and operation-specific
   validation; declared dependency readiness; separate exact-vault
   authorization; then canonical root resolution. No profile, guidance, or
   campaign note is read to establish the vault or authorization.
3. **Shared reference:** Load the canonical plugin-owned shared reference
   through the installed plugin resource mechanism. Do not use the current
   directory, source checkout, or vault as a fallback.
4. **Profile and configured/default guidance:** After authorization, load and
   validate the optional root `.dmassist.yaml` under Feature 002. Apply its
   all-or-nothing validation and configured guidance, or its default
   designated guidance behavior, including `.dmassist-guidance.md` when
   present. Before each guidance content or dependency-fingerprint read,
   verify that both the designated name and resolved target are Markdown. A
   present invalid profile is not an absent profile and does not permit
   fallback discovery.
5. **Request-selected extra guidance:** In normalized selection order, safely
   resolve each explicitly selected path and load eligible Markdown after the
   Feature 002 source. These sources supplement, not replace, the shared
   reference or configured/default guidance. Apply the essential/optional
   rules below before any dependent campaign-note content read.
6. **Inventory and response:** Establish the explicitly null campaign/group
   context; this operation produces DM-facing orientation, not a handout.
   Enumerate the in-scope entries, read eligible Markdown only if the guidance
   gate permits it, form mappings and alternatives, and revalidate the
   request-scoped decisions against the current scan. Return the unchanged
   Feature 003 result and the operation-specific report as one wrapper.

The current `Get-DmPreNoteContext` checks guidance readability and
fingerprints it but does not check the Markdown extension before those reads,
and returns the loaded state and versions rather than the guidance text.
Before inventory reuses it, extend the shared guidance-reference and
dependency-snapshot read paths so the Markdown check occurs before **every**
guidance byte read, including fingerprinting. Preserve existing behavior for
valid references and cover shared consumers with regression tests. When
inventory needs to interpret configured/default guidance, safely read it
through the boundary API, verify the bytes match the validated dependency
snapshot. Capture and recheck versions of every successfully loaded selected
guidance source and note-content source used as evidence before returning the
report. If a checked source changes, return `TARGET_CONFLICT` with no report.

### Guidance gate

For an additional selected source, usable means readable Markdown with at
least one non-empty, non-whitespace body line outside frontmatter and
headings; a fixed guidance schema is not required. Usable guidance that is
silent about a location does not block: its mapping remains provisional.
Check both the selected name and final contained target for the Markdown
extension before opening or fingerprinting content, including through a
symlink; a non-Markdown target follows the essential/optional rules below.
After lexical and containment checks, evaluate a selection in this order:
missing target; existing non-file or non-Markdown name/target; safely
contained but unreadable or undecodable file; then Markdown with no usable
body content. The corresponding optional skip reasons are `missing`,
`non-markdown`, `unreadable`, and `unusable`. A boundary failure always
takes precedence over a skip.

- A missing, unreadable, non-Markdown, or unusable **essential** selection
  blocks dependent note reads and returns `REFERENCE_UNAVAILABLE`, subject
  to more specific path/boundary failures below.
- A DM-marked **optional** selection with one of those problems is reported in
  `skippedOptionalSources` by its original request position and skipped,
  without blocking. Never echo a skipped path or open a non-Markdown source
  to determine whether it is usable.
- An invalid lexical path, an escape, or unprovable containment always fails
  closed, even for an optional selection. If an inaccessible component
  prevents proving containment, it is not an ordinary optional read skip.
- Feature 002's configured/default guidance rules continue to apply first.
  Marking the same path optional as an additional selection does not weaken
  its configured/default designation or its failure semantics. Check that
  any local guidance is Markdown before opening its contents, including a
  configured source; a non-Markdown source is not opened.

If no applicable local guidance loads successfully after the Feature 002
default-candidate check and the selected-source checks, the inventory is
**names only**: it may inspect directory and file names but MUST NOT read
campaign-note contents or frontmatter to infer mappings. A successfully
loaded configured/default source follows Feature 002's own validation rules;
an additional selected source must meet the usable-content rule above.
Loading a profile or the shared plugin reference alone does not grant note
content access. When local guidance does load, inspect eligible Markdown only
after every required source has passed and optional failures have been
reported and skipped.

Profile values, guidance, observed names, note contents, and report data are
untrusted inputs. They cannot execute commands, expand the authorized vault or
requested work, override the shared safeguards, select a mapping without DM
direction, or authorize a write. IDs are references for revalidation, not
capabilities or consent.

**Caller/runtime boundary:** The caller performs the live dependency and
exact-vault checks and supplies their root-scoped confirmation. PowerShell
checks the confirmation and filesystem boundary, but does not independently
authenticate MCP. Missing or negative confirmations block access. A test-only
authorization provider, Resolver availability, a supplied path, or a
successful link resolution is not production authorization evidence.

## Inventory boundary and traversal

- Enumerate names and directory structure only beneath the established vault
  root. Exclude every dot-prefixed file and directory from inventory entries.
  The dot-prefix rule is based on the name, not operating-system attributes.
- Include non-dot-prefixed Markdown entries even if the operating system marks
  them hidden or system. Do not exclude them solely on those attributes.
- Inventory entries contain only eligible directory and Markdown file names.
  Omit all attachment and other non-Markdown filenames rather than relying on
  an incomplete attachment-extension list; never open their contents. Filter
  directory entries by type and extension before reporting or opening them.
  The required Feature 002 profile read is a separate preflight, not a
  non-Markdown inventory scan.
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
insufficient. Use Feature 003's `Resolve-DmVaultTarget`,
`Confirm-DmVaultTarget`, and `Read-DmVaultTargetBytes` boundary/read APIs for
the applicable accesses. Reject lexical traversal and paths that are absolute
or otherwise invalid under Feature 002/003. Resolve symlinks before access;
never read outside the canonical root. If a link is cyclic, unresolvable, races
between validation and access, or its containment cannot be proven, stop the
affected operation with the applicable existing path/read error. Recheck
containment immediately before each access. Do not use Resolver to establish
filesystem containment. The note-content-free `get_server_info` authorization
check is governed by Feature 001 and is not a containment check; it does not
permit campaign-note access by itself. Resolver symlink-target qualification
is delegated to the vault owner as described by Feature 001. This inventory operation
has no need to call `resolve_obsidian_link`. Do not recursively traverse
directory links; a link entry may be reported by name, but its descendants
are not enumerated. For an inventory file link, require both the visible name
and final contained target to be Markdown, and exclude it as an inventory item
if the target's vault-relative path has a dot-prefixed component. Resolve and
revalidate the link before reporting or opening it. Explicitly selected
guidance remains subject to its separate dot-prefixed-source rule.

## Response wrapper and report payload

Every call returns exactly `{ result, inventoryReport }`; both properties are
present even when `inventoryReport` is `null`. `result` is the unchanged
Feature 003 result envelope, in its prescribed field order:
`operation`, `completionStatus`, `completionCode`, `changedTargets`,
`unchangedTargets`, `remainingWork`, and, for an incomplete result,
`errorDetails`. For a valid request both target arrays are empty, and
`changedTargets` is empty for every outcome. If an invalid request contains
safely identifiable non-empty targets, retain Feature 003's reporting of
them as unchanged/not attempted; never access them. `errorDetails.code` equals
`completionCode`. Do not put inventory data into the shared envelope or imply
a dispatcher or transport.

The report is an object with the following fields, in this order:

| Field | Type and meaning |
| --- | --- |
| `schemaVersion` | Integer `1`. |
| `operation` | String `vault.orientation.inventory`. |
| `scan` | Object containing Boolean `contentInspected`, `dotPrefixedEntriesExcluded: true`, `nonMarkdownEntriesExcluded: true`, `nonDotMarkdownIncludedRegardlessOfOsAttributes: true`, `nonMarkdownContentsRead: false`, and `attachmentContentsRead: false`. `contentInspected` reflects actual eligible campaign-note reads, not profile or guidance preflight. |
| `guidance` | Object described below, distinguishing loaded local sources from skipped optional selections. |
| `entries` | Array of `{ path, kind }` records: `path` is vault-relative and `kind` is `directory` or `markdown`. These are observed in-scope names, without content; no attachment or other non-Markdown filename is an inventory entry. |
| `candidateMappings` | Array of mapping records described below, separate from the observed entries. |
| `ambiguities` | Array of current ambiguity records described below, including their alternatives. |
| `profileProposal` | `null` unless requested; otherwise a `drafted-unapproved` proposal object described below. On an operation failure the whole `inventoryReport` is `null`, not a partially populated proposal. |

`guidance` contains:

| Field | Type and meaning |
| --- | --- |
| `loadedSources` | Ordered array of `{ path, selectionKind }`, where `path` is vault-relative and `selectionKind` is exactly `configured`, `default-designated`, or `request-selected`. Report each successful origin, including when a path has more than one origin. The plugin-owned shared reference is a prerequisite, not a vault-local source. |
| `skippedOptionalSources` | Ordered array of exact `{ selectionIndex, reason }` records for skipped request-selected optional paths. `selectionIndex` is the non-negative, zero-based position of the first retained selection in the original `selectedGuidance` request array, before de-duplication; `reason` is `missing`, `unreadable`, `non-markdown`, or `unusable`. The caller uses the original request to identify the selection; no skipped path is echoed. A boundary violation is not a skip. |
| `configuredOrDefaultLoaded` | Boolean indicating a successfully loaded Feature 002 source. |
| `requestSelectedLoaded` | Ordered array of vault-relative selected paths successfully loaded as additional guidance. |
| `contentInspectionBasis` | `guidance_loaded` when an applicable local source loaded and the content gate is open; otherwise `names_only`. This does not claim that a note was actually read. |

### Mapping records and evidence

Each `candidateMappings` record has:

| Field | Type and meaning |
| --- | --- |
| `role` | Non-empty string identifying the proposed section or role. |
| `path` | One vault-relative directory or Markdown location. It may be an observed entry, an explicitly configured location, or a location directly stated by loaded guidance; a stated path is not a license to enumerate an excluded entry or assert its existence. Do not report excluded non-Markdown filenames in mappings, evidence, or ambiguity records. |
| `classification` | Exactly `observed` when the mapping itself is directly stated by the loaded profile or guidance; otherwise `inferred`. An observed filesystem name alone is not an observed mapping. |
| `basis` | Non-empty array/set of distinct evidence kinds, drawn exactly from `profile-configured`, `configured-guidance`, `default-guidance`, `dm-selected-guidance`, `default-convention`, `entry-name`, `folder-name`, `frontmatter`, and `markdown-content`. |
| `evidence` | Non-empty array of `{ basis, source, summary }` records. `basis` is one of the mapping's basis values; `source` is a vault-relative path or plugin-resource identity; `summary` is a concise non-verbatim explanation. |
| `uncertainty` | Non-empty explanation when inferred, conflicted, or otherwise uncertain; otherwise `null`. Evidence and uncertainty are distinct. |

The classification describes the evidence, not DM confirmation: a mapping
directly stated by a source can still conflict with another source, and an
inferred mapping stays inferred after the DM selects it. Effective default
conventions and observed entry/folder names are not explicit profile
statements. Frontmatter or Markdown-content evidence is permitted only after
the guidance gate allowed the source read. Never classify every root-level
note as an adventure or invent missing folders. Apply FR-017's candidate
threshold: require an explicit profile/guidance assignment, an exact
recognized conventional section name, an explicit role token in an eligible
entry name, or a permitted note-content role label/self-identification.
General thematic resemblance alone does not qualify; unsupported entries
remain in `entries` without a candidate mapping.

### Ambiguities and request-scoped choices

Each `ambiguities` record contains:

| Field | Type and meaning |
| --- | --- |
| `ambiguityId` | Non-empty opaque deterministic string bound to the normalized subject, current alternatives, their relevant source evidence, and canonical vault identity. |
| `subject` | Non-empty normalized subject string; a path-valued subject is vault-relative. |
| `alternatives` | Array of at least two records, each with a non-empty opaque `alternativeId`, a non-empty `interpretation` string, a vault-relative `path` or `null`, and a non-empty `evidence` array of the records above. |
| `reason` | Non-empty concise explanation of the competing interpretations. |
| `requiresDmDecision` | Boolean: true when an unresolved choice affects the requested profile proposal; false for orientation-only informational ambiguity and for a choice already matched to current explicit DM direction. |
| `selectedAlternativeId` | The currently matched alternative ID, or `null` when no supplied decision currently matches this ambiguity. It records only the current request's explicit DM direction. |

For orientation alone, every ambiguity is informational and does not pause the
inventory. For a requested proposal, every unresolved ambiguity that would
change its content requires a DM choice; never rank or silently select an
alternative as a substitute. The caller must independently apply FR-015
before using any inventory mapping for a separate task, and obtain DM
direction before relying on a task-relevant ambiguity.

Compute IDs as deterministic opaque digests of a canonical representation of
the canonical root, normalized subject, ordered alternative set, and relevant
source evidence; domain-separate ambiguity and alternative identifiers. First
order alternative descriptors without IDs by normalized interpretation, path,
and canonical evidence, then compute the ambiguity ID. Derive each alternative
ID from its parent ambiguity ID and its own descriptor. Emit only the encoded
digest as an ID, never the serialized root, source paths, or content; relative
evidence paths may still appear in the report. A change to the root, relevant
alternatives, or source evidence must make the old choice stale. For a source
actually read, bind its
relevant evidence or version even if the resulting label is unchanged.
Request IDs, timestamps, proposal intent, and supplied decisions must not
affect IDs. IDs must not expose absolute paths or content and do not authorize
any action. Profile and guidance content may contribute only after their
permitted preflight reads; campaign-note content or frontmatter may contribute
only when the guidance gate permitted its read. ID generation itself never
authorizes an extra read or a byte fingerprint of a note in names-only mode.

On every new request, rescan and verify each decision against the current
ambiguity and alternative IDs. A syntactically valid but stale or unknown
choice requires renewed DM direction, not silent removal or automatic
replacement. Return all current alternatives that exist. If the old ID no
longer corresponds to any current ambiguity, report the unmatched decision
without inventing a subject or alternatives; the caller must seek renewed
direction.

### Profile proposal and preservation

When a report is returned and `proposeProfile` is true, `profileProposal` has:

| Field | Type and meaning |
| --- | --- |
| `status` | Exactly `drafted-unapproved`. It never becomes an approval or active configuration in this operation. |
| `content` | String containing proposed YAML when fully determined, or `null` while a proposal-relevant choice is unresolved or any supplied choice is stale or unknown. Parse and normalize the proposed YAML, then validate it against Feature 002's version-1 schema and applicable profile/path rules before returning finalized content. |
| `evidence` | Array of the mapping records above, including the `classification`, basis, evidence, and uncertainty for the mappings considered for the proposal. The report's `ambiguities` retains unresolved alternatives even when `content` is `null`. |
| `differences` | A string containing a reviewable text diff, or `null` while `content` is `null`. When present, it describes all text changes from the existing profile to the proposal, or all proposed content when the profile is absent; use only the vault-relative `.dmassist.yaml` target in diff labels. If content is unchanged, explicitly say so. Make comment, formatting, and line-ending changes visible, not just changed schema keys. This is not a write preview or authorization. |
| `decisionIssues` | Ordered array of `{ decisionIndex, reason }` records for unmatched supplied decisions. `decisionIndex` is the zero-based request-array index and `reason` is `stale-or-unknown`. The index avoids echoing an untrusted ID; an empty array means no supplied decision was unmatched. |

A schema-valid profile must not invent unsupported fields, locations, or
folders. An observation the Feature 002 profile cannot represent, such as a
root-level adventure file used as a section directory, remains report
evidence rather than an invented profile setting. Account for effective
defaults when deciding whether proposal content is fully determined. If
generated YAML cannot be constructed or fails its own validation, return
`not completed` / `OPERATION_FAILED` with `inventoryReport: null`; retain
more specific missing-resource, prerequisite, or stale-input codes where
applicable. A present invalid input profile still uses Feature 002's specific
profile-validation codes.

When proposing a change to an existing valid profile, retain all unrelated
existing configuration values and user-authored data and comments, including
comments associated with changed mappings. Preserve unaffected profile text,
including comments and formatting, and expose every intended difference; a
parse-and-reserialize operation that silently drops comments is not sufficient.
The proposal's YAML and diff may contain existing profile text and comments
as needed for this review, but must not contain raw campaign-note or guidance
text, excluded non-Markdown filenames, or absolute paths. The fixed profile
identity is allowed as a target or diff label. If exact preservation cannot be
represented safely—including when preserving source text would violate the
report's content/path boundary—do not redact or discard it to make a seemingly
complete proposal. Return `not completed` / `OPERATION_FAILED`, `inventoryReport: null`,
and a concise safe diagnostic explaining the preservation limitation. The
caller may separately request orientation.

The proposal is request-scoped, review-only content; inventory neither writes
it nor persists an approval or decline. A DM mapping choice does not change a
mapping's classification or authorize a profile write.

### Ordering and privacy

Preserve original vault spelling in reported paths. Sort entries by normalized
vault-relative path using a stable case-insensitive comparison with an ordinal
tie-break. Sort candidate mappings by role, path, classification, and
canonical evidence; ambiguities by subject and ID; and alternatives by
normalized interpretation, path, and ID, using the same deterministic
comparison and ordinal tie-breaks. Order basis values as listed above and
evidence by basis then source and summary. Preserve selection order for loaded
and skipped additional guidance, and request order for `decisionIssues`.
Proposal evidence and unresolved alternatives follow the corresponding report
order.

No report or diagnostic exposes an absolute path, raw campaign-note body,
frontmatter, guidance body, or runtime dump. No inventory report exposes a
non-Markdown filename except the fixed `.dmassist.yaml` identity; directory
names are not excluded merely for having a suffix. Summaries are non-verbatim
and DM-facing. The profile text and diff exception above does not permit
exposing excluded filenames, raw note text, or absolute paths.

## Outcomes and existing completion codes

Use Feature 003's existing codes and prescribed status mapping; no new
completion code or result-envelope field is introduced.

| Outcome | `result` | `inventoryReport` |
| --- | --- | --- |
| Successful orientation, including informational ambiguity | `complete` / `OK` | Complete report; `profileProposal: null`. |
| Requested proposal with all required choices current and preservation possible | `complete` / `OK` | Complete report with schema-valid, `drafted-unapproved` YAML and its differences. |
| Successful scan but a proposal-relevant DM choice is missing, or any supplied choice is stale or unknown | `not completed` / `AMBIGUOUS_CONTEXT` | Complete scan report with current alternatives, any `decisionIssues`, mapping labels/evidence, and `profileProposal.content: null`. This is not an I/O failure. |
| Existing profile cannot be safely preserved for a requested complete proposal | `not completed` / `OPERATION_FAILED` | `null`; provide a concise safe preservation diagnostic. The caller can request orientation separately. |
| Validation, preflight, boundary, required-guidance, traversal, or read failure | `not completed` / the applicable existing code below | `null`; do not expose a partial scan or proposed content. |
| Other unexpected operation failure | `not completed` / `OPERATION_FAILED` | `null`; do not expose a partial scan or proposed content. |

An identified preservation limitation is an operation failure, not a request
for a mapping choice; do not label it `AMBIGUOUS_CONTEXT`. If it is detected
alongside an unresolved mapping, the preservation failure returns no report;
the caller can request a separate orientation to review alternatives.
Optional-guidance problems that qualify for a safe skip are not operation
failures.

| Existing code | Application to this operation |
| --- | --- |
| `VAULT_TARGET_INVALID` | Explicit vault root is missing, ambiguous, inaccessible, or invalid. |
| `PREREQUISITE_MISSING` | A declared dependency or required runtime prerequisite is missing or unsupported. |
| `VAULT_AUTHORIZATION_UNPROVEN` | Caller confirmation of exact-vault authorization is absent, negative, or for another root. No profile or note access is permitted. |
| `INVALID_REQUEST` | Required Feature 003 values or operation arguments are absent, malformed, unknown, duplicated as prohibited, or invalid for the operation. |
| `PATH_INVALID` | A supplied relative guidance path violates lexical path rules. |
| `PATH_OUTSIDE_VAULT` | A traversal or resolved link escapes the root, or containment cannot be proven. |
| `RESOURCE_MISSING` / `RESOURCE_INCOMPATIBLE` | A required installed shared reference or schema is missing/unreadable or incompatible. |
| `PROFILE_PARSE_INVALID`, `PROFILE_NORMALIZATION_INVALID`, `PROFILE_SCHEMA_INVALID`, `PROFILE_FILESYSTEM_INVALID` | The present profile fails the corresponding Feature 002 validation stage. Do not mask an invalid profile with discovery. |
| `REFERENCE_UNAVAILABLE` | Required configured/default guidance or essential selected guidance is missing, unreadable, non-Markdown, or unusable, subject to the applicable Feature 002 and boundary rules. |
| `TARGET_CONFLICT` | A profile, relevant loaded guidance, or note-content source used as evidence changes after its validated read and before the report is returned. Do not mix snapshots. |
| `READ_FAILED` | A filesystem component, enumeration, or required read fails for an operational reason not more specifically represented above. An optional source is skippable only when its containment was proved. |
| `OPERATION_FAILED` | A safe, preserving existing-profile proposal cannot be represented, or another unexpected operation failure occurs. |

For any incomplete outcome, provide the Feature 003 `errorDetails` and safe
`remainingWork`; do not place inventory payload in either field. Diagnostics
must be concise, use vault-relative identifiers when needed, and omit raw note
contents, absolute paths, and runtime dumps. Since no target changes, this
operation never returns `partially completed`. A traversal/read failure never
returns a partial scan as a completed inventory.

## Future-only profile-write and consent boundary

Feature 006 defines requirements only; it does not implement a profile
writer. No registered profile-specific write operation exists. The existing
note preview/change plan requires an existing target and cannot create a
missing `.dmassist.yaml`; it is not a profile writer or an implicit
continuation of inventory.

Inventory and its caller MUST NOT substitute `note.replace-text`, any other
generic note-edit operation, or direct file writing for the unimplemented
profile-specific approval boundary. This is a workflow requirement, not a
runtime-wide enforcement claim.

**Verified current limitation:** After the other runtime gates pass,
`note.replace-text` can technically target an existing `.dmassist.yaml`: the
change plan requires an existing file but imposes no `.md` extension
restriction. The operation is registered with `FactChanging=false` and
`ChangeKind=edit`, so the current single-target classification does not
require an approved preview or later-message approval. Its generic text
replacement is not validated against the proposed-profile schema before
writing; validation of the existing profile in pre-note context is not
validation of the replacement. See the
[operation registration](../../../skills/vault-orientation/scripts/OperationRequest.psm1#L568-L581),
[preview classification](../../../skills/vault-orientation/scripts/ChangePreview.psm1#L283-L301),
[target resolution](../../../skills/vault-orientation/scripts/ChangePreview.psm1#L368-L395),
[replacement preparation](../../../skills/vault-orientation/scripts/ChangePreview.psm1#L411-L439),
[apply approval check](../../../skills/vault-orientation/scripts/ApplyNoteChanges.psm1#L288-L295),
and [generic writer](../../../skills/vault-orientation/scripts/SafeNoteWriter.psm1#L347-L375).
The caller-confirmation contract does not independently authenticate the
active MCP session or enforce this profile-specific policy.

The explicit scope decision is to **document this existing limitation only**:
Feature 006 does not plan or implement a generic-writer guard or a profile
writer. Separately scoped remediation is needed before claiming that generic
callers cannot bypass this policy.

Any future implementation must provide a **separate registered
profile-specific preview/apply operation**, limited to the exact root
`.dmassist.yaml` target:

1. Preview the exact target and replacement bytes for DM review, show all
   intended differences, preserve unrelated existing configuration and
   comments, and validate the resulting profile under Feature 002's schema
   and applicable semantics. Record the target's old state, including absence,
   and all relevant dependencies. Existing note previews provide replacement
   fingerprints, not replacement text; a future caller must show the exact
   reviewed content and encoding represented by that fingerprint. The
   inventory proposal or its diff is not this preview.
2. Obtain explicit DM approval in a **later message** after that preview.
   The proposal, a mapping choice, a request to prepare a write, and a
   `previewId` by itself are not approval or permission to apply.
3. Carry Feature 003's `approvedPreviewId` string, ordered `reviewedVersions`
   array, and ordered `reviewedDependencyVersions` array into the separate
   apply. The target record carries `path`, `observedVersion`,
   `replacementVersion`, and `conversionDecision`; dependency records carry
   `identity` and `version`. The future contract must define a compatible
   creation encoding and conversion decision for an absent target; the
   existing note preview cannot produce that create operation. Revalidate
   exact-vault authorization, containment, canonical root, runtime/plugin/module
   and dependency identities and versions, old target state, and the exact
   reviewed replacement bytes immediately before writing. Bind the approval
   to the reviewed scope and current inputs.
4. Define and verify conflict-safe no-clobber creation for an absent profile
   and guarded replacement for an existing profile; a check followed by an
   unguarded overwrite is insufficient. Staleness, decline or withdrawal,
   validation failure, or an unsupported boundary must stop before any target
   write. Define atomic-commit and interruption behavior: if a failure occurs
   after a commit, report the actual or uncertain outcome rather than falsely
   claiming the target was unchanged. No vault folder or campaign note is
   changed.

This contract is not evidence of installed-client or production qualification,
nor of a profile-write implementation. Features 001/002/003 remain authoritative
for their respective boundaries.
