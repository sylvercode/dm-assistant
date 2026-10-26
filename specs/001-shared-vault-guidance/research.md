# Research: Shared Vault Guidance

## Installed plugin resource lookup

**Decision**: Use GitHub Copilot CLI as the supported client for installed-resource validation. Keep one canonical shared reference bundled with the vault-orientation skill in the plugin's fixed `skills/` tree. An activated skill receives its own base directory and related-files listing independently of the process working directory. Current official documentation does not provide a cross-skill filesystem lookup contract. Treat the installed lookup required by FR-012 as an empirical release gate, and do not begin dependent implementation until a supported mechanism is demonstrated.

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

## Locally bundled Obsidian convention defaults

**Decision**: Put concise, paraphrased defaults for Aliases, Tags, Internal
links, and Callouts in the plugin-owned shared reference. Keep the official
documentation URLs as provenance and maintenance references, but do not fetch
the pages or require the DM or skill to reinterpret them during a
vault-facing task.

**Verified source concepts**:

- **Aliases** ([official guide](https://obsidian.md/help/aliases)): aliases are
  reusable alternate names for a note, while link display text is appropriate
  for a one-off presentation change. Note aliases use a YAML list property.
- **Tags** ([official guide](https://obsidian.md/help/tags)): tags classify
  notes and support retrieval; they may be inline or represented in a YAML
  list property. Slash-separated nested tags provide a hierarchy. The exact
  campaign vocabulary remains DM-owned.
- **Wikilinks/internal links**
  ([official guide](https://obsidian.md/help/links)): Obsidian supports
  wikilink and Markdown internal-link formats, with optional heading/block
  targets and display text. The spec clarification selects wikilinks as the
  default and covers both formats, while an explicitly established preference
  from DM input or designated vault-local guidance takes precedence. Resolve
  targets rather than inventing them.
- **Callouts** ([official guide](https://obsidian.md/help/callouts)): native
  callouts use blockquote syntax with a `[!type]` marker; titles and collapsible
  markers are presentation options. Callout styling may be customized, so
  avoid assuming community-defined types exist. A collapsed callout is not
  access control.

These defaults describe native behavior and general recommended use; they do
not mandate a vault structure or tag vocabulary.
DM-designated guidance may supplement, customize, or replace general
recommendations for that campaign. It cannot redefine supported syntax or
override shared safety requirements.

The official Obsidian help pages are source references, not runtime
dependencies. Obsidian need not be running and no network access is required
to use the local summaries.

**Sources**:

- [GitHub Copilot plugins](https://docs.github.com/en/copilot/concepts/customizations/plugins) — Agent Plugins 1.0 portability and fixed component locations.
- [Add skills to GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills) — skill directory resources and discovery commands.
- [Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference) — plugin installation/list behavior.
- [Copilot CLI skills](https://docs.github.com/en/copilot/how-tos/copilot-sdk/features/skills) — per-skill base-directory and related-resource behavior.
- [Copilot CLI MCP servers](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers) — `copilot mcp list` and `copilot mcp get` readiness/status surfaces.
- `README.md` — repository's local install and new-session discovery steps.
- `docs/architecture.md` — component boundaries and campaign-vault separation.
- `docs/vault-guidance-brainstorm.md` — recommended three-layer guidance model and loading sequence.
- [Obsidian Link Resolver](https://github.com/sylvercode/obsidian-link-resolver) — resolver release, MCP startup requirements, and tool contract.
- [Obsidian Aliases](https://obsidian.md/help/aliases), [Obsidian Tags](https://obsidian.md/help/tags), [Obsidian Internal links](https://obsidian.md/help/links), and [Obsidian Callouts](https://obsidian.md/help/callouts) — primary references for local, paraphrased convention defaults; none is a runtime dependency.

## Updated research: clarified loading order and resource verification

The implementation order is governed by the updated specification: identify
the authorized vault location without reading campaign notes; verify required
dependencies are available and authorized for that vault; load the shared
reference and designated vault-local guidance; establish campaign/group and
whether the requested output includes a handout or read-aloud section; then
access campaign notes. Dependency readiness and vault authorization are
distinct checks. Copilot CLI's MCP status/tool discovery can establish server
readiness without resolving a link, but server presence alone does not prove
the intended vault is authorized.

Current Copilot CLI documentation describes a runtime-provided base directory
and related-files listing for an activated skill's own resources. It does not
document a cross-skill filesystem lookup primitive. Plugin manifests can name
independent skill paths, so sibling adjacency is not a portable lookup
contract. The canonical shared-reference design remains preferred, but
cross-skill lookup must be empirically verified in the installed client from
multiple working directories before dependent skill implementation. If it
fails, treat it as a blocker and select a supported packaging/loading approach;
do not infer success from a skill loading its own resource.

The Resolver's source/contract documentation describes its allowed vault roots
as a server-startup allow-list that requests cannot widen. Copilot CLI
documents `copilot mcp get` as reporting server status and available tools.
These support checking tool readiness separately from vault authorization.
Exact CLI JSON output and a safe, generally available authorization
introspection mechanism remain unverified. Do not claim an untested command
schema or resolve a campaign link merely to establish authorization.

### Foundational verification procedures

T001 must use a disposable installed-plugin fixture with two skills: an owner
skill containing a unique sentinel resource and a consumer skill instructed
to load that resource. Test the consumer from both the fixture/plugin working
directory and a different working directory, and verify the sentinel rather
than relying on source-tree presence or a path relative to the current
directory. Remove the fixture after recording the exact supported method and
evidence. If the client does not provide a supported cross-skill lookup, keep
the gate blocked until a documented alternative is selected and tested.

T002 must use an isolated Copilot CLI configuration and a disposable vault.
The documented MCP status/tool checks can establish Resolver readiness, but
are not authorization evidence. Test only a documented, note-content-free
signal that confirms the exact disposable vault root is authorized; do not
resolve a link or inspect/change live user MCP configuration. The
authorization-introspection method remains unverified. If no safe supported
signal can be demonstrated, record authorization as blocked and do not permit
campaign-note access.

### No-designated-guidance and knowledge boundaries

No designated vault-local guidance is a valid state, not a missing-source
failure. Once the authorized vault, dependencies, shared reference, and
campaign/output context are established, a straightforward read-only lookup
may use provisional layout assumptions. Pause when uncertainty affects the
findings or next action; provisional assumptions never authorize note writes.
A designated-but-missing or unreadable source still blocks dependent work.

Updates to character/group knowledge or world facts require an actual-play
record or explicit DM judgment where permitted. DM judgment alone is
sufficient; an evidence log or session reference is not required.

The skill inventory acceptance is a static inventory and source audit only:
enumerate all immediate-child `skills/*/SKILL.md` files, confirm an exact
one-to-one match with `skills/README.md`, and inspect every vault-facing
skill's declared preflight. It does not require runtime invocation of every
vault-facing skill. SC-004 retains an informal short walkthrough with the
existing threshold of at least 4 of 5 DMs; examples and scoring are not
standardized.
