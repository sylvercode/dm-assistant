Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
Import-TestProductionModule -Name 'VaultConfiguration'

Describe 'Vault profile schema validation and defaults' {
    It 'validates the normalized profile against the installed Draft 2020-12 schema' {
        $valid = [ordered]@{ version = 1 }
        $invalid = [ordered]@{ version = 1; unknown = 'not allowed' }
        (Test-DmProfileSchema -Profile $valid).passed | Should -BeTrue
        (Test-DmProfileSchema -Profile $invalid).code | Should -Be 'PROFILE_SCHEMA_INVALID'
    }

    It 'requires a runtime with Draft 2020-12 Test-Json support' {
        $profile = [ordered]@{ version = 1 }
        (Test-DmProfileSchema -Profile $profile -PowerShellVersion ([version]'7.3')).code | Should -Be 'PREREQUISITE_MISSING'
    }

    It 'applies documented defaults only after validation without mutating source' {
        $source = [ordered]@{ version = 1 }
        (Test-DmProfileSchema -Profile $source).passed | Should -BeTrue
        $resolved = Resolve-DmProfileDefaults -Profile $source
        $source.Contains('sections') | Should -BeFalse
        $resolved.sections.lore | Should -Be 'Lore'
        $resolved.preparation.heading | Should -Be 'Preparation'
    }
}
