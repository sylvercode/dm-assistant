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

## Planned Template Resources

Default article templates will be bundled with the relevant skills, for example
under `skills/<skill-name>/templates/`, and resolved from the installed skill
location. DM customizations belong in the vault, not in the plugin installation,
so plugin updates cannot overwrite them.

The recommended vault location is `.dmassist-templates/`, with dot-prefixed
Markdown filenames for new support files. Existing vault templates may instead
be referenced in place. `.dmassist.yaml` will map article types to vault-relative
custom paths; exact fields and template contents are deferred.

An explicit custom template takes precedence over the plugin default. An invalid
or unreadable override is an error, not a reason to silently fall back. Future
skills must read the selected template before creating a note and validate that
custom paths remain within the vault. This does not migrate existing notes or
automatically integrate with Obsidian's Templates feature. See the
[template selection contract](vault-guidance-brainstorm.md#article-template-storage-and-selection)
for the full design. No templates or runtime loader exist yet.

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

## Next Logical Development Steps

These are future milestones, not implemented capabilities. Use the
[Vault Guidance Brainstorm](vault-guidance-brainstorm.md) for detailed decisions,
open questions, and acceptance scenarios.

1. **Establish shared AI guidance.** Extract the agreed vault meanings and
   safeguards into a reference bundled with a vault-orientation skill. Verify
   installed-resource lookup and explicitly require every vault-facing skill to
   read it, along with designated `.dmassist-guidance.md` guidance.
2. **Define the configuration contract.** The proposed `.dmassist.yaml`
   version-1 contract, defaults, and machine-readable schema are documented in
   `specs/002-vault-configuration-contract/`. A reader, validator integration,
   and runtime behavior are not implemented.
3. **Establish the script runtime.** Choose supported platforms and provisioning
   for latest stable `pwsh` and required modules, including powershell-yaml.
   Review dependencies and record exact versions; define shared inputs,
   structured outputs, errors, and vault-path safety checks.
4. **Deliver read-only vault orientation.** Implement configuration loading and
   a first inventory or validation script. Support unconfigured vault discovery,
   resolve the target vault independently of the plugin location, and report
   ambiguity rather than restructuring files.
5. **Add article authoring and template selection.** Design template contents
   when authoring workflows are ready. Bundle skill defaults, read selected
   templates explicitly, and support DM overrides without overwriting them or
   migrating existing notes. Apply the agreed Obsidian tag and callout conventions.
6. **Deliver an end-to-end session workflow.** Separate preparation from recaps,
   record lore evolution with applicable session links, and accept DM knowledge
   judgments without evidence logs. Preserve run adventure plans, report
   contradictions without resolving them, and keep handouts player-safe. Require
   approval for major changes, not redundant approval for requested local edits.
7. **Validate in the installed client.** Exercise the brainstorm's acceptance
   scenarios, verify resource and skill discovery after reinstalling the plugin,
   and check generated notes in Obsidian. Cover failure cases, path boundaries,
   preservation of user edits, and supported-platform behavior.
8. **Add integrations only for demonstrated gaps.** Introduce supported hooks,
   specialized agents, or MCP tools only when the working skills require them.
   Keep shared-campaign support and dynamic template expressions deferred until
   their separate contracts are designed.
