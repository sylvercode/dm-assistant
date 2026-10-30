BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, VaultInspection, PluginResources, VaultConfiguration
}

Describe 'Vault profile state and pre-note sequence' {
    BeforeEach {
        Set-TestDependencyReadiness -State ready
        $fixture = New-TestVaultFixture
        $request = New-TestOperationRequest -VaultRoot $fixture.Root -Targets @('Lore/Invented Town.md')
    }
    AfterEach { Remove-TestVaultFixture -Fixture $fixture }

    It 'blocks profile access before exact-vault authorization when no provider is supplied' {
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith { throw 'Profile read before authorization.' }
        $outcome = Invoke-DmInspect -Request $request
        $outcome.result.completionCode | Should -Be 'VAULT_AUTHORIZATION_UNPROVEN'
        Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
    }

    It 'uses read-only discovery when the profile is absent and permits a direct inspect lookup' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $preflight = Invoke-DmPreflight -Request $request
        (Get-DmPreNoteContext -Preflight $preflight).discovery.changed | Should -BeFalse
        $outcome = Invoke-DmInspect -Request $request
        $outcome.result.completionCode | Should -Be 'OK'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'does not fall back to discovery for a present invalid profile' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nunknown: value`n")
        $outcome = Invoke-DmInspect -Request $request
        $outcome.result.completionCode | Should -Be 'PROFILE_SCHEMA_INVALID'
    }

    It 'blocks mapping-dependent requests without designated local guidance' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        Register-DmOperation -Name 'notes.mapping-check' -Modes @('inspect') -FactChanging $false -RequiresMappings -MinTargets 1 -MaxTargets 1 | Out-Null
        try {
            $mapped = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'notes.mapping-check' -Targets @('Lore/Invented Town.md')
            $outcome = Invoke-DmInspect -Request $mapped
            $outcome.result.completionCode | Should -Be 'AMBIGUOUS_CONTEXT'
        }
        finally { Unregister-DmOperation -Name 'notes.mapping-check' | Out-Null }
    }

    It 'records the ordered pre-note gates before campaign-note inspection' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nguidance:`n  path: .dmassist-guidance.md`n")
        [System.IO.File]::WriteAllText((Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'), 'Synthetic local guidance.')
        $preflight = Invoke-DmPreflight -Request $request
        $context = Get-DmPreNoteContext -Preflight $preflight
        $context.passed | Should -BeTrue
        $context.sequence | Should -Be @('vault-root-selected', 'dependency-readiness', 'vault-authorization', 'shared-reference', 'profile-validated', 'guidance-loaded', 'campaign-group')
        $outcome = Invoke-DmInspect -Request $request
        $outcome.result.completionCode | Should -Be 'OK'
    }
}
