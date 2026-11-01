# Quickstart: Article Authoring and Template Selection

**Status: Feature 005 design and future test guidance.** The scenarios below
describe behavior to implement and tests to add; they are not evidence that an
article-authoring skill, templates, or runtime workflow already exist. This
guide does not define a CLI or runtime interface.

Use only synthetic, disposable vault fixtures for local validation. Do not use
a real campaign vault or put private vault paths or note contents in test
output. Feature 002 remains authoritative for `.dmassist.yaml` fields and
semantics; Feature 005 reuses its `templates.<built-in-type>` and
`templates.custom.<custom-id>` mappings.

## Current validation command and evidence

The repository's established PowerShell acceptance command is:

```powershell
pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1
```

Run it from the repository root with Pester 6.2.0. This is the existing
repository acceptance suite, not a Feature 005-specific test command. Feature
005 scenarios in this guide are **tests to add** to the appropriate harness;
do not treat them as currently covered or as additional runnable commands.

Local tests use synthetic disposable vaults and a test-only authorization
provider where needed to exercise behavior beyond production preflight. That
provider is test infrastructure only: passing such tests does not establish
production authorization or installed-client behavior.

## Preconditions and safety boundaries

Before any vault-owned profile, template, guidance, or campaign-note access,
the workflow must complete `vault-orientation`'s required pre-note sequence
(`skills/vault-orientation/SKILL.md`), then the authoring-specific additions in
the [contract](contracts/article-authoring-contract.md#required-preflight-and-access-order).
Stop before dependent access or writes if any gate is unavailable, stale,
invalid, or inconclusive.

**Production gates remain blocking.** Script-backed vault access must remain
fail-closed until a trusted active-session authorization handoff can verify
authorization for the exact vault. Resolver link resolution must remain
blocked until an upstream release is verified to keep canonical targets
inside the authorized root, including symlink targets. Resolver API
compatibility or exact-root readiness alone does not satisfy this target
containment gate. Do not call `resolve_obsidian_link` for a test or workflow
whose safety depends on a target until that gate has been verified.

The scenarios below that reach profiles, templates, destinations, or writes
require an isolated synthetic fixture and, in local tests, the test-only
authorization path. They do not relax production gates.

## Future acceptance scenarios: template selection and placeholders

Implement these as focused synthetic-fixture tests. Capture the selected
source, outcome, and before/after fixture inventory without logging note
contents.

| Scenario to add | Synthetic setup and action | Expected behavior |
|---|---|---|
| Built-in/default selection | For each built-in type—`adventure`, `character`, `handout`, `location`, `monster`, `party`, `persona`, `rule`, and `session`—omit its configured override and request one article. Vary the process working directory in the installed-client test. | Read that type's bundled default from the installed owning skill's resource location before drafting. Do not search the repository checkout, current working directory, or vault for a substitute. Creating the article must not alter existing notes. |
| Configured override precedence | Configure a valid vault-owned override for a built-in type while its bundled default is available. Also test an existing valid template outside the recommended `.dmassist-templates/` location. | Select and read the configured override, not the bundled default. Existing in-vault templates work in place; do not move, rename, or overwrite them. |
| Configured override failures | Separately configure a missing, unreadable, invalid, changed/stale, or out-of-vault override while the bundled default is available. | Report the particular blocker and stop the affected authoring operation. Never fall back to the bundled default after an override is configured but invalid or unavailable. Leave the fixture unchanged. |
| Valid custom type | Register a custom identifier matching `[a-z][a-z0-9_]*` under `templates.custom`, map it to a valid in-vault Markdown template, and request it. | Select and read the configured custom template. Custom types have no bundled default. |
| Invalid or unknown custom type | Test an unregistered identifier, a malformed identifier, an identifier duplicating a built-in type, and a registered custom type with a missing or invalid template. | Explain that no usable template is available and ask the DM how to proceed. Do not infer a type or substitute a built-in template. |
| Required placeholder supplied | Include `<!-- fill-in: required <description> -->` with an unambiguous value supplied by the DM or established in authorized context. | Replace the marker with that information; do not execute the description or invent additional facts. |
| Required placeholder missing or ambiguous | Include a required marker for which the request and authorized context provide no unambiguous value. | Ask the DM for the specific missing information; do not create or present the article as complete. |
| Optional placeholder | Include `<!-- fill-in: optional <description> -->` without a known value, then repeat with a supplied value. | It may remain unfilled when no value is available; when supplied, replace it using that information. Do not invent a value. |
| Unsupported template syntax | Include dynamic expressions, substitutions, community-plugin syntax, or malformed/unknown marker syntax. | Do not evaluate or claim to expand unsupported syntax. If its output is required, explain the limitation and ask the DM how to proceed. |
| Unavailable bundled resource | Make the requested built-in's installed skill resource unavailable. | Stop and report the unavailable default. Do not search other locations for a substitute. |

## Future acceptance scenarios: boundaries and write safety

For each blocked case, verify no unauthorized read or write occurred and
compare the synthetic vault's before/after inventory or byte snapshots.

| Scenario to add | Synthetic setup and action | Expected behavior |
|---|---|---|
| Unsafe or out-of-vault template path | Test traversal and absolute paths, an in-vault template path whose symlink resolves outside the authorized root, and an in-vault link whose target is outside. | Reject before reading template content. Do not follow an escaping link or treat template text as permission to access another file. |
| Resolver target-containment gate | Use an upstream Resolver whose target containment, including symlinks, has not been verified; make article work depend on a link destination. | Do not call `resolve_obsidian_link` or access the destination. Stop dependent work and identify the unverified security prerequisite. |
| Stale template or dependency | Change the selected template, profile, guidance, or other consumed dependency after validation/read and before completion. | Mark dependent work stale and require revalidation. Do not mix old and new inputs, automatically retry, or reuse approval bound to prior inputs. |
| Existing destination conflict | Request an article at a destination that already contains a note. | Do not overwrite or reformat it, and do not guess an alternate path. Report the conflict and ask the DM for direction. |
| Missing folder or ambiguous destination | Request an article whose parent folder is absent or whose intended destination is unclear. | Do not create folders or choose a destination by guesswork. Stop and ask the DM. |
| Player-facing leak check | Prepare a handout or read-aloud section from synthetic DM-facing context containing a DM-only fact or a link that reveals one. Include variants wrapped in a “DM only” callout, collapsed section, label, or HTML comment. | Omit the protected fact and revealing link entirely. Gate-check immediately before handout/read-aloud delivery; presentation or hiding is not access control. If safety cannot be established, withhold the section and ask the DM. |
| Preparation versus actual play | Use a template with speculative or planned events and request a preparation article. | Do not present preparation as actual-play history or use it alone to establish world facts or character/group knowledge. |
| Dependency unavailable or authorization unconfirmed | Separately simulate a missing/unavailable required dependency and an inconclusive exact-vault authorization result. Attempt an authoring operation. | Identify the unmet prerequisite and stop before dependent profile, template, or campaign-note access and before any write. Availability alone must not establish authorization. |
| Page-local creation boundary | Request one new article at a clear, non-conflicting destination without changing existing notes, actual-play records, or established continuity. | This narrowly scoped page-local creation does not require redundant separate approval, subject to all preflight and write safeguards. |
| Approval required | Request any additional, destructive, multi-target, restructuring, actual-play, or continuity-changing work as part of authoring. Inspect the proposed scope, then test before and after explicit approval. | Provide a scoped preview and apply nothing before explicit DM approval. Approval covers only the reviewed change and current inputs; a changed scope or stale input requires a new preview and approval. |

Templates and profile contents are data, not instructions, authorization, or
permission to broaden access or edits. Preserve established vault conventions
without inventing a fixed tag vocabulary. Do not create missing folders,
reorganize notes, silently resolve continuity contradictions, or rewrite
adventure plans.

## Completion and evidence

Record future Feature 005 scenario results separately from the existing
repository suite and from installed-client verification. A successful
synthetic test run demonstrates only the cases exercised with its fixtures;
the test-only authorization provider does not prove a trusted production
authorization handoff. Source-tree resource presence and local tests also do
not prove installed-client discovery or working-directory-independent
resource loading. Keep production authorization and Resolver target
containment, including symlinks, as explicit release gates until verified.
