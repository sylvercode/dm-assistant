# Quickstart: Read-Only Vault Orientation and Inventory

**Status: Proposed validation guide; Feature 006 is pending implementation.**
The scenarios below define acceptance checks for a future
`vault.orientation.inventory` operation. They are not claims about current
runtime behavior. The [operation contract](contracts/vault-orientation-inventory.md)
defines request/result details and failure codes; the [data model](data-model.md)
defines the request-scoped inventory concepts and validation boundaries.

## Prerequisites and test boundary

- PowerShell 7.6.9 on the candidate Windows environment, the declared
  `powershell-yaml` 0.4.12 dependency for profile scenarios, and Pester 6.2.0.
  See [PowerShell Runtime Support](../../docs/powershell-runtime-support.md)
  for current support and installation limits. The acceptance runner checks
  for Pester 6.2.0 and does not install it.
- Run from the repository root. Tests should use Pester's disposable
  `$TestDrive` and the ownership-checked fixture helpers in
  `tests/powershell/TestHarness.psm1`, such as
  `New-TestVaultFixture -ParentPath $TestDrive`. Create only invented notes,
  profiles, guidance, and file names. Do not point tests at a campaign vault.
- The test harness's authorization provider and dependency-readiness overrides
  are **test-only** mocks. They allow isolated tests to exercise code behind
  preflight; they do not prove production authorization, create an authorized
  real vault, or belong in the installed plugin. Without that provider,
  production script-backed access must remain fail-closed until the trusted
  active-session exact-vault handoff is implemented and verified.
- The Resolver is not needed for inventory traversal or containment. Do not
  call link-resolution operations as part of these checks.

Once implementation adds the proposed test file, run its focused suite:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1 -Path tests\powershell\VaultOrientationInventory.Tests.ps1
```

Run the complete existing acceptance suite as a regression check:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1
```

The focused command is a future acceptance target: the inventory operation
and its Pester tests do not exist yet, so it is not expected to pass against
the current tree. The runner's `-Path` parameter accepts a test file or folder.
Use the common request/result harness and production modules; do not make a
test-only implementation of the inventory algorithm.

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
per scenario. Capture a before/after fixture snapshot (names, file hashes, and
timestamps) around every inventory/proposal run; each read-only case must
leave it unchanged. Keep snapshots and output sanitized and inside the test
run.

## Acceptance scenarios

Run each row as an isolated Pester case. Where a scenario is expected to reach
inventory behavior, use the harness-only exact-root authorization provider
for that synthetic fixture. Assert the structured result using the
Feature 003 envelope and Feature 006 payload in the contract; do not invent
new codes or duplicate their field definitions here.

| Check | Synthetic setup and action | Expected outcome |
|---|---|---|
| Names-only without local guidance | Omit the profile and all applicable configured/default guidance. Include ordinary Markdown notes and recognizable synthetic words in their bodies/frontmatter. Request a non-content-dependent orientation. | The inventory reports eligible names/structure and name-based candidates only. `contentInspected` is false and no body/frontmatter-derived mapping or evidence appears. Loading the shared plugin reference alone does not open campaign-note contents. |
| Configured/default guidance gates content | Test separately with valid profile-designated guidance and with the Feature 002 default `.dmassist-guidance.md` candidate present and successfully loaded. Include marker text in Markdown note bodies/frontmatter. | After the applicable guidance is loaded, eligible Markdown contents, including frontmatter, may be inspected. Content-based findings cite the permitted evidence. Assert event/order instrumentation proves the guidance read completed before any campaign-note read. |
| Request-selected extra guidance | With no configured/default local guidance, explicitly select an existing readable Markdown guidance file such as `.extra-guidance.md`; then repeat with the selection omitted. | Selected guidance is additive and loaded before dependent note contents; explicitly selected dot-prefixed guidance is allowed, but it is never discovered by scanning. Without any applicable local guidance, notes remain names-only. |
| Dot-prefix versus OS hidden/system attributes | Include `.ignored.md` and `.private/secret.md`; also mark a non-dot-prefixed Markdown note hidden/system where the test OS permits. Enumerate the fixture. | Dot-prefixed entries and their descendants are absent from inventory traversal. The non-dot-prefixed Markdown entry remains eligible despite OS attributes; hidden/system metadata is not the exclusion rule. Skip or adapt only the OS-attribute setup if the platform cannot set or report it, while retaining the dot-prefix assertion. |
| Attachments and other non-Markdown content | Put unique marker bytes/text in `map.png`, a binary attachment, and `readme.txt`, alongside Markdown. Instrument safe reads or assert content-read records. | Names may be reported for eligible non-Markdown files, but attachment and other non-Markdown contents are never opened or used as mapping evidence. Both content-read flags remain false for these files. |
| Ambiguous mappings | Create two plausible synthetic section folders or a profile mapping that conflicts with observed organization. Request a task whose interpretation depends on that mapping. | Report the competing alternatives and their evidence; require DM direction and do not rely on either mapping for dependent work. The applicable ambiguity result follows the contract. Do not rename, move, or otherwise alter the fixture. |
| Profile proposal is read-only | Request a proposal with `proposeProfile: true` against a synthetic inventory, including at least one inferred or ambiguous mapping. | Return only an unapproved proposal, clearly distinguishing observed facts from inference and preserving unresolved alternatives. No `.dmassist.yaml` or other file is created or changed; fixture snapshot is identical. Decline/unapproved status must not trigger a write. |
| Profile and guidance failures | Test a malformed/present invalid `.dmassist.yaml`, an unavailable or unreadable configured/default guidance file, and a request-selected missing, unreadable, or non-Markdown source. Make guidance task-essential where required by the scenario. | Stop before reading dependent campaign-note content. Do not mask an invalid profile as an absent profile, substitute guessed guidance, or fall back to note-content inspection. Return the existing owner-contract failure code and safe diagnostic. |
| Preflight fails closed | Without enabling the test authorization provider, attempt the operation with dependency readiness missing/incompatible and then ready-but-authorization-unproven. Instrument profile, guidance, and note reads. | Stop before profile, guidance, or campaign-note access. Readiness failure reports the applicable prerequisite failure; ready-but-unproven authorization reports `VAULT_AUTHORIZATION_UNPROVEN`. No inventory payload implies notes were inspected. Repeat through the test harness only for downstream functional cases; never describe that mock as production authorization. |
| Symlink boundaries | In the synthetic fixture, create an in-vault directory/file link, a link to a sibling outside-boundary directory/file, and a cyclic or unresolvable link. Attempt traversal and any selected guidance/note read through each. Add a controlled swap-to-escaping-link case if the filesystem/test harness can do so reliably. | Do not follow directory links during traversal. Every access must revalidate canonical, component-aware containment. In-vault file links may be used only where the contract permits and containment is proven; escaping, cyclic, unresolvable, or raced links stop the operation with the applicable path/read error and no partial report, without reading outside content. Do not use string-prefix containment checks. |
| No write side effects | Run the ordinary, ambiguous, blocked, and proposal cases with before/after snapshots of the entire owned fixture. | Zero files or folders are created, edited, moved, renamed, or deleted in every inventory outcome, including proposal generation and failures. Cleanup removes only the unique fixture directory owned by the test. |

For Windows symlink coverage, directory symlinks may require elevation or
Developer Mode; a junction can exercise directory-link boundaries where
appropriate. If file-symlink creation is unavailable, mark only those cases
skipped with the environmental reason; do not claim those cases passed.
Include a disposable sibling target with an invented marker to prove that
outside content was not read.

## Completion and evidence

The guide is satisfied only when the future focused tests pass and the full
suite remains green. Record sanitized pass/fail counts, skipped symlink cases,
and platform/runtime versions separately from installed-client checks. Test
results using synthetic fixtures and mocked authorization do not establish
production access, installed-client behavior, or support for untested
operating systems. The production authorization handoff remains a separate
fail-closed prerequisite; a successful local test must not be presented as
real-vault authorization.

These are proposed checks pending implementation. Until then, the current
runtime does not provide the Feature 006 inventory operation, and this guide
does not imply that any listed scenario has been executed.
