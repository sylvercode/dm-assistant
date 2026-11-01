# Quickstart: Link Resolver Integration

This guide validates the required Obsidian Link Resolver integration without
using campaign notes. Use only a disposable test vault. The Resolver is a
separately installed MCP server; it is not installed by the plugin.

See the [Resolver MCP contract](contracts/resolver-mcp-contract.md) for the
normative readiness, authorization, privacy, and outcome rules, and the
[data model](data-model.md) for the conceptual states.

## Prerequisites

- GitHub Copilot CLI installed and available.
- Obsidian Link Resolver MCP release `2.1.0` or later, installed separately
  using the [upstream instructions](https://github.com/sylvercode/obsidian-link-resolver).
- A disposable vault directory with no campaign content.
- A vault-facing skill/plugin installation containing the changes being
  validated.

Do not use a production vault for the failure cases below. Do not copy private
vault paths into repository files, shared examples, or test output.

## Configure and verify a fresh client session

1. Configure the Resolver through a supported GitHub Copilot CLI MCP
   configuration location, such as the user configuration or a repository
   `.mcp.json` / `.github/mcp.json`. Use the Copilot CLI's `type: local`
   configuration format and the Resolver's documented executable and
   arguments. Supply the disposable vault as an explicitly authorized
   `--vault` root. Do not use the VS Code `.vscode/mcp.json` example; Copilot
   CLI does not read that configuration.
2. Start a new Copilot CLI session so it loads the current MCP settings.
3. Use `copilot mcp get <server-name>` or the `/mcp` interface to confirm that
   the server is available and both `get_server_info` and
   `resolve_obsidian_link` are exposed. These checks confirm status and tools,
   not the minimum server version or vault authorization.
4. Ask the client to call `get_server_info` without arguments. Confirm the
   reported version is `2.1.0` or later and that a returned canonical
   `vaults[].path` exactly matches the disposable vault under Feature 001's
   normalization rules. This call must not read note content.
5. Confirm the vault-facing skill proceeds to link resolution only after this
   check succeeds. Record only pass/fail and sanitized diagnostic details;
   avoid copying private paths or note content into test reports.

**Expected result:** A fresh session reports a compatible Resolver, exposes
both required tools, and confirms an exact authorized-root match. Server
availability or successful link resolution alone does not satisfy this check.

## Verify fail-closed cases

Run each case in a fresh session with no campaign notes in the disposable
vault. Confirm the skill identifies the unmet prerequisite and stops before
campaign-note access or changes.

| Case | Setup | Expected result |
|---|---|---|
| Server unavailable | Temporarily disable the Resolver configuration. | Stop before note access; explain that the required server is unavailable. |
| Required tool unavailable | Use a test configuration that does not expose one required tool. | Stop before note access; identify the unavailable capability. |
| Incompatible or unconfirmed version | Use a Resolver below `2.1.0`, or a response where the version cannot be confirmed. | Stop before note access; report the compatibility failure. |
| No exact authorized root | Configure a different test root, or only a parent/child of the intended test vault. | Stop before note access; do not treat containment or a resolved link as authorization. |
| Stale session | Change the configured roots after the client session starts. | Treat existing evidence as unconfirmed, request a fresh session, and do not access notes. |
| Invalid server information | Make `get_server_info` fail or return no usable root list. | Stop before note access; report that authorization could not be confirmed. |

Restore the valid disposable-vault configuration and create a fresh session
before the next checks.

## Verify resolution outcomes

Using only the disposable vault and valid preflight evidence, exercise a
controlled input for each Resolver outcome. Confirm that the skill reports
the outcome and available relevant details without changing notes or guessing
a destination.

| Resolver outcome | Expected result |
|---|---|
| Resolved | Report the Resolver's destination. |
| Unresolved | Report that no destination was found; do not guess. |
| Missing subtarget | Report the missing requested subtarget; do not substitute another. |
| Ambiguous | Report the ambiguity and available candidates; do not select one. |
| Error | Report the failure and available relevant details; do not present it as resolved. |

The Resolver's upstream documentation defines the exact tool arguments and
response representation. Do not invent test payload fields or treat the
conceptual outcome names in this guide as wire-format values.

## Repository checks

From the repository root, inspect the skill inventory and confirm that every
immediate-child `skills/*/SKILL.md` file has exactly one classified entry in
`skills/README.md`. For every vault-facing skill, verify that its instructions
check the shared dependency contract and exact-vault authorization before
campaign-note access.

If PowerShell runtime code or its test surfaces changed, run the existing
synthetic acceptance suite:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1
```

Record source/static checks, synthetic test results, and installed-client
verification as separate evidence. Passing local tests do not establish an
installed-client authorization handoff or enable production script-backed
vault access.
