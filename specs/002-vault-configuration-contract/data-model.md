# Data Model: Vault Configuration Contract

**Status:** Proposed contract for a future plugin workflow. The repository is an Agent Plugins 1.0 scaffold; none of the entities, parsing, validation, or state transitions below are implemented.

## Scope and Ownership

The authorized campaign vault is obtained from the user's workspace or explicit input. It is not the plugin installation. The optional `.dmassist.yaml` profile is stored at the root of that vault; campaign notes, guidance, and DM-owned templates remain vault content. The profile stores organization and references only: it does not contain lore, session history, character knowledge, permissions, or executable instructions.

All paths in the profile are vault-relative. A path is usable only if its fully resolved target, including symbolic links, remains inside the authorized vault. Plugin-bundled default templates are separate plugin resources and are not profile paths.

## Entities and Fields

The YAML shape below is illustrative of the proposed contract and shows the field names used in this model:

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
party:
  note: "Lore/Player/Party.md"
preparation:
  mode: "session_section"
  heading: "Preparation"
guidance:
  path: ".dmassist-guidance.md"
templates:
  persona: ".dmassist-templates/persona.md"
  custom:
    downtime_activity: ".dmassist-templates/downtime-activity.md"
```

| Entity / field | Type and cardinality | Required / default | Meaning and validation |
| --- | --- | --- | --- |
| **Vault profile** | YAML mapping, zero or one per authorized vault | Optional; absent profile invokes read-only discovery | `.dmassist.yaml` at the vault root. Unknown top-level fields are errors. |
| `version` | Integer scalar | Required; no inferred value | Initially, only integer `1` is supported. Missing, invalid, or unsupported values reject the profile. |
| `sections` | Mapping containing optional built-in locations and custom section entries | Optional | Overrides locations for the six recognized sections below and may define custom categories. Omitted built-in entries retain their conventional path as a discovery candidate; defaults do not require directories to exist. |
| `sections.adventures` | Relative directory path string | `Adventures` candidate | Playable arcs, encounters, events, and DM instructions; root-level adventure candidates may also be discovered. |
| `sections.lore` | Relative directory path string | `Lore` candidate | Shared world background and any campaign-specific lore subsections. |
| `sections.monsters_stats` | Relative directory path string | `Monsters Stats` candidate | Reusable monster statistics, distinct from persona identity and history. |
| `sections.rules` | Relative directory path string | `Rules` candidate | Recurring rules, reminders, and DM-approved rulings. |
| `sections.sessions` | Relative directory path string | `Sessions` candidate | Session records, principally recaps and logs of actual play. |
| `sections.handouts` | Relative directory path string | `Handouts` candidate | Player-intended documents; the mapping does not authorize publishing them. |
| `sections.custom` | Mapping from custom section identifier to section definition | Optional; no custom sections by default | Permits vault-specific section categories. Keys must match `[a-z][a-z0-9_]*` and cannot duplicate built-in section names. |
| `sections.custom.<id>.path` | Relative directory path string | Required for each custom section | The existing vault directory for that category; subject to the same existence and boundary validation as explicitly configured built-in sections. |
| `sections.custom.<id>.description` | Non-empty string | Required for each custom section | Describes the intended content/use of that category to help workflows identify relevant notes. Treated as descriptive data, not instructions or authorization. |
| **Party context** | Mapping, zero or one per profile | Optional | Represents the one active party context supported per vault. Shared-campaign selection is out of scope. |
| `party.note` | Relative Markdown file path string | Required if `party` is present; otherwise absent | Reference to the active party's note; the note remains the source of party knowledge. It is not copied into the profile. Validate its boundary before access; if unavailable when needed, report the problem rather than selecting another note. |
| **Preparation location** | Mapping, zero or one per profile | Optional | Keeps tentative preparation distinct from recorded outcomes. |
| `preparation.mode` | String enum: `session_section` or `separate_folder` | `session_section` | `session_section` means a section titled by `preparation.heading` in a session note. `separate_folder` requires `preparation.path`. |
| `preparation.heading` | Non-empty string | `Preparation` in `session_section` mode; forbidden in `separate_folder` mode | Heading text for tentative preparation within a session note, separate from recorded outcomes. |
| `preparation.path` | Relative directory path string | Required only for `separate_folder`; otherwise forbidden | Dedicated preparation directory. It must already exist and remain inside the vault. It does not become a session outcome merely by containing prepared material. |
| **Guidance path** | Mapping with one relative Markdown file path string | Optional; when omitted, the optional root-level `.dmassist-guidance.md` is the default candidate | If present, `guidance.path` is required. An absent default candidate is not an error. An explicit path replaces that candidate; it must remain inside the vault. An unavailable or unreadable designated file is reported when needed, not silently ignored. |
| **Built-in template overrides** | Mapping from built-in article-type identifier to relative Markdown file path string | Optional | Selects DM-owned templates in the vault for supported built-in types. Paths are validated against the vault boundary. An explicitly selected missing, unreadable, or invalid template is an error for the dependent authoring operation, not a reason to substitute a plugin default. With no override, the relevant plugin default may be used. |
| `templates.custom` | Mapping from custom article-type identifier to relative Markdown file path string | Optional; no custom template types by default | Enables the DM to register templates for other article needs. Identifiers must match `[a-z][a-z0-9_]*` and cannot duplicate a built-in type. |
| `templates.custom.<id>` | Relative Markdown file path string | Required for each custom template type | The vault-owned template used when that custom article type is explicitly requested. It must remain inside the vault; missing, unreadable, or invalid templates stop the dependent operation. There is no plugin default for custom types. |
| **Discovery candidate** | Existing directory or note/folder identified by read-only inspection | Generated only during unconfigured discovery; not persisted | A candidate is evidence of a likely location, not a confirmed mapping. Root-level items are not automatically adventures. |
| **Validation dependency** | Profile, configured path target, guidance file, or selected template used by an operation | Captured for a validated operation | The dependency's content/identity and resolved path boundary are inputs to validation. A detected change invalidates dependent work and requires revalidation. |

`sections` may map different section keys to the same directory or to nested directories. The profile records those mappings without asserting that every item under a mapped location belongs to that section. Folder placement alone cannot settle note classification.

## Relationships

- A vault has at most one profile at its root and one active party context in that profile.
- A profile has zero or more built-in section mappings and zero or more custom section definitions. Each section identifier has at most one configured path. Omitted built-in mappings refer to conventional discovery candidates, not required folders.
- The party context references one party note but does not own or duplicate its contents.
- Preparation is associated either with a session-note section or with one separate location, never with actual-play outcomes by implication.
- The guidance path and template overrides reference vault-owned files. Each is independently subject to boundary validation and change detection when used.
- Custom template identifiers extend user-selectable article types without changing the built-in template catalog; each maps to exactly one vault-owned Markdown template.
- A read-only discovery result may contain several candidates per section and one selected candidate with alternatives. An inferred selection is not a configured mapping and does not authorize edits.
- An operation depends on the validated profile and on each referenced file or path it consumes. A change to any dependency makes that operation's validation stale.

## Schema Validation Rules

The schema defines the expected resolved configuration, not the parser or
runtime implementation. Reader selection, YAML feature support, scalar
conversion mechanics, and dependency provisioning are specified by Issue #4,
“Establish the PowerShell runtime and safe operation contracts.”

1. **YAML input:** YAML syntax accepted by the selected reader may be used if the resulting configuration satisfies this schema. Parser errors stop loading.
2. **Exact schema and duplicates:** Reject duplicate mapping keys, unknown top-level fields, unknown built-in `sections` names, invalid custom section or template identifiers, missing or extra custom section fields, unsupported fields, invalid mapping/value shapes, and unexpected fields for a selected preparation mode. If supported YAML features resolve conflicting values, reject an invalid or conflicting result according to the schema.
3. **Field types:** `version` must resolve to integer `1`. Other fields must resolve to their documented types and non-empty values; explicit nulls and collections where a scalar is required are invalid. The reader must apply a consistent interpretation of scalar values.
4. **Section paths:** Every explicitly configured built-in or custom section path must resolve to an existing directory. If any such directory is missing or invalid, reject the entire profile; do not create it, fall back to discovery, or use only the remaining valid mappings. This requirement does not apply to omitted conventional defaults.
5. **Path safety:** Reject absolute, drive-qualified, UNC, or vault-escaping paths, including paths that escape after symbolic-link resolution. Resolve and check the final target against the authorized vault before access or modification. Treat paths as data; never interpolate them as commands or expressions.
6. **Other referenced files:** Enforce the same vault boundary for party-note, guidance, and template paths. Their availability/readability or template validity is reported when a dependent workflow needs them; no unvalidated substitution or silent omission is allowed.
7. **Overlap:** Shared and nested section paths are valid. When an operation cannot determine a classification or destination from overlapping mappings, ask the DM before proceeding; do not infer authorization from the overlap.
8. **Determinism:** Given the same profile and unchanged authorized-vault state, resolution must produce the same effective settings and path boundaries.
9. **Data-only semantics:** Profile text, campaign notes, guidance, and templates are input data, not commands or safety policies. None can authorize destructive, restructuring, continuity-changing, or player-facing disclosures, or weaken required approval safeguards.
10. **Validation unavailable:** If a workflow cannot validate a profile, report that validation is unavailable and stop work that depends on it. Runtime and dependency handling are defined by Issue #4.

## Resolution and State Transitions

### Profile lifecycle

`Absent` → **read-only discovery**. The workflow may report existing and inferred locations without creating or changing configuration, folders, or notes. If multiple locations plausibly match one section, select the likeliest candidate, report it as inferred with the reason and alternatives, and continue read-only work. That choice cannot override explicit mappings or authorize edits.

`Present` → `Unvalidated` → `Validating` → one of:

- `Validated`: schema, required configured section directories, and path boundaries pass. Work may use only these validated settings, subject to operation-specific checks and existing approval safeguards.
- `Invalid`: any profile/schema failure, missing explicitly configured section directory, or failed boundary check rejects the whole profile. Report the cause; do not use partial settings, guessed replacements, or discovery fallback in place of the rejected profile.
- `Unavailable`: validation cannot be performed. Report that validation is unavailable; dependent work stops. Runtime and dependency behavior are owned by Issue #4.

Changes to the profile, a referenced guidance file, template, or path after validation transition the affected operation from `Validated` to `Stale`. On detecting staleness: stop that affected operation, report what changed, and require revalidation before retrying. Do not auto-retry or combine old and new inputs; check the vault boundary again before further access. Unaffected work may continue only if it does not depend on the changed input.

### Operation-level outcomes

- **Read-only discovery:** report identified locations and uncertainty; never create a profile or folders. For ambiguous unconfigured discovery, choose and report the most likely candidate for read-only use.
- **Configured lookup:** explicit mappings take precedence over inferred candidates. A missing explicitly configured section folder is a profile-wide validation failure, not an operation-local omission.
- **Classification or destination:** if overlap leaves the note's role or write target unresolved, pause and ask the DM. Discovery confidence does not resolve this case.
- **Template-backed authoring:** use an explicit, valid override when configured; otherwise a plugin default may be used. If the configured override is unavailable or invalid, stop that article's creation rather than silently falling back.
- **Preparation and actual play:** preparation remains tentative, whether stored in a `Preparation` session-note section or separate location. Only confirmed events belong in session outcomes; unused preparation does not establish campaign history or character knowledge. Do not rewrite run adventure plans or resolve contradictions.
- **Player-facing handouts:** the Handouts mapping does not make content safe by location alone. Keep DM-only facts and revealing links out of handouts; a profile or template cannot authorize disclosure.
