# Research: Article Authoring and Template Selection

## Decisions

### Skill and resource packaging

- Implement one vault-facing `article-authoring` skill with a `SKILL.md` and
  nine type-specific Markdown defaults under its own `templates/` directory.
- Register the skill exactly once in `skills/README.md` and mark it as
  vault-facing with its required preflight.
- Keep custom templates in the authorized campaign vault, preferably under
  `.dmassist-templates/`; support existing in-vault paths without moving them.
- Resolve bundled defaults from the installed owning-skill resource location,
  never from the current working directory, repository checkout, or campaign
  vault.

**Rationale:** Skills are immediate children of `skills/`; a skill can own
bundled resources. A single skill keeps type-specific defaults with their
owner. The mandatory preflight stays owned by `vault-orientation`, which the
skill activates through the client's skill tool, a pattern verified by the
installed two-skill fixture test. Plugin-owned defaults
and DM-owned vault templates have separate ownership and update lifecycles.

**Alternatives considered:** Nine separate skills would multiply inventory
entries and preflight delegation. A separate shared template skill would add
another cross-skill resource dependency. Restating the preflight in the new
skill would drift from `vault-orientation`. Keeping DM templates in the plugin would violate
the vault boundary and risk replacing user customizations on plugin updates.

**Sources:** `docs/architecture.md` (Layout, Component Boundaries, Planned
Template Resources); `skills/vault-orientation/scripts/PluginResources.psm1`;
`skills/README.md`; `specs/005-article-authoring/spec.md` (FR-003, FR-006).

### Configuration and selection

- Reuse Feature 002's version-1 `.dmassist.yaml` `templates` mapping without
  adding a competing configuration shape.
- A configured built-in override takes precedence over its bundled default.
  If the override is missing, unreadable, invalid, changed, or outside the
  authorized vault, stop that article operation; do not fall back.
- A custom type is available only when registered in `templates.custom` with
  a vault-relative Markdown template path. Custom identifiers match
  `[a-z][a-z0-9_]*` and cannot duplicate a built-in type. Custom types have no
  bundled default.
- Read and validate the selected template before authoring. Treat profile and
  template content as data, not executable instructions or authorization.
- Recognize static required and optional fill-ins only through the clarified
  HTML-comment markers. Do not execute dynamic expressions or community
  plugin syntax.

**Rationale:** Feature 002 owns profile fields and defaults. Strict
override-failure behavior prevents silent changes in article structure or
content. Explicit marker semantics distinguish supported static fill-ins from
Obsidian and community-plugin expressions.

**Alternatives considered:** Adding new profile keys would duplicate the
configuration contract. Falling back after an invalid override would hide a
DM configuration error. Executing template expressions is explicitly out of
scope.

**Sources:** `specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`
(version 1 profile, templates, schema interpretation); `specs/005-article-authoring/spec.md`
(Clarifications, FR-004–FR-009, FR-015).

### Vault boundaries, preflight, and change handling

- Delegate the shared ordered pre-note sequence to `vault-orientation`,
  activated through the client's skill tool, instead of restating it; add only
  authoring-specific profile, template, and containment steps afterward.
- Resolve custom template targets against the canonical authorized vault root.
  Reject traversal and symlink targets outside the vault before reading them.
- Bind template/profile validation to the inputs used by the operation. If a
  selected template or other dependency changes, stop and require
  revalidation; do not automatically retry with mixed old and new inputs.
- Do not call `resolve_obsidian_link` until an upstream Resolver release with
  verified target containment, including symlinks, is confirmed.

**Rationale:** Exact-root authorization and target containment are separate
controls. Existing contracts require fail-closed behavior and revalidation of
stale profile, path, guidance, and template inputs.

**Alternatives considered:** Resolver availability or an exact configured root
alone does not protect link targets that escape through symlinks. Automatic
retry could combine different templates or profile settings within one
operation.

**Sources:** `specs/001-shared-vault-guidance/contracts/vault-guidance-loading.md`;
`specs/002-vault-configuration-contract/contracts/vault-configuration-contract.md`
(path safety and stale inputs); `specs/004-link-resolver-integration/contracts/resolver-mcp-contract.md`.

### Writes, approval, and failure behavior

- Reuse the Feature 003 structured runtime and safe note-write behavior rather
  than introducing a new command interface or direct file-write path.
- Stop if the target already exists, its destination is ambiguous, or a
  required folder is absent; do not overwrite or create folders by
  assumption.
- A single new article at a clear destination may use the page-local path.
  Any additional, destructive, restructuring, actual-play, or
  continuity-changing edits require a scoped preview and explicit DM
  approval before application.
- Preserve explicit failures; do not convert blocked, stale, invalid, or
  failed writes into success-shaped results.

**Rationale:** The safe-write contract centralizes boundary rechecks,
dependency-version checks, approval binding, and atomic replacement. Keeping
article creation page-local avoids unnecessary approval while preserving
continuity and user-data protections.

**Alternatives considered:** Direct writes from skill instructions would
bypass the established safe-operation boundary. Treating every article as
approval-free would exceed the narrow page-local exception.

**Sources:** `specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`;
`skills/vault-orientation/scripts/SafeNoteWriter.psm1`;
`specs/005-article-authoring/spec.md` (FR-010, FR-017).

### Security and evidence boundaries

- Production script-backed vault access remains blocked until the runtime can
  verify a trusted active-session authorization handoff. Do not infer
  authorization from profile contents, Resolver availability, test injection,
  or successful link resolution.
- The Resolver integration requires API compatibility `2.1.0` or later and
  both declared tools, but API compatibility alone does not satisfy the
  target-containment gate; no compliant upstream release is verified in the
  current repository evidence.
- Use synthetic disposable vaults and the test-only authorization provider
  for local Pester tests. Report those as local runtime evidence only, not as
  production authorization or installed-client verification.
- Keep installed-client validation, target-containment qualification, and
  cross-platform support as explicit release gates where applicable.

**Rationale:** The README, architecture documentation, and runtime contracts
state that test-only authorization does not prove production authorization.
The installed-client evidence for Resolver readiness does not establish a
PowerShell handoff.

**Alternatives considered:** Enabling production reads/writes based on local
synthetic tests or an earlier client check would exceed the evidence and
contradict the fail-closed contract.

**Sources:** `README.md` (Project Status); `docs/architecture.md` (External
Resolver Dependency, Verification Evidence Boundaries);
`docs/powershell-runtime-support.md`; `specs/004-link-resolver-integration/contracts/resolver-mcp-contract.md`.

## Validation approach

- Run the repository's Pester 6.2.0 acceptance suite with
  `pwsh -NoProfile -File tests\powershell\Invoke-Tests.ps1` after
  implementation.
- Add synthetic-vault coverage for each built-in template and selection
  precedence; required/optional placeholders; unknown custom types; unreadable,
  invalid, changed, and out-of-vault templates; target conflicts; unsafe
  destinations; and player-facing leakage checks.
- Verify the static skill inventory contains exactly one entry for the new
  immediate-child skill and that every vault-facing skill explicitly performs
  the required preflight before campaign-note access.
- Distinguish local synthetic acceptance coverage from Copilot CLI
  installed-client verification. No build or lint command is defined.

**Sources:** `AGENTS.md`; `specs/001-shared-vault-guidance/spec.md` (FR-017);
`specs/003-powershell-runtime-safety/contracts/powershell-runtime-contract.md`;
`docs/powershell-runtime-support.md`.
