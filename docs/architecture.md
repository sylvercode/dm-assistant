# Plugin Architecture

DM Assistant uses Agent Plugins 1.0. The repository root is the installable
plugin directory. The repository includes a portable vault-orientation skill
and its bundled shared reference, schema, and PowerShell runtime modules.
The Resolver server is configured separately, and production script-backed
vault access is not enabled. Feature 001 exercised `get_server_info` and
cross-skill resource loading in disposable client fixtures. The PowerShell
runtime has no verified handoff from the active Resolver session; its
installed-client and cross-platform verification remain outstanding. The
orientation skill must fail closed whenever exact-vault authorization cannot
be established.

## Layout

```text
dm-assistant/
|-- plugin.json
|-- skills/
|   |-- README.md
|   `-- vault-orientation/
|       |-- SKILL.md
|       |-- VAULT-REFERENCE.md
|       |-- assets/
|       |   |-- dmassist.schema.json
|       |   `-- runtime-dependencies.json
|       `-- scripts/
|-- tests/
|   `-- powershell/
|-- com.github.copilot/
|   `-- agents/
|       `-- README.md
|-- docs/
|   `-- architecture.md
|-- README.md
`-- LICENSE
```

The component directory READMEs describe where to add future content. They are
not plugin components.

## Component Boundaries

| Component | Location | Responsibility |
| --- | --- | --- |
| Manifest | `plugin.json` | Plugin identity, version, and distribution metadata. |
| Portable skills | `skills/<skill-name>/SKILL.md` | Task-specific workflows and any bundled templates or scripts. Each skill must be an immediate child of `skills/`. The current vault-orientation skill bundles `VAULT-REFERENCE.md`. |
| Copilot agents | `com.github.copilot/agents/<name>.agent.md` | Copilot-specific assistant profiles and orchestration. |
| Skill inventory | `skills/README.md` | Declares every immediate-child skill directory containing `SKILL.md` and classifies each as vault-facing or non-vault-facing. It is contributor documentation, not a plugin component. |
| MCP integration (future) | `mcp.json` | Register actual tool servers using the Agent Plugins MCP schema. |
| Copilot hooks (future) | `com.github.copilot/hooks/hooks.json` | Lifecycle automation when a concrete need exists. |
| Vault configuration schema | `skills/vault-orientation/assets/dmassist.schema.json` | Canonical JSON Schema for the proposed normalized version-1 vault profile, packaged with its consuming skill and located by the skill's PowerShell resource lookup independently of the working directory. |
| Runtime modules | `skills/vault-orientation/scripts/` | Explicit requests, prerequisite and authorization gates, installed resources, profile validation, inspection, previews, and per-note atomic writes. Production access remains fail-closed. |
| Packaged dependency inventory | `skills/vault-orientation/assets/runtime-dependencies.json` | Runtime projection of Feature 001's authoritative dependency inventory; update both together, never infer authorization from readiness. |
| Acceptance harness | `tests/powershell/` | Synthetic tests and explicit test-only authorization injection; never loaded or discovered by production modules or skills. |

Agent Plugins 1.0 discovers skills and MCP configuration at fixed locations.
Do not add legacy component-path fields such as `skills`, `agents`, or
`mcpServers` to the manifest. Client-specific manifest data, if needed, belongs
under `extensions`, keyed by reverse-domain namespace.

## Campaign Data Boundary

The plugin is an installable package, not a campaign vault. Campaign Markdown
files remain in the user's Obsidian vault, outside the plugin installation.
Future workflows must obtain the target vault from the user's workspace or
explicit input, rather than assuming the plugin directory is the vault.

The README describes intended vault conventions. Any skill that reads,
interprets, creates, or changes campaign material is vault-facing and must be
listed as such in `skills/README.md`. Before implementation is considered
complete, a static inventory and source audit must match every immediate-child
`skills/*/SKILL.md` file to exactly one classified inventory entry and inspect
each vault-facing skill for its required preflight. This audit does not require
runtime execution of every skill.

The planned pre-note sequence is: establish the authorized vault location
without reading campaign notes; verify every declared required dependency is
available and authorized for that vault; load the plugin-owned shared reference
and any designated vault-local guidance; establish the campaign/group and
identify any handout or read-aloud section; then access campaign notes. No
designated local guidance is a valid state, not a missing-source failure. After
all other checks pass, a lookup may read only relevant notes identified without
relying on uncertain folder or note-role mappings. Keep that lookup read-only
and pause if uncertainty affects findings or the next action. Before a handout
is handed out or a read-aloud section is spoken, gate-check that section for
DM-only facts and revealing links. All other task content is DM-facing.

Updates to character/group knowledge or world facts require an actual-play
record or explicit DM judgment where permitted. Explicit DM judgment is
sufficient without an evidence log or session link.

The
[Vault Guidance Brainstorm](vault-guidance-brainstorm.md) explores how future
skills could load a shared AI reference and vault-local guidance, with optional
hooks. These are design inputs, not implemented runtime contracts. The
[Shared Vault Guidance specification](../specs/001-shared-vault-guidance/spec.md)
records the current proposed requirements; it does not mean those requirements
are implemented. Define note templates, link-resolution behavior, and
permissions for modifying campaign content alongside the workflows and tools
that implement them.

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
for the full design. No default templates or authoring workflow exist yet.
The profile runtime validates configured template references and tracks their
versions; this is not an implemented template-rendering workflow.

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

These milestones distinguish local runtime foundations from remaining
production capabilities. Use the
[Vault Guidance Brainstorm](vault-guidance-brainstorm.md) for detailed decisions,
open questions, and acceptance scenarios.

1. **Establish shared AI guidance.** The canonical reference and
   vault-orientation skill are present. Installed cross-skill resource lookup
   and exact-vault authorization through Resolver 2.1.0's `get_server_info`
   have been verified, and agent-run acceptance scenarios pass. The informal
   human DM walkthrough (SC-004) is still outstanding. Keep
   `skills/README.md` as the authoritative inventory and statically audit its
   exact match to skill files and each vault-facing skill's preflight.
2. **Define the configuration contract.** The proposed `.dmassist.yaml`
   version-1 contract, defaults, and machine-readable schema are documented in
   `specs/002-vault-configuration-contract/`. Feature 003 implements its reader,
   validator integration, reference checks, and read-only discovery under the
   authorization gate; downstream behavior has synthetic coverage only.
3. **Qualify the script runtime.** The selected `pwsh`, powershell-yaml, and
   Pester versions, provisioning, and evidence are recorded in
   [PowerShell Runtime Support](powershell-runtime-support.md). Shared inputs,
   structured results, path boundaries, previews, and atomic writes exist.
   Windows remains a candidate; macOS/Linux are unsupported and unverified.
4. **Enable script-backed vault orientation.** Inspection and configuration
   loading are locally tested. Verify a trusted active-session authorization
   handoff and installed-client execution before enabling script-backed
   campaign-note access. Before enabling writes, also resolve the single-note
   actual-play and continuity classification gap tracked by Feature 003 T048.
   Keep discovery read-only and report ambiguity rather than restructuring files.
5. **Add article authoring and template selection.** Design template contents
   when authoring workflows are ready. Bundle skill defaults, read selected
   templates explicitly, and support DM overrides without overwriting them or
   migrating existing notes. Apply the agreed Obsidian tag and callout conventions.
6. **Deliver an end-to-end session workflow.** Separate preparation from recaps,
   record lore evolution with applicable session links, and accept DM knowledge
   judgments without evidence logs. Preserve run adventure plans, report
   contradictions without resolving them, and keep handouts player-safe. Require
   a preview and later-message approval for actual-play or continuity changes
   and other major edits, without redundant approval for safe local edits.
7. **Validate in the installed client.** Verify resource and skill discovery
   after reinstalling the plugin, exercise representative acceptance and
   failure scenarios, and check generated notes in Obsidian. Cover dependency
   authorization, player-facing handout/read-aloud gate checks, path boundaries,
   preservation of user edits, and supported-platform behavior. The inventory
   and source-compliance audit remains static; it does not require runtime
   execution of every vault-facing skill.
8. **Add integrations only for demonstrated gaps.** Introduce supported hooks,
   specialized agents, or MCP tools only when the working skills require them.
   Keep shared-campaign support and dynamic template expressions deferred until
   their separate contracts are designed.
