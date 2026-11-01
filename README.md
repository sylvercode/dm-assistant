# DM Assistant

A GitHub Copilot plugin scaffold for helping Dungeon Masters organize and run tabletop RPG campaigns stored in an Obsidian vault.

## Overview

The plugin will give an AI assistant a focused set of tools and guidance for working with campaign notes written in Markdown. The vault remains the campaign workspace: the assistant can help find and connect information, make supported changes, and produce useful summaries without treating campaign content as unstructured chat history.

## Planned Capabilities

- **Campaign organization:** Follow a documented vault structure and conventions for where different kinds of campaign information belong.
- **Vault assistance:** Help the Dungeon Master create, update, and organize campaign notes in Markdown.
- **Summaries:** Turn campaign material into concise summaries for preparation, play, or review.
- **Guided workflows:** Use skills that describe how to handle common Dungeon Master tasks and which tools are appropriate for each one.
- **Specialized tools:** Provide tools for campaign-specific operations, including resolving links between notes.

## Design Goals

- Keep the Obsidian vault and its Markdown files as the campaign's working knowledge base.
- Make information predictable to find by using documented file and folder conventions.
- Give the assistant clear, task-specific guidance instead of relying on broad instructions alone.
- Make changes and summaries useful to the Dungeon Master while keeping campaign material organized.

## Project Status

This repository contains an Agent Plugins 1.0 plugin with a portable
vault-orientation skill and its bundled shared reference. It does not bundle
the Obsidian Link Resolver server or enable production script-backed vault access.
PowerShell modules implement prerequisite checks, profile validation,
read-only inspection, preview approval, and conflict-aware atomic note writes;
these have local synthetic acceptance coverage, not installed-client or
cross-platform verification. Installed
cross-skill resource loading was verified in a disposable two-skill fixture
using owner-skill activation, not assumed sibling paths. The orientation skill
checks exact-vault authorization with the separately configured Resolver's
`get_server_info` tool and must stop when that check cannot be established.
The PowerShell runtime cannot yet verify a handoff from the active session and
remains fail-closed. Other planned capabilities above are not currently available.

See [Plugin Architecture](docs/architecture.md) for component locations, extension boundaries, and the separation between the plugin and campaign vaults.

## Intended Vault Structure and Workflow

The following conventions describe the intended workflow for users and AI
guidance. The vault-orientation skill and bundled reference encode these
boundaries; earlier installed-client scenarios used a disposable fixture, but
the merged script-backed workflow has not been verified in an installed client.
Campaign notes belong in your Obsidian vault, not in the plugin installation.

The proposed `.dmassist.yaml` version-1 contract, defaults, and machine-readable
JSON Schema are documented in
[`specs/002-vault-configuration-contract/`](specs/002-vault-configuration-contract/).
The canonical schema artifact is packaged with its consuming skill at
[`skills/vault-orientation/assets/dmassist.schema.json`](skills/vault-orientation/assets/dmassist.schema.json).
The PowerShell configuration reader and runtime validator use this installed
skill-owned artifact with built-in `Test-Json -Schema`. Script-backed profile
access remains blocked by the unverified authorization handoff. Plugin-added
support files use dot-prefixed names to stay hidden
from Obsidian's normal note view. Campaign articles remain ordinary, visible
Markdown notes.

The vault is for the DM's eyes only. Documents meant to be shown to players are
**handouts**, kept separate from DM commentary and hidden facts. A player-facing
section is limited to a handout or material the DM will read aloud; each must
pass a check for DM-only facts and revealing links immediately before it is
handed out or read aloud. All other task content is DM-facing.

Every vault-facing skill—any workflow that reads, interprets, creates, or
changes campaign material, including the current orientation skill—must follow
the shared vault-guidance contract. It must establish the authorized vault
without reading campaign notes, verify required tools and separate vault
authorization, load the plugin's shared reference and any designated
vault-local guidance, and establish the campaign/group and any handout or
read-aloud section before accessing campaign notes. With no designated local
guidance, after all other preflight checks pass, a lookup may read only
relevant notes identified without relying on uncertain folder or note-role
mappings. The lookup remains read-only and pauses if uncertainty affects
findings or the next action. Resolver 2.1.0's `get_server_info` supplies the
skill's note-content-free exact-vault check; the PowerShell runtime still
fails closed until it can verify a trusted active-session handoff. Other skills
must use the tested owner-activation pattern rather than assumed sibling
paths. Source instructions alone do not validate runtime behavior.

### Vault Sections

These are suggested folder names, not a mandatory tree. Keep an existing vault's organization, explain any different locations to the assistant, and do not assume a missing folder needs to be created.

| Section | Contents |
| --- | --- |
| **Adventures** | Playable story arcs, events, encounters, and instructions for the DM when running them. An adventure may be a single Markdown file or a folder containing an arc's notes. Adventure files may also live at the vault root without an Adventures folder. |
| **Lore** | Shared world knowledge referenced by adventures and other notes to keep storytelling consistent. Historical events belong here when they provide background rather than events the players will run. |
| **Monsters Stats** | Reusable monster stat blocks, referenced by personas, adventures, lore, or other notes. |
| **Rules** | Important recurring rules, reminders, and DM-approved house rules. Distinguish official rules from custom rulings. |
| **Sessions** | Primarily recaps and logs of what actually happened during play, used as references for later sessions. Clearly separate any preparation from recorded outcomes. |
| **Handouts** | Documents intended for players, such as letters, maps, and player-safe summaries. Do not include DM-only facts or revealing links. |

Lore may include the following subsections, along with any others a campaign needs:

- **Player:** One article per player character, plus an article for each adventuring group.
- **Locations:** Towns and cities, regions, landmarks, and planes.
- **Cosmology:** The world's cosmic structure and related background.
- **Persona:** People of interest in adventures. Reference a monster stat block separately when relevant.

Link shared information instead of duplicating it across notes. Keep playable adventure instructions distinct from general lore, and keep planned events distinct from events confirmed during play.

### Players, Characters, and Knowledge

The **Player** section describes player characters, not the real people playing them. A person may play multiple characters, and multiple people may share a character; there is no required one-to-one relationship.

Record each character's knowledge in their article and shared group knowledge in the group article, with clear links between the group and its characters. Distinguish what a character currently knows from what they might discover and from DM-only world information. Players should roleplay based on their character's knowledge, not everything the player or DM knows.

Party lore can hold shared knowledge with explicit exceptions for absent or
uninformed characters. Character/group knowledge or world-fact updates require
an actual-play record or explicit DM judgment where permitted; the DM's
judgment is sufficient to establish character knowledge or change an
exception, with no evidence log or session link required. Label rumors and
mistaken beliefs and reference the real facts in DM-facing notes, without
exposing those facts to characters who do not know them. If the truth is
unknown, record that uncertainty rather than inventing a correction.

Use Obsidian tags to classify knowledge exceptions, rumors, and mistaken beliefs,
with prose for details and links to supporting facts. The exact tag vocabulary
remains to be defined.

### Editing and Recovery

The vault is expected to be in a Git repository. A clearly requested page-local
edit needs no separate approval unless it changes an actual-play record or
established continuity. Multi-note edits, deletion, moves, merges,
reorganization, and actual-play or continuity changes require a scoped preview
followed by DM approval in a later message. Git history does not replace
approval or justify overwriting user edits.

### Preparing and Recording Sessions

1. Prepare from the relevant adventure, lore, rules, and the group's current knowledge.
2. Put preparation likely to be used in the session note under a clearly labeled preparation section. Alternatively, keep it in a `Preparations` subfolder within Sessions, especially when its use is uncertain.
3. After play, record what actually happened in the session recap or log. Prepared content may remain unused because of player choices; do not treat it as an outcome merely because it was prepared.
4. Record lore changes caused by player actions or other events as **evolution**,
   preserving the prior context. Link to a session when applicable; the session
   contains the event details. DM judgment is sufficient for character knowledge,
   without recording evidence.
5. Do not update adventure plans to match outcomes after they have been run;
   they are expected to become outdated.
6. Never automatically correct contradictions. Tell the DM and leave the
   conflicting accounts unchanged until the DM clarifies; accepted reality may
   be decided later.

### Multiple Campaigns and Reusing Adventures

Initial workflows target one campaign per vault. Supporting multiple campaigns
sharing a vault is a future evolution, which will require clearly identifying
each group's campaign and keeping their knowledge and outcomes separate.

To rerun an adventure as a fresh campaign:

1. Copy the vault, keeping the original campaign intact.
2. In the copy, remove the previous campaign's session logs, player-character and group articles, and their accumulated knowledge, including references elsewhere in the vault.
3. Review retained adventure and lore notes for previous campaign outcomes or revealed secrets recorded as character knowledge, and reset those to the intended starting state. Keep reusable world lore, adventure material, monster statistics, and applicable rules.
4. Add the new campaign's characters and group, establish their starting knowledge, and begin fresh session records.

This is an intended manual workflow, not an automated vault-copying or cleanup feature.

See the [Vault Guidance Brainstorm](docs/vault-guidance-brainstorm.md) for proposed AI reference loading, skills, hook opportunities, and open development decisions.

## Local Installation

PowerShell is a prerequisite only for script-backed vault operations, which
make mechanical vault operations more predictable. Installing the plugin and
discovering its skills does not require PowerShell, and no workflow installs or
upgrades PowerShell or its modules. The selected `pwsh` release, exact module
versions such as `powershell-yaml`, supported operating systems, provisioning
guidance, and verification evidence are recorded in
[PowerShell Runtime Support](docs/powershell-runtime-support.md). Script-backed
vault access remains blocked until exact-vault authorization can be verified;
see the
[scripting proposal](docs/vault-guidance-brainstorm.md#powershell-and-predictable-operations).

### Install and configure Obsidian Link Resolver

The Obsidian Link Resolver MCP server is a separate installation; the
`dm-assistant` plugin does not install or configure it. The API baseline is
version 2.1.0 or later, but that version alone is not safe for link resolution:
Resolver 2.1.0 can follow file symlinks outside an authorized root when reading
heading or block targets. Before resolving any link, require an upstream
release whose documentation or verified behavior guarantees canonical
target-containment checks, including symlink targets. This repository has not
verified such a release; until then, do not call `resolve_obsidian_link`.
This known symbolic-link limitation and follow-up validation are tracked in
[sylvercode/obsidian-link-resolver#27](https://github.com/sylvercode/obsidian-link-resolver/issues/27).

Before installing, check the version of any existing
`obsidian-link-resolver-mcp` executable. Keep it if it already meets both the
API and target-containment requirements; do not run an installer that would
replace a compatible installation. If an upgrade is needed, choose a release
that meets both requirements from the
[upstream installation instructions](https://github.com/sylvercode/obsidian-link-resolver#mcp-server-install--update)
(choose the MCP server installer, not the Resolver CLI-only installer).
On Windows, the PowerShell installer requires PowerShell 7 or later (`pwsh`).
For example, after setting `ResolverVersion` to a verified compatible release:

```powershell
$ResolverVersion = '<VERIFIED_COMPATIBLE_VERSION>'
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/sylvercode/obsidian-link-resolver/main/scripts/install-mcp.ps1))) -Version $ResolverVersion
```

```shell
RESOLVER_VERSION='<VERIFIED_COMPATIBLE_VERSION>'
curl -fsSL https://raw.githubusercontent.com/sylvercode/obsidian-link-resolver/main/scripts/install-mcp.sh | bash -s -- --version "$RESOLVER_VERSION"
```

Configure Copilot CLI's user MCP file (`~/.copilot/mcp-config.json`) with its
local server format. Set `command` to the absolute path of the installed
`obsidian-link-resolver-mcp` executable so Copilot can launch it regardless of
whether the installer directory is on Copilot's inherited `PATH`. Replace
both placeholders with absolute paths on your machine; repeat the `--vault`
argument and path pair for each additional authorized vault root. Keep this
personal configuration out of the plugin and any shared repository file.

```json
{
  "mcpServers": {
    "obsidian-link-resolver": {
      "type": "local",
      "command": "<ABSOLUTE_PATH_TO_OBSIDIAN_LINK_RESOLVER_MCP>",
      "args": ["--vault", "<ABSOLUTE_PATH_TO_YOUR_VAULT>"],
      "tools": ["get_server_info", "resolve_obsidian_link"]
    }
  }
}
```

Start a fresh Copilot CLI session after configuring the server. In that
session, use `copilot mcp get obsidian-link-resolver` or `/mcp` to confirm the
server is available and both `get_server_info` and `resolve_obsidian_link`
are listed. Then call `get_server_info` without arguments and check that it
reports version 2.1.0 or later and an authorized root that exactly matches
the intended vault. This check requires no campaign-note content; server
availability or tool discovery alone does not establish authorization.
The exact-root check does not establish that link resolution is safe: do not
call `resolve_obsidian_link` until the configured release is verified to
contain resolved targets within the selected vault, including through
symlinks.
The setup was verified in an isolated Copilot CLI session with a disposable
vault using session-scoped MCP configuration; no user/global MCP configuration
or campaign vault was changed. See the [Resolver MCP contract](specs/004-link-resolver-integration/contracts/resolver-mcp-contract.md)
for the readiness and authorization rules.

With GitHub Copilot CLI installed, start a session that loads this local plugin
directory from the repository root:

```shell
copilot --plugin-dir .
```

In the session, check component discovery with `/agent` and `/skills list`;
the vault-orientation skill should be listed. To verify the local plugin is
loaded, run `copilot --plugin-dir . plugin list`; it should appear under
**External Plugins (via --plugin-dir)** as `dm-assistant`. When starting from
another working directory, pass the absolute path to this plugin directory.
`--plugin-dir` loads a local plugin for that CLI session; it does not install
or persistently register the plugin. No Copilot-specific agents are currently
included. See the feature
[validation guide](specs/001-shared-vault-guidance/quickstart.md) for the
resource-loading and exact-vault authorization checks. Installation or skill
discovery alone does not validate campaign-note access behavior.

Start a new session after changing the local plugin to test the updated files.

Contributors can run the synthetic acceptance suite with Pester 6.2.0:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1
```

The test-only authorization provider is confined to the harness. Passing tests
does not authorize a real vault or establish installed-client support; see the
[support matrix and evidence](docs/powershell-runtime-support.md).
