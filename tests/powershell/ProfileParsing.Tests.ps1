Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
Import-TestProductionModule -Name 'VaultConfiguration'

Describe 'Vault profile YAML parsing and normalization' {
    It 'rejects malformed YAML and duplicate mapping keys' {
        $malformed = ConvertFrom-DmVaultProfileYaml -Yaml "version: ["
        $duplicate = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`nversion: 1"
        $multipleDocuments = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`n---`nversion: 1"
        $emptyDocument = ConvertFrom-DmVaultProfileYaml -Yaml "---`n---`nversion: 1"
        $malformed.code | Should -Be 'PROFILE_PARSE_INVALID'
        $duplicate.code | Should -Be 'PROFILE_PARSE_INVALID'
        $multipleDocuments.code | Should -Be 'PROFILE_PARSE_INVALID'
        $emptyDocument.code | Should -Be 'PROFILE_PARSE_INVALID'
    }

    It 'normalizes typed scalar values with invariant formatting and keeps version integer' {
        $profile = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`nsections:`n  lore: true`n  rules: 12`n  adventures: 2026-10-30"
        $profile.passed | Should -BeTrue
        $profile.profile.version | Should -BeOfType ([int])
        $profile.profile.sections.lore | Should -Be 'true'
        $profile.profile.sections.rules | Should -Be '12'
        $profile.profile.sections.adventures | Should -Be '2026-10-30'
    }

    It 'rejects null and collection values in scalar positions' {
        $nullValue = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`nparty:`n  note: null"
        $collection = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`nparty:`n  note:`n    - Lore/Party.md"
        $nullValue.code | Should -Be 'PROFILE_NORMALIZATION_INVALID'
        $collection.code | Should -Be 'PROFILE_NORMALIZATION_INVALID'
    }

    It 'accepts merge syntax only when the resulting profile passes the schema' {
        $profile = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`nsections:`n  defaults: &defaults`n    lore: Lore`n  <<: *defaults"
        $profile.passed | Should -BeTrue
        (Test-DmProfileSchema -Profile $profile.profile).code | Should -Be 'PROFILE_SCHEMA_INVALID'
    }

    It 'parses aliases as data and leaves schema validation to reject unsupported placements' {
        $profile = ConvertFrom-DmVaultProfileYaml -Yaml "version: 1`nsections: &mapped`n  lore: Lore`ncopy: *mapped"
        $profile.passed | Should -BeTrue
        $profile.profile.copy.lore | Should -Be 'Lore'
        (Test-DmProfileSchema -Profile $profile.profile).code | Should -Be 'PROFILE_SCHEMA_INVALID'
    }
}
