# Data Model: Link Resolver Integration

## Status and scope

This document describes the conceptual entities, fields, relationships, and
state transitions required by the [feature specification](spec.md). It defines
neither an MCP wire schema nor a persistence format, client configuration
syntax, or runtime implementation. Obsidian Link Resolver's external MCP
payload details are contract-delegated to the compatible resolver release;
this feature does not invent tool arguments, response fields, or status enums.

Feature 001's
[dependency contract](../001-shared-vault-guidance/spec.md#expected-runtime-dependencies-initial-non-exhaustive)
is authoritative for dependency readiness and exact-vault authorization.
Link resolution is never authorization evidence. The model describes a
preflight gate and result interpretation, not production authorization or
implementation status.

## Entities and fields

### Resolver dependency

The separately installed Obsidian Link Resolver service required by every
vault-facing skill.

| Field | Meaning and constraint |
| --- | --- |
| `dependencyIdentity` | Obsidian Link Resolver; a separately installed MCP server, not part of the plugin. |
| `compatibleVersion` | Version `2.1.0` or later, per Feature 001. If compatibility cannot be confirmed, readiness is unconfirmed. |
| `requiredTools` | Both `resolve_obsidian_link` and `get_server_info` must be available in the supported client session. Exact MCP payload details are delegated to the resolver contract. |
| `configurationRoots` | One or more absolute, user-authorized vault roots supplied to the resolver with `--vault`. Vault-specific paths are not plugin configuration or distributed plugin data. |
| `configurationSession` | Client session in which resolver settings are active and checked. Settings changed after session startup require a fresh session and new verification. |

### Task vault

The vault independently established for the current task from the user's
workspace or explicit input. It is the authorization subject, not a path
discovered by resolving a campaign link.

| Field | Meaning and constraint |
| --- | --- |
| `establishedLocation` | The vault location established independently for this task, without campaign-note access. |
| `canonicalLocation` | Canonical form used for the exact comparison with a returned authorized root, applying Feature 001's normalization rules. |
| `establishmentState` | Whether the task's vault has been established. An unknown or unestablished location cannot pass authorization. |

### Resolver preflight evidence

Operation-scoped, note-content-free evidence that the dependency is ready and
authorized for the task vault. It does not grant authorization beyond that
vault or establish a trusted handoff to another runtime.

| Field | Meaning and constraint |
| --- | --- |
| `sessionIdentity` | The supported client session whose active resolver settings and tools were checked. |
| `compatibilityState` | Confirmed compatible (`2.1.0+`) or unconfirmed. |
| `toolAvailability` | Availability of both required tools; partial availability is not ready. |
| `serverInfoState` | Whether `get_server_info` completed and provided a usable vault list, or failed/was unusable. Its arguments and payload structure remain resolver-contract delegated. |
| `reportedCanonicalRoots` | The canonical `vaults[].path` values returned by `get_server_info`, normalized according to Feature 001. Raw response shape is contract-delegated. |
| `authorizationState` | `authorized`, `not authorized`, or `unconfirmed` for this task vault. `authorized` requires an exact normalized match between the established task vault and one returned canonical root. |
| `checkedAt` | Context/time of the check; evidence is valid only for the settings and session actually checked. |

This evidence is not a campaign-note record and contains no note content.

### Link-resolution request

One request to resolve a user- or task-specified Obsidian link after the
preflight gate succeeds.

| Field | Meaning and constraint |
| --- | --- |
| `linkReference` | The requested link input passed to `resolve_obsidian_link`; its exact shape is delegated to the resolver contract. |
| `taskVault` | The already-established and authorized vault against which resolution is requested. |
| `preflightEvidence` | The successful, current-session readiness and exact-vault authorization evidence required before the call. |

This conceptual request does not prescribe additional MCP arguments or
imply that the link or its destination is trusted.

### Resolution outcome

The feature-level interpretation of the resolver's result. These are distinct
outcomes; they do not prescribe external response field names or enum values.

| Outcome | Meaning and constraint |
| --- | --- |
| `resolved` | One destination is reported as resolved. Convey the reported destination without modifying the note or asserting more than the result establishes. |
| `unresolved` | No destination was found. Report that status; do not infer or guess a destination. |
| `missing subtarget` | The link's requested subtarget is absent. Report the missing subtarget; do not substitute a guessed one. |
| `ambiguous` | Multiple destinations may match. Convey available candidate information without selecting one. |
| `error` | Resolution failed or the result cannot be interpreted reliably. Report the failure and only details defined by the Resolver contract and present in the result; identify unavailable details without guessing a destination. |

The resolver's exact result representation and any available candidate or
diagnostic fields are contract-delegated. If a response is incomplete or
cannot be classified confidently as one of these outcomes, treat it as
`error`, not as a successful resolution.

## Relationships

- Each vault-facing skill uses the one required resolver dependency declared
  by Feature 001; this feature does not maintain a divergent dependency
  inventory.
- A resolver configuration can authorize multiple roots, but a task is
  authorized only by an exact normalized match between its independently
  established vault and one returned canonical `vaults[].path`.
- A parent or child root is not an exact match. Path normalization follows
  Feature 001: remove a Windows `\\?\` prefix and trailing separators, and
  compare case-insensitively on Windows. Do not broaden the comparison into
  containment, link resolution, or another inferred relationship.
- A preflight evidence record is scoped to the task vault and active client
  session. It precedes and gates any link-resolution request.
- A resolution outcome belongs to one request and does not change note
  contents, authorize a vault, or silently establish another destination.

## Invariants and validation

1. Establish the intended task vault independently and without campaign-note
   access.
2. Before any campaign-note access, confirm resolver compatibility, both
   required tools, and a usable `get_server_info` result; then confirm the
   exact normalized match for the established task vault.
3. `get_server_info` is the authorization check. Service presence,
   `resolve_obsidian_link`, and any resolution result are not authorization.
4. If the service or either tool is unavailable, compatibility is
   unconfirmed, `get_server_info` fails or has no usable vault list, or no
   exact root match exists, fail closed. Explain the unmet prerequisite and
   stop before campaign-note access or changes.
5. A changed resolver setting makes the active session's settings
   unconfirmed. Require a fresh session and repeat readiness and authorization
   checks before note access.
6. Preserve the five outcome distinctions. Do not guess, silently choose an
   ambiguous candidate, substitute a missing subtarget, or present an error
   as a resolved destination.
7. Keep external MCP field and payload definitions delegated to the compatible
   resolver contract; do not turn conceptual fields here into a fabricated
   wire schema.

## Lifecycle and state transitions

### Resolver preflight

`unconfirmed` → `checking` → `ready and authorized` or `blocked`.

- `checking` evaluates version compatibility and availability of both tools,
  obtains note-content-free server information, and compares its canonical
  roots with the established task vault.
- Transition to `ready and authorized` only if all checks succeed and the
  exact normalized vault match is present.
- Any failed, missing, or uncertain prerequisite transitions to `blocked`;
  no campaign-note access or changes may occur from that state.
- A settings change, session change, or loss of required evidence invalidates
  the successful state and returns it to `unconfirmed`. Verification must be
  repeated in a fresh session after settings change.

### Link-resolution operation

`not started` → `preflight` → `resolving` → one terminal outcome:
`resolved`, `unresolved`, `missing subtarget`, `ambiguous`, or `error`.

- A blocked or unconfirmed preflight stops the operation before
  `resolving`; the link-resolution tool must not be used to bypass the gate.
- Only a current `ready and authorized` preflight permits a request.
- The terminal outcome is reported faithfully with only details defined by
  the Resolver contract and present in the result. Identify unavailable
  details; do not guess a destination. The outcome does not itself mutate
  notes or authorize future operations.
