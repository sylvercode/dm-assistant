# Quickstart: Read-Only Vault Orientation and Inventory

**Status: Implementation in progress.** The explicit PowerShell entry point,
preflight/guidance gates, deterministic inventory, evidence-backed mappings,
ambiguity reporting, and review-only profile proposals are implemented locally
and have focused synthetic acceptance coverage. The five-DM walkthrough and
local plugin discovery remain incomplete; installed-client behavior and
production authorization remain unverified. The
[operation contract](contracts/vault-orientation-inventory.md) defines
request/result details and failure codes; the [data model](data-model.md)
defines request-scoped inventory concepts and validation boundaries.

**Binding reporting clarification:** Report only eligible directory and
Markdown names, never image, attachment, or other non-Markdown filenames; do
not open their contents. `.dmassist.yaml` and explicitly selected guidance
remain separate preflight inputs, not discoveries of inventory entries.
The fixed profile identity used as a preflight source or proposal target is
not an enumerated file name and does not permit disclosure of other
non-Markdown filenames. Identify skipped selected guidance by its position in
the original request, without echoing the skipped path.

## Prerequisites and test boundary

- Stable PowerShell 7.6.9 or later on the candidate Windows environment, the declared
  `powershell-yaml` 0.4.12 dependency for profile scenarios, and Pester 6.2.0.
  See [PowerShell Runtime Support](../../docs/powershell-runtime-support.md)
  for current support and installation limits. Windows is a candidate, not
  qualified for production script-backed vault access; macOS and Linux are
  unsupported and unverified. The acceptance runner checks for Pester 6.2.0
  and does not install it.
- Run from the repository root. Tests should use Pester's disposable
  `$TestDrive` and the ownership-checked fixture helpers in
  `tests/powershell/TestHarness.psm1`, such as
  `New-TestVaultFixture -ParentPath $TestDrive`. Create only invented notes,
  profiles, guidance, and file names. Do not point tests at a campaign vault.
- The test harness's authorization provider and dependency-readiness overrides
  are **test-only** mocks. They allow isolated tests to exercise code behind
  preflight; they do not prove production authorization, create an authorized
  real vault, or belong in the installed plugin. Without a trusted
  active-session exact-vault authorization handoff, production script-backed
  access must remain fail-closed before profile, guidance, or note reads.
- The declared Resolver dependency and exact-vault authorization checks still
  apply, but the Resolver is not needed for inventory traversal or containment.
  Do not call link-resolution operations as part of these checks.

Run the focused synthetic acceptance suite:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1 -Path tests\powershell\VaultOrientationInventory.Tests.ps1
```

Then run the complete acceptance suite as a regression check:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1
```

The runner's `-Path` parameter accepts a test file or folder. Use the common
request/result harness and production modules; do not make a test-only
implementation of the inventory algorithm. File-symlink cases may be skipped
when the environment cannot create those links; report such skips explicitly.

## Explicit local operation invocation

The operation registry validates request metadata but is not a dispatcher.
The caller must explicitly import the skill-owned module and call the exported
function; the installed plugin does not currently register a transport or
automatic command for this operation. The manual PowerShell invocation is:

```powershell
$modulePath = Join-Path (Get-Location) 'skills\vault-orientation\scripts\VaultInventory.psm1'
Import-Module -Name $modulePath -Force
$outcome = Invoke-DmInventory -Request $request
```

`$request` must follow the
[operation contract](contracts/vault-orientation-inventory.md), including
the explicit authorized vault root and zero-target inspect envelope. Import
and registration do not establish authorization; the function must perform
the existing preflight itself and return the shared result with
`inventoryReport`. This example does not establish production authorization or show that the current installed
client can dispatch the operation.

## Local discovery and static source audit

These are separate from the proposed inventory tests. Follow the
[README local-installation instructions](../../README.md#local-installation):
from the repository root, start a fresh local-plugin session with

```powershell
copilot --plugin-dir .
```

Inside that session, check discovery:

```text
/skills list
/agent
```

The `vault-orientation` skill should be listed and no Copilot-specific agents
are currently included. In a separate shell, check the plugin listing:

```powershell
copilot --plugin-dir . plugin list
```

Expect `dm-assistant` under **External Plugins (via --plugin-dir)**. Start a
new session after changing the local plugin. `--plugin-dir` loads it only for
that session; it does not install or persistently register the plugin.
Discovery does not require PowerShell and does not prove installed-client
resource loading, inventory execution, or vault authorization.

For Feature 001's **static one-to-one skill inventory and source audit**,
enumerate all immediate-child `skills/*/SKILL.md` files and compare them with
the declared inventory in [`skills/README.md`](../../skills/README.md). Require
an exact one-to-one match, with no missing, extra, duplicate, or unclassified
entries. Inspect the source of every vault-facing skill for the ordered
pre-note safeguards: establish the explicit vault, check every declared
dependency and separate exact-vault authorization, load the canonical shared
reference and designated local guidance, establish campaign/group and
audience context, and only then access notes. Compare dependency checks with
the authoritative [Expected Runtime Dependencies](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive)
table. Verify the source requires an actual-play record or permitted explicit
DM judgment for knowledge/world-fact updates, and leaves them unchanged and
asks the DM when neither basis exists. See the
[Feature 001 audit](../001-shared-vault-guidance/quickstart.md#static-skill-inventory-and-source-audit).
This is a source-only audit, not a requirement to execute every skill; mark
an unimplemented or uninspectable behavior blocked rather than passed.

## Proposed call and request/result acceptance

The implemented local operation still requires an explicit module import and
invocation; registration supplies validation metadata and is **not** an
automatic dispatcher or installed transport:

```powershell
Import-Module -Name .\skills\vault-orientation\scripts\VaultInventory.psm1 -ErrorAction Stop
$outcome = Invoke-DmInventory -Request $request
```

Construct `$request` using the Feature 003
envelope and an explicitly established absolute root from the synthetic
fixture, not the plugin directory. Set `contractVersion` to `"1"`, supply a
caller-generated `requestId`, and require exactly
`operation: vault.orientation.inventory`, `mode: inspect`,
`campaignGroup: { campaign: null, group: null }`, and `targets: []`.
The required `arguments` object accepts only these case-sensitive fields:

| Argument | Proposed value and acceptance checks |
|---|---|
| `selectedGuidance` | Ordered array of explicit vault-relative Markdown guidance paths, default `[]`. Normalize and de-duplicate stably under the existing lexical/platform rules, preserving the first spelling and order. Explicit dot-prefixed Markdown is permitted. |
| `optionalGuidance` | Ordered array, default `[]`, identifying the DM-marked optional subset of `selectedGuidance` after the same normalization. Every other selection is essential. On Windows, path comparison is ordinal case-insensitive; a non-subset is `INVALID_REQUEST`. |
| `proposeProfile` | Boolean, default `false`; request an unapproved proposal, never a write. Reject string or other scalar coercion. |
| `mappingDecisions` | Ordered array, default `[]` when omitted, of exact `{ ambiguityId, alternativeId }` records. It may be supplied only when `proposeProfile` is `true`, even if the supplied array is empty. IDs must be non-empty, non-whitespace, single-line opaque strings without control characters and are compared case-sensitively. Reject unknown record fields, duplicate decisions, and more than one choice for an ambiguity. |

In the future focused suite, check omitted defaults and valid inputs, then
reject scalar or null arrays, non-string paths, non-Boolean proposal intent,
malformed decision records, unknown or wrong-case request/argument/context
fields, a missing or null `arguments` object, missing or non-null
campaign/group values, a wrong operation or mode, and missing, null, or
nonempty targets. These shape violations return `INVALID_REQUEST` before
vault access.
The inventory request must omit `approvedPreviewId`, `reviewedVersions`,
`reviewedDependencyVersions`, and `declinedReviewId`; supplying any is
`INVALID_REQUEST`. Verify shape errors retain Feature 003's
`INVALID_REQUEST` precedence over a simultaneous lexical-path error; an
otherwise well-shaped invalid path yields `PATH_INVALID`. Existing
string, Boolean, and integer argument validation must continue to accept and
reject the same scalar cases; do not encode arrays as strings or bypass the
shared validator. Validation failures must not access the vault.

Assert every call returns exactly `{ result, inventoryReport }`. `result`
retains the unchanged Feature 003 envelope and field order: `operation`,
`completionStatus`, `completionCode`, `changedTargets`, `unchangedTargets`,
`remainingWork`, and `errorDetails` for an incomplete result. For a valid
request both target arrays are empty; `changedTargets` is empty for every
outcome. An invalid request's safely identifiable nonempty targets may be
reported as unchanged/not attempted, without accessing them. On an incomplete
result, `errorDetails.code` matches `completionCode`; inventory data belongs
in `inventoryReport`, not in the shared envelope. A returned report has
`schemaVersion: 1` and the inventory operation identity. Registry lookup or
registration alone must not invoke inventory or cause vault reads or writes.

## Synthetic fixture outline

For content-boundary cases, build an isolated fixture containing, for example:

```text
Adventures/
  The Glass Comet.md
Lore/
  Hidden Harbor.md
.private/
  secret.md
.ignored.md
.dm-assist-test.bin
map.png
readme.txt
Unrelated Root Note.md
```

Use clearly synthetic text in Markdown frontmatter and bodies, plus distinct
marker strings in the dot-prefixed, binary/attachment, and non-Markdown files.
Add or omit `.dmassist.yaml`, its designated guidance, the default
`.dmassist-guidance.md`, and any explicitly selected extra Markdown guidance
per scenario. Capture a before/after snapshot of the entire owned fixture,
including directory entries, file hashes, modification times, and link
metadata, around every inventory/proposal call and decline. Each read-only
case must leave it unchanged. Keep snapshots and output sanitized and inside
the test run; do not follow links when snapshotting. Distinguish test-harness
setup and snapshot reads from the operation's instrumented reads. Any fixture
change used to simulate stale evidence happens between calls, before the next
snapshot.

## Inventory acceptance scenarios

These cases are the acceptance oracle for the implementation. The focused
suite currently covers the preflight/guidance gates, six layout oracles,
names-only and guidance-enabled reads, mapping evidence, privacy exclusions,
no-write snapshots, orientation/proposal ambiguity, fresh/stale decisions,
schema validation, and profile-text preservation. Environment-dependent
file-link cases are skipped when symlink creation is unavailable. The
five-DM walkthrough, local plugin discovery, installed-client behavior, and
production authorization remain outstanding or unverified and must not be
reported as passed.
Where a scenario is expected to reach inventory behavior, use the harness-only
exact-root authorization provider for that synthetic fixture. Assert the
Feature 003 envelope and Feature 006 payload as described above and in the
contract. Do not invent completion codes or duplicate implementation code.

### Preflight and guidance

| Check | Synthetic setup and expected outcome |
|---|---|
| Preflight fails closed | Without the test authorization provider, test missing/incompatible dependency readiness and separately ready-but-unproven authorization. Assert `PREREQUISITE_MISSING` or `VAULT_AUTHORIZATION_UNPROVEN`, respectively, and `inventoryReport: null`, before any profile, guidance, or note read. Also check a missing/unavailable shared reference blocks dependent note access. Exact-vault authorization is distinct from dependency availability; never present the harness mock as production authorization. |
| Names-only without local guidance | Request orientation with no profile or local guidance, then repeat with a valid profile but no applicable local guidance. After the other preflight gates pass, return `complete` / `OK` with an inventory report: absence of local guidance must not block names-only inventory. Only eligible directory and Markdown names are inventoried; names may support inferred candidates and explicit profile mappings may be observed. Assert `contentInspectionBasis: names_only`, `scan.contentInspected: false`, and no campaign-note body/frontmatter reads or evidence. A profile or the shared reference alone does not open the content gate, and a filename alone never designates guidance. |
| Configured/default guidance gates content | Separately load valid profile-designated guidance and the present Feature 002 default `.dmassist-guidance.md`. With all required sources successful, eligible Markdown bodies and frontmatter may be read, with permitted evidence. Instrument the order: authorized preflight, shared reference, profile and its configured/default source, request-selected sources, then dependent note reads. |
| Configured/default Markdown check before bytes | After authorized preflight, use a syntactically valid, schema-shaped synthetic profile that designates an existing non-Markdown guidance file. Assert `not completed` / `REFERENCE_UNAVAILABLE`, a null report, and no dependent note read; retain a more specific profile/path error where applicable. Instrument the designated file's byte reads, fingerprints, and version reads: all must be zero, even during reference validation and dependency snapshotting. Separately exercise valid configured and default Markdown guidance, proving the Markdown check occurs before their first content or version read. Legitimate reads of `.dmassist.yaml` are separate from reads of the designated guidance. |
| Feature 002 source failures | A missing profile is allowed, but a present malformed or otherwise invalid profile returns its Feature 002 profile failure and no report, not discovery fallback. An explicit `guidance.path` replaces the default candidate; if that designated source is missing, unreadable, invalid, or unavailable, stop rather than substituting the default. With no explicit path, absence of the default candidate is optional, but a present unreadable/invalid candidate or one whose availability cannot be established blocks dependent work. Selected guidance, even through an optional alias, cannot weaken a configured/default source. Do not open a non-Markdown guidance source. |
| Explicit extra guidance and dot files | With no configured/default local guidance, explicitly select readable, usable `.extra-guidance.md`, then repeat without selecting it. The selection supplements Feature 002 sources and loads before dependent note contents; the dot-prefixed file is handled in guidance preflight, never discovered or emitted by inventory scanning. Without any loaded local guidance, the repeat is names-only. |
| Scope-silent guidance | Load usable selected guidance that says nothing about a particular requested location. Continue rather than block, report the gap, and keep mappings for that location provisional instead of claiming the guidance established them. |

**Current helper limitation:** `Get-DmPreNoteContext` currently calls
`Test-DmProfileReference`, which reads and fingerprints the configured
reference without first checking for a Markdown extension; dependency
snapshotting can also read it. Feature 006 must arrange the configured/default
Markdown check **before any guidance content or version-byte read**, not
merely after calling that helper. The regression above is a future acceptance
target, not a claim that the current helper already enforces this boundary.
It must not turn absence of local guidance into a blanket inventory failure:
names-only orientation remains allowed while campaign-note content reads are
blocked.

For **each** additional request-selected source below, test it once as
essential (the default) and once as explicitly included in `optionalGuidance`.
Prove containment before treating a read problem as an optional skip. The
usable-content threshold applies to these extra selections; configured/default
sources follow Feature 002's own validation rules.

| Selected source | Essential selection | Explicitly optional selection |
|---|---|---|
| Missing | `REFERENCE_UNAVAILABLE`, null report, no dependent note read. | Report and skip with reason `missing`; continue. |
| Unreadable after containment is proven | `REFERENCE_UNAVAILABLE`, null report, no dependent note read. | Report and skip with reason `unreadable`; continue. |
| Non-Markdown | `REFERENCE_UNAVAILABLE`, null report, no dependent note read; never open its content. | Report and skip with reason `non-markdown`; continue without opening its content or disclosing its filename in the inventory report. |
| Empty, whitespace-only, frontmatter-only, or heading-only | `REFERENCE_UNAVAILABLE`, null report, no dependent note read. | Report and skip with reason `unusable`; continue. |

Contrast the last row with readable Markdown containing at least one
non-empty, non-whitespace **body** line outside frontmatter and headings:
that source is usable without a fixed schema. Report optional skips in order;
each `skippedOptionalSources` record is exactly `{ selectionIndex, reason }`.
`selectionIndex` is the zero-based position of the first retained selection
in the original `selectedGuidance` array, before de-duplication, and no
skipped path is echoed. Check duplicate selections so the index cannot
accidentally refer to the post-deduplication position. The caller can match
the index against the original request and present a human-readable request
position without repeating a skipped non-Markdown filename.
After proving containment, check missing, non-file or non-Markdown,
unreadable, and unusable states in that order.
If every optional selection is skipped and no other local guidance loaded,
assert `contentInspectionBasis: names_only`, `scan.contentInspected: false`,
and no campaign-note body/frontmatter reads.

An invalid lexical path, escaping link, or unprovable containment always
fails closed, including for an optional selection: expect the applicable
`PATH_INVALID` or `PATH_OUTSIDE_VAULT`, a null report, and no outside read.
An inaccessible component that prevents proving containment is not an
ordinary optional skip. A lexical alias must not make an essential source
optional. Do not repair traversal components, guess guidance, or substitute a
different source.

### Traversal and content boundaries

| Check | Synthetic setup and expected outcome |
|---|---|
| Dot-prefix versus OS hidden/system attributes | Include `.ignored.md` and `.private/secret.md`; also mark a non-dot-prefixed Markdown note hidden/system where the OS permits. Dot-prefixed entries and descendants are absent from inventory traversal. The non-dot Markdown entry remains eligible regardless of OS attributes. Skip or adapt only the OS-attribute setup if unsupported; retain the dot-prefix assertion. |
| Images, attachments, and all other non-Markdown files | Include an image/attachment such as `map.png`, a binary attachment, and `readme.txt` with distinct markers alongside Markdown. Assert these and every other ordinary non-Markdown file are absent from `inventoryReport.entries` and their filenames are absent everywhere in `inventoryReport`, including mappings, evidence, and ambiguities. Instrument safe reads to prove none is opened for content; `nonMarkdownEntriesExcluded` is true and both `nonMarkdownContentsRead` and `attachmentContentsRead` are false. Only eligible directory and Markdown names are reported; every entry kind is `directory` or `markdown`. Do not rely on extension-based attachment detection to choose which non-Markdown names to suppress. |
| Directory names are not file extensions | Include an eligible non-dot directory whose name ends in `.txt` and a Markdown note beneath it. Report the directory and eligible note normally; suppress non-Markdown **files** without excluding directories solely because their names have a suffix. |
| Symlink boundaries | Create in-vault directory/file links, links to a synthetic sibling outside the boundary, and cyclic or unresolvable links. Do not follow directory links during traversal. Every attempted access must revalidate canonical, component-aware containment. Include a `.md` file link to a non-Markdown target and another to a target with a dot-prefixed vault-relative component: neither is reported or opened as inventory. An eligible in-vault Markdown file link may be read only after containment is proven. An escaping, cyclic, unresolvable, or raced access stops with the applicable path/read error and no partial report, without reading outside content. If reliable, add a controlled swap to an escaping link. Never use string-prefix containment checks. |
| Scan or read failure | Cause a traversal or required note read to fail after scanning begins. Return the applicable failure and `inventoryReport: null`, not a partial report or a completed inventory. |
| Source changes during inspection | Change a successfully loaded selected guidance source or a note-content source used as evidence after its safe read but before the report is returned. Return `not completed` / `TARGET_CONFLICT` and `inventoryReport: null`, rather than mixing versions or silently retrying. |

For Windows symlink coverage, directory symlinks may require elevation or
Developer Mode; a junction can exercise directory-link boundaries where
appropriate. If file-symlink creation is unavailable, mark only those cases
skipped with the environmental reason; do not claim those cases passed.
Include a disposable sibling target with an invented marker to prove that
outside content was not read.

### Layouts, mappings, and decisions

For deterministic layout assertions, use the following synthetic fixtures.
An observed entry is always reported according to the report contract, but a
candidate mapping is emitted only when one of the evidence rules in FR-017
applies. Apply the exact conventional section vocabulary and case-insensitive
whole-word role tokens in FR-017 as complete path components/tokens, not
substrings. A conventional name or role token yields an `inferred` candidate
with uncertainty, never confirmation. A renamed section is `observed` only
when loaded profile/guidance directly assigns its role.
With applicable local guidance loaded, note content supports a candidate
only when frontmatter explicitly labels the role or the body text
self-identifies it as such; thematic similarity alone does not qualify.
Unsupported entries stay in `entries` but have no candidate mapping.

| Fixture | Synthetic entries and available evidence | Expected candidates and excluded classification |
|---|---|---|
| Root-level adventure plus unrelated note | `The Glass Comet Adventure.md`; `Unrelated Root Note.md`; no local guidance | The first entry may map to role `Adventures` at `The Glass Comet Adventure.md`, `inferred` from the exact `Adventure` name token with uncertainty. The unrelated note is reported as an entry only; it has no candidate mapping and is not an adventure. |
| Single-file adventure in a conventional section | `Adventures/The Glass Comet.md`; no local guidance | `Adventures` may map to role `Adventures` at path `Adventures`, `inferred` from the exact conventional section name. The Markdown file is an eligible entry, but its evocative title alone is not a separate role assignment. |
| Folder-based adventure arc | `Adventures/Arc - The Glass Comet/Encounters.md`; no local guidance | `Adventures` maps to role `Adventures` at path `Adventures` from the exact conventional section name; `Adventures/Arc - The Glass Comet` may map to role `Adventure` from the exact `Arc` basename token. Both are `inferred` with uncertainty. `Encounters.md` is an entry, not an additional role unless qualifying evidence supports it. |
| Mixed single-file and folder arcs | `Adventures/Adventure - The Glass Comet.md`; `Adventures/Arc - Iron Crown/Session 1.md`; no local guidance | `Adventures` maps as the conventional section; the file and folder may each map to role `Adventure` from their exact basename token, `inferred` with uncertainty. Do not infer roles for unrelated root notes. |
| Renamed section | `Chronicles/The Glass Comet.md`; selected usable guidance explicitly states that `Chronicles` contains adventures | `Chronicles` maps to role `Adventures`, `observed` with `dm-selected-guidance` evidence. The note title alone supplies no additional role. |
| Additional Lore sections | `Lore/Locations/Harbor.md`; `Lore/Cosmology/Planes.md`; no local guidance | `Lore`, `Lore/Locations`, and `Lore/Cosmology` may map to their corresponding role paths from exact conventional section names, `inferred` with uncertainty. Preserve both additional subsections; no other semantic role is inferred solely from note titles. |

| Check | Synthetic setup and expected outcome |
|---|---|
| Six supported layouts | Use the fixture rows above as the expected-entry and candidate-mapping oracle. Assert the listed paths, roles, evidence bases, and classifications; assert unsupported entries have no candidate mapping; never classify the unrelated root note or every root Markdown file as an adventure. The report must preserve all observed names without imposing a tree or migration. |
| Observed versus inferred | A role/path mapping directly stated by the loaded profile or guidance is `observed`; a mapping derived from a name, default convention, or permitted note content is `inferred`. An observed filesystem name alone is not an observed mapping. Assert each mapping's labeled basis, non-verbatim evidence, and uncertainty where applicable; a DM choice does not change its evidence-based classification. |
| Informational ambiguity | Give one folder two plausible roles and request orientation only. Return `complete` / `OK` with a successful report, both alternatives and evidence, `requiresDmDecision: false`, no selected alternative, and `profileProposal: null`. The caller must independently obtain DM direction before relying on an ambiguity that affects a separate task's scope or result. |
| Separate task depends on an ambiguity | Use the orientation report in a synthetic downstream task: separately cover a renamed folder whose possible roles change which notes would be read, and a profile mapping that conflicts with observed organization. The caller presents the alternatives and waits for DM direction before choosing a mapping or accessing dependent notes. Do not invent a task-scope argument for the inventory request or treat orientation itself as blocked. |
| Proposal-relevant ambiguity | Use multiple plausible roles or a profile/observation conflict that would change proposed profile content. Return `not completed` / `AMBIGUOUS_CONTEXT` **with** the complete, successful `inventoryReport`, current alternatives and evidence, and a `drafted-unapproved` proposal whose `content` and `differences` are `null`. Require DM direction instead of choosing either interpretation. |
| Fresh explicit decision | Have the DM explicitly choose an `alternativeId` from a reported `ambiguityId`, then supply that exact pair in a new `proposeProfile: true` request. Verify a fresh scan occurs and, if all required choices are current and no other ambiguity remains, the proposal is complete. Unchanged canonical root, alternatives, and evidence yield stable IDs even with a new request ID; the selection neither persists nor approves a write. |
| Stale or mismatched decision | Between requests, change relevant synthetic evidence even when its resulting label is unchanged, change the alternatives or root, or supply an unknown/mismatched ambiguity or alternative ID. Verify a fresh rescan, no silent choice or finalized content, `not completed` / `AMBIGUOUS_CONTEXT`, a successful report, and the appropriate `decisionIssues` index with reason `stale-or-unknown`. Show current alternatives when they exist; if no matching ambiguity remains, report the mismatch without inventing alternatives. |

### Profile proposal and read-only outcomes

| Check | Synthetic setup and expected outcome |
|---|---|
| Fully determined proposal | Request a proposal for a fixture with no unresolved content-affecting choice. Every returned proposal remains `drafted-unapproved`; its YAML must validate against Feature 002's version-1 schema and applicable profile/path rules. Show labeled mapping evidence and a reviewable text diff, including all content when no profile exists. Do not invent schema fields or folders for observations the profile cannot represent. |
| Existing valid profile | Start with unrelated configuration and user comments, including comments associated with changed mappings. The proposed YAML preserves unrelated values, user-authored data, comments, and unaffected text/formatting. The diff makes every intended change, including comment, formatting, and line-ending differences, reviewable; if unchanged, say so. No raw note/guidance text or absolute paths are exposed. |
| Preservation cannot be guaranteed | Use a synthetic profile for which preserving unrelated content and representing the complete diff safely is not possible, including when preserving it would disclose a forbidden non-Markdown filename in the report. Return `not completed` / `OPERATION_FAILED` with `inventoryReport: null` and a safe diagnostic, even if an ambiguity is also known. Never return a destructive replacement or silently discard content; a separate orientation request can still be made. |
| No write side effects | Compare complete before/after snapshots for ordinary, ambiguous, blocked, proposal, explicit mapping-choice, and declined-proposal cases, with and without an existing profile. No inventory result, proposal generation, mapping choice, or decline creates, edits, moves, renames, or deletes any file, folder, or profile. Cleanup removes only the unique fixture directory owned by the test. |

## Future profile-write boundary: design only

These are requirements for separately scoped future work, **not runnable
Feature 006 acceptance tests**. This feature defines the boundary but does
not implement a profile writer. A proposal and its diff are not a write
preview, and a mapping decision, a request to prepare a write, or a preview
identifier alone is not approval.

1. A future profile-specific operation must preview the exact root
   `.dmassist.yaml` target, replacement content, encoding and bytes, and all
   intended differences for DM review. Bind that target and those exact bytes
   to the preview identity; validate the replacement against Feature 002 and
   preserve unrelated configuration and comments. Record the prior target
   state, including absence, and relevant dependencies.
2. Obtain explicit DM approval in a **later message** after that preview.
   The approved scope must be the exact reviewed target and replacement bytes.
3. A separate apply must carry `approvedPreviewId`, `reviewedVersions`, and
   `reviewedDependencyVersions`, and freshly revalidate exact-vault
   authorization, canonical root and containment, old target existence and
   version, dependency and runtime/plugin/module identities and versions,
   and the exact reviewed replacement bytes immediately before writing.
4. Future work must define conflict-safe, no-clobber creation for an absent
   profile and guarded replacement for an existing profile. Decline,
   withdrawal, stale approval, or a failed pre-write check means no write.
   If a failure occurs after an atomic commit, report the actual or uncertain
   outcome rather than claiming the target was unchanged.

The current note preview provides replacement fingerprints, **not replacement
text**, and its change plan requires an existing target; it cannot create a
missing profile. No profile-specific writer is registered. A future caller
must show the exact content and encoding represented by the fingerprint.
Neither future create/replace semantics nor generic-editor remediation is
implemented or tested as part of Feature 006.

**Existing generic-editor limitation:** When the current preflight and
containment gates pass, `note.replace-text` can target an existing
`.dmassist.yaml` because it has no Markdown-extension check. A single ordinary
target does not require the approval fields, and the proposed YAML replacement
is not validated against the profile schema. Production script-backed
authorization nevertheless remains fail-closed. Feature 006 and its caller
must not use that generic edit or direct writes for profile changes; this is a
workflow rule, **not** a runtime-wide guard. Separately scoped remediation is
needed before claiming other generic callers cannot bypass the policy. Do not
make an acceptance test expect the current generic editor to reject this
target. The [contract's limitation](contracts/vault-orientation-inventory.md#future-only-profile-write-and-consent-boundary)
records the source evidence.

## SC-005 human walkthrough: outstanding

No Feature 006 walkthrough is recorded. This check requires **five real DMs**,
not simulated agents, and remains outstanding until conducted after the
proposal workflow exists:

1. Prepare one invented synthetic fixture and the same fully determined
   proposal for all five participants. It must contain at least six mappings,
   including at least two directly stated by the profile or loaded guidance
   (`observed`) and at least two inferred from names or permitted content
   (`inferred`). Prepare a separate answer key from those sources.
2. Each DM independently reviews the same proposal, labeled evidence, and
   diff, and classifies **every** mapping as observed or inferred. Do not
   reveal the answer key or other participants' answers during review.
3. Each DM must be able to decline the proposal. Compare the synthetic vault
   snapshot immediately before and after each decline; no vault file,
   folder, or profile may change. Do not offer an unsupported profile apply.
4. Pass only if at least **four of the five DMs each classify every mapping
   correctly**, and all five can decline with no vault change. Record
   anonymized per-participant all-correct and decline/no-change outcomes,
   aggregate counts, fixture/proposal identity, and environment; do not
   record real campaign content or claim a result before the walkthrough.

## Completion and evidence

The implementation exists locally, but Feature 006 acceptance remains
incomplete until the focused tests and full suite pass, local discovery and
the static source audit pass, and the five-DM walkthrough meets SC-005. The
static audit found one skill with a one-to-one inventory match and verified
its pre-note gates. Interactive discovery found `vault-orientation` and no
Copilot-specific agents, but the separate plugin listing did not show
`dm-assistant` under the documented **External Plugins (via --plugin-dir)**
grouping, so local discovery remains incomplete.

On 2026-11-11, under Windows, PowerShell 7.7.0, and Pester 6.2.0, the
focused suite passed 44 tests, failed 0, and skipped 1; the full suite passed
459, failed 0, and skipped 7. File-symlink cases were skipped because this
environment requires Windows Developer Mode or elevation to create them.
The five-DM review has not been performed.
Synthetic fixtures and mocked authorization do not establish production
access, installed-client behavior, or support for untested operating systems.
The production authorization handoff remains a separate fail-closed
prerequisite; a successful local test must not be presented as real-vault
authorization.
