# Research: PowerShell Runtime and Safe Operations

**Status:** Design decisions underlying the locally tested PowerShell runtime.
Current implementation evidence and limitations are recorded in
[`docs/powershell-runtime-support.md`](../../docs/powershell-runtime-support.md).
These decisions do not establish production authorization or installed-client
and cross-platform support.

## Decision 1: Use a supported PowerShell 7 runtime, selected and recorded per release

**Decision:** Future script-backed workflows target cross-platform PowerShell
7 (`pwsh`), selecting the latest stable release at selection time, and only
support operating-system/runtime combinations that pass the release's
prerequisite, repeatability, and failure checks and can reliably perform the
contract's path-resolution, atomic-replace, and encoding checks. Publish the
exact runtime and add-on versions, selection date, installation guidance, and
any unsupported environments in `docs/powershell-runtime-support.md`. Do not
install or upgrade prerequisites during workflow execution.

**Rationale:** PowerShell 7 is available across Windows, macOS, and Linux,
whereas Windows PowerShell 5.1 is Windows-only. A dated, tested version matrix
is more actionable than a floating minimum or a statement that all systems
are supported. Exact versions must be selected when a release's dependencies
are validated; this plan does not freeze a version that will become stale
before implementation.

**Alternatives considered:** Windows PowerShell 5.1 alone was rejected because
it cannot meet the cross-platform requirement. Silently degrading when a
module or runtime is unavailable was rejected because the specification
requires an explicit unsupported or blocked result.

**Sources:** [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle),
[PowerShell installation overview](https://learn.microsoft.com/powershell/scripting/install/installing-powershell).

## Decision 2: Keep plugin discovery independent of script prerequisites

**Decision:** The Agent Plugins 1.0 manifest and skill Markdown remain static
plugin resources. Only a future operation that invokes a script checks for
PowerShell and its declared modules; plugin installation and skill discovery
must not execute PowerShell or install prerequisites.

**Rationale:** This preserves the current scaffold's installability and keeps
future runtime behavior a proposal until a skill and script are implemented.
Plugin-owned resources must resolve from the installed component, not the
repository checkout, campaign vault, or caller's current directory. For
script-local resources, use the executing script's own location where
available, then validate the selected owner-skill resource lookup in an
installed-client fixture. Do not assume that MCP-only `PLUGIN_ROOT` variables
are passed to skill scripts.

**Alternatives considered:** Loading resources from `$PWD`, the source
checkout, or an assumed sibling skill path was rejected because these depend
on the user's starting directory or unverified package layout. Making plugin
installation invoke PowerShell was rejected because it couples static
discovery to a future runtime.

**Sources:** [GitHub Copilot plugins](https://docs.github.com/en/copilot/concepts/customizations/plugins),
[PowerShell automatic variables](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_automatic_variables),
[Plugin Architecture](../../docs/architecture.md).

## Decision 3: Consume the Feature 002 profile schema from an installed skill resource

**Decision:** The consuming vault-facing skill must have one canonical
packaged copy of the Feature 002 JSON Schema inside its own component resource
directory. This plan selects
`skills/vault-orientation/assets/dmassist.schema.json` as the installed
resource location because `vault-orientation` is the current profile/discovery
consumer. Keep Feature 002's schema semantics authoritative; update its
documentation to identify the canonical packaged location rather than
maintaining a divergent schema copy. The installed skill must be tested from
multiple current working directories, and a missing or incompatible resource
blocks profile-dependent work.

**Rationale:** A repository-root `schemas/` folder is not guaranteed by the
plugin component contract to be packaged or discoverable from an installed
skill. Bundling the schema with its consumer gives the resource an unambiguous
owner and enables script-relative lookup without adding a manifest extension
or assuming an undocumented global plugin path.

**Alternatives considered:** A free-standing root schema path and a second
copy under the skill were rejected because the first is not a guaranteed
installed component resource and the second can drift. A sibling-skill lookup
was rejected because cross-skill paths are not a guaranteed resource contract.

**Sources:** [Plugin Architecture](../../docs/architecture.md),
[Feature 002 data model](../002-vault-configuration-contract/data-model.md),
[Feature 002 schema](../../skills/vault-orientation/assets/dmassist.schema.json),
[GitHub Copilot plugin creation](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating).

## Decision 4: Parse YAML, normalize it, then validate the normalized schema instance

**Decision:** Keep the boundaries defined by Feature 002: a YAML reader parses
`.dmassist.yaml`, rejects duplicate mapping keys, and normalizes supported
typed scalars before a Draft 2020-12 validator evaluates the normalized
profile against the canonical schema resource. Do not reimplement profile
defaults or schema semantics in the reader.

**Rationale:** JSON Schema validates the normalized data shape; it does not
parse YAML, recover duplicate keys discarded during parsing, apply defaults,
or inspect the filesystem. `powershell-yaml` uses YamlDotNet, whose mapping
loader rejects duplicate keys by default. Its merge-key mode is opt-in and
must remain explicit. YAML readers may turn plain date-, boolean-, or
number-like scalars into typed values, so normalization must apply Feature
002's locale-independent string rules before validation. Use the built-in
`Test-Json -Schema` cmdlet as the Draft 2020-12 validator: from PowerShell
7.4 it is backed by `JsonSchema.Net` and honors the schema's `$schema`
dialect, so it adds no separate module dependency. A probe on PowerShell
7.6.9 validated the canonical artifact and rejected a missing `version`.
Serialize the normalized profile to JSON before validation, and map a schema
failure to `PROFILE_SCHEMA_INVALID` without echoing profile values. The
cmdlet reports one violation per call, which is sufficient for that code.
PowerShell releases before 7.4 used a validator without Draft 2020-12
support, so they are unsupported.

**Alternatives considered:** Treating JSON Schema as a YAML parser or
filesystem validator was rejected as outside its portable validation model.
Parser-dependent coercion was rejected because it makes profile behavior
vary by reader. A hand-coded duplicate schema in PowerShell was rejected
because it would drift from Feature 002's artifact. Loading `JsonSchema.Net`
as a separate add-on was rejected because `Test-Json` already provides the
same engine in supported PowerShell releases.

**Sources:** [Feature 002 research](../002-vault-configuration-contract/research.md),
[powershell-yaml](https://github.com/cloudbase/powershell-yaml),
[YamlDotNet](https://github.com/aaubry/YamlDotNet),
[JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12/json-schema-core),
[Test-Json](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/test-json),
[JsonSchema.Net](https://docs.json-everything.net/schema/basics/).

## Decision 5: Resolve paths and check the canonical vault boundary before access

**Decision:** Validate configured paths lexically, resolve each existing path
component including intermediate symbolic links, canonicalize both target
and authorized vault root, and perform a component-aware containment check
before every access. Never execute a shell command to resolve an untrusted
path. Treat unresolved, cyclic, inaccessible, or out-of-bound targets as
blocked operations.

**Rationale:** Lexical normalization alone does not follow symbolic links;
resolving only a leaf link misses symlinked parent directories. A raw string
prefix check also confuses sibling paths with a vault boundary. Rechecking
near access reduces check/use races, though portable path-based APIs cannot
eliminate every race if another process replaces a link between the check and
the filesystem operation.

**Alternatives considered:** String-prefix checks and external `realpath`
shell calls were rejected: the former are unsafe, while the latter add
platform-specific process invocation and command-quoting risk. Cross-platform
long-lived file locking was rejected as an assumed safety guarantee because
lock semantics differ and cannot reliably constrain other vault tools.

**Sources:** [.NET `ResolveLinkTarget`](https://learn.microsoft.com/dotnet/api/system.io.filesysteminfo.resolvelinktarget),
[.NET file I/O improvements](https://devblogs.microsoft.com/dotnet/file-io-improvements-in-dotnet-6/),
[Feature 002 path contract](../002-vault-configuration-contract/contracts/vault-configuration-contract.md).

## Decision 6: Replace each note atomically and report multi-note partial completion

**Decision:** For each individual note, prepare replacement bytes in a
temporary file on the same filesystem as the target, recheck the target's
version immediately before replacement, then use a rename-class replacement
operation. Preserve supported encodings and line endings when they can be
reliably round-tripped. Otherwise, return `ENCODING_UNSAFE` without writing
or converting the note. This supersedes the earlier conversion-warning
approach. For a multi-note operation, stop at the first failure, leave earlier
completed writes intact, do not roll them back, do not attempt later notes,
and report exact changed and unchanged targets.

**Rationale:** A same-filesystem rename avoids exposing a partially written
individual note after interruption. Atomicity is per note, not for the whole
batch. Optimistic concurrency checks detect changed notes but do not prevent
every concurrent filesystem race; the replace failure or detected change
must be reported, not silently retried.

**Alternatives considered:** In-place truncation/rewrite and copy-then-delete
were rejected because interruption can expose partial content. Batch rollback
was rejected by the user's clarification and can overwrite newer user edits.
Always normalizing every file was rejected because it would alter
well-formed, safely preservable notes without need.

**Sources:** [POSIX `rename`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/rename.html),
[.NET `File.Move`](https://learn.microsoft.com/dotnet/api/system.io.file.move),
[PowerShell character encoding](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_character_encoding),
[Feature 003 clarifications and requirements](spec.md).

## Decision 7: Use stable result statuses and codes across operations

**Decision:** A result has one of three progress statuses: `complete`,
`not completed`, or `partially completed`. A stable completion code
distinguishes why an operation did not complete, including prerequisite
blocks, invalid input, conflicts, cancellations, and operational failures.
Results also report operation, changed and unchanged targets, remaining work,
and error details when present. Do not use prose parsing as a machine contract.

**Rationale:** The same small status vocabulary describes progress, while
codes let consuming workflows distinguish actionable causes without relying
on localized error messages. Publish the exact code names in the interface
contract before implementation.

**Alternatives considered:** A single success/failure flag loses partial
completion and actionable failure categories. Creating a unique status for
every error conflates progress with cause and expands the status contract
unnecessarily.

**Sources:** [Feature 003 clarification and result requirements](spec.md),
[Feature 001 loading contract](../001-shared-vault-guidance/contracts/vault-guidance-loading.md).

## Decision 8: Verify with a synthetic harness and an isolated test-only authorization provider

**Decision:** Propose a PowerShell acceptance harness under
`tests/powershell/` that runs only against invented, disposable vault
fixtures, in two tiers. Production-gate tests run the real preflight with no
authorization provider and expect `VAULT_AUTHORIZATION_UNPROVEN` before any
profile, guidance, or note access. Downstream tests reach profile, path,
preview, and write behavior through a test-only authorization provider that
is supplied solely by an explicit harness parameter. Production code never
discovers or accepts a provider from a path, environment variable, or
configuration, and never references `tests/`. A static audit of the
production script directory enforces the no-dynamic-execution,
literal-path, no-network, and no-`tests/` rules. Pester 6 is the selected
runner because the task list already follows its `*.Tests.ps1` convention
and it is installed in the development environment; pin its exact version
when the harness is created, and never fall back to the Pester 3 module that
ships with Windows PowerShell.

**Rationale:** At the time of this decision, Feature 001 had not defined a
note-content-free exact-vault authorization signal. It now defines
`get_server_info`, but the runtime has no verified active-session handoff, so
the production gate still fails closed. Downstream behavior (profile handling,
containment, preview, atomic writes, conflicts) would otherwise be
unverifiable. A provider confined to the harness lets those paths be tested
without implying the production handoff works. Because the repository root is
the installable plugin, `tests/` could
ship with it; verifying that the installed plugin excludes `tests/` or gains
no bypass from it keeps the test seam from becoming an authorization
shortcut.

**Alternatives considered:** Waiting for Feature 001 was rejected because it
would leave Feature 003's own requirements untestable. A production
environment-variable, flag, or configuration bypass was rejected because it
would weaken the fail-closed gate. Manual-only verification was rejected
because repeatable results are required in every supported environment.

**Sources:** [Pester quick start](https://pester.dev/docs/quick-start),
[Pester installation and compatibility](https://pester.dev/docs/introduction/installation),
[Feature 003 requirements](spec.md),
[Runtime contract](contracts/powershell-runtime-contract.md).

## Decisions deferred to implementation readiness

- Select and record the exact latest stable PowerShell (7.4 or later, for
  `Test-Json` Draft 2020-12 support) and YAML-reader versions, plus the
  selection date and per-platform support matrix, when the runtime
  dependency set is tested for release.
- Pin the exact Pester 6 acceptance-test runner version, and
  confirm that it supports the selected PowerShell release before relying on
  it.
- Verify actual installed-client skill activation and owner-skill resource
  resolution in the disposable fixture described by
  `docs/architecture.md`; source-tree inspection is not sufficient.
- Validate filesystem primitives (atomic replace, symlink behavior, and
  encoding detection) on every supported OS and report unsupported cases
  rather than claiming untested portability.
