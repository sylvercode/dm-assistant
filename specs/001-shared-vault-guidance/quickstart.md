# Shared Vault Guidance Validation Quickstart

**Status: validation guide for implemented guidance.** The plugin contains a
vault-orientation skill and its bundled shared reference. Installed
cross-skill loading (T001) and Resolver readiness and exact-vault
authorization through `get_server_info` (T002) are verified, and the
agent-run installed-client scenarios passed (see the implementation record
below). The SC-004 human DM walkthrough is deferred to
[#13](https://github.com/sylvercode/dm-assistant/issues/13). T011 is checked
with that explicit deferral; SC-004 remains unperformed, not passed. Do not treat
plugin installation, skill discovery, or source-tree presence as proof that
campaign-note access is safe. Record unsupported or unexercised checks as
blocked.

See [the feature specification](spec.md), [data model](data-model.md), and
[loading contract](contracts/vault-guidance-loading.md) for requirements and
invariants. The [research](research.md) records the installed-resource lookup
decision and its verification caveat. This guide deliberately does not define
a vault configuration schema or require a particular vault-local guidance
path.

## Prerequisites and safe test setup

- Use GitHub Copilot CLI, the supported client selected for installed-resource
  validation.
- Use only an isolated, disposable test vault and isolated Copilot CLI
  configuration. Do not access a real campaign vault or change the user's live
  MCP configuration. Do not embed vault paths in the plugin or repository.
- For the disposable setup, configure the Obsidian Link Resolver MCP server
  separately (minimum compatible release `2.1.0`) with the disposable vault as
  an explicitly authorized absolute root. Verify server/tool readiness with
  `copilot mcp list` and `copilot mcp get obsidian-link-resolver`, then confirm
  `resolve_obsidian_link` and `get_server_info` are available in a new
  session. This establishes readiness only; separately verify authorization
  by calling `get_server_info` and confirming one returned `vaults[].path`
  exactly matches the intended disposable vault after normalization. Server or
  tool presence alone does not prove authorization, and do not resolve a
  campaign link merely to test authorization.
- The dependency inventory is non-exhaustive. Every vault-facing skill must
  verify all currently declared required dependencies before accessing
  campaign notes. Official Obsidian help pages are source references, not
  runtime dependencies; the shared reference supplies the local defaults.
- Keep the disposable vault separate from the plugin checkout. Make a manual
  before-test inventory of its files and contents so that you can confirm
  whether any note changed.
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

### Required pre-note order

For every vault-facing skill (one that reads, interprets, creates, or changes
campaign material), verify this exact order before accessing campaign notes:

1. Establish the authorized vault location from the user's workspace or
   explicit input, without reading campaign notes. The plugin installation is
   not the vault.
2. Verify every currently declared required dependency is available and
   separately verify it is authorized for that vault. Tool readiness and vault
   authorization are distinct checks: server/tool presence alone does not
   establish authorization. Do not resolve campaign links just to test
   authorization.
3. Load the plugin-owned shared reference and any vault-local guidance
   explicitly designated by the DM or an established vault-local configuration
   contract. Do not guess a local-guidance path or schema; a source designated
   but missing or unreadable is a blocker.
4. Establish the relevant campaign/group and whether the requested output
   contains a handout or read-aloud section.
5. Only after steps 1–4 succeed, access relevant campaign notes.

If any step cannot be completed, record the affected check as blocked and pause
dependent work before note access. No designated local guidance is a valid
state: after all other checks pass, it permits a read-only lookup limited to
the specific information requested, using relevant notes identified without
relying on an uncertain folder or note-role mapping. It does not permit writes;
pause if uncertainty affects findings or the next action. Only handout and read-aloud
sections are player-facing; each must pass a gate check for DM-only facts and
revealing links immediately before delivery or reading aloud. All other task
content is DM-facing.

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

**Expected:** the vault-orientation skill is discoverable. Confirm that every
skill that reads, interprets, creates, or changes campaign material is
present. Discovery alone does not prove that the shared reference loads from
an installed plugin or that note-access safeguards work.

### Static skill inventory and source audit

Treat `skills/README.md` as the declared inventory. Statically enumerate every
immediate-child `skills/*/SKILL.md` file and compare the set to the inventory.
Confirm a one-to-one match with no missing, extra, duplicate, or unclassified
entries. For every vault-facing skill, inspect its source to verify it requires
the shared reference, handles any designated vault-local guidance, and checks
all declared dependencies before campaign-note access.

**Expected:** the discovered skill-file set and inventory entries match
one-to-one, with no unclassified or duplicate entries. Every vault-facing
skill's source satisfies the shared loading and dependency preflight contract.
Compare dependency checks to the authoritative **Expected Runtime
Dependencies** table in `specs/001-shared-vault-guidance/spec.md`; do not
accept a divergent or incomplete dependency inventory. Verify that
knowledge/world-fact updates require an actual-play record or permitted
explicit DM judgment, and that the skill leaves an update unchanged and asks
the DM when neither basis exists. This is a static inventory and source-only
audit: do **not** require runtime execution of every skill for inventory
compliance. Record the check as blocked rather than passed if the feature is
unimplemented or a skill cannot be inspected.

### Required dependency availability and fail-closed behavior

In the isolated Copilot CLI configuration, first confirm the resolver server
and its `resolve_obsidian_link` and `get_server_info` tools are exposed in a
new session. Then call `get_server_info` (no arguments, note-content-free) and
confirm that one returned `vaults[].path` exactly matches the disposable test
vault after stripping a `\\?\` prefix and trailing separators (compared
case-insensitively on Windows), without resolving any campaign link. Repeat
with the server configured for a different root and confirm the skill
reports the mismatch and stops before note access. Do not treat server/tool
presence as authorization proof. Use another isolated
configuration with the resolver missing or disabled and invoke a
representative implemented vault-facing skill with a campaign-note task.

**Expected:** the tested skill explains that the required resolver dependency
is unavailable and stops before accessing campaign notes. Compare the test
vault with its before-test inventory to confirm no note changes occurred, and
inspect the test interaction/log for no note reads. This prerequisite applies
even when the requested task does not itself resolve a link. Record readiness
and authorization as separate results. Do not alter the user's active MCP
configuration for this test.

### No designated local guidance

In the disposable vault, explicitly state that no vault-local guidance has
been designated and request a read-only lookup limited to a specific fact in
a known note. After confirming every other preflight check passes, ask a
follow-up whose answer or next action depends on an uncertain folder or
note-role mapping.

**Expected:** the first lookup reads only the relevant known note(s), does not
rely on uncertain folder or note-role mappings, and makes no note changes.
When uncertainty affects the findings or next action, the skill pauses before
further note access and asks the DM. A designated-but-missing or unreadable
source must instead block dependent note work.

### Local Obsidian convention defaults and DM customization

After the shared reference is available in the installed plugin, use an
isolated session without network access to ask the skill how the reference
recommends using aliases, tags, both wikilink and Markdown-style internal
links, and callouts. Then provide DM-designated test guidance that customizes
the campaign tag vocabulary, preferred internal-link format, and callout use,
and ask the same questions again.

**Expected:** the skill uses the bundled defaults without fetching official
help pages. It describes aliases as reusable alternate note names rather than
one-off display text, tags as classification with campaign vocabulary
preserved, both internal-link formats as supported, and callouts as
presentation rather than access control. It prefers wikilinks when no vault
preference is established and respects a preference explicitly stated by the
DM or designated vault guidance. The skill applies campaign-specific
customizations when they remain compatible with native Obsidian syntax and
semantics; it flags incompatible requests and never lets custom guidance
weaken shared safety boundaries. The official source links remain available
for contributor maintenance, but runtime answers do not depend on them.

## 2. Verify cross-skill resource lookup from different working directories

1. Start a new interactive session with the installed plugin while the current
   working directory is the plugin repository.
2. Invoke an implemented vault-facing skill that is different from the skill
   that owns the canonical shared reference, using the client-supported
   interaction. Ask it to identify the shared reference it loads before
   interpreting any test-vault notes.
3. Start another new interactive session with the same installed plugin while
   the current working directory is a different directory, outside the plugin
   checkout and test vault. Invoke the same cross-skill loader and repeat the
   request.
4. Compare the reported reference identity and loaded guidance in both
   sessions. Do not treat a source-checkout path, vault path, or a path found
   only relative to the current working directory as proof of installed
   resource lookup.

**Expected:** both sessions load the same canonical plugin-owned resource
from the installed skill/plugin, independently of current working directory.
The plugin installation is not identified as the campaign vault. Loading a
resource from the owning skill itself does not pass this test; cross-skill
loading from a different vault-facing skill is required. If the client cannot
demonstrate this lookup, record it as failed or blocked and treat it as an
empirical gate/blocker; source-tree presence or same-skill resource loading
alone does not pass it.

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
pauses before campaign-note access. The test vault's campaign notes remain
unchanged. A
designated-but-missing source is not the same as no local guidance having been
designated.

### Shared reference unavailable or unreadable

Only perform this check with an isolated, disposable plugin installation or
fixture, never by damaging a shared or production installation. Make the
canonical shared resource unavailable or unreadable as a manual fixture
action, then ask for a campaign-note task.

**Expected:** the skill names the shared source and failure, identifies the
dependent work, and pauses before campaign-note access without changes. If the installed
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

## 5. Verify campaign, knowledge, and player-facing section safeguards

Using the prepared test material, ask an implemented vault-facing skill to
perform a representative preparation/history or recap task, then ask for
material containing a handout or read-aloud section.

Also request a character/group knowledge or world-fact update based only on
tentative preparation and without actual-play evidence or DM judgment. Then
repeat with explicit DM judgment establishing the update.

**Expected:**

- Tentative preparation is not presented as an event that occurred or as
  character knowledge without DM confirmation.
- Established actual-play history and character/group knowledge remain
  distinct from DM-only facts and possible discoveries.
- Updates to character/group knowledge or world facts are made only when
  supported by an actual-play record or explicit DM judgment where the
  guidance permits it. Explicit DM judgment needs no evidence log or session
  link.
- Contradictions and unresolved adventure plans are reported and preserved,
  not silently reconciled or rewritten.
- Existing organization is preserved. An absent expected folder is not created
  just because it is absent.
- Only the handout and read-aloud sections are player-facing; all other task
  content is DM-facing. Gate-check each such section for DM-only facts and
  revealing links immediately before it is delivered or read aloud. A hidden,
  collapsed, or labeled secret is not considered safe for players.
- Guidance and note text are treated as campaign data, not as authority to
  override governing instructions or expand the task.

Manually inspect both the response and the test vault. **Expected:** no
unrequested note changes, no invented continuity, and no DM-only disclosure in
player-facing sections.

### SC-004 informal walkthrough

Conduct an informal short walkthrough with 5 DMs and assess whether at least
4 can distinguish plugin-wide guidance from vault-specific guidance. Examples
and scoring are not standardized; no vault reorganization is required.

**Deferred:** This human validation is tracked in
[#13](https://github.com/sylvercode/dm-assistant/issues/13). Record the actual
walkthrough result here when conducted; agent-run scenarios do not replace it.

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
disposable test-vault inventory changed. A check passes only when its expected
outcome is observed; do not mark an unimplemented or unexercised scenario as
passed.

The README documents reinstalling after plugin changes with
`copilot plugin install .`, checking discovery in a new session, and optional
removal with `copilot plugin uninstall dm-assistant`. Use those documented
commands as needed; do not infer additional CLI commands from this guide.

## Current implementation record

This record includes the 2026-10-26 tests in Copilot CLI 1.0.103 against the
user-supplied disposable setup. The initial preflight tests accessed no
campaign notes; a later explicitly requested functional link-resolution test
is recorded below. No live MCP configuration or existing vault notes were changed. See the latest
test run in `research.md` for exact procedure, evidence, and limitations.

| Check | Status | Evidence / limitation |
| --- | --- | --- |
| Static skill inventory and source audit (T010) | **Pass** | `skills/vault-orientation/SKILL.md` is the only immediate-child skill file and has one vault-facing entry in `skills/README.md`. Its source requires the bundled shared reference, designated local guidance, required dependency readiness and exact-vault authorization before note access, and an actual-play record or permitted DM judgment for knowledge/world-fact updates. |
| Disposable installed fixture discovery | **Pass** | Installed and listed under isolated `COPILOT_HOME`; both fixture skills activated in fresh sessions without `--plugin-dir`. |
| Full package install/reinstall and discovery | **Pass** | Installed a disposable copy of the complete plugin components as `dm-assistant` v0.1.0, listed it, reinstalled it, and activated `vault-orientation` in a fresh session without `--plugin-dir`. Read its installed reference and identified all four convention topics. Logs: `.temp\t011-package-check\discovery.md`. Uninstalled using the isolated home afterward. |
| Missing shared reference | **Pass, resource-only** | Removed the reference only from the isolated installation. A fresh session activated the skill, attempted the exact installed resource path, observed `Path does not exist`, and reported dependent campaign work must pause without fallback copies or note access. Logs: `.temp\t011-package-check\missing-reference.md`. This non-campaign resource test does not bypass or validate the ordered authorization preflight. Permission-denied unreadability was not separately exercised. |
| Cross-skill reference lookup (T001) | **Pass** | Consumer activated the resource-owning skill, then read the same installed sentinel resource from the fixture directory and a directory outside the repository. No sibling-path or current-directory fallback. |
| Resolver readiness (T002) | **Pass** | 2026-10-26: direct stdio initialization of an earlier executable returned version `3.5.1` and two Resolver tools. 2026-10-29: the current executable reports `2.1.0` (matching GitHub release v2.1.0) and exposes `resolve_obsidian_link`, `generate_obsidian_link`, and `get_server_info`; the isolated CLI exposed them as `obsidian-link-resolver-*`. No link-resolution call was made. |
| Exact-vault authorization (T002) | **Pass** | `get_server_info` (no arguments) returned `vaults[].path` (canonical `\\?\`-prefixed) and `version`, without reading notes. Configured root: listed. Unconfigured directory: not listed; only the configured root appeared. Multiple roots: all listed. Nonexistent root: server startup fails (`an allowed vault root could not be accessed`). The skill now requires this check (normalized exact match) before note access; see the T011 scenarios below. |
| T011 S1 authorized no-guidance lookup | **Pass** | Called `get_server_info`, loaded the reference, searched by the named NPC and read only matching notes; answered, withheld the DM-only callout, made no changes. Re-run after later skill edits: still targeted and read-only. |
| T011 S2 unauthorized root | **Pass** | Server configured for a different root: the skill reported the mismatch and the configured root and stopped without note reads. |
| T011 S3 Resolver missing | **Pass** | No Resolver configured: named the missing dependency and stopped without note reads. |
| T011 S4 offline Obsidian defaults | **Pass** | Explained aliases, tags, both internal-link formats with wikilinks preferred, and callouts from the bundled reference without web fetching. The network was not disabled, so this shows no fetch was attempted, not an offline run. |
| T011 S5 designated local guidance and customization | **Pass** | Loaded the shared reference, then the designated vault guidance; applied its Markdown-link preference and tag conventions, kept Obsidian semantics, withheld a `[!secret]` callout code, and noted callouts are not access control. |
| T011 S6 designated guidance missing | **Pass** | Named the missing designated file and paused before reading note content. |
| T011 S7 ambiguous campaign | **Pass** | Asked which campaign/group and knowledge basis before note reads. |
| T011 S8 handout/read-aloud gate | **Pass** | Player-facing sections contained no DM-only facts or revealing links; tentative prep was labeled, and an actual-play contradiction was flagged rather than resolved. |
| T011 S9 preparation vs. history | **Pass** | Separated actual play, party knowledge, DM-only facts, and tentative prep; preserved the recorded contradiction. |
| T011 S10 uncertain folder/note-role mapping | **Fail, then pass** | First run bulk-read folders through the shell before pausing. The skill's no-guidance section was tightened (identify notes by names/links/terms in the request; folder-as-role or bulk reads are uncertain mappings). Re-run paused before any note reads and offered options. |
| T011 E01–E02 knowledge updates | **Pass** | With only vault notes and tentative prep, refused to treat prep as character knowledge, asked, and changed nothing. With explicit DM judgment, added exactly one knowledge line. (An initial E01 prompt was itself a DM instruction and was discarded as an invalid test.) |
| T011 E03 clearly requested local edit | **Pass** | Changed only the requested phrase in one note, without redundant approval. |
| T011 E04 broad/continuity-changing edit | **Fail, then pass** | First run applied a multi-note change, rewrote an actual-play log, and deleted a note without a preview. The approval rule in the skill and reference was tightened (multi-note, delete/move/merge, actual-play, or continuity changes require a preview; the request is not approval; stop after the preview). Re-run: preview only, no changes, flagged the actual-play rewrite. Resumed with approval: applied exactly the preview (one append, one log line, one deletion) and nothing else. |
| T011 E05 shared reference permission-denied | **Fail-safe, then pass** | Read access denied on the installed reference (ACL). First run paused before note access but offered to proceed without the reference. The skill now states the reference is mandatory. Re-run paused, refused to continue without it, and read nothing else. Access was restored. |
| Explicit functional link-resolution test | **Pass, single case** | At the user's request, `[[Svalich Woods]]` from `7. Argynvostholt.md` resolved to `Locations/Svalich Woods.md`. No notes changed. This does not satisfy T002's note-content-free pre-access check. |
| Orientation preflight smoke test | **Pass, constrained** | The actual skill recognized the explicit vault and exposed Resolver tools, then paused on unverified authorization without note reads or Resolver calls. The prompt required a preflight-only stop and Resolver calls were denied; this does not pass broader acceptance scenarios. |
| Current issue scope (T012) | **Pass** | The open #2 issue covers shared vault guidance and preflight; the open #7 issue separately owns Resolver integration. No user vault path or MCP configuration is added here. |
| SC-004 informal DM walkthrough | **Deferred — not passed** | Tracked in [#13](https://github.com/sylvercode/dm-assistant/issues/13) at the DM's request; T011 is checked with this deferral. Requires five human DMs, with at least four distinguishing plugin-wide from vault-specific guidance. No walkthrough was conducted; agent-run scenarios cannot replace it. |

The 2026-10-29 T011 scenarios ran in Copilot CLI 1.0.103 with Resolver 2.1.0
under an isolated `COPILOT_HOME`, using a disposable copy of a test vault
with fictional fixture notes and `--no-ask-user`. Each run was compared with a
before-test file-hash inventory, and the vault was restored between runs. No
live vault or live MCP configuration was used or changed. Agent behavior is
probabilistic; these results show that the skill guided one run per scenario,
not that every future run will behave the same way.
