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

    It 'requires campaign and group context before profile or note access (<Missing>)' -ForEach @(
        @{ Missing = 'both values'; Campaign = $null; Group = $null }
        @{ Missing = 'campaign'; Campaign = $null; Group = 'Synthetic Group' }
        @{ Missing = 'group'; Campaign = 'Synthetic Campaign'; Group = $null }
        @{ Missing = 'blank campaign'; Campaign = '  '; Group = 'Synthetic Group' }
        @{ Missing = 'blank group'; Campaign = 'Synthetic Campaign'; Group = '  ' }
    ) {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        Register-DmOperation -Name 'notes.group-check' -Modes @('inspect') -FactChanging $false `
            -RequiresCampaignGroup -MinTargets 1 -MaxTargets 1 | Out-Null
        try {
            $missingContext = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'notes.group-check' `
                -Targets @('Lore/Invented Town.md') -Extra @{ campaignGroup = [ordered]@{ campaign = $Campaign; group = $Group } }
            Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith { throw 'Profile read before campaign/group gate.' }
            Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'Campaign note read before campaign/group gate.' }

            $outcome = Invoke-DmInspect -Request $missingContext

            $outcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
            Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
            Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
        }
        finally { Unregister-DmOperation -Name 'notes.group-check' | Out-Null }
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

    It 'loads default local guidance when <ProfileState> and permits it to be absent' -ForEach @(
        @{ ProfileState = 'the profile is absent'; ProfileContent = $null }
        @{ ProfileState = 'the profile omits guidance'; ProfileContent = "version: 1`n" }
    ) {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        if ($null -ne $ProfileContent) { [System.IO.File]::WriteAllText($fixture.ProfilePath, $ProfileContent) }
        [System.IO.File]::WriteAllText((Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'), 'Synthetic local guidance.')

        $preflight = Invoke-DmPreflight -Request $request
        $context = Get-DmPreNoteContext -Preflight $preflight

        $context.passed | Should -BeTrue
        $context.context.guidanceLoaded | Should -BeTrue

        Remove-Item -LiteralPath (Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md')
        $absent = Get-DmPreNoteContext -Preflight $preflight
        $absent.passed | Should -BeTrue
        $absent.context.guidanceLoaded | Should -BeFalse
    }

    It 'does not read unrelated configured party or template notes during inspection' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        $profile = "version: 1`nparty:`n  note: Lore/Invented Town.md`ntemplates:`n  adventure: Lore/Template.md`n"
        [System.IO.File]::WriteAllText($fixture.ProfilePath, $profile)
        $templatePath = Join-Path -Path (Join-Path -Path $fixture.Root -ChildPath 'Lore') -ChildPath 'Template.md'
        [System.IO.File]::WriteAllText($templatePath, 'Synthetic template.')
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -ParameterFilter {
            $Resolution.path -cin @('Lore/Invented Town.md', 'Lore/Template.md')
        } -MockWith { throw 'Unrelated configured note was read.' }

        $inspectRequest = New-TestOperationRequest -VaultRoot $fixture.Root -Targets @('Adventures/Synthetic Arc.md')
        $outcome = Invoke-DmInspect -Request $inspectRequest

        $outcome.result.completionCode | Should -BeExactly 'OK'
        Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It -ParameterFilter {
            $Resolution.path -cin @('Lore/Invented Town.md', 'Lore/Template.md')
        }
    }

    It 'blocks inspection when default guidance exists but is not a file' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'))

        $outcome = Invoke-DmInspect -Request $request

        $outcome.result.completionCode | Should -BeExactly 'REFERENCE_UNAVAILABLE'
        @($outcome.result.unchangedTargets | ForEach-Object { $_.outcome }) | Should -Be @('not attempted')
    }

    It 'blocks the pre-note context when default guidance cannot be read' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        [System.IO.File]::WriteAllText((Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'), 'Synthetic local guidance.')
        Mock -ModuleName VaultConfiguration -CommandName Test-DmProfileReference -MockWith {
            [pscustomobject][ordered]@{
                passed = $false
                code = 'READ_FAILED'
                message = 'The configured reference could not be read.'
            }
        }
        $preflight = Invoke-DmPreflight -Request $request

        $context = Get-DmPreNoteContext -Preflight $preflight

        $context.passed | Should -BeFalse
        $context.result.completionCode | Should -BeExactly 'READ_FAILED'
        @($context.result.unchangedTargets | ForEach-Object { $_.outcome }) | Should -Be @('not attempted')
    }

    It 'blocks when designated guidance is deleted between validation and its dependency snapshot' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        $guidancePath = Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'
        [System.IO.File]::WriteAllText($guidancePath, 'Synthetic local guidance.')
        $guidanceBytes = [System.IO.File]::ReadAllBytes($guidancePath)
        $validatedVersion = 'sha256:' + [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($guidanceBytes)
        ).ToLowerInvariant()
        Mock -ModuleName VaultConfiguration -CommandName Test-DmProfileReference -MockWith {
            [System.IO.File]::Delete($guidancePath)
            [pscustomobject][ordered]@{
                passed = $true
                code = $null
                message = ''
                version = $validatedVersion
                path = $Path
            }
        }
        $preflight = Invoke-DmPreflight -Request $request

        $context = Get-DmPreNoteContext -Preflight $preflight

        $context.passed | Should -BeFalse
        $context.result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
        Should -Invoke -ModuleName VaultConfiguration -CommandName Test-DmProfileReference -Times 1 -Exactly -Scope It
    }

    It 'blocks on a profile snapshot changed after validation with requested targets retained' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`n")
        $preflight = Invoke-DmPreflight -Request $request
        $loaded = Read-DmVaultProfile -Boundary $preflight.boundary
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith {
            [System.IO.File]::AppendAllText($fixture.ProfilePath, "sections: {}`n")
            $loaded
        }

        $context = Get-DmPreNoteContext -Preflight $preflight

        $context.passed | Should -BeFalse
        $context.result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
        @($context.result.unchangedTargets | ForEach-Object { $_.path + ':' + $_.outcome }) |
            Should -Be @('Lore/Invented Town.md:not attempted')
    }

    It 'returns sanitized target outcomes when dependency snapshots throw' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        Mock -ModuleName VaultConfiguration -CommandName Get-DmProfileDependencyVersions -MockWith {
            throw 'C:\private\vault\secret-profile-path'
        }
        $preflight = Invoke-DmPreflight -Request $request

        $context = Get-DmPreNoteContext -Preflight $preflight

        $context.passed | Should -BeFalse
        $context.result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
        $serialized = $context.result | ConvertTo-Json -Depth 10 -Compress
        $serialized | Should -Not -Match 'C:\\private'
        @($context.result.unchangedTargets | ForEach-Object { $_.path + ':' + $_.outcome }) |
            Should -Be @('Lore/Invented Town.md:not attempted')
    }

    It 'does not expose an invalid configured profile path in structured errors' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`n")
        Mock -ModuleName VaultConfiguration -CommandName Test-DmProfileFilesystem -MockWith {
            [pscustomobject][ordered]@{
                passed = $false
                code = 'PROFILE_FILESYSTEM_INVALID'
                message = 'A configured vault location is unavailable or invalid.'
                path = 'C:\private\vault\secret'
            }
        }
        $preflight = Invoke-DmPreflight -Request $request

        $context = Get-DmPreNoteContext -Preflight $preflight

        $context.passed | Should -BeFalse
        $context.result.completionCode | Should -BeExactly 'PROFILE_FILESYSTEM_INVALID'
        ($context.result | ConvertTo-Json -Depth 10 -Compress) | Should -Not -Match 'C:\\private'
    }

    It 'returns a sanitized failed inspection envelope when a target read throws' {
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith {
            throw 'C:\private\vault\secret-note.md'
        }

        $outcome = Invoke-DmInspect -Request $request

        $outcome.result.completionCode | Should -BeExactly 'READ_FAILED'
        $serialized = $outcome.result | ConvertTo-Json -Depth 10 -Compress
        $serialized | Should -Not -Match 'C:\\private'
        @($outcome.result.unchangedTargets | ForEach-Object { $_.path + ':' + $_.outcome }) |
            Should -Be @('Lore/Invented Town.md:failed')
    }
}
