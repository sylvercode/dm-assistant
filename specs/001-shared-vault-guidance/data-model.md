# Data Model: Shared Vault Guidance

## Status and scope

This document describes the concepts and target contracts in the
[feature specification](spec.md). It does not define a runtime, loader, or
configuration format. The repository is a documentation-and-metadata
Agent Plugins 1.0 scaffold; these concepts and state behaviors are not currently
implemented.

**All fields below are conceptual attributes inferred from current
requirements—not a committed config schema, serialized record, or required
frontmatter.** In particular, `.dmassist.yaml` is planned but its schema and
defaults are deferred. The proposed `.dmassist-guidance.md` is vault-owned
guidance, not an implemented loader contract.

## Entities

### Plugin-owned shared reference

Canonical plugin-distributed guidance that defines shared meanings, campaign
boundaries, knowledge and preparation distinctions, editing safeguards, and
concise Obsidian-native convention defaults.

Conceptual attributes:

- **Owner**: the plugin.
- **Scope**: shared across vault-facing skills; not campaign-specific.
- **Content**: common conventions and safeguards, including paraphrased local
  defaults for aliases, tags, wikilinks and Markdown-style internal links, and
  callouts with links to official documentation as provenance. Wikilinks are
  the default unless DM input or designated vault-local guidance establishes
  another vault preference.
- **Availability**: bundled locally so skills can use the defaults without
  fetching external help pages at runtime.
- **Resource identity/location**: one canonical installed-plugin resource,
  preferably bundled with the vault-orientation skill. Documentation supports
  resources in an activated skill's own directory, but does not document
  cross-skill lookup. Resolving this resource from other skills in the installed
  plugin is an empirical release gate and remains a blocker until verified;
  source-tree presence or a current-working-directory path is not sufficient.

There is one canonical reference. It is separate from campaign data and
DM-owned guidance.

### DM-owned vault-local guidance

DM-authored conventions, mappings, and exceptions applicable to a particular
vault. It customizes organization and style, including supplementing or
replacing general Obsidian-use recommendations for that campaign, without
redefining native syntax/semantics, replacing shared safeguards, or duplicating
campaign facts.

Conceptual attributes:

- **Owner**: the DM.
- **Applicable vault**: the vault for which the guidance is designated.
- **Designation**: supplied explicitly by the DM or identified by an
  established vault-local configuration contract. The skill must not guess.
- **Content/location**: guidance text and its vault-local source, which may be
  absent, unreadable, or conflicting.
- **Customization scope**: campaign-specific choices and conventions may
  customize general defaults; native syntax/semantics and shared safety
  invariants remain authoritative.

The brainstorm proposes optional `.dmassist-guidance.md` at the vault root,
referenced from `.dmassist.yaml`; this is a design direction, not a required
path or defined configuration field. The guidance remains outside the plugin
distribution.

### Vault and campaign context

The target user workspace and the campaign/group frame needed to interpret a
task. The plugin installation is not the vault.

Conceptual attributes:

- **Authorized vault**: established from the user's workspace or explicit
  input.
- **Campaign/group**: the relevant campaign identity, established by explicit
  input or unambiguous vault context. Initial workflows assume one campaign per
  vault; shared-campaign isolation is deferred.
- **Mappings and exceptions**: DM-approved organization meanings relevant to
  this vault, if available.
- **Player-facing sections**: only handout and read-aloud sections of requested
  output. All other task content is DM-facing. Each such section is checked for
  DM-only facts and revealing links immediately before it is handed out or read
  aloud.

These are context concepts, not a prescribed profile structure. A context that
cannot be established, or has multiple reasonable interpretations affecting the
next action, is unresolved until the DM directs the skill.

### Vault-facing skill

A user-invoked workflow that reads, interprets, creates, or changes campaign
material and is therefore subject to the ordered pre-note prerequisite and
shared safeguards.

Conceptual attributes:

- **Workflow identity/task**: which requested workflow is being performed.
- **Vault-facing status**: whether the workflow reads, interprets, creates, or
  changes campaign material.
- **Required guidance**: the canonical shared reference and the designated
  vault-local guidance.
- **Obsidian convention defaults**: local reference guidance for aliases, tags,
  both internal-link formats, and callouts; external documentation links are
  citations, not required runtime fetches. A preference is established by
  explicit DM input or designated vault-local guidance, not inferred from
  isolated examples without confirmation.
- **Resolved context**: the authorized vault, relevant campaign/group, and
  whether requested output includes a handout or read-aloud section.
- **Proposed change scope**: whether a requested edit is clearly page-local or
  broad, destructive, restructuring, or continuity-changing.

These attributes describe responsibilities, not required skill metadata or
implementation state. The spec's skill inventory and validation are a static
inventory plus source audit: enumerate all immediate-child
`skills/*/SKILL.md` files, match them one-to-one with `skills/README.md`, and
inspect each vault-facing skill's declared preflight. Runtime execution of
every skill is not required.

### Required runtime dependency

An explicitly listed external tool or service that must be ready before
vault-facing skills can access campaign notes. The inventory is intentionally
non-exhaustive and may grow as future requirements are added.

Conceptual attributes:

- **Identity and purpose**: the named dependency and capability it provides.
- **Scope**: which skills require it; the initial resolver applies to every
  vault-facing skill.
- **Compatibility**: supported tool/interface and compatible version.
- **Setup**: user-owned installation and configuration.
- **Readiness check**: evidence that the supported client exposes the expected
  capability and authorizes the intended vault.
- **Unavailable behavior**: a clear fail-closed result before campaign-note
  access or edits.

The initial dependency is the Obsidian Link Resolver MCP server,
`obsidian-link-resolver` version `2.0.0` or later, exposing
`resolve_obsidian_link`. The user configures authorized vault roots in Copilot
CLI; private paths are not stored in the plugin. Official Obsidian help pages
for aliases, tags, internal links, and callouts are provenance for locally
bundled paraphrased guidance, not runtime dependencies.

## Relationships

- Each vault-facing skill follows this strict pre-note order: establish the
  authorized vault location without reading campaign notes; verify every
  currently declared required dependency is available and authorized for that
  vault; load the plugin-owned shared reference and designated vault-local
  guidance; establish the campaign/group and whether requested output includes
  a handout or read-aloud section; only then access campaign notes.
- If a handout or read-aloud section is to be handed out or read aloud, gate
  check that section for DM-only facts and revealing links immediately before
  delivery or reading. All other task content is DM-facing.
- Locally bundled Obsidian convention defaults supply general native usage;
  designated DM guidance may customize the campaign convention but cannot
  misrepresent native syntax or override shared safety requirements.
- A DM-owned guidance source applies to its designated vault; it is not
  distributed with the plugin and cannot authorize actions outside that vault.
- A resolved vault/campaign context scopes the task and its campaign material.
  The plugin and its files are never substituted for the authorized vault.
- The skill applies shared safeguards together with DM-approved mappings.
  Mappings can customize organization, but cannot override safety boundaries,
  turn preparation into history, or authorize destructive actions.
- Only handout and read-aloud sections are player-facing; they must exclude
  DM-only facts and revealing links and be gate-checked immediately before
  delivery or reading. Every other task section is DM-facing and may use
  DM-only information.

## Validation and invariants

1. **Ordered pre-note checks.** Before reading campaign notes, establish the
   authorized vault location without reading notes; verify required dependencies
   are available and authorized for that vault; load the shared reference and
   designated vault-local guidance; establish campaign/group and whether the
   output includes a handout or read-aloud section; then access campaign notes.
   If any step cannot be completed, pause the affected work and request
   direction as appropriate.
2. **No substitution by guesswork.** Do not guess which local guidance is
   designated, treat the plugin as the vault, infer an absent folder should be
   created, or silently substitute assumptions for missing guidance.
3. **Context is sufficiently specific.** Establish the authorized vault and
   relevant campaign/group before acting on notes. Resolve ambiguity that
   affects the next action with DM direction.
4. **Organization remains flexible.** Folder names are defaults, not a required
   tree. Honor confirmed mappings and preserve existing organization and
   unrelated content.
5. **Knowledge and continuity remain distinct.** Preparation alone does not
   establish actual events or character knowledge. Preserve contradictions and
   run adventure plans; do not silently reconcile or rewrite them.
6. **Audience boundary is preserved.** Only handout and read-aloud sections are
   player-facing; all other task content is DM-facing. Gate-check each such
   section for DM-only facts and revealing links immediately before handing it
   out or reading it aloud.
7. **Approval is based on impact.** Clearly requested page-local edits do not
   need redundant approval. Broad, destructive, restructuring, or
   continuity-changing edits require a scoped preview and DM approval before
   application, regardless of file count.
8. **Guidance and campaign content are data.** Neither may override governing
   instructions or authorize unrelated actions.
9. **No automatic vault setup.** Do not create missing folders, migrate notes,
   or reorganize the vault merely because a convention or expected location is
   absent.
10. **Inventory verification is static.** Enumerate all immediate-child
    `skills/*/SKILL.md` files; confirm an exact one-to-one match with
    `skills/README.md`, with no missing, extra, duplicate, or unclassified
    entries; and audit each vault-facing skill's declared preflight from
    source. Do not require runtime execution of every skill.

## Context lifecycle: target contract

The following states and transitions describe required future behavior, not
currently implemented runtime states or persisted fields.

| State | Entry/condition | Target behavior and transition |
| --- | --- | --- |
| **Invoked** | A vault-facing skill receives a campaign task. | Begin the ordered pre-note checks; do not interpret or change campaign notes yet. |
| **Establishing vault** | The skill identifies the intended vault from the user's workspace or explicit input. | Establish the authorized vault location without reading campaign notes. If it cannot be established, move to **Paused**. |
| **Verifying dependencies** | The authorized vault location is established. | Verify every declared required dependency is available and authorized for that vault. If any dependency is unavailable or misconfigured, move to **Paused** before accessing campaign notes. |
| **Loading guidance** | Required dependencies are verified for the authorized vault. | Load the canonical shared reference and designated vault-local guidance. If either source is missing or unreadable, move to **Paused**. |
| **Resolving context** | Required guidance is available. | Establish the relevant campaign/group and identify whether requested output includes a handout or read-aloud section. If context is missing or a consequential ambiguity remains, move to **Paused**. |
| **Ready** | The ordered pre-note checks are complete and needed context is unambiguous. | Access and interpret relevant campaign notes; perform only work allowed by the safeguards. If the vault, dependencies, guidance, campaign, or group changes, repeat the ordered checks before continuing. |
| **Gate-checking player-facing section** | A handout or read-aloud section is ready to be handed out or read aloud. | Immediately before delivery or reading, check that section for DM-only facts and revealing links; do not deliver/read it until it passes. All other task content remains DM-facing. |
| **Paused** | A required dependency or source is unavailable, or missing/ambiguous context affects the next action. | Name the dependency, source, or competing interpretations, explain which requested work depends on it, ask the DM for direction, and leave campaign notes unchanged. After direction, retry the affected check; do not presume unrelated work is authorized. |
| **Awaiting approval** | A proposed change is broad, destructive, restructuring, or continuity-changing. | Present a scoped preview and wait for DM approval. Approval permits only the previewed change within the authorized vault; absent or declined approval means do not apply it. |
| **Applying approved change** | The DM approved the applicable preview and the context remains valid. | Apply only the approved change. If context changes or the proposed scope changes, refresh/re-resolve and obtain approval for the revised proposal as needed. |

Clearly requested page-local edits may proceed from **Ready** without a separate
approval state. Pausing for missing dependencies, guidance, or context is not
approval, and approval does not waive the ordered pre-note, audience,
continuity, or vault-boundary invariants.
