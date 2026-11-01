# Research: Read-Only Vault Orientation and Inventory

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

**Alternatives considered:** A new command or MCP integration was rejected
because no transport or plugin integration is required, and the runtime
contract explicitly defers transport choice. A standalone inventory scanner
was rejected because it would duplicate or bypass established preflight and
path-boundary safeguards.

**Evidence:** `specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`;
`specs/002-vault-configuration-contract/data-model.md`;
`specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`;
`skills/vault-orientation/scripts/RuntimeContract.psm1`;
`skills/vault-orientation/scripts/VaultInspection.psm1`.

## Read-only traversal and content boundary

**Decision:** Enumerate one explicitly authorized vault without following
directory links during traversal. Exclude dot-prefixed entries from inventory
enumeration; explicitly selected dot-prefixed guidance and Feature 002
profile/designated guidance are loaded separately, not discovered by scanning.
Filter extensions before opening files. Include names for entries; inspect
Markdown contents, including frontmatter, only after applicable configured or
request-selected local guidance is loaded. Without such guidance, report
name-based candidates only. Resolve and revalidate every selected target
through the existing boundary APIs before reading bytes. Never open
attachments or non-Markdown contents.

**Rationale:** This satisfies the inventory scope while preserving Feature
001's limited no-guidance read boundary, Feature 002's configured/default
guidance behavior, and Feature 003's safe path access. Dot-prefix filtering
applies to inventory enumeration, not explicit guidance paths;
operating-system Hidden/System attributes are not access-control filters.
Uncontainable or inaccessible paths must fail closed or be reported as
unavailable without reading outside the root.

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

## Profile and additional guidance

**Decision:** Load `.dmassist.yaml` and its configured/default guidance under
Feature 002 rules. Load any additional Markdown guidance only when the DM
selects it for the current request. A selected extra source must be readable
Markdown and contain usable guidance essential to the task; no fixed schema is
required. Without any applicable local guidance, do not read campaign-note
contents.

**Rationale:** This preserves backward compatibility with the configuration
contract and the shared vault guidance contract, while making request-scoped
extra guidance explicit. Invalid present profiles and unavailable configured
guidance continue to use existing Feature 002 failure semantics; extra
guidance failures use the existing safe reference failure behavior.

**Alternatives considered:** Making `.dmassist.yaml` request-selected was
rejected because it contradicts Feature 002. Automatically discovering and
loading arbitrary Markdown files was rejected because it would silently infer
guidance from filenames. Requiring a fixed schema for extra human-authored
guidance was rejected by the clarification.

**Evidence:** `specs/002-vault-configuration-contract/data-model.md`;
`specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`;
`specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`;
`skills/vault-orientation/scripts/VaultConfiguration.psm1`;
`specs/006-vault-orientation-inventory/spec.md`.

## Candidate mappings and uncertainty

**Decision:** Return observed structure separately from candidate mappings.
Use deterministic evidence from existing configured/default section paths,
folder and file names, and (only when guidance permits) Markdown content.
Represent inferred mappings with their evidence and alternatives; do not
persist them or use an unresolved mapping for dependent work. Do not classify
every root-level note as an adventure.

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

## Platform, test, scale, and operational limits

**Decision:** Target the existing PowerShell 7.6.9 runtime and Windows
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
