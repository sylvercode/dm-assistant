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

## Local Installation

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
