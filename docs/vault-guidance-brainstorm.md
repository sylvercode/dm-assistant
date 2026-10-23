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
installing the current empty scaffold. The supported version and platforms
remain to be decided; a cross-platform PowerShell runtime (`pwsh`) is the
recommended direction.

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

### Preparation and Actual Play

- Likely preparation may be included in a session note under a separate section.
- Preparation may instead live in a Preparations subfolder within Sessions.
- Any prepared event may remain unused because of player choices.
- Session recaps record what happened. Unused preparation is not campaign history
  and does not establish character knowledge.

### Campaigns and Reuse

- A vault may contain multiple campaigns, with clearly identified groups in the
  Player section.
- Knowledge and actual outcomes must remain scoped to the relevant campaign and
  group, rather than leaking between campaigns.
- Rerunning an adventure as a fresh campaign means copying the vault and removing
  the old session logs, characters, groups, and their accumulated knowledge from
  the copy. Preserve the original.
- Review retained notes for campaign-specific changes and references before
  establishing the new campaign's starting state.

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
2. Read the plugin reference and the designated vault profile, if present.
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
| Knowledge and continuity update | Propose character/group knowledge and lore changes supported by recorded play. | A witnessed event is not automatically known by every character; show sources and resolve contradictions with the DM. |
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
- Default inspection operations to read-only. Any future write operation needs
  a preview, explicit authorization, and protection against overwriting notes
  changed since the preview. Preserve Markdown content and encoding.
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
- Campaign/group identifiers and references to their notes.
- Preparation locations, note-naming options, and preview preferences.
- Paths to additional vault-specific Markdown guidance the AI must read.

Do not duplicate lore, session history, or character knowledge in configuration.
The filename, exact schema, defaults, and discovery mechanism remain open.
Prefer one clearly named file at the vault root, with optional fields and a
read-only discovery fallback for unconfigured vaults.

The shared PowerShell loader should parse and validate configuration before
skills or hooks consume it. Parsing YAML does not validate field types, supported
schema versions, or path boundaries. Before implementation, select and review a
module version and its dependencies, decide how it is provisioned, and verify
its behavior for duplicate keys, custom tags, aliases, and implicit scalar
conversions. These behaviors are not assumed to be enforced by the parser.

Prefer a restricted YAML subset of mappings, lists, and scalar values. Reject
duplicate keys and custom tags, define unknown-field handling, and report invalid
configuration rather than silently falling back to guessed settings. Configuration
must not execute commands, override safety rules, or grant permission for
destructive actions. Preview preferences may strengthen safeguards, not remove
the write-preview and authorization requirements.

Start with existing headings, links, and prose. Consider optional metadata for
note role, campaign/group scope, preparation versus actual-play status, or
knowledge audience only if those cannot be determined reliably. Metadata must
not force a migration of existing notes.

Keep campaign-specific profiles and content in the user's vault, outside the
distributed plugin. A profile must not authorize reading outside that vault
through relative paths or links without explicit permission.

## Open Questions

- What configuration filename, schema, defaults, and discovery rules should be
  used, including behavior for missing, invalid, or newer schema versions?
- How will skills reliably locate the installed shared reference and additional
  vault-local Markdown guidance?
- Which powershell-yaml version and dependencies should be approved, how will
  they be provisioned, and which YAML features will the shared loader accept?
- How should one vault represent divergent world facts across campaigns sharing
  the same lore without overwriting each other's history?
- How should group membership changes affect shared knowledge, especially for
  characters absent from a session?
- How should uncertain memories, rumors, mistaken beliefs, and retcons be
  represented without confusing them with established world facts?
- What is the minimum source reference needed to support a continuity update?
- Which recap and knowledge edits may be applied directly on request, and which
  should always be presented as a preview?
- Which supported hook events address a real gap after the skill workflow works?
- Which PowerShell version and platforms will be supported, and what input,
  output, and failure contracts should be shared by skills and hooks?

## Suggested Development Sequence

1. Review this report and settle the reference location and profile-discovery
   contract, YAML schema, and parser provisioning. Keep unresolved campaign
   semantics explicit.
2. Extract the agreed meanings and safeguards into the shared AI reference.
3. Implement orientation with the explicit read prerequisite and a read-only
   fallback for an unconfigured vault. Define the PowerShell support baseline
   and validate an initial read-only inventory or profile-checking script.
4. Implement a preparation/recap workflow and source-backed continuity proposals.
5. Exercise the acceptance scenarios below in the installed client.
6. Add hooks only where verified client support closes a demonstrated gap.

### Acceptance Scenarios for Future Implementation

- An adventure at the root is found without classifying every root note as an
  adventure or creating an Adventures folder.
- A folder-based arc and a single-file adventure both work without migration.
- Renamed folders follow the confirmed profile; extra Lore sections are retained.
- Multiple people sharing a character, or one person playing several characters,
  does not merge distinct characters' knowledge.
- Mixed preparation and recap notes never turn an unused encounter into history.
- Character-facing output excludes DM-only facts, and unknown knowledge is not
  guessed from what the assistant can read.
- Selecting another group does not carry over the previous group's discoveries
  or campaign-specific outcomes.
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
