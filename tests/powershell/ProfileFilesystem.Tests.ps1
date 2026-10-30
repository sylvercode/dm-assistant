BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, PluginResources, VaultConfiguration
}
Describe 'Vault profile filesystem and reference validation' {
    BeforeEach {
        $fixture = New-TestVaultFixture -ProfileText "version: 1`n"
        $gate = [pscustomobject]@{ gate = 'vault-authorization'; passed = $true }
        $root = Resolve-DmVaultRoot -Gate $gate -VaultRoot $fixture.Root -Operation 'profile.validate'
    }

    It 'rejects a configured section folder whose link escapes the vault' {
        $linkPath = Join-Path -Path $fixture.Root -ChildPath 'OutsideMapping'
        try { [void][System.IO.Directory]::CreateSymbolicLink($linkPath, $fixture.OutsidePath) }
        catch {
            try { $null = New-Item -ItemType Junction -Path $linkPath -Target $fixture.OutsidePath -ErrorAction Stop }
            catch { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        }
        $profile = [ordered]@{ sections = [ordered]@{ lore = 'OutsideMapping' } }
        (Test-DmProfileFilesystem -Boundary $root.boundary -Profile $profile).code | Should -Be 'PROFILE_FILESYSTEM_INVALID'
    }

    AfterEach { Remove-TestVaultFixture -Fixture $fixture }

    It 'accepts existing configured section folders and rejects missing ones' {
        $valid = [ordered]@{ sections = [ordered]@{ lore = 'Lore' } }
        (Test-DmProfileFilesystem -Boundary $root.boundary -Profile $valid).passed | Should -BeTrue
        $missing = [ordered]@{ sections = [ordered]@{ lore = 'No Such Folder' } }
        (Test-DmProfileFilesystem -Boundary $root.boundary -Profile $missing).code | Should -Be 'PROFILE_FILESYSTEM_INVALID'
        $wrongType = [ordered]@{ sections = [ordered]@{ lore = 'Adventures/Synthetic Arc.md' } }
        (Test-DmProfileFilesystem -Boundary $root.boundary -Profile $wrongType).code | Should -Be 'PROFILE_FILESYSTEM_INVALID'
    }

    It 'requires an existing separate preparation directory' {
        $profile = [ordered]@{ preparation = [ordered]@{ mode = 'separate_folder'; path = 'Sessions/Preparations' } }
        (Test-DmProfileFilesystem -Boundary $root.boundary -Profile $profile).code | Should -Be 'PROFILE_FILESYSTEM_INVALID'
    }

    It 'applies lexical path rules to configured references' {
        $result = Test-DmProfileReference -Boundary $root.boundary -Path '../outside/secret.md' -Kind party
        $result.code | Should -Be 'PATH_INVALID'
    }

    It 'rejects unsafe configured reference paths during profile validation' {
        $profile = [ordered]@{ party = [ordered]@{ note = '../outside/secret.md' } }
        (Test-DmProfileFilesystem -Boundary $root.boundary -Profile $profile).code | Should -Be 'PATH_INVALID'
    }

    It 'reports a missing configured reference only when that reference is needed' {
        foreach ($kind in @('guidance', 'template', 'party', 'preparation')) {
            $result = Test-DmProfileReference -Boundary $root.boundary -Path 'Lore/Missing.md' -Kind $kind
            $result.code | Should -Be 'REFERENCE_UNAVAILABLE'
        }
        (Test-DmProfileReference -Boundary $root.boundary -Path 'Lore' -Kind template).code | Should -Be 'REFERENCE_UNAVAILABLE'
    }

    It 'does not mutate the source when resolving nested defaults' {
        $source = [ordered]@{ version = 1; sections = [ordered]@{ custom = [ordered]@{} } }
        $resolved = Resolve-DmProfileDefaults -Profile $source
        $source.sections.Contains('lore') | Should -BeFalse
        $resolved.sections.lore | Should -Be 'Lore'
    }

    It 'detects profile changes against the reviewed dependency versions' {
        $profile = Read-DmVaultProfile -Boundary $root.boundary
        $versions = Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $profile.profile
        [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nsections: {}`n")
        $check = Test-DmProfileDependencyVersions -Boundary $root.boundary -Profile $profile.profile -ReviewedVersions $versions
        $check.code | Should -Be 'TARGET_CONFLICT'
        $check.changedIdentities | Should -Contain '.dmassist.yaml'
    }

    It 'does not substitute a plugin template when the profile has no matching template' {
        $profile = [ordered]@{ version = 1; templates = [ordered]@{ adventure = 'custom/adventure.md' } }
        (Resolve-DmProfileTemplate -Profile $profile -ArticleType 'monster').available | Should -BeFalse
        (Resolve-DmProfileTemplate -Profile $profile -ArticleType 'adventure').path | Should -Be 'custom/adventure.md'
    }

    It 'reports shared or nested section mappings as ambiguous when they match one note' {
        $profile = [ordered]@{ sections = [ordered]@{ lore = 'Shared'; rules = 'Shared/Sub' } }
        (Resolve-DmSectionDestination -Profile $profile -NotePath 'Shared/Sub/Note.md').code | Should -Be 'AMBIGUOUS_CONTEXT'
    }

    It 'returns stable read-only discovery candidates' {
        $first = Get-DmVaultDiscovery -Boundary $root.boundary
        $second = Get-DmVaultDiscovery -Boundary $root.boundary
        $first.changed | Should -BeFalse
        ($first.candidates | ConvertTo-Json -Compress) | Should -Be ($second.candidates | ConvertTo-Json -Compress)
    }
}
