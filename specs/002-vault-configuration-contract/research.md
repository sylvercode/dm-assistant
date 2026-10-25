# Research: Feature Boundary

## Decision

Issue #3 defines the `.dmassist.yaml` schema and the observable behavior
required when a profile is valid, invalid, or absent. It does not define the
reader implementation.

Issue #4, [Establish the PowerShell runtime and safe operation
contracts](https://github.com/sylvercode/dm-assistant/issues/4), owns YAML
reader selection, YAML library behavior, PowerShell/module versions, dependency
provisioning, supported platforms, runtime checks, and reader integration.

## Rationale

The GitHub issue scopes distinguish configuration from runtime foundations:
Issue #3 asks for the versioned schema, defaults, validation outcomes, and
vault-boundary guarantees; Issue #4 asks for runtime/module provisioning and
checks, script I/O and error contracts, and safe path operations. Keeping those
deliverables separate prevents this schema feature from prematurely locking in
a reader or duplicating runtime requirements.

## Contract requirements retained in Issue #3

- Define each field's type, required/default status, and invalid-value outcome.
- Reject duplicate keys, unknown fields, unsupported schema versions, and
  invalid values with clear errors.
- Accept YAML syntax supported by the eventual reader when the resolved
  configuration satisfies the schema; stop on parser errors.
- Require deterministic field interpretation and consistent scalar handling.
- Do not proceed with settings the workflow cannot validate.

These are user-visible schema and validation outcomes. Issue #4 chooses and
tests the mechanism that provides them.

## Sources

- [Issue #3: Define the vault configuration contract](https://github.com/sylvercode/dm-assistant/issues/3)
- [Issue #4: Establish the PowerShell runtime and safe operation contracts](https://github.com/sylvercode/dm-assistant/issues/4)
- `specs/002-vault-configuration-contract/spec.md`
- `docs/vault-guidance-brainstorm.md`, “YAML Vault Configuration and Note Metadata” and “PowerShell and Predictable Operations”
