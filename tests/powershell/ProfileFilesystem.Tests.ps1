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

    It 'rejects configured guidance with a non-Markdown visible path before reading or fingerprinting it' {
        $path = 'Lore/guide.txt'
        [System.IO.File]::WriteAllText((Join-Path -Path (Join-Path -Path $fixture.Root -ChildPath 'Lore') -ChildPath 'guide.txt'), 'Synthetic guidance.')
        $reads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -MockWith {
            $reads.Add([string]$Resolution.path)
            $reads.Add([string]$Resolution.resolvedPath)
            $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
            [pscustomobject][ordered]@{
                ok = $true
                code = $null
                bytes = $bytes
                version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
        }
        $profile = [ordered]@{ guidance = [ordered]@{ path = $path } }

        $reference = Test-DmProfileReference -Boundary $root.boundary -Path $path -Kind guidance
        { Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $profile } | Should -Throw

        $reference.passed | Should -BeFalse
        $reference.code | Should -Be 'REFERENCE_UNAVAILABLE'
        $reads | Should -Not -Contain $path
    }

    It 'rejects default guidance whose Markdown visible path resolves to a non-Markdown target before reads' {
        $path = '.dmassist-guidance.md'
        $target = Join-Path -Path (Join-Path -Path $fixture.Root -ChildPath 'Lore') -ChildPath 'guidance.txt'
        [System.IO.File]::WriteAllText($target, 'Synthetic guidance.')
        $reads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName VaultConfiguration -CommandName Resolve-DmVaultTarget -ParameterFilter {
            $Path -ceq '.dmassist-guidance.md'
        } -MockWith {
            [pscustomobject][ordered]@{
                path = $Path
                status = 'resolved'
                code = $null
                exists = $true
                itemType = 'file'
                resolvedPath = $target
                resolvedRelativePath = 'Lore/guidance.txt'
                viaLink = $true
                reason = ''
            }
        }
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -MockWith {
            $reads.Add([string]$Resolution.path)
            $reads.Add([string]$Resolution.resolvedPath)
            $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
            [pscustomobject][ordered]@{
                ok = $true
                code = $null
                bytes = $bytes
                version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
        }

        $reference = Test-DmProfileReference -Boundary $root.boundary -Path $path -Kind guidance
        { Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $null } | Should -Throw

        $reference.passed | Should -BeFalse
        $reference.code | Should -Be 'REFERENCE_UNAVAILABLE'
        $reads | Should -Not -Contain $path
        $reads | Should -Not -Contain $target
    }

    It 'rejects configured guidance whose Markdown visible path resolves to a non-Markdown target before reads' {
        $path = 'Lore/visible.md'
        $target = Join-Path -Path (Join-Path -Path $fixture.Root -ChildPath 'Lore') -ChildPath 'guidance.txt'
        [System.IO.File]::WriteAllText($target, 'Synthetic guidance.')
        $reads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName VaultConfiguration -CommandName Resolve-DmVaultTarget -ParameterFilter {
            $Path -ceq 'Lore/visible.md'
        } -MockWith {
            [pscustomobject][ordered]@{
                path = $Path
                status = 'resolved'
                code = $null
                exists = $true
                itemType = 'file'
                resolvedPath = $target
                resolvedRelativePath = 'Lore/guidance.txt'
                viaLink = $true
                reason = ''
            }
        }
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -MockWith {
            $reads.Add([string]$Resolution.path)
            $reads.Add([string]$Resolution.resolvedPath)
            $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
            [pscustomobject][ordered]@{
                ok = $true
                code = $null
                bytes = $bytes
                version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
        }
        $profile = [ordered]@{ guidance = [ordered]@{ path = $path } }

        $reference = Test-DmProfileReference -Boundary $root.boundary -Path $path -Kind guidance
        { Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $profile } | Should -Throw

        $reference.passed | Should -BeFalse
        $reference.code | Should -Be 'REFERENCE_UNAVAILABLE'
        $reads | Should -Not -Contain $path
        $reads | Should -Not -Contain $target
    }

    It 'does not read or fingerprint guidance after a lexical or resolved-boundary failure' {
        $reads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -MockWith {
            $reads.Add([string]$Resolution.path)
            $reads.Add([string]$Resolution.resolvedPath)
            $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
            [pscustomobject][ordered]@{
                ok = $true
                code = $null
                bytes = $bytes
                version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
        }

        $invalid = Test-DmProfileReference -Boundary $root.boundary -Path '../outside/secret.md' -Kind guidance
        { Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $null -ReferencePaths @('../outside/secret.md') } | Should -Throw

        $invalid.code | Should -Be 'PATH_INVALID'
        $reads | Should -Not -Contain '../outside/secret.md'

        Mock -ModuleName VaultConfiguration -CommandName Resolve-DmVaultTarget -ParameterFilter {
            $Path -ceq 'EscapingGuidance.md'
        } -MockWith {
            [pscustomobject][ordered]@{
                path = $Path
                status = 'outside'
                code = 'PATH_OUTSIDE_VAULT'
                exists = $false
                itemType = 'missing'
                resolvedPath = $null
                resolvedRelativePath = $null
                viaLink = $true
                reason = 'outside'
            }
        }

        $escaped = Test-DmProfileReference -Boundary $root.boundary -Path 'EscapingGuidance.md' -Kind guidance
        { Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $null -ReferencePaths @('EscapingGuidance.md') } | Should -Throw

        $escaped.passed | Should -BeFalse
        $escaped.code | Should -Be 'PATH_OUTSIDE_VAULT'
        $reads | Should -Not -Contain 'EscapingGuidance.md'
    }

    It 'continues to accept readable non-Markdown non-guidance references' {
        $path = 'Lore/party-reference.txt'
        $absolutePath = Join-Path -Path (Join-Path -Path $fixture.Root -ChildPath 'Lore') -ChildPath 'party-reference.txt'
        [System.IO.File]::WriteAllText($absolutePath, 'Synthetic party reference.')

        $result = Test-DmProfileReference -Boundary $root.boundary -Path $path -Kind party

        $result.passed | Should -BeTrue
        $result.version | Should -Match '^sha256:[0-9a-f]{64}$'
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

    It 'snapshots only guidance used by the current operation, not party notes or templates' {
        $profile = [ordered]@{
            version = 1
            guidance = [ordered]@{ path = '.dmassist-guidance.md' }
            party = [ordered]@{ note = 'Lore/Invented Town.md' }
            templates = [ordered]@{ adventure = 'Lore/Template.md' }
        }
        [System.IO.File]::WriteAllText((Join-Path $fixture.Root '.dmassist-guidance.md'), 'Synthetic guidance.')
        $reads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -MockWith {
            $reads.Add([string]$Resolution.path)
            $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
            [pscustomobject][ordered]@{
                ok = $true
                code = $null
                bytes = $bytes
                version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
        }

        $versions = Get-DmProfileDependencyVersions -Boundary $root.boundary -Profile $profile

        $versions.identity | Should -Contain '.dmassist-guidance.md'
        $reads | Should -Contain '.dmassist.yaml'
        $reads | Should -Contain '.dmassist-guidance.md'
        $reads | Should -Not -Contain 'Lore/Invented Town.md'
        $reads | Should -Not -Contain 'Lore/Template.md'
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
