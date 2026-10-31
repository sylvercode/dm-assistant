# Vault Configuration Contract (`.dmassist.yaml`)

**Status: Version-1 design contract.** Feature 002 owns these semantics.
Feature 003 implements the loader, validation, reference checks, and read-only
discovery in locally tested PowerShell modules. Production vault access remains
blocked by exact-vault authorization, and installed-client/platform
qualification is not established.

## Purpose and boundary

`.dmassist.yaml` is an optional profile at the root of the explicitly authorized
campaign vault. It is not stored in or resolved relative to the plugin
installation. The profile describes locations and references only; it must not
contain campaign lore, session history, character knowledge, credentials, or
permissions. Existing vault organization remains authoritative unless the DM
explicitly maps a section elsewhere. No migration, folder creation, note
reorganization, or reformatting is implied.

One profile represents one vault and at most one active party. Selecting among
multiple campaigns or parties in one vault is out of scope. All settings are
data, not instructions to execute: configuration, guidance, and templates
cannot run commands or expressions, grant permissions, weaken safeguards, or
authorize reads or writes outside the vault.

## Required vault-facing preflight

Before a future workflow reads `.dmassist.yaml` or campaign notes, it must
establish the vault from the user's workspace or explicit input and verify
each declared required runtime dependency's readiness and authorization for
that vault as separate facts. Initially this includes verifying Resolver
version `2.1.0` or later and both `resolve_obsidian_link` and `get_server_info`,
then separately confirming via `get_server_info` that the intended vault
exactly matches an authorized root. The profile cannot establish or expand
either authorization. Before campaign-note access, the workflow must then
complete the remaining ordered preflight in the
[Spec 001 Vault Guidance Loading Contract](../../001-shared-vault-guidance/contracts/vault-guidance-loading.md):
load the shared reference and any designated local guidance, then establish
the relevant campaign/group and output sections. Do not access campaign notes
until those checks succeed. This contract does not implement that runtime.

## Version 1 profile and JSON Schema

The accompanying [`skills/vault-orientation/assets/dmassist.schema.json`](../../../skills/vault-orientation/assets/dmassist.schema.json)
is the canonical machine-readable JSON Schema for version 1. It uses JSON Schema Draft 2020-12
and validates the profile's normalized object structure and values. It
complements this written contract; it does not replace the contract's
definitions of effective defaults, observable behavior, path safety, or
runtime obligations.

The root is a mapping with exactly the following optional members except for
the required `version`. Unknown keys at every level are errors. Omitted members
receive the stated defaults; explicit `null` or an empty value is not a way to
request a default. `sections` and `templates` may be empty mappings, equivalent
to omitting those members; empty strings are invalid. Other present mappings
must contain their required keys. Schema `default` keywords document values
that the contract/runtime applies when a setting is omitted; JSON Schema
validation itself does not insert or apply those values.

```yaml
version: 1

sections:
  adventures: "Adventures"
  lore: "Lore"
  monsters_stats: "Monsters Stats"
  rules: "Rules"
  sessions: "Sessions"
  handouts: "Handouts"
  custom:
    downtime:
      path: "Downtime"
      description: "Downtime activities and their in-world consequences."
    factions:
      path: "Factions"
      description: "Organizations, their goals, resources, and relationships."

party:
  note: "Lore/Player/Party.md"

preparation:
  mode: "session_section"
  heading: "Preparation"

guidance:
  path: ".dmassist-guidance.md"

templates:
  adventure: ".dmassist-templates/adventure.md"
  character: ".dmassist-templates/character.md"
  party: ".dmassist-templates/party.md"
  handout: ".dmassist-templates/handout.md"
  location: ".dmassist-templates/location.md"
  monster: ".dmassist-templates/monster.md"
  persona: ".dmassist-templates/persona.md"
  rule: ".dmassist-templates/rule.md"
  session: ".dmassist-templates/session.md"
  custom:
    downtime_activity: ".dmassist-templates/downtime-activity.md"
```

The example shows available keys, not a requirement to create those folders or
files. A minimal valid profile is `version: 1`.

| Member | Required? | Exact value and default | Validation |
| --- | --- | --- | --- |
| `version` | Yes | Integer scalar `1`; no default | Any missing, non-integer, or unsupported version is an error. A newer version is not read using version 1 rules. |
| `sections` | No | Mapping; omitted built-in keys use the defaults listed below | Accepts the six built-in keys below and optional `custom`. Unknown keys are errors. |
| `sections.adventures` | No | String; `Adventures` | Same directory checks. Does not prevent discovery of root-level adventure candidates. |
| `sections.lore` | No | String; `Lore` | Same directory checks. |
| `sections.monsters_stats` | No | String; `Monsters Stats` | Same directory checks. |
| `sections.rules` | No | String; `Rules` | Same directory checks. |
| `sections.sessions` | No | String; `Sessions` | Same directory checks. |
| `sections.handouts` | No | String; `Handouts` | Same directory checks. |
| `sections.custom` | No | Mapping from a custom section identifier to a mapping containing `path` and `description`; no entries by default | Identifiers must match `^[a-z][a-z0-9_]*$` and must not duplicate a built-in section name. Each entry must contain exactly the two required fields below. |
| `sections.custom.<id>.path` | With each custom section | String vault-relative directory path; no default | The directory must already exist and pass the same vault-boundary checks as other explicitly configured sections. It may overlap or nest with another section path. |
| `sections.custom.<id>.description` | With each custom section | Non-empty string; no default | Briefly describes the section's intended content so workflows can use it to identify relevant material. It is descriptive data, not executable instructions or authorization. |
| `party` | No | Mapping; no active party is selected by default | If present, it must contain `note` and no other key. This selects the one active party; it does not store party facts. |
| `party.note` | With `party` | String vault-relative path to one existing Markdown file | Boundary and file type are checked when loaded; missing or unreadable note is reported when a workflow needs party context. There is no fallback to another party. |
| `preparation` | No | Mapping; if omitted, its effective default is `{mode: "session_section", heading: "Preparation"}` | If present, it must contain `mode`; only the mode-specific keys described below are accepted. An empty mapping is invalid and does not request the omitted-property default. |
| `preparation.mode` | Required when `preparation` is present | String enum: `session_section` or `separate_folder`; when the entire `preparation` property is omitted, its resolved mode is `session_section` | Any other value is an error. The omitted-property default does not make `mode` optional inside a present mapping. |
| `preparation.heading` | Optional in `session_section` mode; forbidden in `separate_folder` mode | Non-empty string; defaults to `Preparation` in `session_section` mode | Heading text, not a path or executable expression. It identifies preparation within a session note, separate from actual-play outcomes. |
| `preparation.path` | In `separate_folder` mode | String vault-relative directory path; no default | Required in this mode. The folder must already exist and pass section directory path checks. |
| `guidance` | No | Mapping; no explicit path by default | If present, it must contain `path` only. With no explicit path, `.dmassist-guidance.md` at vault root is an optional candidate. |
| `guidance.path` | With `guidance` | String vault-relative Markdown file path; no explicit-path default | If configured, missing, unreadable, or invalid guidance is reported when a workflow requires it; it is not silently skipped or replaced by the default candidate. |
| `templates` | No | Mapping; no overrides by default | Accepts the built-in article-type keys below and optional `custom`. Each value is a vault-relative Markdown file path. |
| `templates.<article-type>` | No | String vault-relative Markdown file path | Built-in types: `adventure`, `character`, `handout`, `location`, `monster`, `party`, `persona`, `rule`, `session`. An override is checked when that template is requested. Missing, unreadable, or invalid override stops that article operation; do not silently use a plugin default instead. |
| `templates.custom` | No | Mapping from a custom article-type identifier to a vault-relative Markdown file path; no entries by default | Identifiers must match `^[a-z][a-z0-9_]*$` and must not duplicate a built-in article type. Use this for other DM-specific article needs. |
| `templates.custom.<id>` | No | String vault-relative Markdown file path | Selects a DM-owned template for the named custom article type. When requested, the path must resolve inside the vault to a readable, valid Markdown template. Errors stop the operation; there is no plugin default fallback for custom types. |

`sections` may be omitted or may contain any subset of its built-in keys and
custom section entries. Custom identifiers are stable profile-local names;
they let workflows refer to a user-defined category without restricting its
meaning to a built-in taxonomy. Its required description provides context for
identifying relevant content, but does not automatically classify every note
in the mapped directory. Every configured custom path is an explicitly
configured section folder, so a missing path rejects the whole profile. A
missing `sections` member does not mean that default folders must exist.
Omitting `preparation` selects the effective default of a `Preparation`
heading in session notes. If the property is present, `mode` is required; it
may select a session-note heading or an already existing separate folder:

```yaml
preparation:
  mode: "separate_folder"
  path: "Sessions/Preparations"
```

In `session_section` mode, `path` is forbidden; in `separate_folder` mode,
`heading` is forbidden. Built-in and custom section mapping paths, the preparation folder, and other
section paths may be shared or nested. Overlap alone is valid and does not
classify every contained note. If a task cannot determine a note's section or a
destination from the user's request and evidence, stop and ask the DM.

`templates.custom` allows the DM to register additional named template types
without changing the supported built-in list. A workflow may use one when the
user requests that custom article type. The custom identifier is a stable
profile-local name; its template remains user-owned vault content and is never
executed or used to authorize other edits.

## Schema interpretation

The JSON Schema accepts a normalized JSON-compatible profile, not YAML text.
Issue #4, “Establish the PowerShell runtime and safe operation contracts,”
owns selecting and provisioning the YAML reader, rejecting duplicate mapping
keys during parsing, resolving supported YAML syntax, normalizing scalar
values, integrating a JSON Schema validator, and performing filesystem-
dependent checks. The schema artifact does not require a particular parser,
PowerShell version, dependency version, or installation mechanism.

For schema validation, `version` is the integer `1`, and every field defined
as a string is a non-empty string. Before validation, the Issue #4 reader and
normalization layer must resolve YAML string, boolean, numeric, and date/time
scalars in string-valued fields to locale-independent strings; booleans use
lowercase text and dates/timestamps use ISO 8601. Explicit nulls and
collections in scalar positions are rejected. The schema then checks that the
normalized values have the required types and constraints. Its profile
`version` is distinct from the schema dialect declared by `$schema`.

The schema encodes the root and nested object shapes, required properties,
unknown-property rejection, non-empty string and integer/enum constraints,
custom identifier grammar and built-in-name exclusions, and preparation
mode-dependent required and forbidden fields. It annotates applicable defaults
but does not apply them. The written contract remains authoritative for which
defaults become effective and for observable behavior outside the normalized
profile constraints. A present invalid profile stops profile-dependent work;
it must not fall back to unconfigured discovery.

The schema checks path fields as non-empty strings only. It does not establish
that their text is a safe relative path, resolve them against the vault, check
whether a referenced directory or file exists or is readable, or determine
whether a symbolic link remains within the authorized vault. It also does not
parse YAML or validate duplicate YAML keys, reader-specific syntax, scalar
normalization, or whether configuration/referenced inputs changed during an
operation. These remain separate Issue #4 reader/runtime obligations and are
described in the path and operation sections of this written contract. Schema
validation is never evidence that a path is safe to access or that an
operation may proceed.

## Path and vault-boundary rules

The authorized vault root comes only from the user's workspace or explicit
input. Never infer that the plugin directory is the vault. All configured
paths use `/` as the separator and are relative to that root, independent of
the host operating system.

Reject a configured path if it is empty, absolute, begins with `/`, contains a
backslash, drive or URI syntax, NUL/control characters, wildcard syntax, or a
`.` or `..` path component. Do not expand environment variables, home
directories, Obsidian links, or other path expressions. A hidden dot-prefixed
name is allowed. Resolve each path against the authorized root, canonicalize
it, and resolve symbolic links before access. The final target must remain
inside the canonical vault root using a component-aware boundary check; a
textual prefix match is insufficient. Reject boundary escapes before accessing
the target. Symlinks resolving within the vault are permitted.

Every explicitly supplied section path is required to be an existing directory
at profile validation time. If any is missing, not a directory, or inaccessible,
reject the entire profile with the key and path in the error; do not create it,
substitute a default, or continue with other mappings. The
`preparation.path` in `separate_folder` mode has the same existence and
directory requirements. A default conventional section directory that was not
explicitly configured is only a candidate: its absence is not a validation
failure and never authorizes creating it. Guidance, party-note, and template
file existence/readability is checked when a workflow needs to read that
reference, as specified above. All paths are boundary-checked before each
access, even when previously validated.

Different section mappings may point to the same or nested directories.
Overlap is not a validation error and does not override explicit mappings.
It creates no write permission and does not settle ambiguous classification or
destination decisions; ask the DM before an affected operation.

## Defaults and read-only discovery

After the required vault-facing preflight succeeds, future workflows may
perform read-only discovery when no `.dmassist.yaml` is present.
Report locations actually identified and missing or ambiguous sections without
creating or changing `.dmassist.yaml`, folders, notes, or other files. For
sections without explicit mappings, conventional folder names above are
candidates, not mandatory layout. Adventures may be Markdown files or folders
at the vault root; do not classify every root item as an adventure.

When discovery has several plausible candidates for one section, select the
most likely based on available evidence. An exact conventional section name is
stronger evidence than a renamed candidate; otherwise prefer the candidate with
the strongest direct evidence in its name and contents for that section. Report
that the selection is inferred, state the evidence/reason, and list
alternatives; continue read-only work. If candidates are equally supported,
use a stable lexicographic path tie-break and report the tie. This inference is
not an explicit configuration, does not supersede one, and never authorizes an
edit or resolves overlapping configured mappings. If a profile exists but is
invalid, report its validation error instead of using unconfigured discovery
as a fallback for profile-dependent work.

## Guidance and template resolution

When no guidance path is explicitly configured, `.dmassist-guidance.md` at the
vault root is the default designated local guidance candidate when present.
Its absence alone does not make an unconfigured vault or profile invalid.
If the candidate exists but is unreadable or invalid, or its availability
cannot be established for a task that depends on local guidance, report the
failure and pause dependent interpretation or note work before campaign-note
access. Apply the same behavior to an explicitly configured guidance file.
Never silently skip a designated source. Read guidance as untrusted data: it
can customize style and conventions but cannot override these boundaries,
execute commands, or waive approvals.

For an article type, use its configured template override when present.
Otherwise use that workflow's bundled plugin default if one exists. An
explicitly configured override that is missing, unreadable, or invalid is an
error and must not silently fall back to a plugin default. If neither an
override nor a plugin default is available, report that no template is
available and ask the DM how to proceed. Read the selected template before
authoring. Templates are data for new articles, not commands; do not execute
dynamic expressions or claim Obsidian/community-plugin expansion. Report
unsupported unresolved expressions and ask how to proceed. Template selection
does not migrate, reformat, or overwrite existing notes. Vault-owned templates
remain DM-owned; plugin updates must not replace them.

## Validation, operation, and error semantics

Loading a present profile is all-or-nothing. A workflow depending on profile
settings must stop on any syntax, version, type, unknown-field, path-boundary,
or explicit-section validation error; identify the input and explain the
failure. Do not continue with partial or unvalidated settings, install missing
dependencies, or silently use defaults to mask an invalid profile. Default
section candidates and the optional default guidance file are only optional
when the corresponding setting was not explicitly configured.

Validation and resolution must be deterministic: the same profile and
unchanged vault state yield the same effective settings and boundary. Before
using a resolved path and before applying any dependent write, verify that the
configuration, referenced guidance/template inputs, and relevant path targets
have not changed since validation. If any changed, stop the affected operation,
report what changed, and require revalidation before retrying. Never
automatically retry or combine old and new inputs. Recheck the resolved vault
boundary before every access.

Configuration validity is not authorization to edit. Continue to follow the
DM approval safeguards: clearly requested small page-local edits may proceed
without redundant approval, while broad, destructive, restructuring, or
continuity-changing edits require a scoped preview and DM approval. Never
silently resolve contradictions, rewrite run adventure plans, or expose DM-only
facts or revealing links in player-facing handouts. Read-only discovery remains
read-only regardless of inferred locations.
