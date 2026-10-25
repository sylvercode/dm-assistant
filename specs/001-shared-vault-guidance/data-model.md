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
boundaries, knowledge and preparation distinctions, and editing safeguards.

Conceptual attributes:

- **Owner**: the plugin.
- **Scope**: shared across vault-facing skills; not campaign-specific.
- **Content**: common conventions and safeguards.
- **Resource identity/location**: a resolvable installed-plugin resource. The
  research recommends bundling it with a vault-orientation skill, but installed
  lookup must be verified; a source-tree path is not sufficient.

There is one canonical reference. It is separate from campaign data and
DM-owned guidance.

### DM-owned vault-local guidance

DM-authored conventions, mappings, and exceptions applicable to a particular
vault. It customizes organization and style without replacing shared safeguards
or duplicating campaign facts.

Conceptual attributes:

- **Owner**: the DM.
- **Applicable vault**: the vault for which the guidance is designated.
- **Designation**: supplied explicitly by the DM or identified by an
  established vault-local configuration contract. The skill must not guess.
- **Content/location**: guidance text and its vault-local source, which may be
  absent, unreadable, or conflicting.

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
- **Output audience**: DM or characters/players when relevant to the requested
  task.

These are context concepts, not a prescribed profile structure. A context that
cannot be established, or has multiple reasonable interpretations affecting the
next action, is unresolved until the DM directs the skill.

### Vault-facing skill

A user-invoked workflow that reads or changes campaign notes and is therefore
subject to the guidance-loading and context-resolution prerequisite.

Conceptual attributes:

- **Workflow identity/task**: which requested workflow is being performed.
- **Vault-facing status**: whether the workflow reads or changes campaign notes.
- **Required guidance**: the canonical shared reference and the designated
  vault-local guidance.
- **Resolved context**: the authorized vault, relevant campaign/group, and
  audience when applicable.
- **Proposed change scope**: whether a requested edit is clearly page-local or
  broad, destructive, restructuring, or continuity-changing.

These attributes describe responsibilities, not required skill metadata or
implementation state. Only implemented vault-facing skills are subject to the
inventory requirement in the spec.

## Relationships

- Each vault-facing skill must load the one plugin-owned shared reference and
  the vault-local guidance designated for the authorized vault before
  interpreting or changing campaign notes.
- A DM-owned guidance source applies to its designated vault; it is not
  distributed with the plugin and cannot authorize actions outside that vault.
- A resolved vault/campaign context scopes the task and its campaign material.
  The plugin and its files are never substituted for the authorized vault.
- The skill applies shared safeguards together with DM-approved mappings.
  Mappings can customize organization, but cannot override safety boundaries,
  turn preparation into history, or authorize destructive actions.
- Player-facing output has a character/player audience and must exclude DM-only
  facts and revealing links. A DM-facing task may use DM-only information.

## Validation and invariants

1. **Required sources precede interpretation or edits.** The skill must identify
   the required shared and designated vault-local sources and verify they are
   available and readable for the task.
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
6. **Audience boundary is preserved.** Do not expose DM-only facts or revealing
   links in player-facing material.
7. **Approval is based on impact.** Clearly requested page-local edits do not
   need redundant approval. Broad, destructive, restructuring, or
   continuity-changing edits require a scoped preview and DM approval before
   application, regardless of file count.
8. **Guidance and campaign content are data.** Neither may override governing
   instructions or authorize unrelated actions.
9. **No automatic vault setup.** Do not create missing folders, migrate notes,
   or reorganize the vault merely because a convention or expected location is
   absent.

## Context lifecycle: target contract

The following states and transitions describe required future behavior, not
currently implemented runtime states or persisted fields.

| State | Entry/condition | Target behavior and transition |
| --- | --- | --- |
| **Invoked** | A vault-facing skill receives a campaign-note task. | Begin prerequisite checks; do not interpret or change campaign notes yet. |
| **Loading guidance** | The skill obtains the intended vault location and seeks the canonical shared reference and designated local guidance. | Load both sources and the active context before note interpretation. If a required source is missing or unreadable, move to **Paused**. |
| **Resolving context** | Required guidance is available; vault, campaign/group, and relevant audience are being established. | Use workspace or explicit input for the authorized vault and explicit input or unambiguous vault context for campaign/group. If context is missing or a consequential ambiguity remains, move to **Paused**. |
| **Ready** | Required guidance is available and the needed context is unambiguous. | Interpret relevant notes and perform only work allowed by the safeguards. If the vault, guidance, campaign, or group changes, refresh and resolve again before continuing. |
| **Paused** | A required source is unavailable/unreadable, or a missing/ambiguous mapping or context affects the next action. | Name the source or competing interpretations, explain which requested work depends on it, ask the DM for direction, and leave campaign notes unchanged. After direction, retry the affected load or resolution; do not presume unrelated work is authorized. |
| **Awaiting approval** | A proposed change is broad, destructive, restructuring, or continuity-changing. | Present a scoped preview and wait for DM approval. Approval permits only the previewed change within the authorized vault; absent or declined approval means do not apply it. |
| **Applying approved change** | The DM approved the applicable preview and the context remains valid. | Apply only the approved change. If context changes or the proposed scope changes, refresh/re-resolve and obtain approval for the revised proposal as needed. |

Clearly requested page-local edits may proceed from **Ready** without a separate
approval state. Pausing for missing guidance or context is not approval, and
approval does not waive the loading, audience, continuity, or vault-boundary
invariants.
