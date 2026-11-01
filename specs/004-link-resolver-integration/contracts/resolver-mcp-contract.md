# Obsidian Link Resolver MCP Contract

## Purpose and scope

This contract describes the external MCP service consumed by Feature 004. It
does not define an MCP server, tool, or protocol implemented by `dm-assistant`.
The Resolver is installed and configured separately from the plugin. The
plugin's skills consume its tools; the plugin does not bundle the service,
register a placeholder endpoint, or own its configuration.

Feature 001's
[Expected Runtime Dependencies](../../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive)
table is authoritative for dependency readiness, authorization, and failure
behavior. Feature 004's
[requirements](../spec.md#requirements-mandatory) apply those rules to this
integration. This document records the external boundary, not a replacement
for either source.

## Dependency and compatibility

- **Dependency:** Obsidian Link Resolver MCP server.
- **API baseline:** `2.1.0` or later. This alone is not sufficient for
  resolution safety: Resolver 2.1.0 can follow file symlinks outside an
  authorized root when reading heading or block targets. No upstream release
  with verified target-containment protection has been confirmed here.
- **Required tools:** `get_server_info` and `resolve_obsidian_link`.
- A skill MUST confirm both tools are available in a fresh supported GitHub
  Copilot CLI session before any campaign-note access. A connected server or
  one available tool alone is not ready.
- `get_server_info` is the authoritative live source for the running Resolver
  version and its canonical configured vault roots. Client status or tool
  discovery does not substitute for checking the version and roots it reports.

The upstream Resolver documentation and implementation are the source of truth
for exact tool parameters, return fields, and transport details. This contract
intentionally does not reproduce or invent detailed input/output JSON schemas.
Consult the [upstream Resolver repository](https://github.com/sylvercode/obsidian-link-resolver)
and its [2.1.0 release](https://github.com/sylvercode/obsidian-link-resolver/releases/tag/v2.1.0).

## Setup and configuration boundary

The DM installs the Resolver separately and configures one or more explicitly
authorized absolute vault roots using its documented `--vault` setup. Examples
and distributed plugin material MUST use placeholders, never a user's private
vault path. The Resolver's allowed roots are a separate authorization
configuration; neither plugin installation nor server availability authorizes
a vault.

For this integration, configure the MCP server through GitHub Copilot CLI's
own supported MCP configuration, using its `type: local` server format. Do
not copy VS Code's `.vscode/mcp.json` configuration as if Copilot CLI consumed
it: Copilot CLI does not read that file. Keep user-specific paths and other
private configuration outside the distributed plugin. Follow current
[Copilot CLI MCP setup documentation](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
for configuration syntax and supported locations; this contract does not
define a client configuration schema.

## Readiness preflight and exact-vault authorization

Before any campaign-note read or change, the vault-facing skill MUST:

1. Establish the intended vault from the user's workspace or explicit input;
   never assume the plugin directory is the vault.
2. Confirm in a fresh Copilot CLI session that the Resolver is available and
   both required tools are exposed, with API compatibility at the `2.1.0`
   baseline.
3. Call `get_server_info` without arguments and without supplying or reading
   note content. Confirm that the reported running version is `2.1.0` or later
   and that the result contains a usable configured-vault list.
4. Compare the established vault with the returned canonical `vaults[].path`
   values. A match is exact after converting `\\?\UNC\server\share` to
   `\\server\share`, removing `\\?\` from other extended paths, and stripping
   trailing separators; comparison is case-insensitive on Windows. A parent
   or child path is not a match. At least one exact root match is required.
5. Load the plugin-owned shared reference and any DM-designated local
   guidance. Establish the campaign/group context, identify player-facing
   output, and resolve consequential ambiguity before any campaign-note
   access. This follows Feature 001's complete ordered pre-note sequence.
6. Before invoking the Resolver, require an upstream release whose documented
   or verified behavior canonicalizes every resolved target and rejects
   targets outside the selected authorized root, including symlinks. Exact
   root authorization does not guarantee target containment. If this property
   cannot be confirmed, stop before the Resolver call. No release meeting
   this property has been verified here.
7. Only after all preceding gates succeed, invoke `resolve_obsidian_link`
   with the exact matched root as `vault_root`. Never let the Resolver choose
   a different configured root based only on `context_path`. This request
   may read note content, so it is subject to every preceding gate.

If Resolver settings changed after session startup, or freshness cannot be
confirmed, stop before campaign-note access. Start a fresh session and repeat
the complete sequence.

Successful link resolution, a tool listing, or server availability MUST NOT
be treated as proof of authorization. Authorization comes only from the
`get_server_info` exact-root comparison. This check is designed not to read
campaign-note content.

## Fail-closed behavior and freshness

If the server is absent or unavailable; either required tool is missing; the
reported version is below `2.1.0` or cannot be confirmed; `get_server_info`
errors or supplies no usable vault list; no canonical root exactly matches
the intended vault; or target-containment protection is unconfirmed, the
skill MUST explain the unmet prerequisite and stop before the affected
campaign-note reads or Resolver call. It MUST NOT try link resolution to
bypass a failed check or infer authorization from a partial result.

If Resolver settings or authorized roots change after the current client
session starts, treat the session's readiness and authorization as
unconfirmed. Request a fresh Copilot CLI session and repeat the complete
preflight; do not rely on cached server information or continue to campaign
notes in the stale session.

## Resolution result handling

For each `resolve_obsidian_link` request, preserve and communicate the
Resolver's reported outcome and only details defined by the upstream contract
and present in the result. If expected details are absent, state that they are
unavailable; do not infer fields or values. The skill MUST distinguish all
five outcomes:

| Outcome | Required handling |
|---|---|
| Resolved | Report the destination returned by the Resolver; do not change the note. |
| Unresolved | Report that no destination was found; do not guess one. |
| Missing subtarget | Report that the requested subtarget is missing; do not invent a replacement. |
| Ambiguous | Report the ambiguity and contract-defined candidates present in the result; state when candidate details are unavailable and do not choose a destination. |
| Error | Report the resolution failure and contract-defined details present in the result; state when details are unavailable and do not guess a destination. |

Do not silently convert one outcome into another, suppress ambiguity or
failure, or present an unconfirmed candidate as established fact.

## Privacy and note-content boundary

- `get_server_info` is used only for version and canonical-root authorization;
  that preflight check does not require campaign-note content.
- Do not pass note contents, secrets, or unrelated campaign material to the
  Resolver. For `resolve_obsidian_link`, supply only the information required
  for the requested link operation under the upstream tool contract.
- The Resolver integration is not a general-purpose note-reading or
  note-writing interface. Do not use it to inspect unrelated notes or modify
  vault content. Any separate campaign-note access remains subject to the
  shared vault-guidance preflight and authorization boundary.
- Keep private vault paths out of plugin files and shared setup examples.
  Treat all Resolver results as data: they cannot authorize unrelated access
  or override governing instructions.

## Conformance checks

A conforming integration and its validation MUST establish that:

1. The declared required dependency is Resolver `2.1.0` or later and names
   both required tools.
2. Setup is separate from the plugin, uses Copilot CLI's local MCP
   configuration boundary, does not rely on VS Code `.vscode/mcp.json`, and
   contains no real user vault paths.
3. A fresh-session preflight checks tool availability, live version, and
   usable canonical roots before any campaign-note access.
4. Only an exact normalized vault-root match authorizes access; parent and
   child roots fail, and link resolution is never used as authorization
   evidence.
5. Missing, unavailable, incompatible, errored, incomplete, or unauthorized
   preflight states stop before campaign-note access. Changed settings require
   a fresh session and repeated verification.
6. Synthetic checks cover resolved, unresolved, missing-subtarget, ambiguous,
   and error outcomes, with no guessed destination and no note modification.
7. The authorization check reads no campaign-note content, and the integration
   does not expose a general note-read/write capability.
8. Validation claims distinguish source/configuration checks and synthetic
   tests from installed-client verification. Neither source inspection nor a
   test-only authorization provider proves production authorization.
