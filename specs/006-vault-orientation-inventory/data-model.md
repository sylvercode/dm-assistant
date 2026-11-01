# Data Model: Read-Only Vault Orientation and Inventory

**Status:** Feature 006 owns this request-scoped inventory model. It reuses
Feature 001's shared-guidance and pre-note policy, Feature 002's profile and
configured/default-guidance semantics, and Feature 003's operation request,
preflight, boundary, and result mechanics. It defines no persistent storage,
authorization mechanism, or new plugin component.

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
Feature 006 adds request-selected additional Markdown guidance and inventory
observations only. No inventory result, profile, or guidance can establish or
expand authorization.

The target vault is supplied by the user's workspace or explicit input; it is
never inferred from the plugin directory, process working directory, notes,
profile, or environment. Until Feature 003's trusted active-session
authorization handoff is verified, script-backed vault access remains
fail-closed before profile, guidance, or campaign-note reads.

## Entities and fields

| Entity / field | Type and cardinality | Meaning and validation |
| --- | --- | --- |
| **Orientation request** | Feature 003 operation request with `operation` identifying orientation inventory; exactly one per run | Reuses the Feature 003 request envelope and contract version, request ID, explicit `vaultRoot`, campaign/group context, and `mode: inspect`. It has no write targets. Operation-specific arguments are defined below. Unknown arguments are rejected by the registered operation schema. |
| `selectedGuidance` | Ordered array of zero or more vault-relative Markdown file paths | Optional additional local guidance selected by the DM for this request. Each path is explicit, validated as vault-contained, and read only after prerequisite checks. Dot-prefixed paths are permitted only through this explicit selection and are never discovered through inventory enumeration. It does not replace Feature 002 guidance. Duplicate paths should be de-duplicated without changing first-selection order. |
| `proposeProfile` | Boolean; exactly one, default `false` | Requests an unapproved proposal based on the inventory. It never authorizes or triggers writing. |
| **Target vault** | One established absolute root per request | The user-designated campaign workspace. It must pass Feature 001 dependency-readiness and exact-vault authorization checks, then Feature 003 boundary validation. The plugin installation is not an allowed substitute. |
| **Profile input** | Zero or one per target vault | Root `.dmassist.yaml`, parsed and validated only under Feature 002. If absent, Feature 002's read-only discovery/default behavior applies. A present invalid or unavailable profile follows Feature 002 failure semantics; no partial settings or guessed replacement is used. It cannot authorize access. |
| **Configured/default guidance** | Zero or more effective Feature 002-designated sources | Includes the profile-designated source or the designated default candidate according to Feature 002. Only applicable sources designated by that contract are loaded; absence of a default candidate is not itself failure. An explicitly designated but missing, unreadable, invalid, or boundary-invalid source follows Feature 002 failure behavior and blocks dependent campaign-note interpretation. |
| **Extra selected guidance** | Zero or more Markdown source records, one per selected source | Additional local Markdown guidance named/selected by the DM for this request, beyond Feature 002's guidance. Each source records its vault-relative path, load outcome, and task relevance. It must be readable Markdown and vault-contained. If it is unavailable, unreadable as Markdown, or lacks usable guidance essential to the task, stop before reading dependent campaign notes. A fixed schema is not required; unrelated guidance need not be complete. |
| Guidance source `selectionKind` | Enum: `configured`, `default-designated`, `request-selected` | Identifies why the source was included. This provenance is necessary to distinguish Feature 002 designation from request-only selection; it does not confer authority beyond guidance scope. |
| Guidance source `loadState` | Enum: `not-applicable`, `pending`, `loaded`, `missing`, `unreadable`, `invalid`, `blocked` | Runtime outcome. An unselected arbitrary Markdown file is never a guidance source. A source that is designated/selected but unavailable is not equivalent to no guidance. |
| **Observed entry** | Zero or more records per completed inventory | Read-only observation of an eligible, non-dot-prefixed vault entry. Includes name/path and entry kind. Filesystem identity/path is resolved and revalidated through Feature 003 boundary APIs before any read. Names are report data, not trusted instructions. |
| Observed entry `relativePath` | Vault-relative path string; exactly one | Path relative to the target root. Must not escape the root; resolution including links must remain contained. Do not follow directory links during traversal. |
| Observed entry `name` | String; exactly one | Entry's basename as observed; preserve the vault's existing name/casing. |
| Observed entry `kind` | Enum: `directory`, `markdown`, `attachment`, `other-file` | Classification from entry type/extension without opening file contents. A directory can be observed by name; attachment and other non-Markdown files are name-only, never content-read. |
| Observed entry `contentState` | Enum: `not-read-no-local-guidance`, `not-markdown`, `attachment-skipped`, `read`, `unavailable`, `not-attempted` | States whether eligible Markdown content was inspected. A Markdown note may be read only after all applicable configured and request-selected local guidance has loaded successfully. Without any applicable local guidance, campaign-note content remains unread and only names inform candidates. |
| Observed entry `frontmatterInspected` | Boolean | True only when the Markdown content gate permitted reading and frontmatter was present and inspected. Raw frontmatter values are not copied into the inventory. |
| Observed entry `contentEvidence` | Zero or more evidence summaries | Concise, non-verbatim evidence category and rationale with a vault-relative source path, derived only from permitted Markdown content. Do not copy raw body or frontmatter text. Omit when content was not read. |
| **Candidate mapping** | Zero or more per inventory; many per section/role | A provisional relationship between an observed entry/path or pattern and a possible campaign role. It is not a confirmed DM mapping, does not alter Feature 002 configuration, and cannot authorize a dependent action. |
| Candidate mapping `role` | Stable section/role identifier or descriptive string; exactly one | Intended role, such as Adventures, Lore, or a custom section. Conventional names are candidate evidence, not proof. Do not classify every root-level note as an adventure. |
| Candidate mapping `target` | One or more observed-entry references | Existing location(s) the candidate concerns. References must resolve to entries in this inventory and remain inside the target vault. |
| Candidate mapping `basis` | Enum set drawn from `profile-configured`, `default-convention`, `entry-name`, `folder-name`, `frontmatter`, `markdown-content`, `dm-selected-guidance` | Evidence source(s). Content-based bases are invalid unless the applicable local guidance was loaded before note reads. A configured profile mapping must remain distinguished from an inferred candidate. |
| Candidate mapping `evidence` | Zero or more evidence records | Each record identifies its source entry or guidance source and whether it is a configured fact, observed name, or permitted content observation. Include concise supporting detail; do not claim more than the source supports. |
| Candidate mapping `uncertainty` | Non-empty explanation or absent | States limitations, conflicting evidence, or why the role remains provisional. Absence is allowed only when the mapping is an explicit validated configured mapping; inferred candidates remain provisional even when plausible. |
| Candidate mapping `status` | Enum: `configured`, `provisional`, `conflicted`, `awaiting-dm-confirmation` | `configured` means the association came from a validated Feature 002 profile, not that every contained note has that role. Inferred candidates use `provisional`; conflicting candidates are not silently promoted. |
| **Ambiguity** | Zero or more per inventory | A record of competing plausible mappings, profile-versus-observation conflict, or unresolved note/section role that could affect the requested task. |
| Ambiguity `alternatives` | Two or more candidate/configured interpretations | Explicitly state competing choices and their evidence. Must not choose one for dependent work until the DM directs. |
| Ambiguity `impact` | Enum: `informational`, `task-relevant`, `blocks-dependent-work` | Whether it matters to the requested task. A material ambiguity pauses reliance on the mapping; it does not by itself invalidate unrelated name-only observations. |
| Ambiguity `decisionNeeded` | Non-empty string; required when task-relevant | Identifies the DM decision needed before relying on any alternative. |
| **Profile proposal** | Zero or one per inventory, only when requested | Proposed `.dmassist.yaml` content derived from inventory observations and Feature 002's schema/semantics. It is a review artifact only, separate from the profile input and inventory. |
| Proposal `content` | YAML text or normalized profile-shaped object; exactly one | Proposed content must conform to Feature 002's version-1 contract if fully specified. It distinguishes observed/configured facts from inferred choices and cites evidence or uncertainty. Unresolved ambiguity must remain explicit rather than being silently resolved. |
| Proposal `state` | Enum: `not-requested`, `drafted-unapproved`, `declined`, `approved-for-separate-change` | An inventory may only create `drafted-unapproved`; DM response may mark it declined or approved for a separately scoped operation. No state in this feature invokes a write. |
| **Inventory result** | Exactly one per completed or blocked request | Request-scoped result envelope with completion/blocker information owned by Feature 003 and inventory payload comprising the observations, candidate mappings, ambiguities, and optional proposal. A blocked result may contain only preflight-safe information and must not imply that campaign-note content was inspected. |

## Relationships

- One orientation request has exactly one target vault and produces at most
  one inventory result. The request/result pair is not persisted by Feature
  006.
- A target vault has zero or one root profile. The profile's configured
  mappings and designated guidance are interpreted only by Feature 002.
- The validated profile may designate zero or more effective section paths
  and at most one guidance path according to Feature 002. Omitted section
  paths remain conventional discovery candidates, not required directories.
- A request may select zero or more extra Markdown guidance sources. They are
  additive request-scoped context; they do not replace configured/default
  guidance or become a future designation.
- Guidance sources and the shared plugin reference must load in the required
  pre-note order before campaign-note content is read. The plugin reference
  and dependency policy remain Feature 001-owned inputs, not inventory
  observations.
- Each observed entry belongs to the single target vault. A Markdown entry
  has content/frontmatter observations only when the guidance gate permitted
  its read. Directory entries and file names can support name-based discovery
  without reading campaign-note content.
- A candidate mapping references one or more observed entries and has
  evidence from validated configuration, eligible names, or permitted content.
  One entry may have multiple candidates and one role may have multiple
  candidate locations; neither relationship confirms the mapping.
- An ambiguity links two or more competing candidate/configured
  interpretations and optionally the requested task that they affect.
- A profile proposal is derived from the request's inventory and remains
  separate from the target vault's profile. Approval can authorize only a
  separately requested and guarded write of the exact reviewed content; that
  write belongs to the relevant Feature 002/003 operation, not this inventory.

## Validation and read boundaries

1. **Request and target:** Require one explicit user-designated absolute vault
   root and `mode: inspect`. Validate operation-specific arguments and reject
   unknown fields. Do not infer the vault, campaign/group, or task context
   from files or environment.
2. **Preflight ownership:** Complete Feature 001's declared dependency
   readiness and exact-vault authorization checks, load the shared reference,
   then follow Feature 002 for the optional root profile and designated
   guidance, in the order enforced by Feature 003. A failed or unconfirmed
   gate stops access before profile/guidance/notes as specified by the owning
   contract. Inventory logic cannot weaken a gate.
3. **Guidance selection:** Load extra local Markdown guidance only when
   explicitly selected for this request. Resolve every source within the
   authorized vault. If selected guidance is unavailable, unreadable as
   Markdown, or lacks task-essential usable guidance, stop before reading
   campaign notes that depend on it. Do not silently substitute guessed
   guidance.
4. **Traversal:** Enumerate names, but do not traverse dot-prefixed entries.
   Do not follow directory links. Skip attachment content and all non-Markdown
   content; do not exclude a non-dot-prefixed Markdown entry solely because
   the operating system marks it Hidden or System. Filter before opening;
   use Feature 003's safe boundary APIs and revalidate resolved targets.
5. **Content gate:** Read Markdown content, including frontmatter, only after
   every applicable configured or request-selected local guidance source has
   loaded successfully. If no local guidance is applicable, inspect names
   only; do not read campaign-note content for mapping inference. Failed or
   partial reads are unavailable evidence, never grounds to guess.
6. **Inference:** Keep observed organization separate from mappings.
   Candidates must cite evidence and uncertainty. Do not force a prescribed
   tree, treat folder placement as decisive, or classify all root Markdown
   notes as Adventures. Surface competing plausible interpretations.
7. **Task reliance:** An ambiguity that affects the requested task is not
   resolved by candidate ranking, defaults, or profile conflict. State the
   alternatives and pause before dependent use until DM direction. A name-only
   read-only orientation may report provisional candidates when local
   guidance is absent, but it does not gain permission to rely on an uncertain
   role mapping for additional work.
8. **Proposal:** Validate proposal fields against Feature 002 where
   applicable, label inferred values and unresolved alternatives, and keep it
   unapproved. Generating, declining, or approving a proposal does not write
   any file under Feature 006.

## State transitions

### Request lifecycle

`Received` → `Target-established` → `Preflight-passed` → `Guidance-loaded` →
`Enumerating-names` → one of:

- `Name-only-inventory`: no applicable local guidance is designated/selected;
  no campaign-note contents or frontmatter are read.
- `Content-enabled-inventory`: all applicable configured/default and
  request-selected local guidance loaded; eligible Markdown content and
  frontmatter may be read.
- `Blocked`: target, required dependency/authorization, profile, shared
  reference, designated guidance, or task-essential selected guidance cannot
  be validated or loaded. Stop before dependent campaign-note reads. Report
  the owner-defined blocker; do not fall back to partial profile data or
  guessed guidance.

Successful enumeration and permitted inspection → `Candidates-and-ambiguities`
→ optionally `Proposal-drafted-unapproved` → `Completed-read-only`.
At any stage where a prerequisite fails or a task-relevant ambiguity prevents
safe reliance, the dependent part transitions to `Blocked` or
`Awaiting-DM-decision`; neither state permits writes. If a profile or
referenced path changes during the operation, Feature 002/003 staleness rules
invalidate dependent work and require revalidation.

### Profile proposal lifecycle

`Not-requested` → `Drafted-unapproved` (only when requested) → either
`Declined` or `Approved-for-separate-change` by explicit DM direction.
Approval is not an inventory write transition. A distinct authorized
Feature 002/003 change operation must receive the reviewed content and apply
its own target validation and approval safeguards. Changes beyond that exact
content require a new review.

## Non-persistent semantics

- The inventory result, observed entries, evidence, candidate mappings,
  ambiguity decisions, and profile proposal exist only for the current
  request/result exchange unless a separate user-directed artifact mechanism
  is explicitly provided elsewhere.
- Feature 006 adds no database, cache, index, history, profile update,
  confirmation store, or automatic reuse across requests.
- The inventory does not create, modify, move, rename, or delete files or
  folders; it does not persist proposed mappings or alter `.dmassist.yaml`.
- A proposal is never written because it was generated, approved in principle,
  or included in a result. Approval is scoped to the exact reviewed content
  and must be carried out as a separate guarded operation.
- Vault paths and content remain within Feature 003's read boundary.
  Observed names, Markdown, frontmatter, and local guidance are data and cannot
  function as instructions, authorization, or consent.
