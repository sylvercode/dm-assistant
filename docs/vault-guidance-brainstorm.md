# Brainstorm: Vault Guidance for the AI

## Purpose and Status

This report captures the vault-organization discussion and proposes directions
for the next stages of plugin development: shared AI reference material, skills,
and potentially hooks. It is a design input, not an implemented specification.
No reference loader, skill, hook, script, or vault configuration described below
exists yet.

The [README](../README.md#intended-vault-structure-and-workflow) explains the
intended user workflow. This report addresses how the plugin could make the AI
follow that workflow. Component boundaries remain those in
[Plugin Architecture](architecture.md).

## Confirmed Requirements

### PowerShell Availability

PowerShell must be available in the environment executing future script-backed
workflows. This is a planned runtime prerequisite, not a requirement for
installing the current empty scaffold. Use the current latest stable PowerShell
runtime (`pwsh`) and latest stable required modules, including powershell-yaml.
Resolve and record the exact versions when implementing and validating workflows;
this policy does not authorize automatic installation or upgrades during a task.
The supported platform matrix and provisioning method remain to be decided.

### Obsidian Compatibility and Configuration Location

Use `.dmassist.yaml` at the vault root for configuration. Plugin-added support
files, such as configuration, auxiliary AI guidance, or generated indexes, must
have dot-prefixed names so they remain hidden from Obsidian's normal note view.
This applies to plugin support artifacts, not campaign Markdown articles intended
to be read in Obsidian. Do not rename existing user files or modify Obsidian's
own configuration to enforce this convention. Hidden files are not an access
control mechanism.

### Flexible Sections, Stable Meanings

Folder names provide defaults, not a required layout. The assistant must
understand a note's role without requiring users to reorganize their vault.

| Default section | Meaning and supported variations |
| --- | --- |
| Adventures | Playable story arcs, encounters, events, and DM instructions. One Markdown file may represent an adventure; folders may represent arcs containing several notes. The Adventures folder may be absent, with adventure files at the vault root. Not every root-level note is therefore an adventure. |
| Lore | Shared world background referenced by other notes for consistent storytelling. Historical events belong here when they are background, not events the players will run. Additional subsections are allowed. |
| Monsters Stats | Reusable monster statistics referenced from personas, adventures, lore, or other notes. A persona's identity and history are distinct from its combat statistics. |
| Rules | Recurring rules, reminders, and DM-approved custom rulings. Official rules and house rules should be distinguishable. |
| Sessions | Primarily recaps and logs of actual play, used as references for subsequent sessions. Preparation must remain distinguishable from confirmed outcomes. |
| Handouts | Documents explicitly intended to be shown to players, such as letters, maps, or player-safe summaries. Keep DM commentary and revealing source links out of them. |

The vault as a whole is for the DM's eyes only. Ordinary notes can contain both
world truth and character beliefs; they need not be sanitized as if players
could browse the vault. Any document intended for players is a handout, with
Handouts as an additional suggested section. Creating a handout does not
authorize publishing or sharing the vault.

Suggested Lore subsections are Player, Locations, Cosmology, and Persona.
Locations may include Town-Cities, Regions, Landmarks, and Planes. These are
examples, not an exhaustive taxonomy.

### Characters and Knowledge

- Player means player character, not the real person at the table.
- A person may play several characters, and people may share a character.
- Each character has an article; each adventuring group also has an article.
- Character and group knowledge must be distinct from DM-only information and
  information that might be discovered later.
- Players roleplay from their character's knowledge, not all information
  available to the DM or the people playing.
- Record lore shared by the party in the party/group article, with explicit
  per-character exceptions for absent or otherwise uninformed characters.
  Absence alone must not imply later knowledge. The DM's judgment is sufficient
  to establish knowledge or remove an exception; no evidence log, source link,
  or recorded information-sharing event is required for that judgment.
- Explicitly label rumors and mistaken beliefs and reference the real facts in
  the underlying DM-facing record. If the real facts are not established, mark
  them as unknown and ask the DM rather than inventing a correction. These
  references do not grant characters access to the truth; character-facing
  output, including handouts, must not reveal DM-only facts or links that
  disclose them. This does not prevent DM-facing notes from explaining both.

### Preparation and Actual Play

- Likely preparation may be included in a session note under a separate section.
- Preparation may instead live in a Preparations subfolder within Sessions.
- Any prepared event may remain unused because of player choices.
- Session recaps record what happened. Unused preparation is not campaign history
  and does not establish character knowledge.
- Do not update adventure plans to match outcomes after they have been run.
  They are expected to become outdated; sessions record what actually happened.

### Lore Evolution and Contradictions

- Record changes to lore caused by player actions or other events as
  **evolution**, preserving the previous context rather than silently replacing
  it. Link to the relevant session when applicable; the session contains the
  detailed account of the event.
- Evolution can also come from events outside a play session. Do not fabricate
  a session reference when none applies.
- Never automatically correct contradictions, even when chronology seems to
  suggest a resolution. Tell the DM about the conflicting accounts and leave
  them unchanged until the DM clarifies. Accepted reality may be decided later.
- A clearly established change over time is evolution, not permission to resolve
  a contradiction. If the relationship between accounts is ambiguous, report it
  rather than choosing, reconciling, or inventing an explanation.
- Knowledge decisions do not require an evidence trail. Respect the DM's
  judgment while keeping optional session links for lore evolution distinct
  from proof of a character's knowledge.

### Campaigns and Reuse

- Initial workflows target one campaign per vault. Multiple campaigns sharing a
  vault or world state are a future evolution, not an initial implementation
  requirement. Such vaults would need clearly identified campaign groups in the
  Player section.
- Knowledge and actual outcomes must remain scoped to the relevant campaign and
  group, rather than leaking between campaigns.
- Rerunning an adventure as a fresh campaign means copying the vault and removing
  the old session logs, characters, groups, and their accumulated knowledge from
  the copy. Preserve the original.
- Review retained notes for campaign-specific changes and references before
  establishing the new campaign's starting state.

### Editing Approval and Git History

Expect the vault to be maintained in a Git repository for review and recovery,
but verify that assumption before relying on history. Do not initialize Git,
commit, push, or discard user changes without authorization.

Small, clearly requested edits local to a page may be applied without a separate
approval or mandatory preview. Major changes require a scoped preview and DM
approval: for example, bulk edits, restructuring, deletion, campaign resets, or
changes with broad continuity consequences. Impact matters more than file count;
a one-page rewrite that changes established history can still be major.

Keep changes within the request and protect concurrent or uncommitted user
edits. Git is a recovery aid, not permission to make destructive changes.

## Recommended Guidance Model

Use three layers with distinct responsibilities:

1. **Plugin-owned reference:** Shared meanings, defaults, examples of ambiguous
   notes, and safeguards for knowledge, preparation, and campaign isolation.
2. **Vault-local profile:** DM-approved mappings of those meanings to this vault's
   paths, plus campaign/group identifiers and organization exceptions.
3. **Task skill:** Instructions to load the reference and relevant profile before
   reading or changing campaign material, then perform a specific workflow.

The README is an entry point for users, not a substitute for AI instructions.
Do not assume Markdown in the plugin's docs directory is automatically loaded
into the model's context.

### Where the Reference Could Live

| Option | Benefit | Trade-off |
| --- | --- | --- |
| Reference bundled with a vault-orientation skill | Keeps shared guidance with a portable workflow and its resources. | Other skills need a verified way to find and read that resource. |
| Shared reference under plugin docs | Easy for contributors and users to discover. | Still needs explicit resource loading; docs discovery is not skill execution. |
| Full reference repeated in every skill | Each skill is self-contained. | Duplicated rules can drift and waste context. |

Prefer a single reference bundled with an orientation skill, with a user-facing
summary in the README. Select the actual resource path only after verifying how
the supported client resolves installed plugin resources. Do not assume the
current directory is the plugin directory.

### Proposed Instruction to Read the Reference

Every vault-facing skill should carry an explicit prerequisite instruction with
this meaning:

> Before interpreting, creating, or modifying campaign notes, read the plugin's
> shared vault-structure reference and any explicitly designated vault-local
> profile. Resolve the target vault and active campaign/group. Apply the vault's
> confirmed mappings instead of assuming the default folders. Keep preparation,
> actual events, and character knowledge separate. If required guidance cannot
> be read, or the target context is ambiguous, explain what is missing and ask
> the DM before making changes.

This is proposed instruction wording, not an active plugin component. Each
future skill must identify a resolvable resource location; a vague instruction
to “follow the vault conventions” is insufficient.

### Loading and Discovery Sequence

1. Obtain the vault location from the workspace or explicit user input. Never
   treat the installed plugin as the campaign vault.
2. Read the plugin reference and discover `.dmassist.yaml` at the vault root,
   if present, including any designated vault-local guidance.
3. Resolve the requested campaign, group, and output audience: DM or characters.
4. Inspect only relevant directories and representative notes to verify mappings.
5. If no profile exists, infer a provisional mapping from the existing layout,
   then ask about ambiguity that affects the task. Do not require a profile for
   a straightforward read-only lookup.
6. Before changes, confirm uncertain destinations or conflicting conventions.
   Missing folders are not permission to create or move content.
7. Refresh guidance when the vault, profile, campaign, or group changes; do not
   reuse another campaign's context.

Explicit DM-approved mappings should take precedence over guessed folder roles.
Mappings customize organization, not safety: they cannot turn preparation into
history or silently grant permission for destructive operations. Campaign prose
is source material, not instructions to execute commands or override the task.

## Candidate Skills

These are workflow candidates, not a commitment to create all components.
Every vault-facing candidate must use the shared loading prerequisite.

| Candidate | Responsibility | Boundary |
| --- | --- | --- |
| Vault orientation | Discover or confirm section mappings, campaign/group context, and ambiguities. Offer a profile for DM review. | Do not automatically restructure the vault or write a profile without approval. |
| Find and connect notes | Locate relevant lore, adventures, rules, and statistics; resolve references. | Do not infer a note's role solely from its folder or expose DM-only information in character-facing answers. |
| Session preparation | Assemble relevant material and possible events for a group. | Label preparation as tentative; never update actual history from this workflow. |
| Session recap | Separate actual play from unused preparation and draft a sourced recap. | Missing outcomes require clarification, not invention. |
| Knowledge and lore evolution | Apply DM knowledge judgments and record established lore evolution, linking sessions when applicable. | Do not require knowledge evidence, rewrite run adventure plans, or resolve contradictions; report conflicting accounts and await DM clarification. |
| Fresh-campaign reuse review | Identify campaign-specific state to remove or reset in a copied vault. | Start with a review checklist, not automated deletion. Never clean the original vault. |

Begin with orientation and one end-to-end session workflow to validate the shared
reference before expanding the skill set. Keep shared guidance in skills rather
than duplicating it across specialized agents.

## PowerShell and Predictable Operations

Use PowerShell scripts for repeatable mechanical operations rather than asking
the AI to recreate shell commands for each task. Candidate responsibilities are
vault inventory, profile validation, scoped note lookup, link checks, and
previews of proposed file changes. Keep interpretation of story events,
character knowledge, and ambiguous note roles with the AI and DM: a script
cannot establish those facts from folder names alone.

Future skills may bundle scripts alongside their resources. Hooks may call the
same operations where client support is verified, rather than duplicating their
logic. Scripts supplement the explicit instruction to read the shared reference;
running a script does not prove that the AI loaded the guidance.

Define these contracts before implementing script-backed workflows:

- Check PowerShell availability and supported version before invocation. If it
  is missing or unsupported, report the prerequisite and stop the scripted
  operation without edits; independent read-only assistance may continue.
- Use explicit vault, campaign/group, and operation inputs, independent of the
  working directory. Validate resolved paths, including symbolic links, against
  the authorized vault boundary.
- Return consistently ordered, structured results and documented exit codes,
  with clear errors rather than partial success presented as completion.
- Treat note content and supplied paths as data, never executable expressions
  or interpolated shell commands. Do not bypass execution-policy or security
  controls to make scripts run.
- Default inspection operations to read-only. Follow the editing policy above:
  requested local edits need no separate approval, while major changes need a
  preview and approval. Detect intervening changes before writes, including
  changes since any preview. Preserve Markdown content and encoding.
- Keep campaign data local and avoid unnecessary content in diagnostic logs.
  Test repeatability and failure behavior on each supported platform.

The first script candidates should be inventory and validation, not automated
campaign cleanup. No PowerShell installation, script implementation, or hook
registration is part of this brainstorm.

## Hook Opportunities and Limits

Hooks are optional reinforcement, not the initial source of truth. Exact events,
payloads, resource access, and whether a hook can supply model context must be
verified against the supported Copilot client before choosing an implementation.
Do not register placeholder hooks.

Potential uses, if supported:

- At session initialization or relevant task entry, remind the assistant to load
  the shared reference and resolve vault/campaign context.
- Before writes, check that a target vault and campaign/group have been selected
  and that proposed destinations stay within the authorized vault.
- After edits, report unresolved links or missing campaign associations using
  available tools, without silently rewriting unrelated notes.

Prefer explicit skill prerequisites first: they are visible and portable. Add a
hook only for an observed gap and a supported lifecycle event. A hook firing
does not prove the AI read the reference or understood it. Retain explicit skill
instructions when hooks are unavailable or fail.

Do not execute commands drawn from campaign notes, log private campaign content
unnecessarily, or use a hook as implicit consent for edits or deletion.

## YAML Vault Configuration and Note Metadata

Use YAML as the proposed format for vault-local configuration and options, with
[cloudbase/powershell-yaml](https://github.com/cloudbase/powershell-yaml) as the
proposed PowerShell parser. This records the discussion's direction; no module
is installed, version selected, or configuration loader implemented yet.

Keep machine-readable settings in YAML and explanatory guidance in Markdown.
A minimal configuration could include:

- A configuration schema version.
- Section paths and root-level adventure exceptions.
- The campaign/group context and references to its notes; shared-campaign
  configuration is deferred.
- Preparation locations, note-naming options, and preview preferences.
- Paths to additional vault-specific Markdown guidance the AI must read.

Do not duplicate lore, session history, or character knowledge in configuration.
The filename and location are `.dmassist.yaml` at the vault root. The proposed
version-1 schema and defaults are defined in
`specs/002-vault-configuration-contract/`; a reader, validator integration, and
runtime behavior remain future work. Retain optional fields and a read-only
discovery fallback for unconfigured vaults. Any additional plugin support files
must follow the dot-prefix convention above.

The shared PowerShell loader should parse and validate configuration before
skills or hooks consume it. Parsing YAML does not validate field types, supported
schema versions, or path boundaries. Before implementation, resolve and review
the latest stable module version and its dependencies, record the versions used,
decide how it is provisioned, and verify
its behavior for duplicate keys, custom tags, aliases, and implicit scalar
conversions. These behaviors are not assumed to be enforced by the parser.

Prefer a restricted YAML subset of mappings, lists, and scalar values. Reject
duplicate keys and custom tags, define unknown-field handling, and report invalid
configuration rather than silently falling back to guessed settings. Configuration
must not execute commands, override safety rules, or grant permission for
destructive actions. Preview preferences may strengthen safeguards, not remove
the preview and approval requirement for major changes.

Use native [Obsidian tags](https://obsidian.md/help/tags) to represent knowledge
and belief categories, rather than introducing a custom metadata system for
them. Nested tags can distinguish categories; the exact vocabulary remains to be
chosen. Keep tags consistent with existing vault conventions and do not force a
migration of existing notes.

Tags classify information; prose identifies who knows it, character exceptions,
and the claim being classified, while links reference the real facts and source
notes. In mixed-content notes, keep a tag beside the relevant passage or heading
so a rumor label is not mistaken for the status of the entire article. Tags do
not establish truth, grant access, or replace those explanations.

Keep campaign-specific profiles and content in the user's vault, outside the
distributed plugin. A profile must not authorize reading outside that vault
through relative paths or links without explicit permission.

## Vault-Specific AI Guidance and Obsidian Syntax

Use optional `.dmassist-guidance.md` at the vault root for free-form campaign
instructions, referenced from `.dmassist.yaml`. Future vault-facing skills must
read that designated file along with the plugin reference before generating or
editing notes. This is an agreed design direction, not an implemented loader;
the YAML field name remains part of the deferred schema.

The plugin reference should explain standard Obsidian Markdown conventions.
The vault guidance can customize their use, narrative style, and language without
duplicating structured settings or campaign facts. Preserve existing conventions
when editing notes, and do not reformat unrelated content.

### Proposed Callout Uses

Use native [Obsidian callouts](https://obsidian.md/help/callouts) with descriptive
titles to distinguish material at a glance:

| Purpose | Proposed callout | Content boundary |
| --- | --- | --- |
| Text to read aloud | `quote`, titled “Read aloud” | Player-safe narration for the specified scene, without DM instructions or hidden facts. |
| Important DM tips | `tip`, titled “DM tip” | Pacing, portrayal, or other practical advice; not text intended to be read aloud. |
| Important cautions | `warning`, with a specific title | Consequences, continuity risks, or reminders the DM should notice. |
| Secret information | `note`, titled “DM only” | DM-facing facts kept separate from player-facing narration. |

These are proposed defaults that vault guidance may override. Prefer built-in
callout types so no theme, CSS snippet, or community plugin is required.
Formatting a prepared scene as “Read aloud” does not establish that it happened.

Future authoring instructions should require valid callout syntax: a blockquote
whose first line contains `[!type]` and a title, with each content line (including
blank lines within the callout) carrying the blockquote prefix. Keep separate
purposes in separate callouts, and use ordinary prose for content that does not
need special presentation.

A “DM only” title or a collapsed callout is a visual cue, not access control.
When producing a player-facing document, omit hidden facts and revealing links
entirely rather than merely placing them in a labeled or collapsed callout.
Read-aloud narration must respect the intended characters' knowledge and the
requested scene; it must not silently reveal the truth behind rumors.

Other useful reference topics are internal note links, heading links, and embeds.
Resolve link targets rather than inventing them, and avoid embedding a whole
DM-facing note into player-facing material. Exact conventions beyond callouts can
be expanded when concrete workflows need them.

## Article Template Storage and Selection

This decision covers storage and selection only. Template contents, exact YAML
fields, and runtime loading are deferred; no templates or loader are implemented
by this report.

### Plugin Defaults and DM Ownership

Bundle default templates as resources of the relevant skills inside the installed
plugin, for example under `skills/<skill-name>/templates/`. They are plugin-owned
defaults, separate from campaign data. Resolve them relative to the installed
skill resource location, not the current working directory.

Recommend `.dmassist-templates/` at the vault root for DM-owned templates, with
dot-prefixed Markdown filenames to follow the plugin support-file convention.
The DM may copy a plugin default there and customize it, or write a template
from scratch. Copying is optional and must not overwrite an existing custom
template. Plugin updates must never replace these vault-owned copies.

The DM may also reference an existing template elsewhere inside the vault.
Do not move or rename existing user templates to enforce the hidden-file
convention; it applies to newly added plugin support artifacts.

### Configuration and Resolution

Use `.dmassist.yaml` to map article types to custom template paths, relative to
the vault root. The exact field names and article-type identifiers will be
designed with the configuration schema.

For each new article:

1. Use the explicitly configured DM template for that article type.
2. If no override is configured, use the relevant plugin default.
3. If a configured template is missing, unreadable, or invalid, report the error
   and stop that article's creation rather than silently substituting a default.
4. If neither an override nor a plugin default exists, explain that no template
   is available and ask the DM how to proceed.

Validate custom template paths against the authorized vault boundary, including
symbolic links and relative-path traversal. Treat templates as authoring
resources, not commands or permission to read other files.

Skills must explicitly read the selected template before creating the article,
along with the shared reference and designated vault guidance. Templates guide
new articles; selecting or updating a template does not migrate, reformat, or
overwrite existing campaign notes. Template selection does not alter the rules
for handouts, lore evolution, contradictions, or preserved adventure plans.

### Obsidian Templates Boundary

These are plugin authoring templates, not automatic integration with Obsidian's
Templates feature. Existing Obsidian template files can be referenced as source
material, but dynamic expressions, substitutions, and community-plugin syntax
require separately defined support. Do not execute expressions or claim that
Obsidian or community-plugin expansion has occurred. If unresolved expressions
are needed for the article, report the limitation and ask the DM how to proceed.

## Open Questions

- How will skills reliably locate the installed shared reference and additional
  vault-local Markdown guidance?
- Which article-type identifiers and configuration fields will select template
  overrides? Template contents and dynamic-expression support remain deferred.
- How will latest stable PowerShell and required modules be provisioned, checked,
  and recorded, and which YAML features will the shared loader accept?
- How should party membership and knowledge exceptions be presented for convenient
  DM maintenance, without requiring evidence for the DM's decisions?
- Which Obsidian tag vocabulary and placement conventions should express party
  knowledge exceptions, rumors, and mistaken beliefs alongside prose and links?
- How should unresolved uncertainty and later DM-directed retcons be represented,
  while leaving contradictions unchanged until clarification?
- What headings or tags should distinguish lore evolution from the original
  context and link applicable sessions?
- What additional examples should clarify the boundary between local edits and
  major changes requiring preview and approval?
- Which supported hook events address a real gap after the skill workflow works?
- Which platforms will be supported, and what input,
  output, and failure contracts should be shared by skills and hooks?

Deferred evolution: representing divergent world facts across campaigns sharing
a vault, without overwriting each other's history. This is not a blocker for the
initial single-campaign workflows.

## Suggested Development Sequence

1. Review this report and settle the shared reference location and parser
   provisioning. Use root-level `.dmassist.yaml`; its proposed version-1 schema
   and defaults are documented in Feature 002, while parser/runtime
   implementation remains separate. Keep shared campaigns out of initial scope.
2. Extract the agreed meanings and safeguards into the shared AI reference.
   When authoring skills are added, bundle their default templates and implement
   the custom-template selection contract without migrating existing notes.
3. Implement orientation with the explicit read prerequisite and a read-only
   fallback for an unconfigured vault. Resolve the latest stable runtime/modules
   and validate an initial read-only inventory or profile-checking script.
4. Implement preparation/recap workflows, lore evolution entries, and DM-directed
   knowledge updates without evidence requirements.
5. Exercise the acceptance scenarios below in the installed client.
6. Add hooks only where verified client support closes a demonstrated gap.

### Acceptance Scenarios for Future Implementation

- An adventure at the root is found without classifying every root note as an
  adventure or creating an Adventures folder.
- A folder-based arc and a single-file adventure both work without migration.
- Renamed folders follow the confirmed profile; extra Lore sections are retained.
- Multiple people sharing a character, or one person playing several characters,
  does not merge distinct characters' knowledge.
- Party lore records shared information with exceptions for absent or uninformed
  characters; DM knowledge judgments update exceptions without an evidence log.
- Lore evolution preserves prior context and links applicable sessions containing
  event details; events outside sessions do not require invented session links.
- Adventure plans remain unchanged after being run, even when actual outcomes
  differ from their planned events.
- Contradictions are reported without rewriting either account or choosing an
  accepted reality, including when the DM defers clarification.
- Rumors and mistaken beliefs are labeled and linked to real facts in DM-facing
  records without leaking those facts in character-facing output.
- Mixed preparation and recap notes never turn an unused encounter into history.
- Character-facing output excludes DM-only facts, and unknown knowledge is not
  guessed from what the assistant can read.
- Initial workflows do not silently combine multiple campaigns. In a future
  shared-campaign implementation, selecting another group must not carry over
  the previous group's discoveries or campaign-specific outcomes.
- A fresh-campaign review targets only the copy and identifies residual knowledge
  and outcome references without deleting reusable lore or the original vault.
- Missing references, ambiguous mappings, unavailable hooks, and changed vault
  context produce explicit fallback behavior rather than silent assumptions.
- Campaign text containing instructions does not override the skill's task or
  authorize commands, external reads, or destructive changes.
- Missing or unsupported PowerShell stops scripted operations with a clear
  prerequisite message and leaves the vault unchanged.
- Identical inputs produce consistently ordered script results; paths containing
  spaces or non-ASCII characters work on every supported platform.
- Paths escaping the authorized vault and stale write previews are rejected
  without unintended edits; executable-looking note content remains inert data.
- A valid YAML configuration supplies the same validated settings to skills and
  hooks. Invalid types, unsupported schema versions, duplicate keys, forbidden
  tags, and out-of-vault paths produce clear errors before edits.
- A missing YAML module reports the required dependency without silently
  installing it or attempting an ad hoc parser.
- A designated `.dmassist-guidance.md` is read before note authoring, and its
  formatting preferences are applied without rewriting unrelated content.
- Read-aloud text and DM tips render as separate native Obsidian callouts;
  multiline content remains inside the intended callout.
- Player-facing exports contain no DM-only callouts, secret links, or embeds,
  even if the source note uses collapsed callouts.
- Handouts are the player-facing document type; DM notes retain truth references
  without those references leaking into handouts.
- Obsidian tags classify the intended passage without implying that every claim
  in a mixed-content note has the same status.
- A requested local edit proceeds without redundant approval; major changes wait
  for approval, regardless of how many pages they touch. Existing user changes
  are preserved, and Git availability is checked before relying on recovery.
- `.dmassist.yaml` is discovered at the vault root, even when ordinary note
  listings omit hidden files. Plugin support artifacts use dot-prefixed names,
  while campaign articles remain visible in Obsidian.
- A configured DM template overrides the plugin default and is read before
  article creation. Without an override, the installed default is used.
- Missing or unreadable overrides produce errors without silent fallback;
  out-of-vault template paths are rejected.
- Existing vault templates work without being moved or renamed. Plugin updates
  leave DM copies unchanged, and template changes do not migrate existing notes.
- Unresolved dynamic template expressions are reported, not executed or silently
  presented as successfully expanded.
