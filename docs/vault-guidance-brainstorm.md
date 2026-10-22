# Brainstorm: Vault Guidance for the AI

## Purpose and Status

This report captures the vault-organization discussion and proposes directions
for the next stages of plugin development: shared AI reference material, skills,
and potentially hooks. It is a design input, not an implemented specification.
No reference loader, skill, hook, or vault configuration described below exists
yet.

The [README](../README.md#intended-vault-structure-and-workflow) explains the
intended user workflow. This report addresses how the plugin could make the AI
follow that workflow. Component boundaries remain those in
[Plugin Architecture](architecture.md).

## Confirmed Requirements

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

## Vault Profile and Note Metadata: Options to Decide

A minimal profile could record section paths, root-level adventure exceptions,
campaign/group identifiers, preparation locations, and knowledge conventions.
Its filename, format, and discovery mechanism remain open. Compare a readable
Markdown profile with structured metadata only when actual validation needs are
known; do not require both by default.

Start with existing headings, links, and prose. Consider optional metadata for
note role, campaign/group scope, preparation versus actual-play status, or
knowledge audience only if those cannot be determined reliably. Metadata must
not force a migration of existing notes.

Keep campaign-specific profiles and content in the user's vault, outside the
distributed plugin. A profile must not authorize reading outside that vault
through relative paths or links without explicit permission.

## Open Questions

- How will users designate a vault profile, and how will skills reliably locate
  the installed shared reference?
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

## Suggested Development Sequence

1. Review this report and settle the reference location and profile-discovery
   contract. Keep unresolved campaign semantics explicit.
2. Extract the agreed meanings and safeguards into the shared AI reference.
3. Implement orientation with the explicit read prerequisite and a read-only
   fallback for an unconfigured vault.
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
