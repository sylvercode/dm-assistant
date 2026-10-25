# Research: Shared Vault Guidance

## Installed plugin resource lookup

**Decision**: Use GitHub Copilot CLI as the supported client for installed-resource validation. Keep one canonical shared reference bundled with the vault-orientation skill in the plugin's fixed `skills/` tree, and require each vault-facing skill to load it explicitly before interpreting or changing campaign notes. Treat successful lookup from an installed plugin, independent of current working directory, as a release acceptance check.

**Rationale**: The repository's local installation procedure uses `copilot plugin install .`, `copilot plugin list`, and a new interactive session for skill discovery. The official Agent Plugins 1.0 contract fixes skills under `skills/<skill-name>/SKILL.md` and supports files distributed with a skill; it does not offer a configurable plugin-wide shared-resource directory. The brainstorm recommends a single reference bundled with a vault-orientation skill to avoid duplicated rules.

**Alternatives considered**:

- Put the reference in plugin `docs/`: discoverable to contributors, but no documented automatic skill-loading behavior.
- Repeat the full reference in every skill: self-contained, but duplicates can drift and conflicts with the single canonical reference requirement.
- Put shared guidance in Copilot-specific agent metadata: not portable to other compatible plugin clients and duplicates skill behavior.
- Use legacy configurable component paths: unnecessary and contrary to the repository's Agent Plugins 1.0 architecture.

**Verification caveat**: Public documentation confirms automatic discovery of files in a skill's own directory and the fixed plugin layout, but does not explicitly guarantee that a skill can resolve a resource in a sibling skill directory using a relative path. Verify actual installed lookup in Copilot CLI from more than one working directory before claiming FR-012 is satisfied. If that cross-skill lookup is unsupported, choose a documented and testable packaging/loading mechanism before implementation is considered complete; do not silently fall back to source-tree or current-directory paths.

**Validation procedure**:

1. Install the local plugin with `copilot plugin install .` and confirm it with `copilot plugin list`.
2. Start a new interactive session and verify the orientation and all implemented vault-facing skills are discovered.
3. Invoke a vault-facing skill from the repository root and a different working directory; verify it reads the same installed canonical reference in both cases.
4. Exercise missing/unreadable-reference, missing vault-local guidance, ambiguous context, and approval-boundary cases; confirm affected note work pauses without changes.

## Required runtime dependency inventory

**Decision**: Require the Obsidian Link Resolver MCP server for every
vault-facing skill, not only tasks that happen to resolve a link. Keep an
explicit, non-exhaustive inventory so future required dependencies can be
added with their purpose, scope, compatible version/interface, user-owned
setup, readiness check, and unavailable behavior.

**Verified resolver contract**:

- Repository: [sylvercode/obsidian-link-resolver](https://github.com/sylvercode/obsidian-link-resolver).
- Minimum compatible release: `2.0.0`, which publishes the MCP server.
- Server name: `obsidian-link-resolver`; required tool:
  `resolve_obsidian_link`.
- Server startup requires one or more accessible, explicitly authorized
  `--vault` roots. Keep those user-specific paths out of the plugin and
  repository.
- If the server/tool is missing or the intended vault is not authorized, every
  vault-facing skill must stop before campaign-note access and report the setup
  needed. Resolution outcomes such as unresolved or ambiguous must not be
  replaced with guessed destinations.

**Setup decision**: The DM installs and configures the resolver separately in
Copilot CLI's user-managed MCP settings. Verify with `copilot mcp list` and
`copilot mcp get obsidian-link-resolver`, then confirm the tool is exposed in
a new session. Do not ship plugin MCP configuration with an empty or
hard-coded vault root.

The official [Obsidian Aliases](https://obsidian.md/help/aliases) and
[Obsidian Tags](https://obsidian.md/help/tags) pages are reference sources,
not runtime dependencies. Obsidian need not be running, and campaign-specific
tag vocabulary remains DM-owned.

**Sources**:

- [GitHub Copilot plugins](https://docs.github.com/en/copilot/concepts/customizations/plugins) — Agent Plugins 1.0 portability and fixed component locations.
- [Add skills to GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills) — skill directory resources and discovery commands.
- [Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference) — plugin installation/list behavior.
- `README.md` — repository's local install and new-session discovery steps.
- `docs/architecture.md` — component boundaries and campaign-vault separation.
- `docs/vault-guidance-brainstorm.md` — recommended three-layer guidance model and loading sequence.
- [Obsidian Link Resolver](https://github.com/sylvercode/obsidian-link-resolver) — resolver release, MCP startup requirements, and tool contract.
- [Obsidian Aliases](https://obsidian.md/help/aliases) and [Obsidian Tags](https://obsidian.md/help/tags) — reference material for native feature semantics.
