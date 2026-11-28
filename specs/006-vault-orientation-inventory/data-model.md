# Data Model: Read-Only Vault Orientation and Inventory

**Status: Locally implemented inventory and review-only proposals; profile
writing remains a proposal.** This request-scoped model reuses Feature 001's
shared-guidance and pre-note policy, Feature 002's profile and
configured/default-guidance semantics, and Feature 003's operation request,
preflight, boundary, and result mechanics. It defines no persistent storage,
authorization mechanism, new plugin component, or profile writer.

## Scope and ownership

An orientation inventory is the result of one explicit, read-only request for
one established target vault. It reports eligible observed names, optional
Markdown observations, provisional mappings, material ambiguity, and
optionally an unapproved profile proposal. It is an in-memory/reporting
outcome, not a vault artifact or a saved profile.

Feature 001 remains authoritative for required dependencies, exact-vault
authorization, shared guidance, and ordered pre-note safeguards. Feature 002
owns `.dmassist.yaml` parsing, validation, defaults, configured paths, and its
designated guidance. Feature 003 owns the operation request/result envelope,
runtime readiness, safe path resolution and reads, and fail-closed behavior.
Feature 006 proposes request-selected additional Markdown guidance and
inventory observations only. No inventory result, profile, guidance, or
mapping decision can establish or expand authorization. A future profile
write is a separate operation whose required boundary is described below,
not work to implement in this feature.

The target vault is supplied by the user's workspace or explicit input; it is
never inferred from the plugin directory, process working directory, notes,
profile, or environment. The caller performs the live MCP checks and supplies
root-scoped `callerPreflight`; PowerShell checks that confirmation but does not
independently authenticate MCP. Failed confirmations block reads.

## Entities and fields

The public report and result diagnostics contain vault-relative paths or
plugin-resource identities, never absolute paths or raw note text. The report
omits non-Markdown filenames everywhere except the fixed `.dmassist.yaml`
profile identity; directory names are not filtered by filename extension.
Frontmatter and guidance contents are not copied into the report; a proposed
profile contains only permitted profile data, not raw campaign-note excerpts.

| Entity / field | Type and cardinality | Meaning and validation |
| --- | --- | --- |
| **Orientation request** | One unchanged Feature 003 request per run | The assistant-facing `Invoke-DmInventory.ps1` entry point accepts JSON and constructs the fixed runtime request, then calls the internal `Invoke-DmInventory -Request $request`. Require `operation: vault.orientation.inventory`, `mode: inspect`, explicit `campaignGroup: { campaign: null, group: null }`, and `targets: []`, plus the required Feature 003 contract version, request ID, explicit `vaultRoot`, and `arguments` object. Omit preview/approval fields. The proposed registry entry supplies validation metadata; it is not a dispatcher. |
| `selectedGuidance` | Ordered string array; default `[]` | Explicit vault-relative paths to additional guidance selected by the DM for this request. Apply existing lexical/platform path rules; normalize and de-duplicate stably, retaining each first-selection order and its zero-based index in the original array. Each path must be proven contained before access. Dot-prefixed Markdown may be read only through explicit selection, never discovered by inventory enumeration. This selection supplements rather than replaces Feature 002 guidance. |
| `optionalGuidance` | Ordered string array; default `[]` | The subset of `selectedGuidance` that the DM explicitly marked optional. Normalize and de-duplicate with the same rules, then require every member to occur in the normalized selected set. Every other selected source is task-essential. Optionality never weakens an essential or configured/default source, even through an alias, or the lexical and containment boundary. |
| `proposeProfile` | Boolean; exactly one, default `false` | Requests an unapproved proposal based on the inventory. It never authorizes or triggers writing. |
| `mappingDecisions` | Optional array of exact `{ ambiguityId, alternativeId }` records; default `[]` | Each ID is a non-empty, single-line opaque string referring to a reported ambiguity and one of its alternatives. The field may be supplied only when `proposeProfile` is `true`; omission with `false` defaults to empty. Reject unknown record fields, malformed values, duplicate decisions, and more than one choice for the same ambiguity. Choices are explicit DM direction relayed by the caller, not approvals or persistent configuration. |
| **Target vault** | One established absolute root per request | The user-designated campaign workspace. It must pass Feature 001 dependency-readiness and exact-vault authorization checks, then Feature 003 boundary validation. The plugin installation is not an allowed substitute. |
| **Profile input** | Zero or one per target vault | Root `.dmassist.yaml`, parsed and validated only under Feature 002. If absent, Feature 002's read-only discovery/default behavior applies. A present invalid or unavailable profile follows Feature 002 failure semantics; no partial settings or guessed replacement is used. It cannot authorize access. |
| **Configured/default guidance** | Zero or more effective Feature 002-designated sources | Includes the profile-designated source or the designated default candidate according to Feature 002. Only applicable sources designated by that contract are loaded; absence of a default candidate is not itself failure. An explicitly designated but missing, unreadable, invalid, or boundary-invalid source follows Feature 002 failure behavior and blocks dependent campaign-note interpretation. |
| **Extra selected guidance** | Zero or more source records, one per normalized selection | Additional vault-local guidance explicitly selected by the DM. Usable guidance is readable Markdown with at least one non-empty body line outside frontmatter and headings; no fixed schema or coverage of every location is required. A missing, unreadable, non-Markdown, or unusable essential source blocks dependent reads. An optional source with one of those problems is reported and skipped, but invalid lexical paths or escaped/unprovable containment fail closed regardless of optionality. Never open non-Markdown contents. |
| Guidance source `selectionKind` | Enum: `configured`, `default-designated`, `request-selected` | Identifies why the source was included. This provenance is necessary to distinguish Feature 002 designation from request-only selection; it does not confer authority beyond guidance scope. |
| Guidance source `loadState` | Internal state: `not-applicable`, `pending`, `loaded`, `missing`, `unreadable`, `non-markdown`, `unusable`, `blocked` | An unselected arbitrary Markdown file is never a guidance source. Skipped optional sources are distinguished from failed required sources; a marked-optional duplicate of a Feature 002-designated source cannot make that designation optional. |
| **Observed entry** | Zero or more records per successfully scanned inventory | Read-only observation of an eligible, non-dot-prefixed directory or Markdown file, including when a requested proposal remains incomplete. Includes name/path and entry kind; attachment and other non-Markdown filenames are not inventory entries. Filesystem identity/path is resolved and revalidated through Feature 003 boundary APIs before any read. Names are report data, not trusted instructions. |
| Observed entry `path` | Vault-relative path string; exactly one | Preserve the vault's existing path spelling and casing. It must remain inside the target root, including link resolution. Do not follow directory links during traversal. The basename can be derived from `path`. |
| Observed entry `kind` | Enum: `directory`, `markdown` | Classification from entry type/extension without opening file contents. A directory can be observed by name; attachment and other non-Markdown files are omitted, not content-read. |
| Observed entry `contentState`, `frontmatterInspected`, `contentEvidence` | Transient inspection state and zero or more evidence summaries | Content/frontmatter may be inspected only after required guidance succeeds and at least one applicable local source loads. A read failure invalidates the report rather than yielding an `unavailable` partial entry. Any emitted evidence is non-verbatim and uses vault-relative paths; no raw body or frontmatter values are copied. |
| **Candidate mapping** | Zero or more per inventory; many per section/role | A provisional relationship between an observed entry/path or pattern and a possible campaign role. It is not a confirmed DM mapping, does not alter Feature 002 configuration, and cannot authorize a dependent action. |
| Candidate mapping `role` | Stable section/role identifier or descriptive string; exactly one | Intended role, such as Adventures, Lore, or a custom section. Emit a candidate only for an explicit profile/guidance assignment, an exact recognized conventional section name, an explicit role token in an eligible entry name, or a permitted note-content role label/self-identification. Conventional names and role tokens are candidate evidence, not proof. General thematic resemblance alone is insufficient. Do not classify every root-level note as an adventure. |
| Candidate mapping `path` | One vault-relative location per record | Refers to an eligible directory or Markdown location that was observed, explicitly configured, or directly stated by loaded guidance; several records may describe several locations for a role. A stated location is not proof that it exists or a license to enumerate an excluded entry. Do not report excluded non-Markdown filenames in mappings, evidence, or ambiguity records. |
| Candidate mapping `classification` | Exactly `observed` or `inferred` | `observed` if and only if the mapping itself is directly stated by the loaded profile or guidance; otherwise `inferred`. Observing a filesystem name does not make the mapping observed. An explicit DM decision does not change this evidence-based classification. |
| Candidate mapping `basis` | Non-empty array/set drawn exactly from `profile-configured`, `configured-guidance`, `default-guidance`, `dm-selected-guidance`, `default-convention`, `entry-name`, `folder-name`, `frontmatter`, `markdown-content` | Identify the actual supporting source(s), with deterministic ordering and no duplicate values. `profile-configured` identifies an explicit profile setting; an implicit convention uses `default-convention` and is inferred. Each guidance origin, name, frontmatter, and note content is a distinct evidence kind. Content-based values require a permitted and successful read. |
| Candidate mapping `evidence` | Non-empty array of `{ basis, source, summary }` records | `basis` must occur in the mapping's basis set; `source` is a vault-relative path or plugin-resource identity, and `summary` gives a concise non-verbatim reason. Keep evidence separate from uncertainty; do not disclose raw note text or absolute paths. |
| Candidate mapping `uncertainty` | Non-empty explanation when inferred, conflicted, or otherwise uncertain; otherwise `null` | State limitations, conflicting evidence, and provisional interpretation without silently resolving them. An observed mapping can also be conflicted; a plausible or DM-selected inferred mapping remains inferred. |
| **Ambiguity** | Zero or more per inventory | Competing plausible mappings, profile-versus-observation conflicts, or unresolved roles. Orientation-only ambiguities are informational; proposal-relevant unresolved choices require DM direction. |
| Ambiguity `ambiguityId`, `subject` | Opaque deterministic identifier and normalized subject | The ID binds the subject, current alternatives, relevant source evidence, and canonical vault identity. A path-valued subject is vault-relative. The ID is not an authorization token and exposes neither absolute paths nor raw contents. |
| Ambiguity `alternatives` | Two or more `{ alternativeId, interpretation, path, evidence }` records | Each alternative has a deterministic, evidence-bound opaque ID, non-empty interpretation, vault-relative `path` or `null`, and supporting evidence records. IDs are checked against a fresh scan, not assumed valid across requests. |
| Ambiguity `reason`, `requiresDmDecision` | Non-empty concise reason and Boolean | Explain the uncertainty. `requiresDmDecision` is true when an unresolved choice affects the requested proposal, and false for orientation-only information or a choice matched to current explicit DM direction. A separate task must independently apply FR-015 before relying on a mapping. |
| Ambiguity `selectedAlternativeId` | Current alternative ID or `null` | Records a matched explicit DM choice for this request only; it is not confirmation stored in the profile or approval to write. |
| **Profile proposal** | `null` unless requested; otherwise one object | A request-scoped review artifact for `.dmassist.yaml`, separate from the existing profile and never active configuration. Its labeled mappings, evidence, and unresolved alternatives remain available through the report even when content is null. |
| Proposal `status` | Exactly `drafted-unapproved` when requested | The inventory never persists approval or decline and never transitions the proposal into an approved or applied state. |
| Proposal `content` | Schema-valid proposed YAML text, or `null` | Fully determined content must satisfy Feature 002's version-1 profile schema and relevant validation rules. It is `null` while a required proposal decision is unresolved, stale, or unknown. When an existing valid profile is being changed, preserve unrelated configuration values and user-authored data, and retain comments, including those on changed mappings. Never silently drop them, select an alternative, or invent unsupported profile fields. |
| Proposal `evidence` | Array of candidate mapping records | Present reviewable `classification`, basis, evidence, and uncertainty for mappings considered for the proposal, with unresolved alternatives in `ambiguities`, even when `content` is `null`. These annotations are report data, not extra keys in the proposed profile schema. |
| Proposal `differences` | Reviewable text diff, or `null` while `content` is `null` | Clearly expose every intended change from the existing profile, including comment, formatting, and line-ending changes, or all proposed content when the profile is absent. Use the vault-relative `.dmassist.yaml` target in diff labels. Do not expose raw note or guidance text or absolute paths, or present an incomplete diff as final. |
| Proposal `decisionIssues` | Ordered array of `{ decisionIndex, reason }` records; empty when none | For an unmatched supplied choice, `decisionIndex` is its zero-based position in the request and `reason` is `stale-or-unknown`. This identifies the issue without echoing an untrusted ID; renewed DM direction is required. |
| **Inventory response** | Exactly `{ result, inventoryReport }` per request | `result` is the unchanged Feature 003 envelope. `inventoryReport` is `null` on validation, preflight, boundary, required-guidance, traversal/read, or profile-preservation failure. After a successful scan it contains the report, including on unresolved proposal ambiguity. No partial scan is returned. |
| `inventoryReport.schemaVersion`, `operation` | Integer `1`; string `vault.orientation.inventory` | Version and identify the operation-specific payload without changing the shared envelope. |
| `inventoryReport.scan` | Scan-boundary summary | Records `contentInspected`, `dotPrefixedEntriesExcluded: true`, `nonMarkdownEntriesExcluded: true`, `nonDotMarkdownIncludedRegardlessOfOsAttributes: true`, `nonMarkdownContentsRead: false`, and `attachmentContentsRead: false`. `contentInspected` reflects eligible campaign-note reads, not guidance preflight. |
| `inventoryReport.guidance` | Guidance-load summary | `loadedSources` is an ordered array of `{ path, selectionKind }` records, including each successful origin. `skippedOptionalSources` is an ordered array of `{ selectionIndex, reason }`, where `selectionIndex` is the zero-based index of the first retained selection in the original `selectedGuidance` request array and `reason` is exactly `missing`, `unreadable`, `non-markdown`, or `unusable`; do not echo skipped paths. Also distinguish `configuredOrDefaultLoaded`, ordered `requestSelectedLoaded`, and `contentInspectionBasis` (`guidance_loaded` or `names_only`). Loaded paths are vault-relative; no raw source text or absolute path is included. |
| `inventoryReport.entries`, `candidateMappings`, `ambiguities`, `profileProposal` | Ordered arrays and nullable proposal | Contain the entities described above in stable order. Entries preserve observed spelling and sort by normalized relative path using a stable case-insensitive comparison and an ordinal tie-break. Mappings sort by role, path, classification, and canonical evidence; ambiguities by subject and ID; alternatives by normalized interpretation, path, and ID. |

Apply the same deterministic comparison and ordinal tie-break to mapping,
ambiguity, and alternative ordering. Order `basis` values as listed in the
table and evidence by basis, source, and summary. Preserve request selection
order for loaded and skipped additional guidance, request order for
`decisionIssues`, and report order for proposal evidence and alternatives.

## Relationships

- One orientation request has exactly one target vault and returns one
  response wrapper containing one Feature 003 result and either one inventory
  report or `null`. Neither the request nor its response is persisted by
  Feature 006.
- A target vault has zero or one root profile. The profile's configured
  mappings and designated guidance are interpreted only by Feature 002.
- The validated profile may designate zero or more effective section paths
  and at most one guidance path according to Feature 002. Omitted section
  paths remain conventional discovery candidates, not required directories.
- A request may select zero or more extra guidance sources and identify a
  subset as optional. They are additive request-scoped context; they do not
  replace configured/default guidance or become a future designation.
- The shared plugin reference, Feature 002 profile/designated guidance, and
  selected guidance are processed in the required pre-note order. Required
  sources must succeed; optional selections may be skipped as described
  above. At least one applicable local source must actually load before
  campaign-note content may be read. The shared reference and a profile alone
  do not satisfy that content gate.
- Each observed entry belongs to the single target vault. A Markdown entry
  has content/frontmatter observations only when the guidance gate permitted
  its read. Eligible directory and Markdown names can support name-based
  discovery without reading campaign-note content.
- A candidate mapping relates a vault-relative location and role, with
  evidence from validated configuration, loaded guidance, eligible names, or
  permitted content. One location may have multiple candidates and one role
  may have multiple candidate locations; neither relationship confirms the
  mapping. Inferred candidates remain provisional. Apply the evidence
  threshold in FR-017; entries without qualifying role evidence remain
  observed entries without a candidate mapping.
- An ambiguity links two or more competing interpretations. Its subject,
  alternatives, and evidence determine stable IDs for the current canonical
  vault. A request-scoped decision selects one currently valid alternative
  only for the requested proposal.
- A profile proposal is derived from the request's inventory and remains
  separate from the target vault's profile. The profile schema cannot encode
  every observed layout, such as a single root-level adventure file as a
  section directory; keep such observations in the report rather than
  inventing profile fields or folders.

## Validation and read boundaries

1. **Request and target:** Require the exact operation, one explicit
   user-designated absolute vault root, null campaign/group, `mode: inspect`,
   `targets: []`, and no approval fields. Validate all operation-specific
   arguments, reject unknown fields and malformed values, normalize/deduplicate
   path arrays stably by the existing lexical/platform rules, and require the
   optional set to be a subset of the selected set. Windows path comparison is
   ordinal case-insensitive; do not repair an invalid path or expand an
   expression. Reject duplicate mapping decisions and multiple choices for
   the same ambiguity. The existing scalar-only argument validator must be
   extended to support these arrays and exact records without weakening
   validation of existing scalar operations or changing the shared envelope.
   Do not infer the vault, campaign/group, or task context from files or
   environment.
2. **Preflight ownership:** Complete Feature 001's declared dependency
   readiness and exact-vault authorization checks, load the shared reference,
   then follow Feature 002 for the optional root profile and designated
   guidance, in the order enforced by Feature 003. The caller independently
   loads the shared reference; a script reporting a load is not proof the
   assistant loaded it. Extend the shared configured/default-guidance read
   path to check Markdown eligibility before any content or fingerprint read.
   `Get-DmPreNoteContext` returns guidance state and versions, not its text;
   safely read needed guidance against that snapshot. Capture and recheck
   versions of selected guidance and note-content sources used as evidence
   before returning; changed sources invalidate the report. A failed or unconfirmed gate stops access before
   profile/guidance/notes as specified by the owning contract. Inventory
   logic cannot weaken a gate.
3. **Guidance selection:** Load extra local Markdown guidance only when
   explicitly selected for this request. First apply lexical validation and
   prove containment for every selected path. An invalid path, escaped target,
   or unprovable boundary fails closed even when optional. After that, a
   missing, unreadable, non-Markdown, or unusable essential source blocks
   dependent campaign-note reads; the same condition on a DM-marked optional
   source is reported in `skippedOptionalSources` and skipped. Never open
   non-Markdown contents. An optional selection cannot weaken or skip an
   essential selection or configured/default Feature 002 source, even if it
   reaches the same file through a distinct alias. Do not substitute guessed
   guidance. Usable guidance that is silent about a location permits the scan
   but leaves that location's mappings provisional.
4. **Traversal:** Enumerate eligible directory and Markdown names, but do not
   traverse dot-prefixed entries or follow directory links. Omit attachment
   and all other non-Markdown filenames from inventory entries and do not read
   their contents; do not exclude a non-dot-prefixed Markdown entry solely
   because the operating system marks it Hidden or System. Filter directory
   entries by type and extension before reporting or opening them; use Feature
   003's safe boundary APIs and revalidate resolved targets. For a file link,
   require an eligible Markdown visible name and final contained target and
   omit it if the final target's vault-relative path has a dot-prefixed
   component. The required
   Feature 002 profile read is a separate preflight, not a scan of a
   non-Markdown inventory entry. Explicitly selected
   dot-prefixed Markdown guidance is likewise read through the separate
   guidance preflight, not discovered or emitted as an inventory entry.
5. **Content gate:** Read Markdown content, including frontmatter, only after
   all required guidance has succeeded and at least one applicable local
   source has actually loaded. If none loads successfully, including when
   every optional selection was skipped, inspect names only; do not read
   campaign-note content for mapping inference. A profile or shared reference
   alone does not open the gate. Failed or partial traversal/note reads are
   not evidence and cause `inventoryReport: null`.
6. **Inference:** Keep observed organization separate from mappings.
   Candidates must cite the exact allowed `basis` values, evidence, and
   uncertainty. Only a mapping directly stated by the loaded profile or
   guidance is `observed`; names and permitted note content alone produce
   `inferred` mappings. Do not force a prescribed tree, treat folder
   placement as decisive, or classify all root Markdown notes as Adventures.
   Surface competing plausible interpretations.
7. **Decision freshness and task reliance:** Rescan on every request and
   compare each explicitly supplied choice with freshly computed
   `ambiguityId` and `alternativeId` values. Identifiers bind the normalized
   subject, all relevant alternatives and source evidence, and the canonical
   root; a change to any of those makes an earlier choice stale. The same
   canonical root, normalized subject, alternatives, and relevant evidence
   yield identical IDs across requests; request IDs or timestamps do not
   affect them. Before assigning IDs, order alternative descriptors by
   normalized interpretation, path, and canonical evidence, then compute the
   ambiguity ID; derive each alternative ID from its parent ambiguity ID and
   its own descriptor. Profile and guidance contents can be used only after
   their permitted preflight reads; campaign-note content and frontmatter can
   enter evidence or IDs only when the guidance gate permitted their read.
   Computing an ID never authorizes an additional read. The IDs contain no raw
   content or absolute paths and grant no authority. A syntactically valid but
   stale or unknown choice requires renewed DM direction: do not silently
   discard it, choose a replacement, or produce finalized proposal content.
   Return current alternatives when they exist; if no matching current
   ambiguity remains, report the mismatch without inventing alternatives.
   Mapping choices do not change `classification`. For any separate
   downstream task the caller must independently apply FR-015 and obtain
   direction before relying on a task-relevant ambiguity.
8. **Proposal:** When requested, label the proposed mappings with their
   evidence and retain unresolved alternatives even with `content: null`.
   Only a fully determined proposal may contain schema-valid YAML; it remains
   `drafted-unapproved`. For an existing valid profile, retain unrelated
   configuration values and unrelated user-authored data; retain comments,
   including their associations with changed mappings, and preserve
   unaffected profile text and formatting. Clearly expose all intended
   differences between the existing profile and the proposed YAML,
   including any formatting changes; do not silently drop or rewrite
   unrelated material.
   If exact preservation or a safe, complete representation of those
   differences is not possible, including when preserving profile text would
   disclose an excluded non-Markdown filename, do not finalize or return a
   proposal: return `not completed` / `OPERATION_FAILED`,
   `inventoryReport: null`, and a
   concise safe diagnostic. The caller may separately request orientation.
   This preservation failure is not `AMBIGUOUS_CONTEXT`; that code is reserved
   for an actually missing, stale, or unknown DM mapping choice. A proposal,
   mapping choice, or request to prepare a write is not write approval and
   never changes the vault.

## Future profile-write boundary

This feature defines requirements only. There is no registered profile writer,
and the existing note preview/change plan requires an existing target; it
cannot create a missing `.dmassist.yaml`. Inventory must not invoke or imply
an available profile-write operation. Inventory and its caller must never
substitute `note.replace-text`, another generic note-edit operation, or
direct file writing for the unimplemented profile-specific approval boundary.
This is a workflow requirement, not a runtime-wide enforcement claim.

**Verified current limitation:** If existing preflight and containment gates
pass, `note.replace-text` can target an existing `.dmassist.yaml`: its target
must be an existing file, but there is no `.md` extension restriction. The
operation is registered with `FactChanging = false` and `ChangeKind = edit`,
so the current runtime does not require preview approval for a single target.
Its replacement is not validated against the proposed-profile schema; checks
of the existing profile and dependencies do not validate the replacement.
Caller confirmation does not enforce this profile-specific policy.

The user chose **document the existing limitation only**: Feature 006 does
not plan or implement a generic-writer guard or a profile writer. Separately
scoped remediation is needed before claiming that generic callers cannot
bypass the workflow policy. Evidence:
`skills\vault-orientation\scripts\OperationRequest.psm1:568-581`,
`skills\vault-orientation\scripts\ChangePreview.psm1:283-301,368-395`,
`skills\vault-orientation\scripts\ApplyNoteChanges.psm1:288-295`, and
`skills\vault-orientation\scripts\SafeNoteWriter.psm1:347-375`.

Any future implementation needs a **separate registered profile-specific
preview/apply operation**, limited to the exact root `.dmassist.yaml` target.
Its preview must present the exact replacement bytes and target for DM review,
validate the proposed profile against Feature 002's schema and applicable
semantics, and record the old target state, including whether the file is
absent. A later-message explicit approval must identify that exact preview;
the proposal, a mapping decision, an instruction to prepare a write, and
`previewId` alone are not authorization. The future operation must not
reorganize the vault or change campaign notes or folders.

The future apply must carry Feature 003's `approvedPreviewId`,
`reviewedVersions`, and `reviewedDependencyVersions`, and revalidate exact
vault authorization and containment, canonical root, runtime/plugin/module
and dependency identities and versions, the old target state, and the exact
reviewed replacement bytes immediately before writing. The future contract
must define how the reviewed target version represents absence; the current
note preview does not support that case. A missing target needs conflict-safe
no-clobber creation; an existing target needs guarded replacement. Decline,
withdrawal, stale approval, validation failure, or an unsupported/unproven
boundary must stop before any target write. The future writer must define
atomic-commit and interruption behavior and report an actual or uncertain
post-commit outcome honestly rather than assuming every reported write failure
left the target unchanged.

## State transitions

### Request lifecycle

`Received` → `Request-validated` → `Target-established` →
`Preflight-passed` → `Guidance-processed` → `Enumerating-names`.

After required guidance succeeds, `Guidance-processed` permits either:

- `Name-only-inventory`: no applicable local guidance loaded successfully,
  including when all selected sources were optional and skipped. No
  campaign-note content or frontmatter is read.
- `Content-enabled-inventory`: at least one applicable local source loaded.
  Eligible Markdown content and frontmatter may be read after every required
  guidance source succeeds.

Validation, prerequisite, boundary, required-guidance, traversal, or read
failure transitions to `Blocked`: return Feature 003's applicable
`not completed` result and `inventoryReport: null`. Inability to preserve an
existing valid profile or safely represent all intended differences also
returns `not completed` / `OPERATION_FAILED` with `inventoryReport: null` and
a safe diagnostic, rather than a partial or destructive proposal. A skippable
optional guidance problem is reported but is not such an operation failure.
If a profile, loaded guidance, or note-content source used as evidence changes
during the operation, staleness rules invalidate dependent work and require
revalidation; do not return a partial scan.

Successful enumeration and permitted inspection → `Candidates-and-ambiguities`
→ one of:

- **Orientation only:** report informational alternatives with
  `requiresDmDecision: false`, `profileProposal: null`, and Feature 003
  `completionStatus: complete` / `completionCode: OK`.
- **Requested proposal, all required choices current and preservation
  possible:** return a `drafted-unapproved` proposal with schema-valid YAML
  content, all intended profile differences, and `complete` / `OK`.
- **Requested proposal, a required choice unresolved, stale, or unknown:**
  return `not completed` / `AMBIGUOUS_CONTEXT` **with** the successful
  `inventoryReport`, current alternatives, mapping labels/evidence, and a
  `drafted-unapproved` proposal whose `content` is `null`. This is a request
  for renewed DM direction, not an I/O failure. Where a stale ID has no
  matching current ambiguity, report that fact without fabricating choices.

All branches are read-only. For a valid request, both changed and unchanged
target arrays are empty; Feature 003 may report safely identifiable targets
from an invalid request as unchanged/not attempted.
Malformed or duplicate decision records are request-validation failures,
not the post-scan stale/unknown-choice outcome. If a preservation failure is
known, it takes the `OPERATION_FAILED` path rather than masquerading as a
mapping ambiguity.

### Profile proposal lifecycle

`Not-requested` → no proposal. A request with `proposeProfile: true` and a
successful scan yields `Drafted-unapproved` unless proposal preservation
fails, in which case there is no report. The proposal's `content` is either
`null` while decisions are unresolved/stale or schema-valid proposed YAML
when they are determined. DM direction is submitted only in a new inventory
request and revalidated against that request's scan; it does not persist or
change the proposal's status. Inventory records neither decline nor approval
and has no apply transition. A separately implemented future operation would
need its own preview and later-message approval of the exact reviewed change.

## Non-persistent semantics

- The inventory result, observed entries, evidence, candidate mappings,
  ambiguity decisions, and profile proposal exist only for the current
  request/result exchange. A later request rescans and validates any explicitly
  relayed DM decisions rather than reading a stored choice.
- Feature 006 adds no database, cache, index, history, profile update,
  confirmation store, or automatic reuse across requests.
- The inventory does not create, modify, move, rename, or delete files or
  folders; it does not persist proposed mappings or alter `.dmassist.yaml`.
- A proposal is never written because it was generated, approved in principle,
  or included in a result. Any future approval is scoped to the exact
  previewed target and bytes and must be carried out by a separate guarded
  operation; no such profile operation exists today.
- Vault paths and content remain within Feature 003's read boundary.
  Observed names, Markdown, frontmatter, and local guidance are data and cannot
  function as instructions, authorization, or consent.
