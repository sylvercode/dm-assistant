# Shared Vault Guidance Validation Quickstart

**Status: validation guide for planned behavior.** This repository is currently
an Agent Plugins 1.0 scaffold; it does not yet implement the skills, loader, or
guidance resource described here. Do not treat a successful plugin install as
proof that the planned behavior exists. Use this guide when those components
are available, and record unsupported or blocked checks as such.

See [the feature specification](spec.md), [data model](data-model.md), and
[loading contract](contracts/vault-guidance-loading.md) for requirements and
invariants. The [research](research.md) records the installed-resource lookup
decision and its verification caveat. This guide deliberately does not define
a vault configuration schema or require a particular vault-local guidance
path.

## Prerequisites and safe test setup

- Use GitHub Copilot CLI, the supported client selected for installed-resource
  validation.
- Install the Obsidian Link Resolver MCP server separately (minimum compatible
  release `2.0.0`) and configure it in Copilot CLI's user-managed MCP settings
  with one or more explicitly authorized absolute vault roots. Verify with
  `copilot mcp list` and `copilot mcp get obsidian-link-resolver`, then confirm
  `resolve_obsidian_link` is available in a new session. Do not embed
  user-specific vault paths in the plugin or repository.
- The dependency inventory is non-exhaustive. Every vault-facing skill must
  verify all currently declared required dependencies before accessing
  campaign notes. Obsidian Aliases and Tags pages are reference sources, not
  runtime dependencies.
- Use a **disposable test vault**, separate from the plugin checkout and any
  live campaign vault. Make a manual before-test inventory of its files and
  contents so that you can confirm whether any note changed.
- Prepare test material manually in that vault: a DM-only fact, tentative
  preparation that may not happen, an actual-play record, a character's
  established knowledge, a conflicting or unresolved account, and an existing
  adventure plan. Keep the test content fictional and recognizable so you can
  check what the skill does with it.
- If testing local guidance, create a test guidance file and explicitly identify
  its location to the skill. Do not assume a filename, configuration field, or
  discovery rule; `.dmassist.yaml` and `.dmassist-guidance.md` are proposals,
  not an implemented schema or required path.
- Use the ordinary, documented client launch method for starting interactive
  sessions. Do not infer or add commands, configuration fields, or skill names
  that are not documented by the installed client or implemented plugin.

Run all note-edit scenarios against this disposable vault. Before and after
each negative test, manually compare the vault with its recorded inventory.
The expected result is **no campaign-note changes** wherever a scenario says
the skill must pause or await approval.

## 1. Install and check discovery

From the plugin repository root, run the documented local installation
commands:

```shell
copilot plugin install .
copilot plugin list
```

**Expected:** the plugin is listed as `dm-assistant`. This only validates
installation; it does not establish that skills or the planned guidance loader
exist.

Start a **new** interactive session, then use the documented discovery checks:

```text
/agent
/skills list
```

**Expected once implemented:** the vault-orientation skill and every
implemented vault-facing skill are discoverable. Confirm that every skill that
reads, interprets, creates, or changes campaign material is present. The
current scaffold has no skills, so discovery of these skills is not an expected
current result.

### Required dependency availability and fail-closed behavior

In an isolated Copilot CLI configuration, first configure the resolver against
the disposable test vault and confirm `resolve_obsidian_link` is exposed in a
new session. Then use a separate isolated configuration with the resolver
missing or disabled and invoke each implemented vault-facing skill with a
campaign-note task.

**Expected:** each skill explains that the required resolver dependency is
unavailable and stops before reading or changing any campaign notes. Compare
the test vault with its before-test inventory to confirm no note access or
changes occurred. This prerequisite applies even when the requested task does
not itself resolve a link. Do not alter the user's active MCP configuration for
this test.

## 2. Verify canonical resource lookup from different working directories

1. Start a new interactive session with the installed plugin while the current
   working directory is the plugin repository.
2. Invoke an implemented vault-facing skill using the client-supported
   interaction. Ask it to identify the shared reference it loads before
   interpreting any test-vault notes.
3. Start another new interactive session with the same installed plugin while
   the current working directory is a different directory, outside the plugin
   checkout and test vault. Repeat the same request.
4. Compare the reported reference identity and loaded guidance in both
   sessions. Do not treat a source-checkout path, vault path, or a path found
   only relative to the current working directory as proof of installed
   resource lookup.

**Expected:** both sessions load the same canonical plugin-owned resource
from the installed skill/plugin, independently of current working directory.
The plugin installation is not identified as the campaign vault. If the client
cannot demonstrate this lookup, record the check as failed or blocked; source
tree presence alone does not pass it.

## 3. Verify vault and local guidance loading

1. In a new session, explicitly identify the disposable test vault and the
   test guidance file's location. Ask for a read-only summary of a known
   convention in that guidance and a relevant test note.
2. Ask which sources and campaign context the skill loaded before it interpreted
   the note.

**Expected:** before interpreting campaign notes, the skill loads the
plugin-owned shared reference, the explicitly designated vault-local guidance,
and the relevant vault/campaign context. It can distinguish the shared rules
from the DM-owned convention. It does not treat the plugin directory as the
vault or infer a different local-guidance source.

## 4. Verify missing, unreadable, and ambiguous inputs pause safely

For each case, start from a fresh session and verify the test-vault inventory
afterward.

### Designated local guidance missing or unreadable

1. In the disposable test setup, designate a local guidance file explicitly
   using the task input. Then, as a manual test-fixture action, make that file
   unavailable or unreadable without changing campaign notes.
2. Ask for work that depends on its convention.

**Expected:** the skill names the designated source and the failure, explains
which requested work depends on it, asks for direction or restoration, and
pauses that work. The test vault's campaign notes remain unchanged. A
designated-but-missing source is not the same as no local guidance having been
designated.

### Shared reference unavailable or unreadable

Only perform this check with an isolated, disposable plugin installation or
fixture, never by damaging a shared or production installation. Make the
canonical shared resource unavailable or unreadable as a manual fixture
action, then ask for a campaign-note task.

**Expected:** the skill names the shared source and failure, identifies the
dependent work, and pauses without campaign-note changes. If the installed
client provides no safe way to exercise this condition, record the case as
blocked rather than claiming it passed.

### Ambiguous campaign context or mapping

1. In the disposable vault, provide two plausible campaign/group identities or
   note mappings that would lead to different next actions.
2. Ask for a task whose next action depends on which interpretation is correct.

**Expected:** the skill states the competing interpretations, identifies the
decision needed, and asks the DM before dependent work. It does not silently
choose, substitute assumptions, or change notes. Verify that the inventory is
unchanged.

## 5. Verify campaign, knowledge, and handout safeguards

Using the prepared test material, ask an implemented vault-facing skill to
perform a representative preparation/history or recap task, then ask for
player-facing handout material.

**Expected:**

- Tentative preparation is not presented as an event that occurred or as
  character knowledge without DM confirmation.
- Established actual-play history and character/group knowledge remain
  distinct from DM-only facts and possible discoveries.
- Contradictions and unresolved adventure plans are reported and preserved,
  not silently reconciled or rewritten.
- Existing organization is preserved. An absent expected folder is not created
  just because it is absent.
- Player-facing output omits DM-only facts and links that reveal them. A
  hidden, collapsed, or labeled secret is not considered safe for players.
- Guidance and note text are treated as campaign data, not as authority to
  override governing instructions or expand the task.

Manually inspect both the response and the test vault. **Expected:** no
unrequested note changes, no invented continuity, and no DM-only disclosure in
player-facing output.

## 6. Verify page-local edits and the approval gate

### Clearly requested page-local edit

Ask for one specific, clearly scoped change to one existing page in the
disposable vault. Before-and-after inspect the page and the rest of the
inventory.

**Expected:** the skill can make the requested page-local edit without
redundant approval, changes only the requested content, and preserves unrelated
notes and user content.

### Broad, destructive, restructuring, or continuity-changing edit

Ask for a representative broad change in the disposable vault, such as
restructuring several notes or changing established continuity. Do not approve
until a preview is presented.

**Expected before approval:** the skill presents a scoped preview and waits;
no proposed note changes have been applied. Review the preview, then explicitly
approve that preview as a manual action.

**Expected after approval:** only the approved, previewed change is applied
within the authorized test vault. If the scope or context changes, the skill
returns for a revised preview/approval. Verify the result against the preview
and inventory. Approval does not waive the guidance, context, continuity, or
audience safeguards.

## Completion record

Record each check as **pass**, **fail**, or **blocked**, with the client/session
used, working directory for resource lookup, skill tested, and whether the
test-vault inventory changed. A check passes only when its expected outcome is
observed; do not mark an unimplemented or unexercised scenario as passed.

The README documents reinstalling after plugin changes with
`copilot plugin install .`, checking discovery in a new session, and optional
removal with `copilot plugin uninstall dm-assistant`. Use those documented
commands as needed; do not infer additional CLI commands from this guide.
