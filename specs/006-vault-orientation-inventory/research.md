# Research: Read-Only Vault Orientation and Inventory

**Integration update:** This records historical decisions. References below to
an always-blocked authorization handoff are superseded by Feature 003's
caller-confirmation contract: the caller performs live MCP checks, while
PowerShell checks the root-scoped confirmation and filesystem safeguards
without independently authenticating MCP. Production qualification remains
unverified.

## Runtime and integration pattern

**Decision:** Extend the existing PowerShell vault-orientation runtime with a
registered, read-only inventory operation. Reuse its preflight, profile and
guidance loading, boundary resolution, safe file reads, and result envelope.
Keep the Copilot skill as the user-facing workflow; do not add a new plugin
component, hook, MCP server, or transport.

**Rationale:** The repository already has a stable operation request/result
contract and the modules that validate requests, enforce the authorized vault
boundary, validate the optional profile, and safely inspect targets. Feature
003 owns runtime mechanics, Feature 002 owns `.dmassist.yaml` semantics and
configured/default guidance, and Feature 001 owns shared guidance and pre-note
policy. Feature 006 should add only inventory behavior and request-selected
additional Markdown guidance.

**Alternatives considered:** A new transport-facing CLI command or MCP
integration was rejected because no transport or plugin integration is
required, and the runtime contract explicitly defers transport choice. A
standalone inventory scanner was rejected because it would duplicate or
bypass established preflight and path-boundary safeguards.

**Evidence:** `specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`;
`specs/002-vault-configuration-contract/data-model.md`;
`specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`;
`skills/vault-orientation/scripts/RuntimeContract.psm1`;
`skills/vault-orientation/scripts/VaultInspection.psm1`.

## Invocation and result boundary

**Decision:** Add the inspect-only `vault.orientation.inventory` registration
and export `Invoke-DmInventory -Request $request` from the new inventory
module. The assistant-facing `Invoke-DmInventory.ps1` entry point accepts JSON,
constructs the fixed runtime request, and invokes that function internally.
Registration does not dispatch it. The runtime checks the exact operation and
mode, runs the existing preflight and guidance sequence, and returns a stable
wrapper with the unchanged shared `result` envelope and an `inventoryReport`
payload. On successful enumeration, an unresolved proposal decision returns
`AMBIGUOUS_CONTEXT` with the report and alternatives; preflight, unsafe-path,
guidance, or traversal/read failures return no report.

**Rationale:** Existing `Invoke-DmInspect` is a callable entry point with a
separate operation-specific payload; the registry holds validation metadata
rather than an operation router. An ambiguity is a reviewable outcome, not a
filesystem failure or permission to present a complete proposal. Returning
the alternatives with the incomplete result allows the caller to ask the DM
without presenting an incomplete scan as a successful one.

**Alternatives considered:** Implicit dispatch was rejected because no such
transport or dispatcher exists. Putting inventory data into shared
`remainingWork` or target fields would change their semantics. Dropping every
report on ambiguity would hide the alternatives needed for DM review.

**Evidence:** `skills/vault-orientation/scripts/OperationRequest.psm1`;
`skills/vault-orientation/scripts/RuntimePreflight.psm1`;
`skills/vault-orientation/scripts/VaultInspection.psm1`;
`skills/vault-orientation/scripts/RuntimeContract.psm1`.

## Read-only traversal and content boundary

**Decision:** Enumerate one explicitly authorized vault without following
directory links during traversal. Exclude dot-prefixed entries from inventory
enumeration; explicitly selected dot-prefixed guidance and Feature 002
profile/designated guidance are loaded separately, not discovered by scanning.
Filter extensions before opening files. Report eligible directory and Markdown
names only; omit all attachment and other non-Markdown filenames rather than
relying on an incomplete attachment-extension list. Inspect Markdown contents,
including frontmatter, only after applicable configured or request-selected
local guidance is loaded. Without such guidance, report name-based candidates
only. Resolve and revalidate every selected target through the existing
boundary APIs before reading bytes. Inventory does not open attachment or
other non-Markdown contents; the Feature 002 profile is loaded separately
under its own contract.

**Rationale:** This satisfies the inventory scope while preserving Feature
001's limited no-guidance read boundary, Feature 002's configured/default
guidance behavior, and Feature 003's safe path access. The DM clarified that
attachment filenames must not be inventory items and chose to omit all
non-Markdown filenames because extensions cannot reliably identify every
attachment. Dot-prefix filtering applies to inventory enumeration, not explicit
guidance paths; operating-system Hidden/System attributes are not access-control
filters.
Uncontainable or unprovable paths always fail closed. An inaccessible optional
guidance source may be reported and skipped only without reading outside the
root.

**Alternatives considered:** Recursive shell enumeration followed by filtering
was rejected because it may traverse links or open excluded files before
filtering. Direct ordinary `Get-Content` was rejected because it bypasses
containment rechecks and protected byte reads. Excluding files based on
operating-system attributes was rejected because the specification requires
that a non-dot-prefixed Markdown file not be excluded for that reason.

**Evidence:** `skills/vault-orientation/scripts/VaultBoundary.psm1`
(`Resolve-DmVaultTarget`, `Confirm-DmVaultTarget`,
`Read-DmVaultTargetBytes`); `skills/vault-orientation/scripts/VaultInspection.psm1`;
`specs/006-vault-orientation-inventory/spec.md`;
`specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`.

## Shared pre-note integration

**Decision:** Reuse `Get-DmPreNoteContext`, but extend its configured/default
guidance read path to reject a non-Markdown source before any content read or
dependency fingerprint, including after resolving a file link. Register this
read-only inventory with `RequiresMappings=false` only so names-only
orientation can proceed without local guidance; the inventory itself must
block note-content reads until applicable guidance has loaded and must not
rely on unresolved mappings. The assistant independently loads the shared
reference under Feature 001. When interpreting configured guidance, inventory
reads it through the safe boundary against the dependency snapshot and
rechecks staleness before returning.

**Rationale:** The existing context helper checks guidance readability and
fingerprints bytes without first checking a Markdown extension, and returns
state and versions rather than the guidance text. Merely wrapping it cannot
guarantee the proposed non-Markdown read boundary or provide content for
evidence. The registration flag alone also cannot enforce the content gate.
Shared changes need regression tests for existing consumers.

**Alternatives considered:** Bypassing the helper or assuming its load flag
contains the guidance was rejected because that would duplicate preflight,
skip the type gate, or treat unobserved content as evidence. Making all
inventory require mappings was rejected because it blocks the specified
names-only orientation when no local guidance is present.

**Evidence:** `skills/vault-orientation/scripts/VaultConfiguration.psm1:396-426,620-660`;
`skills/vault-orientation/scripts/OperationRequest.psm1:153-231`;
`skills/vault-orientation/SKILL.md:18-38`.

## Profile and additional guidance

**Decision:** Load `.dmassist.yaml` and its configured/default guidance under
Feature 002 rules. Preserve the ordered `selectedGuidance` path array and add
an `optionalGuidance` path subset to express explicit DM optionality without
changing selection order. Identify skipped selections by their position in
the original request, rather than echoing non-Markdown filenames. A selected
source is essential by default. It is
usable only if readable Markdown has at least one non-empty body line outside
frontmatter and headings. A missing, unreadable, or unusable essential source
blocks dependent reads; an optional source with the same problem is reported
and skipped. Invalid or uncontained paths remain errors regardless of
optionality. Without any successfully loaded applicable local guidance, do
not read campaign-note contents.

**Rationale:** This preserves backward compatibility with the configuration
contract and the shared vault guidance contract, while making request-scoped
extra guidance explicit. Invalid present profiles and unavailable configured
guidance continue to use existing Feature 002 failure semantics; extra
task-essential guidance failures use the existing safe reference failure
behavior. A separate subset makes optionality explicit instead of guessing it
from file contents.

**Alternatives considered:** Making `.dmassist.yaml` request-selected was
rejected because it contradicts Feature 002. Automatically discovering and
loading arbitrary Markdown files was rejected because it would silently infer
guidance from filenames. Requiring a fixed schema for extra human-authored
guidance was rejected by the clarification. Treating every selected path as
essential was rejected because FR-016 allows the DM to mark it optional.

**Evidence:** `specs/002-vault-configuration-contract/data-model.md`;
`specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`;
`specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`;
`skills/vault-orientation/scripts/VaultConfiguration.psm1`;
`specs/006-vault-orientation-inventory/spec.md`.

## Candidate mappings and uncertainty

**Decision:** Return observed structure separately from candidate mappings.
Label each mapping `observed` only when directly stated by loaded guidance or
the profile; label name- or content-derived mappings `inferred`. Use the same
evidence-basis vocabulary in the data model and operation contract. Report
alternatives and their stable, evidence-bound identifiers. For an
orientation-only request, ambiguity is informational. When an ambiguity
affects proposed profile content, return the alternatives and require DM
direction before finalizing that content. A new request may carry an explicit
DM choice tied to the reported alternatives; a stale or invalid choice is
not silently applied. No choice persists or authorizes a profile write.

**Rationale:** Feature 002 already defines read-only discovery candidates as
non-persistent, inferred locations. Feature 006 requires an inventory that
reports organization without treating names as confirmed roles, and pauses
when ambiguity affects the requested task.

**Alternatives considered:** Treating conventional folder names as confirmed
roles was rejected because profiles may override defaults and folders can be
shared or nested. Automatically assigning every root-level Markdown note to
Adventures was rejected by the acceptance criteria. Persisting confirmed
mappings was rejected because the feature is read-only and proposals require
separate DM approval.

**Evidence:** `specs/002-vault-configuration-contract/data-model.md`;
`skills/vault-orientation/scripts/VaultConfiguration.psm1`
(`Get-DmVaultDiscovery`, `Resolve-DmSectionDestination`);
`specs/006-vault-orientation-inventory/spec.md`.

## Proposal, preview, approval, and apply

**Decision:** Inventory and its `drafted-unapproved` proposal never write.
Proposals for an existing profile must preserve unrelated values and comments;
if preservation cannot be established, report the limitation without
finalizing a replacement. This feature defines, but does not implement, a
separate profile-write boundary. If future work adds such an operation, the
caller must present a preview of the exact profile target and replacement
content, obtain explicit approval in a later message, and pass the
still-current preview identity and reviewed target/dependency versions to a
separate apply. The future operation must revalidate authorization,
containment, runtime/plugin identity, the target's prior existence/version,
dependencies, and exact replacement bytes. An absent profile requires a
separately designed atomic no-clobber create; an existing profile requires
guarded replacement. The caller must not bypass that boundary with a generic
note-edit operation or direct file write. Decline, staleness, and pre-write
validation failures must not change the target; a future writer must report
the actual or uncertain outcome if a failure occurs after an atomic commit.

**Rationale:** The user chose to define the write boundary only. The existing
runtime has preview and apply for registered note changes, but no
profile-specific writer or serializer, and its change plan requires the target
to exist.
Feature 003 approval binds the request, versions, replacement fingerprint,
plugin version, and runtime-module hashes, but the preview does not itself
show the replacement text. The caller must display content bound to that
fingerprint; an inventory proposal or a mapping selection is not authorization
to write. A complete future profile-specific create/replace and
byte-serialization contract is necessary before claiming profile writes are
supported.

**Alternatives considered:** Calling `Invoke-DmApply` directly on a proposal
was rejected because no compatible profile operation exists and the proposal
is not an approved runtime preview. Implementing a profile writer as part of
this read-only feature was excluded by the user's scope decision. Treating a
pre-preview instruction to prepare a write as approval was rejected because
the user has not yet reviewed the exact target and preview.

**Evidence:** `skills/vault-orientation/scripts/ChangePreview.psm1`;
`skills/vault-orientation/scripts/ApplyNoteChanges.psm1`;
`skills/vault-orientation/scripts/SafeNoteWriter.psm1`;
`specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`;
`specs/006-vault-orientation-inventory/spec.md`.

## Existing generic editor limitation

**Decision:** Document, but do not modify, the existing generic-editor
boundary in this feature. The inventory workflow must not use a generic edit
or direct file write to change `.dmassist.yaml`. A separate profile writer
would not by itself prevent an independent generic caller from bypassing the
profile-specific approval and validation rules.

**Rationale:** The current `note.replace-text` registration accepts an
existing regular file without a Markdown-extension restriction. A
single-target ordinary edit is not classified as requiring the Feature 003
approval fields, and the generic replacement builder does not validate the
result as a profile. Production script-backed access is currently blocked by
the unverified authorization handoff, but that block is not a profile-specific
guard. The user chose to document this limitation only; any runtime-wide
remediation is separate work.

**Alternatives considered:** Adding a guard to generic mutation operations was
excluded by the user's scope decision. Treating the generic operation as the
approved profile writer was rejected because it does not supply the required
profile-specific preview, approval, validation, and creation semantics.

**Evidence:** `skills/vault-orientation/scripts/OperationRequest.psm1:568-581`;
`skills/vault-orientation/scripts/ChangePreview.psm1:283-301,368-395`;
`skills/vault-orientation/scripts/ApplyNoteChanges.psm1:288-295`;
`skills/vault-orientation/scripts/SafeNoteWriter.psm1:347-375`.

## Platform, test, scale, and operational limits

**Decision:** Target stable PowerShell 7.6.9 or later and the Windows
candidate environment, validate with Pester 6.2.0 and synthetic disposable
vaults, and keep production script-backed note access fail-closed until the
trusted active-session authorization handoff is verified. Limit each request
to one explicit vault. The specification sets no vault-size, latency, or
throughput target; this plan does not invent one.

**Rationale:** These runtime versions and support limitations are recorded by
Feature 003. Its acceptance harness provides test-only authorization, which is
not production authorization evidence. The inventory is on-demand and
read-only, and no scale threshold is defined by the feature.

**Alternatives considered:** Claiming production access based on synthetic
tests was rejected because repository guidance explicitly separates test
authorization from the production handoff. Adding an arbitrary scan limit or
latency target was rejected because neither is specified.

**Evidence:** `docs/powershell-runtime-support.md`;
`docs/architecture.md`;
`specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`;
`tests/powershell/TestHarness.Tests.ps1`.
