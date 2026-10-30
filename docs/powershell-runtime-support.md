# PowerShell Runtime Support

**Status: Feature 003 runtime support record.** This document records the
PowerShell 7 release, operating systems, and add-on versions selected for the
script-backed vault operations described in
[`specs/003-powershell-runtime-safety/`](../specs/003-powershell-runtime-safety/).
Installing the plugin and discovering its skills never requires PowerShell.
No workflow installs or upgrades PowerShell or any module.

Feature 001 uses Resolver 2.1.0's note-content-free `get_server_info` response
to check exact-vault authorization in the active client session. The
PowerShell runtime cannot yet verify a trusted handoff from that session, so
script-backed vault access remains blocked before reading a profile, guidance,
or campaign note. An unconfirmed dependency returns `PREREQUISITE_MISSING`;
if readiness is established but authorization is not, the runtime returns
`VAULT_AUTHORIZATION_UNPROVEN`. A supported environment below does not imply
that script-backed campaign-vault access works.

The packaged dependency inventory requires Resolver 2.1.0 or later with both
`resolve_obsidian_link` and `get_server_info`. The production PowerShell probe
cannot confirm the running server's version or active-session tools, and it
does not treat a configured server as proof of readiness or authorization.

## Selection

| Item | Selection |
| --- | --- |
| Selection date | 2026-10-29 |
| PowerShell | `pwsh` **7.6.9**, the latest stable PowerShell 7 release available at selection time |
| Minimum PowerShell | 7.4, required so the built-in `Test-Json -Schema` validates JSON Schema Draft 2020-12; versions other than the selected release are unsupported |
| YAML reader | `powershell-yaml` **0.4.12** (exact version), required by profile-dependent operations |
| JSON Schema validator | Built-in `Test-Json -Schema`; no separate validator module |
| Test runner (test-only) | Pester **6.2.0** (exact version); never a prerequisite for installing the plugin or for a DM's workflow |

The runtime prerequisite check in
`skills/vault-orientation/scripts/RuntimePreflight.psm1` enforces the selected
PowerShell version, operating system, and exact module versions, and returns
`PREREQUISITE_MISSING` without installing or upgrading anything.

## Support matrix

A combination is listed as supported only after it passes the prerequisite,
repeatability, and failure checks and reliably performs the path-resolution,
atomic-replace, and encoding checks the contract requires. Every other
combination is unsupported.

| Operating system | PowerShell | Add-ons | Status |
| --- | --- | --- | --- |
| Windows | 7.6.9 | `powershell-yaml` 0.4.12 | Candidate, not supported for production script-backed vault access. Local path-boundary, atomic-replace, and encoding cases pass; four file-symlink cases, installed-client checks, and the runtime authorization handoff remain unverified. |
| Windows | Any other version | Any | Unsupported |
| macOS | Any | Any | Unsupported (unverified) |
| Linux | Any | Any | Unsupported (unverified) |

## Provisioning guidance

Obtain prerequisites yourself before using a script-backed workflow; the
workflow only checks them.

1. Install PowerShell 7.6.9 by following Microsoft's
   [Installing PowerShell on Windows](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
   guidance (for example, the MSI or `winget` package for that exact version).
2. In `pwsh`, install the exact YAML reader version for the current user:
   `Install-Module -Name powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser`.
3. Confirm with `$PSVersionTable.PSVersion` and
   `Get-Module -ListAvailable -Name powershell-yaml`.
4. Do not change execution policy, permissions, or security software for this
   plugin. A workflow that is blocked by these controls stops; read-only
   assistance that does not need scripts remains available.

Contributors running the acceptance tests also need Pester 6.2.0
(`Install-Module -Name Pester -RequiredVersion 6.2.0 -Scope CurrentUser`).
Run the suite with `pwsh -NoProfile -File tests/powershell/Invoke-Tests.ps1`;
it imports Pester 6.2.0 explicitly and never uses the Windows built-in
Pester 3.4.0.

## Verification evidence

Results are sanitized: no vault paths, note content, or user names are
recorded. All tests use synthetic disposable vaults.

### Windows, 2026-10-29 (Feature 003 T010)

| Item | Observed |
| --- | --- |
| Operating system | Windows 10.0.26300 (x64) |
| PowerShell | `pwsh` 7.6.9, Core edition |
| `powershell-yaml` | 0.4.12 |
| Pester (test-only) | 6.2.0 |
| Copilot CLI | 1.0.105 |

- **Full suite.** `pwsh -NoProfile -File tests/powershell/Invoke-Tests.ps1`
  gave 99 passed and 0 failed: 56 contract tests and 43 preflight tests.
- **Repeatability.** The preflight tests were run again from a different
  working directory (the user temp directory) and passed 43 of 43. Within the
  suite, preflight was invoked from three working directories and returned the
  same code each time.
- **Production gate with no authorization provider.** With dependency
  readiness simulated as `ready`, preflight returned `not completed` /
  `VAULT_AUTHORIZATION_UNPROVEN`, and every target was `not attempted`.
  - The profile and notes were held under exclusive locks, filesystem cmdlets
    that named the fixture were spied on, and before/after snapshots were
    compared. There were no profile or note reads and no writes.
  - No `Install-*`, `Update-*`, or `Save-*` module command was invoked.
  - The result did not change for authorization-like request fields,
    environment variables, profile keys, `.mcp.json` content, marker files,
    or vault names.
- **Failure cases.** These all returned `PREREQUISITE_MISSING` before any
  readiness or authorization check:
  - PowerShell 7.3.12, 7.4.0, and 7.7.0, and Windows PowerShell 5.1 (Desktop
    edition);
  - macOS, Linux, or an unknown operating system;
  - `powershell-yaml` missing, 0.4.7, or only 0.4.13.

  Other failure cases:
  - A missing, incompatible, or unknown dependency state returned
    `PREREQUISITE_MISSING` with no authorization query.
  - A missing inventory asset returned `RESOURCE_MISSING`.
  - Malformed requests returned `INVALID_REQUEST` before the readiness check.
- **Real dependency probe.** `copilot mcp get obsidian-link-resolver` reported
  the server as not configured, so readiness was `missing`. Real preflight
  therefore stopped with `PREREQUISITE_MISSING` for the then-declared
  `obsidian-link-resolver` 2.0.0 / `resolve_obsidian_link` requirement.
  - Even when the server is configured, a script cannot confirm its version or
    the tools the session exposes, so readiness is reported as `unknown`.
    `unknown` is not success.
- **Static install and discovery need no PowerShell.** This was checked by
  inspection, not by an install run on a machine without PowerShell.
  - `plugin.json` contains only static metadata. It declares no hooks, MCP
    servers, install steps, or component paths.
  - The repository contains no hook or `.mcp.json` file.
  - Skill discovery reads `skills/*/SKILL.md` front matter and needs no script
    execution. The scripts run only when a vault-facing workflow invokes them.
- **Not verified.** macOS and Linux were not tested and remain unsupported.
  Windows stays a candidate until the path-resolution, atomic-replace, and
  encoding checks of later Feature 003 tasks pass.

### Windows, 2026-10-29 (Feature 003 T017–T019)

Same environment as the T010 entry above.

- **Full suite.** `pwsh -NoProfile -File tests/powershell/Invoke-Tests.ps1`
  gave 207 passed, 0 failed, and 4 skipped: 56 contract tests, 43 preflight
  tests, 96 vault-selection and path-boundary tests (4 skipped), and 16
  installed-resource tests.
- **Repeatability.** The vault-selection and installed-resource files were run
  again from a different working directory (the user temp directory): 92
  passed with 4 skipped, and 16 passed. Within the suite, inspection was
  invoked from five working directories and produced the same selection,
  canonical root, and result each time.
- **Production gate first.** With no authorization provider, inspection
  returned `VAULT_AUTHORIZATION_UNPROVEN` before root resolution or any note
  access, including for a missing vault root. The test-only provider was used
  only for the downstream cases below.
- **Request and lexical path validation.** Malformed requests (unknown or
  wrong-case fields, unregistered operations, unsupported modes or arguments,
  malformed targets, relative/home/variable/device/wildcard vault roots, and
  misplaced approval fields) returned `INVALID_REQUEST`, and forbidden
  vault-relative paths returned `PATH_INVALID`, both before readiness.
- **Vault root and containment.** Missing, file, ambiguous (`.` or `..`), and
  missing-drive roots returned `VAULT_TARGET_INVALID` after authorization. A
  linked root resolved to its canonical folder.
- **Links.** Directory symbolic links need elevation here, so directory cases
  used junctions. In-vault intermediate and leaf links were followed; escaping
  intermediate and leaf links, cyclic chains, and a folder swapped for an
  escaping link between resolution and access returned `PATH_OUTSIDE_VAULT`
  without reading outside the vault. A root moved after resolution was
  detected.
  - **Skipped.** Four file-symbolic-link cases were skipped because file
    symbolic links need Windows Developer Mode or elevation in this
    environment.
- **Inspection.** Existence, type, and SHA-256 byte fingerprints were reported
  without content. Missing targets and variable or home markers were reported
  as literal missing names. A locked note returned `READ_FAILED` at that
  target, and an inaccessible component returned `READ_FAILED` before any
  read. Fixture snapshots were unchanged after every test.
- **Installed schema resource.** The shipped content (`plugin.json` and
  `skills/`) was copied to a disposable install folder, and the resource
  module was imported from there.
  - From four working directories in-process, and from a fresh `pwsh` process
    started in another directory, the lookup loaded the same installed
    artifact, with the same SHA-256 version as the repository file.
  - The installed Draft 2020-12 artifact accepted `{"version":1}` and rejected
    `{"version":2}` and unknown properties.
  - A deleted artifact returned `RESOURCE_MISSING`, with no fallback to decoy
    copies in the working directory or the repository checkout.
  - Malformed JSON, invalid UTF-8, a Draft-07 dialect, a different `$id` or
    title, an open profile object, and an unpinned or unrequired version
    returned `RESOURCE_INCOMPATIBLE`.
  - Blocked results contained no install or temporary paths.
- **Not verified.** This was a simulated installed copy, not a
  client-installed run. macOS and Linux were not tested and remain
  unsupported. Windows stays a candidate until the atomic-replace and encoding
  checks of later Feature 003 tasks pass.

### Windows, 2026-10-30 (Feature 003 T020–T029)

Same Windows/pwsh/dependency versions as above; all fixtures were synthetic.

- **Profile parsing and normalization.** Duplicate keys, malformed YAML,
  merge-key/schema mismatch, nulls, and collection values were rejected.
  Typed scalars were normalized and profile version remained an integer.
- **Schema and defaults.** The installed Draft 2020-12 artifact was checked
  with built-in `Test-Json -Schema`; valid normalized profiles passed,
  unknown fields failed with `PROFILE_SCHEMA_INVALID`, and schema defaults
  were applied only after validation without mutating the source.
- **Filesystem and references.** Explicit missing/wrong-type section paths,
  missing preparation folders, unsafe configured paths, and an escaping
  directory link were rejected. Missing guidance, template, party, and
  preparation references returned `REFERENCE_UNAVAILABLE` when checked.
  Shared/nested mappings produced `AMBIGUOUS_CONTEXT`; absent discovery was
  read-only and deterministic; a changed profile returned `TARGET_CONFLICT`.
- **Pre-note sequence.** The production gate with no authorization provider
  blocked before profile access. With a harness-only provider, tests verified
  the ordered gate/context sequence; a specific direct inspect lookup without
  designated guidance completed, while mapping-dependent inspect stopped
  with `AMBIGUOUS_CONTEXT`.
- **Test result.** The profile-focused suites passed 24 tests. The complete
  suite gave 231 passed, 0 failed, and 4 skipped, including those profile
  tests. This does not verify the runtime's handoff to Feature 001's real
  authorization signal or enable production script-backed profile/note access.
- **Not verified.** Only Windows was tested. Windows remains a candidate
  until preview/write atomicity and encoding verification pass; macOS/Linux
  remain unsupported.

### Windows, 2026-10-30 (Feature 003 T030–T042)

Same Windows/pwsh/dependency versions as above; all fixtures were synthetic.

- **Encoding policy.** Only strictly decoded BOM-marked UTF-8/UTF-16 and
  BOM-less UTF-8 that round-trip byte-for-byte are supported. These formats
  preserve their original encoding and line endings exactly; other encodings
  return `ENCODING_UNSAFE` and are never converted. The conversion-warning
  flow was removed because every supported encoding round-trips exactly while
  unsupported or undecodable input must fail closed.
- **Preview and approval.** Preview made no writes and carried ordered target
  and dependency versions. Exact approval, stale target/profile/guidance/
  template rejection, changed request/replacement/runtime invalidation,
  withdrawal, and deterministic preview IDs across separate processes passed.
- **Safe writes.** BOM-marked UTF-8/UTF-16 and BOM-less UTF-8 preserved their
  original bytes and mixed line endings. Unsupported/undecodable content was
  left unchanged. Atomic replacement, multi-target failure, interruption,
  diagnostics, and command-like data handling passed; the static audit covered
  the completed production scripts.
- **Complete suite.** `pwsh -NoProfile -File
  tests/powershell/Invoke-Tests.ps1` passed 299 tests with 0 failures and 4
  skipped. The skips are file-symbolic-link cases requiring Windows Developer
  Mode or elevation. The focused suites included 12 preview/approval cases,
  3 encoding cases, 7 atomic batch cases, and 5 data-handling/static-audit
  cases.
- **Runtime help.** A source audit checked comment-based help for all 106
  runtime functions and their 227 declared parameters; exported and private
  parameter help was also retrieved through `Get-Help`.
- **Scope limits.** This is local Windows acceptance evidence only; it does
  not verify the runtime in an installed Copilot client, its handoff to
  Feature 001's exact-vault check, or macOS/Linux. Windows remains a candidate
  and production script-backed vault access remains blocked.

### Windows, 2026-10-30 (Resolver 2.1.0 merge)

Same Windows/pwsh/dependency versions as above; all fixtures were synthetic.

- **Complete suite.** The Pester runner passed 310 tests with 0 failures and
  4 skipped file-symbolic-link cases requiring Windows Developer Mode or
  elevation.
- **Dependency reconciliation.** The inventory mirrors Feature 001's
  Resolver 2.1.0 minimum and both required tools. Empty, duplicate, or
  incompatible inventory entries fail closed. The production gate still
  cannot verify readiness or exact-vault authorization from the active session.
- **Approval safety.** Changing the inventory after preview invalidated the
  approval; changing it immediately before replacement produced a conflict
  without writing. Function and parameter help checks passed.
- **Static audit.** The one immediate-child skill matched the classified skill
  inventory and included the ordered vault-facing safeguards.
- **Scope limits.** No new installed-client or cross-platform verification was
  performed. The runtime handoff and single-note classification remain
  outstanding before production script-backed writes.

### Remaining acceptance work

- **T045:** No five-DM usability walkthrough has been performed. SC-006's
  anonymized pass rate is not available; automated result-contract checks do
  not substitute for this review.
- **T010/T046:** A complete client-installed quickstart and installation/skill
  discovery without PowerShell have not been performed. The disposable copied
  package checks above are not client installation evidence. No supported
  production platform combination is claimed.
- **T047:** The runtime has no verified way to consume the active session's
  Resolver readiness and exact-vault authorization evidence.
- **T048:** Before enabling production writes, reconcile single-note operation
  classification with Feature 001's approval requirement for actual-play and
  continuity changes.

## Implemented operation interface

The registry in `skills/vault-orientation/scripts/OperationRequest.psm1`
defines these built-in request operations. They use the common request/result
contract; they are not shell commands and production vault access remains
blocked by prerequisite/authorization checks.

| Operation | Modes | Arguments | Target outcomes and scope |
| --- | --- | --- | --- |
| `notes.inspect` | `inspect` | Empty object | One or more explicit targets; reports existence, type, and byte fingerprint without returning note content or changing established facts. |
| `note.replace-text` | `preview`, `apply` | Required non-empty string `oldText`; required string `newText` (may be empty) | Replaces every ordinal occurrence in one or more explicit existing notes; unchanged targets stay unchanged. Registered as a local text edit, not a workflow for changing actual-play records or established campaign facts. The invoking skill must apply the broader preview/approval safeguards, including approval in a later message, to such work. |

Unknown request fields and operation arguments are rejected. Multi-target
changes require approval of the exact preview. Applying a change preserves
supported encoding and line endings, stops at the first failure, and reports
earlier completed writes without rollback. Full argument, approval, diagnostic,
and result rules are in the
[runtime contract](../specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md).

## Function and parameter help

Each function in `skills/vault-orientation/scripts/` has PowerShell
comment-based help, including its declared parameters. Import the relevant
module and use `Get-Help` to inspect an exported function:

```powershell
Import-Module .\skills\vault-orientation\scripts\OperationRequest.psm1
Get-Help Register-DmOperation -Full
Get-Help Register-DmOperation -Parameter Builder
```

Private helper documentation is in the module source and can also be viewed in
that module's scope:

```powershell
Import-Module .\skills\vault-orientation\scripts\VaultConfiguration.psm1
& (Get-Module VaultConfiguration) {
    Get-Help ConvertTo-DmProfileNormalizedValue -Full
}
```

The help documents local module interfaces; it does not bypass the production
authorization gate or establish installed-client support. The runtime
fingerprint includes module file bytes and the packaged dependency inventory,
so changing either invalidates earlier preview approvals; generate and approve
a fresh preview.
