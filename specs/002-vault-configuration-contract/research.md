# Research: Vault Configuration Contract

## Decision 1: Keep schema definition separate from YAML reader/runtime

**Decision:** Feature 002 defines the `.dmassist.yaml` version-1 profile, its
observable validation outcomes, and a machine-readable JSON Schema for the
normalized profile structure. Issue #4 owns parser selection, scalar
normalization, duplicate-key detection, validator integration, runtime
provisioning, and filesystem-dependent validation.

**Rationale:** JSON Schema validates an instance structure and its values; it
does not parse YAML, detect duplicate YAML mapping keys already lost during
normalization, or check filesystem state and symbolic-link targets. Keeping
these concerns separate preserves portability and the Issue #3/Issue #4
ownership boundary.

**Alternatives considered:** Put all validation into the JSON Schema or select
a YAML implementation in Feature 002. Both were rejected: the former cannot
express parser and filesystem behavior portably, and the latter belongs to
Issue #4.

## Decision 2: Use JSON Schema Draft 2020-12 and keep profile version distinct

**Decision:** The machine-readable artifact will declare
`$schema: https://json-schema.org/draft/2020-12/schema`. The profile's own
`version: 1` remains the application-level version of `.dmassist.yaml`, not
the JSON Schema dialect identifier.

**Rationale:** An explicit dialect makes schema interpretation predictable for
validators and editor tooling. The profile format version and schema-language
dialect version identify different things and must not be conflated.

**Alternatives considered:** Omitting `$schema` and relying on validator
defaults was rejected because it leaves dialect selection implicit. Updating
the profile's `version` to represent a JSON Schema draft was rejected because
it would change the meaning of the user-facing profile version.

**Sources:** [JSON Schema: The `$schema` keyword](https://json-schema.org/understanding-json-schema/reference/schema)

## Decision 3: Model defaults as annotations, not schema mutation

**Decision:** Include applicable JSON Schema `default` annotations to document
the profile defaults, but do not require validators to insert missing values.
Runtime resolution applies documented defaults and candidates after schema
validation.

**Rationale:** In JSON Schema, `default` is an annotation and does not fill in
or mutate instance values during validation. This matches the contract's
distinction between omitted settings, effective defaults, and optional
discovery candidates.

**Alternatives considered:** Treating `default` as an instruction to mutate
the profile was rejected because that behavior is not part of standard
validation and would make validator behavior tool-dependent.

**Sources:** [JSON Schema annotations](https://json-schema.org/understanding-json-schema/reference/annotations), [JSON Schema conditionals](https://json-schema.org/understanding-json-schema/reference/conditionals)

## Decision 4: Express object shapes, conditions, and custom identifiers directly

**Decision:** Use the selected dialect's standard object constraints to
describe allowed and required properties, value types, enums, custom-key
patterns, and the mutually exclusive preparation modes. Anchor custom
identifier patterns as `^[a-z][a-z0-9_]*$`. The version-1 schema will reject
unknown properties at each relevant object boundary.

**Rationale:** These constraints are expressible over the normalized profile
and can be validated by interoperable JSON Schema tooling. Preparation mode
determines whether `heading` or `path` is permitted/required; custom section
and template names are open-ended but restricted by the contract's identifier
grammar.

**Alternatives considered:** A closed enumeration of custom identifiers was
rejected because DMs need to define new identifiers. Leaving unknown fields
open was rejected because typos and unsupported settings must fail clearly.

**Sources:** [JSON Schema conditionals](https://json-schema.org/understanding-json-schema/reference/conditionals), [JSON Schema objects](https://json-schema.org/understanding-json-schema/reference/object), [JSON Schema strings and regular expressions](https://json-schema.org/understanding-json-schema/reference/string)

## Decision 5: Normalize scalar values before JSON Schema validation

**Decision:** Issue #4's reader/normalization layer will provide a
locale-independent normalized profile to the JSON Schema. Values for
string-valued fields resolve from YAML string, boolean, numeric, or date/time
scalars to non-empty strings; booleans use lowercase text, dates/timestamps
use ISO 8601, and explicit nulls or collections in scalar positions fail.
`version` remains integer `1`.

**Rationale:** YAML parsers may resolve plain scalars to non-string runtime
types. A deterministic conversion contract enables equivalent profile
interpretation without tying Feature 002 to a particular parser.

**Alternatives considered:** Reject every non-string scalar for string-valued
fields or allow parser-specific conversions. The former conflicts with the
existing spec's scalar conversion requirement; the latter undermines
determinism across supported readers.

## Decision 6: Keep filesystem and operation validation outside JSON Schema

**Decision:** Schema validation covers only the normalized profile's
structural and value constraints. YAML syntax support and duplicate-key
rejection are parser responsibilities. Path traversal checks, canonical
vault-boundary and symlink checks, section existence, referenced-file
readability, and stale-input detection remain runtime checks.

**Rationale:** Standard JSON Schema has no portable filesystem vocabulary.
Separate runtime checks can use the authorized vault context and report
actionable errors without non-standard keywords.

**Alternatives considered:** Add implementation-specific schema keywords for
path existence or containment. Rejected because ordinary JSON Schema
validators cannot interpret filesystem access and would disagree on behavior.

**Sources:** [JSON Schema: Schema and custom keywords](https://json-schema.org/understanding-json-schema/reference/schema), [JSON Schema objects](https://json-schema.org/understanding-json-schema/reference/object)

## Project ownership

- Feature 002 owns the versioned profile contract, the written validation
  contract, and the version-1 JSON Schema artifact.
- Issue #4 owns choosing and integrating a YAML parser and JSON Schema
  validator, scalar normalization, runtime dependency provisioning, and
  filesystem-dependent checks.
- The repository is a documentation-and-metadata scaffold. These artifacts
  specify future behavior; they do not imply a working loader or validator.
