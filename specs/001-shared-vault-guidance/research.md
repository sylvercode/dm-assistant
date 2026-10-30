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
- Minimum compatible release: `2.1.0`, which adds `get_server_info` to the
  MCP server first published in `2.0.0`.
- Server name: `obsidian-link-resolver`; required tools:
  `resolve_obsidian_link` and `get_server_info`.
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
Exact CLI JSON output was not relied on. As of Resolver 2.1.0, the
`get_server_info` tool reports the running server's configured roots; see the
2026-10-29 T002 result below. Do not resolve a campaign link merely to
establish authorization.

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
resolve a link or inspect/change live user MCP configuration. The 2026-10-29
run below verified `get_server_info` as that signal.

### Earlier prerequisite check (superseded by the test run below)

- **T001 — blocked:** Copilot CLI `1.0.103` listed both fixture skills when
  loaded with `--plugin-dir`. Review of the stopped prompt-mode attempts found
  they did not test independent working directories: the fixture was nested
  under the Git repository and resolved to the repository workspace, while
  the purported alternate directory was also the repository root. Both
  attempts looped on broad `glob` searches and were stopped before returning
  the sentinel. They do not establish success or failure of cross-skill
  loading. The fixture was removed; no supported cross-skill loading method
  has been demonstrated.
- **T002 — blocked:** `copilot mcp list` showed the configured GitHub servers
  and no `obsidian-link-resolver` server. The user identified a local Resolver
  executable; its help output requires one or more `--vault <DIR>` roots and
  accepts `--diagnostics`, but `--version` is unsupported. This confirms the
  executable documents an allow-list argument, not active-session readiness
  or a note-content-free check of the exact authorized vault. The Resolver
  remains unregistered; isolated readiness/tool exposure and exact-vault
  authorization were not tested. No campaign-vault notes were accessed and
  no live MCP configuration was changed.

### User-directed theoretical implementation

The user chose to continue with theoretical implementation while leaving T001
and T002 unresolved. Accordingly, the orientation skill is written to use its
own bundled resource through the documented per-skill resource mechanism and
to stop before campaign-note access whenever the exact-vault authorization
check cannot be established. This does not prove cross-skill resource loading,
does not establish a Resolver authorization signal, and does not satisfy
either foundational verification task. No additional vault-facing consumer
skill is enabled.

The earlier T001 probes will not be rerun as part of this implementation
choice. The cross-skill gate remains open until a valid installed-client
test uses a working directory outside the repository and returns the sentinel
from a separate consumer skill.

### Test run: 2026-10-26

The user supplied a disposable vault with project-local Resolver configuration
and authorized testing. These results supersede the earlier blocked lookup
and readiness observations.

- **T001 passed in Copilot CLI 1.0.103.** A disposable two-skill plugin was
  installed with `copilot plugin install` under an isolated `COPILOT_HOME`.
  The consumer invoked the owner through the `skill` tool; the owner then read
  `SHARED.md` from its client-provided resource directory. Both runs returned
  `VIOLET-CEDAR-9264` from the same
  `installed-plugins\_direct\resource-lookup-probe\skills\dm-probe-owner\SHARED.md`
  resource: once from the fixture directory and once from an empty directory
  outside the Git repository. Neither run used `--plugin-dir`, glob, shell,
  or an inferred sibling path. Separate `--plugin-dir` runs also passed.
  Logs: `.temp\probe-installed-inside.md` and
  `.temp\probe-installed-outside.md`. The fixture installation was removed
  using the same isolated home after testing.
- **T002 readiness passed; authorization remains blocked.** A direct stdio
  MCP probe launched the configured executable with only the exact disposable
  root supplied through `--vault`. `initialize` returned server version
  `3.5.1`; `tools/list` exposed `resolve_obsidian_link` and
  `generate_obsidian_link`. No tool was called and no campaign notes were
  read by the test harness. A fresh CLI session in the user-authorized
  disposable vault also exposed both Resolver tools. The launch arguments
  establish how the harness started its own server, but do not establish a
  generally available authorization-introspection method for an independently
  running client server. Neither advertised tool supplies a note-content-free
  authorized-roots query. Do not equate that absence with proof that no other
  supported method exists. Evidence: `.temp\resolver-probe-result.json` and
  `.temp\orientation-readiness.md`.
- **Orientation authorization pause passed in a constrained smoke test.**
  The real orientation skill activated, recognized the explicitly named vault
  and Resolver tools, reported exact-vault authorization as unverified, and
  stopped without any `view` or Resolver calls. Resolver execution was denied
  by tool permissions, and the prompt explicitly required a preflight-only
  stop, so this is not an unconstrained behavioral acceptance test. An earlier
  run excluded Resolver tools entirely; its missing-tool report is not evidence
  of server failure. Evidence: `.temp\orientation-readiness.md`.
- **Remaining T011 scenarios blocked at this stage.** No campaign-note read/write, link
  resolution, or editing scenario was run while exact-vault authorization
  remained unverified. No human DM walkthrough was performed. No live MCP
  configuration or existing vault notes were changed.

### Deferred authorization and acceptance testing

Additional independent T011 checks on 2026-10-26 passed in CLI 1.0.103:
the complete plugin components were copied into a disposable package, installed
and reinstalled under a new isolated `COPILOT_HOME`, and listed as
`dm-assistant` v0.1.0. A fresh session without `--plugin-dir` activated
`vault-orientation` and read its installed `VAULT-REFERENCE.md`, identifying
aliases, tags, internal links, and callouts. In a separate fresh session after
removing only the isolated installed reference, the read failed with
`Path does not exist`; the response named the missing shared source and
dependent work, required a pause, and did not seek fallback copies. Only
`skill` and read-only `view` tools were available. These were explicit
non-campaign resource checks, not end-to-end authorization-preflight tests.
No campaign-note access occurred. Permission-denied unreadability was not
separately exercised. Logs remain in `.temp\t011-package-check\discovery.md`
and `.temp\t011-package-check\missing-reference.md`; the disposable plugin
was uninstalled using its isolated home. The repository reference and live
plugin settings were unchanged.

On 2026-10-26, T002 readiness passed but authorization verification was
deferred pending a documented note-content-free interface. That gap is
resolved by `get_server_info`; see the 2026-10-29 test run.

At the user's subsequent explicit request, a separate functional link test
resolved `[[Svalich Woods]]` with context `7. Argynvostholt.md` to
`Locations/Svalich Woods.md` in the disposable vault. The result was
`resolved`, with no note modifications. Evidence:
`.temp\explicit-svalich-link-result.json`. This confirms that link case works;
it does not satisfy the pre-access, note-content-free authorization requirement.

T011 needs realistic DM-style installed-client scenarios, not only the
prompt-constrained preflight smoke test already recorded. After T002 is
resolved, exercise the documented successful and blocked workflows in a
disposable vault, inspecting responses and note changes. Technical scenarios
can be agent-driven; they do not all require a human DM or a real campaign.
SC-004 is a separate human requirement: five DMs must take the informal
walkthrough, with at least four distinguishing plugin-wide from vault-specific
guidance.

### Test run: T002 authorization and T011 scenarios (2026-10-29)

**T002 — pass.** Resolver GitHub release v2.1.0 adds "mcp server info". The
local executable reports server version `2.1.0` (an earlier executable
reported `3.5.1`; the current version matches the GitHub release) and lists
`generate_obsidian_link`, `get_server_info`, and `resolve_obsidian_link`.
Direct stdio probes of `get_server_info` with no arguments returned
`structuredContent` `{vaults: [{path}], version}` with `isError: false`.
Paths are canonical and `\\?\`-prefixed on Windows. When started with only an
unconfigured empty directory, the server listed only that directory; with
several roots, it listed all of them; with a nonexistent root, startup failed
with `an allowed vault root could not be accessed`. No notes were read and no
links resolved. The vault-orientation skill now requires Resolver ≥2.1.0,
calls `get_server_info`, normalizes paths (stripping `\\?\` or converting
`\\?\UNC\` to `\\`, removing trailing separators, case-insensitive on
Windows), and requires an exact match. A parent or child root does not match.
It fails closed on errors or no match.

**T011 — agent-run scenarios pass; SC-004 deferred.** The DM requested that
T011 be checked with the unperformed human walkthrough tracked separately in
[#13](https://github.com/sylvercode/dm-assistant/issues/13), not marked as
passing. Copilot CLI 1.0.103 ran
in prompt mode with `--no-ask-user`, an isolated `COPILOT_HOME` holding a
disposable install of the plugin, and a Resolver configured only for a
disposable vault copy containing fictional fixture notes. These notes were an
NPC with a DM-only callout, a tentative prep note, an actual-play log with a
contradiction, and an optional guidance note. File-hash inventories before and
after each run detected changes, and the vault was restored between runs.
Results and fixes are in `quickstart.md`. Three first-run failures led to
skill changes:

- Uncertain mapping: the agent bulk-read folders before asking. The
  no-guidance section now treats folder-as-role and bulk reads as uncertain
  mappings.
- Broad edit: the agent rewrote an actual-play log and deleted a note without
  a preview. The skill and reference now classify these edits and state that
  a request is not approval of the preview.
- Permission-denied reference: the agent offered to proceed without it. The
  skill now makes the reference mandatory.

Each re-run passed, and the approved E04 preview was applied exactly. The
results show that the skill guided one run per scenario. Agent behavior is
probabilistic, and one run does not guarantee the same result every time.
The live `.mcp.json` in the user-supplied test vault was not used because it
authorizes a live vault. SC-004 needs human DMs and remains unperformed;
T011 is checked with the explicit deferral above.

### No-designated-guidance and knowledge boundaries

No designated vault-local guidance is a valid state, not a missing-source
failure. Once the authorized vault, dependencies, shared reference, and
campaign/output context are established, a lookup limited to the specific
information requested may read relevant notes identified without relying on
an uncertain folder or note-role mapping. Keep the lookup read-only. Pause
when uncertainty affects the findings or next action; provisional assumptions
never authorize note writes. A designated-but-missing or unreadable source
still blocks dependent work.

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
