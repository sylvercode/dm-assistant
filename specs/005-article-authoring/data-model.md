# Data Model: Article Authoring and Template Selection

**Status:** Feature 005 design artifact. Feature 002 remains authoritative for `.dmassist.yaml` profile keys and semantics. As revised on 2026-11-17, the calling skill owns live MCP checks and supplies explicit vault-scoped `callerPreflight`; PowerShell enforces filesystem/write safeguards, not independently authenticated MCP authorization. Installed-client and cross-platform qualification remain unverified. Resolver symlink qualification is deferred to the owner, not a gate.

## Scope and ownership

Article authoring operates on one DM request for one new article in the explicitly authorized campaign vault. The vault is not the plugin installation. Built-in templates belong to the installed `article-authoring` skill; configured templates and created articles belong to the DM's vault. An authoring request, its selected template, generated article content, validation findings, and approval decision are operation-level concepts, not additional `.dmassist.yaml` profile fields or a new persistent database.

The version-1 profile model, including its `templates` mapping, is defined only by the [Feature 002 data model](../002-vault-configuration-contract/data-model.md) and [vault configuration contract](../002-vault-configuration-contract/contracts/vault-configuration-contract.md). Feature 005 consumes that contract without adding profile keys, changing defaults, or inferring authorization from configuration.

## Entities and fields

| Entity / field | Type and cardinality | Required / identity | Meaning and constraints |
| --- | --- | --- | --- |
| **Authorized vault** | One established vault per operation | Required before vault-owned profile, template, guidance, or campaign-note access | Canonical root established from the user's workspace or explicit input and separately authorized by required dependencies. It is not inferred from the plugin location, profile, template, or successful link resolution. |
| **Authoring request** | One operation-scoped request | Required; no persistent identifier specified | DM's request to create one new article. Its type is a built-in type or explicitly registered custom type. Purpose, content, and audience are supplied by the DM or resolved from authorized context as needed; the destination must be explicitly supplied by the DM because Feature 002 has no article-destination field. Stop and ask when the type, destination, or required context is unresolved. |
| `article_type` | Identifier string | Required; identity of the requested type within this operation | Built-in values are exactly `adventure`, `character`, `handout`, `location`, `monster`, `party`, `persona`, `rule`, and `session`. A custom identifier must be explicitly present in `templates.custom`, match `[a-z][a-z0-9_]*`, and not duplicate a built-in identifier. An unregistered type has no selectable template. |
| `audience` | Operation context; at least DM-facing or player-facing when relevant | Required when composing player-facing material; not a profile key | Handouts and read-aloud sections are player-facing. Other article content is DM-facing by default. A callout, hidden section, tag, or collapsed state is presentation, not access control. |
| `destination` | Exactly one proposed in-vault Markdown note path, relative or absolute | Required before writing | It is clear only when explicitly supplied by the DM. The entry point converts an absolute path within the selected root to a vault-relative identity before shared containment checks. Feature 002 has no article-destination field; section-folder and template mappings do not by themselves identify a note path. It must resolve within the authorized vault, its parent must already exist, and its target must not already contain an article. Multiple plausible paths, an unknown path, a conflict, missing parent, or unsafe path blocks creation; do not overwrite, choose an alternate by guesswork, or create folders by assumption. |
| **Template mapping** | Existing profile mapping, optional | Identity is the article-type key from Feature 002 | Reuse only `templates.<built-in-type>` for built-in overrides and `templates.custom.<custom-id>` for custom types. Values are vault-relative Markdown paths. These are the authoritative field names; do not introduce a parallel template registry or profile key. |
| **Selected template** | Exactly one template per resolved authoring operation | Required before composing an article | Chosen by the precedence and validation rules below. A template is either a plugin-owned bundled default or a DM-owned vault Markdown file. Its text is data, never authorization or executable instructions. |
| `template_owner` | Enum: `plugin` or `vault` | Required for a selected template | `plugin` applies to a bundled default resolved from the installed owning skill's resource location. `vault` applies to a profile-configured DM-owned template. A plugin path must not be derived from the current working directory, repository checkout, or campaign vault. |
| `template_path` | Resource identity/path | Required for the selected template; storage-specific form depends on owner | Vault-owned paths are profile values and must resolve, including symlinks, inside the authorized vault. Bundled defaults are plugin resources, not profile paths. Establish and authorize the vault and load the shared reference before reading the profile to identify designated guidance; load that guidance and establish context before reading selected templates or campaign notes. |
| `template_content` | Markdown content plus operation-bound identity/version | Required to validate and use the selected template | Must be explicitly read and checked before article creation. Any detected content, identity, or boundary change makes dependent work stale and requires revalidation; do not mix old and new inputs or automatically retry. |
| **Static fill-in marker** | Zero or more marker occurrences in selected Markdown | Identity is its exact marker occurrence in the template | Supported syntax is exactly an HTML comment using `<!-- fill-in: required <description> -->` or `<!-- fill-in: optional <description> -->`. The description identifies the requested information; it is not executable text. Complete a marker only from DM-supplied information or established, authorized campaign context. Ask the DM if required information is absent or ambiguous; optional markers may remain unfilled. |
| **Dynamic template expression** | Zero or more unexpanded template constructs | No supported expansion identity | Dynamic expressions, substitutions, and community-plugin syntax are not static fill-in markers. They remain unexecuted and must not be represented as expanded. If their output is needed, report the limitation and ask the DM how to proceed. |
| **Article content** | One proposed Markdown document, operation-scoped until safely written | Required for creation; no independent persistent identity before write | Derived from the selected template and DM-supplied/authorized context. Must preserve established tags and callout conventions, preparation/actual-play distinction, and audience boundaries. Required fill-ins must not be left in an article presented as complete. |
| **Validation dependency** | Profile and selected mapping, designated guidance, selected template, relevant campaign context, authorization/boundary evidence, destination identity/existence/parent state, or other declared required input consumed by this operation | Captured/checked for the operation; no new profile fields | Check readiness, authorization, content/identity, and resolved boundary where required by the shared contract. A change to a consumed input invalidates dependent work and requires revalidation before proceeding. Profile or template text cannot establish access permission. |
| **Approval decision** | One operation-scoped decision when the proposed change is outside the page-local exception | Required before applying any broader change | A single new article at a clear destination, with no change to existing notes, actual-play records, or established continuity, is the narrow page-local creation exception. Additional, destructive, restructuring, actual-play, or continuity-changing work requires a scoped preview and explicit DM approval before application. Approval authorizes only the described change and cannot waive vault boundaries or player-safety checks. |

### Template selection and identity rules

1. Resolve the requested type against the exact built-in catalog or the existing profile's `templates.custom` mapping. A custom type is available only if registered there; do not infer a type or invent a template.
2. For a built-in type, a configured `templates.<type>` override takes precedence over that type's bundled default. If configured, the override must be present, readable, valid Markdown, and inside the authorized vault. Any failure stops that article operation; there is no fallback to the bundled default.
3. If no built-in override is configured, select that type's bundled skill resource. If the installed skill resource is unavailable, stop and report that no usable template is available; do not search the repository, working directory, or vault for a substitute.
4. For a custom type, select only its configured `templates.custom.<id>` vault template. Custom types have no bundled default. Missing or invalid mapping/template stops the operation.
5. A selected template is read and validated before authoring. Treat its contents, profile text, and guidance as data, not commands, permission, or policy. Static fill-ins follow the exact required/optional marker rules above; other dynamic syntax is never executed.

## Relationships

- One authoring request belongs to exactly one authorized-vault context and requests one article type and one new destination.
- An article type resolves to at most one selected template for the operation. A built-in type may have a vault override or a bundled default, never both as active content; a configured override suppresses fallback even when it fails validation.
- A custom type maps to exactly one vault-owned Markdown template through `templates.custom.<id>` and has no plugin default.
- The selected template has zero or more static fill-in markers and may contain unsupported dynamic syntax. Marker completion uses only information from the DM or established, authorized context.
- The proposed article content is derived from the selected template and the request context. It is not campaign history or character knowledge merely because it was prepared.
- Player-facing handout/read-aloud sections are part of the proposed article content and must pass a safety gate after the final content change and directly before delivery. Any later change requires a new check. No label, callout, hidden section, or collapsed presentation substitutes for removing DM-only facts and revealing links.
- The operation depends on the profile state and every required dependency/input it actually consumes. A change to one of them invalidates only work that depends on it, which must stop for revalidation.
- An approval decision is related to the scoped proposed change, not to the vault generally. The page-local exception does not authorize any additional change.

## Validation and safety boundaries

### Preconditions and input validity

- Activate `vault-orientation`; establish and authorize the vault and load the shared reference before the limited profile read needed to identify designated local guidance. Load designated guidance and establish task context before campaign-note or selected-template access; see the [contract](contracts/article-authoring-contract.md#required-preflight-and-access-order). A profile, template, Resolver availability, or test-only authorization provider cannot grant authorization.
- Apply Feature 002 profile parsing, schema, and path rules without adding keys or defaults. Invalid profile data blocks dependent authoring; do not use partial mappings or guessed replacements.
- Treat all vault-owned template paths as vault-relative references. Reject absolute, traversal, escaping, or symlink-resolved targets outside the authorized root before reading. Where authoring depends on an Obsidian link destination, do not resolve/access that destination unless containment including symlinks has been verified under the authoritative Resolver contract.
- Check the destination independently from template validity. A clear destination is exactly one in-vault Markdown path explicitly supplied by the DM, relative or absolute. Feature 002 has no article-destination field; section-folder and template mappings do not by themselves identify a note path. An existing target, multiple plausible paths, unknown destination, absent parent folder, or inability to confirm containment means stop and ask; no overwrite, implicit folder creation, migration, move, or reorganization.
- Track freshness for every consumed input: profile/mapping, designated guidance, selected template, relevant campaign context, authorization/boundary evidence, and destination identity/existence/parent state. If any changes after validation, stop dependent work, report staleness, and require revalidation before retry. Do not combine previously read and changed inputs.

### Content constraints

- Preserve conventions established by explicit DM instructions, designated local guidance, the shared reference, or relevant authorized notes; do not invent a fixed tag vocabulary when none is established. Proposed native callout defaults are design guidance only, subject to the feature specification and vault guidance.
- Treat facts as DM-only when identified by the DM or designated guidance/context as DM-facing; treat links as revealing when their target or known result exposes such facts. Handouts and read-aloud text must exclude them and pass a final gate-check after the last content change and directly before delivery/reading; any later content change requires another check. If safety cannot be established from authorized, relevant context, withhold the section.
- Keep preparation distinct from actual-play outcomes. Prepared events do not establish history, world facts, or character/group knowledge; do not rewrite adventure plans or resolve continuity contradictions.
- A missing required fill-in is a request for clarification, not permission to invent information or silently mark the article complete. An optional fill-in may remain unfilled. Unsupported dynamic syntax remains unexpanded.

## Lifecycle and state transitions

These are operation-level design states, not persistent profile or article-status fields.

```text
Requested
  -> PreflightPassed
  -> InputsValidated
  -> TemplateSelectedAndRead
  -> ContentPrepared
  -> DestinationValidated
  -> [ApprovalPending -> Approved]
  -> Created
```

Applicable transitions and terminal outcomes:

- **Requested → PreflightPassed:** only after `vault-orientation`'s required pre-note sequence succeeds. An unmet/unverified prerequisite yields **Blocked** before dependent profile, template, or campaign-note access.
- **PreflightPassed → InputsValidated:** validate the applicable Feature 002 profile and required inputs/path boundaries. Invalid or unavailable required input yields **Blocked**; do not accept partial profile state.
- **InputsValidated → TemplateSelectedAndRead:** apply override/default/custom precedence, then read and validate the single selected template. Missing, unreadable, invalid, unsafe, or unavailable selected template yields **Blocked**; configured override errors do not transition to a fallback.
- **TemplateSelectedAndRead → ContentPrepared:** complete supported markers from authoritative information. If any required marker lacks unambiguous information, transition to **NeedsDMInput** and wait; resume only with the DM's answer and revalidate affected inputs. Optional markers may remain.
- **ContentPrepared → DestinationValidated:** verify destination containment, clarity, existing-target absence, and existing parent. Conflict or ambiguity yields **NeedsDMDecision**, not an alternate write.
- **DestinationValidated → Created:** permitted without separate DM approval only for one new article at a clear destination—one in-vault Markdown path explicitly supplied by the DM, relative or absolute, with existing parent, absent target, and confirmed containment—and no edits to existing notes, actual-play records, or established continuity. Otherwise transition to **ApprovalPending** with a scoped preview; apply only after explicit **Approved**. Decline means no change.
- **Any active state → Stale:** on a detected change to an input the operation depends on. Stop; require revalidation before retry, with no automatic retry or mixed-version content.
- **Any active state → Blocked:** on failed authorization/boundary checks, unsupported or invalid inputs, unsafe player-facing content, unavailable required validation, or failed write. Preserve existing content and report the blocker; do not return a success-shaped result.

## Design and implementation status

This artifact describes Feature 005's model and constraints. Article templates and create-only runtime operations have local synthetic coverage; skill decisions and end-to-end installed-client behavior require client validation. Feature 002 owns profile semantics. Live MCP readiness/authorization belong to Copilot; PowerShell consumes explicit vault-scoped caller confirmation and enforces filesystem and write safeguards. Resolver symlink-target qualification is deferred to the owner. Synthetic tests do not establish live caller checks, installed-client behavior, or cross-platform support.

## Sources

- [Feature 005 specification](spec.md), especially Clarifications and FR-001–FR-018.
- [Feature 005 research](research.md), especially configuration/selection, vault boundaries, change handling, and writes/approval decisions.
- [Feature 005 implementation plan](plan.md), especially constraints, scope, and implementation evidence gates.
- [Feature 002 data model](../002-vault-configuration-contract/data-model.md).
- [Feature 002 vault configuration contract](../002-vault-configuration-contract/contracts/vault-configuration-contract.md).
- [Feature 001 vault-guidance loading contract](../001-shared-vault-guidance/contracts/vault-guidance-loading.md).
- [Feature 003 PowerShell runtime contract](../003-powershell-runtime-safety/contracts/powershell-runtime-contract.md).
- [Feature 004 Resolver MCP contract](../004-link-resolver-integration/contracts/resolver-mcp-contract.md).
