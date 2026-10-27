# Portable Skills

This is the declared inventory of every immediate-child skill directory that
contains a `SKILL.md`. Classify each skill as vault-facing or non-vault-facing.
Vault-facing skills must load the canonical shared reference and check every
required runtime dependency, including vault authorization, before campaign
note access. The **Expected Runtime Dependencies** table in
`specs/001-shared-vault-guidance/spec.md` is authoritative; do not duplicate its
dependency inventory here.

| Skill | Classification | Preflight |
| --- | --- | --- |
| [vault-orientation](vault-orientation/SKILL.md) | Vault-facing | Loads its bundled [`VAULT-REFERENCE.md`](vault-orientation/VAULT-REFERENCE.md), any DM-designated local guidance, and verifies the authoritative required-dependency inventory and exact-vault authorization before campaign-note access. |

Add every future skill here when its immediate-child directory contains a
`SKILL.md`. Classify it as vault-facing if it reads, interprets, creates, or
changes campaign material; link to its instructions instead of duplicating
them. For each vault-facing skill, verify from source that it loads the
canonical reference and designated local guidance, and checks every dependency
in the specification's authoritative table before note access.
