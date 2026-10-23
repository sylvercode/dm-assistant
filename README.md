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

This repository contains an Agent Plugins 1.0 scaffold: a plugin manifest and reserved directories for portable skills and Copilot-specific agents. No skills, agents, hooks, or MCP servers are implemented yet. The planned capabilities above are not currently available.

See [Plugin Architecture](docs/architecture.md) for component locations, extension boundaries, and the separation between the plugin and campaign vaults.

## Intended Vault Structure and Workflow

The following conventions describe the intended workflow for users and future AI guidance; the scaffold does not yet load or enforce them. Campaign notes belong in your Obsidian vault, not in the plugin installation.

The planned vault configuration is `.dmassist.yaml` at the vault root; its schema
and defaults are deferred. Plugin-added support files use dot-prefixed names to
stay hidden from Obsidian's normal note view. Campaign articles remain ordinary,
visible Markdown notes.

### Vault Sections

These are suggested folder names, not a mandatory tree. Keep an existing vault's organization, explain any different locations to the assistant, and do not assume a missing folder needs to be created.

| Section | Contents |
| --- | --- |
| **Adventures** | Playable story arcs, events, encounters, and instructions for the DM when running them. An adventure may be a single Markdown file or a folder containing an arc's notes. Adventure files may also live at the vault root without an Adventures folder. |
| **Lore** | Shared world knowledge referenced by adventures and other notes to keep storytelling consistent. Historical events belong here when they provide background rather than events the players will run. |
| **Monsters Stats** | Reusable monster stat blocks, referenced by personas, adventures, lore, or other notes. |
| **Rules** | Important recurring rules, reminders, and DM-approved house rules. Distinguish official rules from custom rulings. |
| **Sessions** | Primarily recaps and logs of what actually happened during play, used as references for later sessions. Clearly separate any preparation from recorded outcomes. |

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
uninformed characters. Update those exceptions only after supported information
sharing or DM confirmation. Label rumors and mistaken beliefs and reference the
real facts in DM-facing notes, without exposing those facts to characters who do
not know them. If the truth is unknown, record that uncertainty rather than
inventing a correction.

### Preparing and Recording Sessions

1. Prepare from the relevant adventure, lore, rules, and the group's current knowledge.
2. Put preparation likely to be used in the session note under a clearly labeled preparation section. Alternatively, keep it in a `Preparations` subfolder within Sessions, especially when its use is uncertain.
3. After play, record what actually happened in the session recap or log. Prepared content may remain unused because of player choices; do not treat it as an outcome merely because it was prepared.
4. Use the session record as a reference for subsequent play, updating relevant character and group knowledge and established world facts only when supported by actual events.

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

PowerShell is a planned prerequisite for future script-backed skills and hooks,
to make mechanical vault operations more predictable. The current scaffold has
no scripts and does not require PowerShell to install. Future workflows will use
the latest stable `pwsh` and required modules, including `powershell-yaml`, with
exact versions recorded during implementation and validation. Platform support
and provisioning remain to be specified; see the
[scripting proposal](docs/vault-guidance-brainstorm.md#powershell-and-predictable-operations).

With GitHub Copilot CLI installed, run these commands from the repository root:

```shell
copilot plugin install .
copilot plugin list
```

The plugin should appear as `dm-assistant`. The empty scaffold does not add any agents or skills. Once components exist, check their discovery in a new interactive session with `/agent` and `/skills list`.

Copilot caches installed plugins. Re-run `copilot plugin install .` after changing the local plugin, then start a new session to test it.

To remove the local installation:

```shell
copilot plugin uninstall dm-assistant
```
