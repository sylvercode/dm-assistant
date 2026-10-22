# Plugin Architecture

DM Assistant uses Agent Plugins 1.0. The repository root is the installable
plugin directory. This scaffold contains metadata and reserved component
directories only; it does not yet provide campaign workflows or tools.

## Layout

```text
dm-assistant/
|-- plugin.json
|-- skills/
|   `-- README.md
|-- com.github.copilot/
|   `-- agents/
|       `-- README.md
|-- docs/
|   `-- architecture.md
|-- README.md
`-- LICENSE
```

The component directory READMEs preserve the reserved directories in Git and
describe where to add future content. They are not plugin components.

## Component Boundaries

| Component | Location | Responsibility |
| --- | --- | --- |
| Manifest | `plugin.json` | Plugin identity, version, and distribution metadata. |
| Portable skills | `skills/<skill-name>/SKILL.md` | Task-specific workflows and any bundled templates or scripts. Each skill must be an immediate child of `skills/`. |
| Copilot agents | `com.github.copilot/agents/<name>.agent.md` | Copilot-specific assistant profiles and orchestration. |
| MCP integration (future) | `mcp.json` | Register actual tool servers using the Agent Plugins MCP schema. |
| Copilot hooks (future) | `com.github.copilot/hooks/hooks.json` | Lifecycle automation when a concrete need exists. |

Agent Plugins 1.0 discovers skills and MCP configuration at fixed locations.
Do not add legacy component-path fields such as `skills`, `agents`, or
`mcpServers` to the manifest. Client-specific manifest data, if needed, belongs
under `extensions`, keyed by reverse-domain namespace.

## Campaign Data Boundary

The plugin is an installable package, not a campaign vault. Campaign Markdown
files remain in the user's Obsidian vault, outside the plugin installation.
Future workflows must obtain the target vault from the user's workspace or
explicit input, rather than assuming the plugin directory is the vault.

The README describes intended vault conventions. The
[Vault Guidance Brainstorm](vault-guidance-brainstorm.md) explores how future
skills could load a shared AI reference and vault-local guidance, with optional
hooks. These are design inputs, not implemented runtime contracts. Define note
templates, link-resolution behavior, and permissions for modifying campaign
content alongside the workflows and tools that implement them.

## Extension Rules

- Add each workflow as a named skill with `name` and `description` frontmatter.
- Keep shared task guidance in skills rather than duplicating it in agents.
- Add an agent only when a specialized role or orchestration is needed.
- Add `mcp.json` only when a real server is available; do not register placeholder commands or endpoints.
- Add hooks only for required lifecycle behavior, not as empty configuration.
- Keep credentials and campaign content out of the distributed plugin.

## References

- [Plugins for GitHub Copilot](https://docs.github.com/en/copilot/concepts/customizations/plugins)
- [Creating a plugin for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating)
