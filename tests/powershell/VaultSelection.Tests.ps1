BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, VaultConfiguration, VaultInspection, ChangePreview

    function Get-TestSha256 {
        param([string]$Path)
        'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path))).ToLowerInvariant()
    }

    function Get-LinkSafeSnapshot {
        # Like Get-TestVaultSnapshot, but never descends into links (a cyclic junction would recurse forever).
        param([Parameter(Mandatory)][string]$Path)
        $entries = [System.Collections.Generic.List[string]]::new()
        $pending = [System.Collections.Generic.Stack[string]]::new()
        $pending.Push($Path)
        while ($pending.Count -gt 0) {
            $dir = $pending.Pop()
            foreach ($item in [System.IO.Directory]::GetFileSystemEntries($dir)) {
                $relative = [System.IO.Path]::GetRelativePath($Path, $item)
                $attributes = [System.IO.File]::GetAttributes($item)
                $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $info = if ($isDirectory) { [System.IO.DirectoryInfo]::new($item) } else { [System.IO.FileInfo]::new($item) }
                    $entries.Add("L|$relative|$($info.LinkTarget)")
                }
                elseif ($isDirectory) {
                    $entries.Add("D|$relative")
                    $pending.Push($item)
                }
                else {
                    $hash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($item)))
                    $entries.Add("F|$relative|$hash|$([System.IO.File]::GetLastWriteTimeUtc($item).Ticks)")
                }
            }
        }
        $array = $entries.ToArray()
        [System.Array]::Sort($array, [System.StringComparer]::Ordinal)
        $array
    }

    function New-TestDirectoryLink {
        # Directory symbolic link when permitted, else a junction. Returns the kind created or $null.
        param([string]$Path, [string]$Target)
        try { [void][System.IO.Directory]::CreateSymbolicLink($Path, $Target); return 'symlink' } catch { $null = $_ }
        if ($IsWindows) {
            try { $null = New-Item -ItemType Junction -Path $Path -Target $Target -ErrorAction Stop; return 'junction' } catch { $null = $_ }
        }
        $null
    }

    function New-TestFileLink {
        # File symbolic link (target kept verbatim, so relative targets stay relative). Returns $true when created.
        param([string]$Path, [string]$Target)
        try { [void][System.IO.File]::CreateSymbolicLink($Path, $Target); return $true } catch { return $false }
    }

    function Remove-TestLink {
        param([string]$Path)
        $attributes = $null
        try { $attributes = [System.IO.File]::GetAttributes($Path) } catch { return }
        if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) { [System.IO.Directory]::Delete($Path, $false) } else { [System.IO.File]::Delete($Path) }
    }

    function Assert-NotCompleted {
        param($Outcome, [string]$Code, [string[]]$Targets)
        $r = $Outcome.result
        $r.completionStatus | Should -BeExactly 'not completed'
        $r.completionCode | Should -BeExactly $Code
        $r.errorDetails.code | Should -BeExactly $Code
        $r.changedTargets.Count | Should -Be 0
        @($Outcome.inspection).Count | Should -Be 0
        (Test-DmResult -Result $r -RequestedTargets $Targets).isValid | Should -BeTrue
    }

    $script:FileLinkSkipReason = 'Creating file symbolic links requires Windows Developer Mode or elevation in this environment; directory cases use junctions instead.'
}

Describe 'Vault selection and inspection' {
    BeforeEach {
        $fixture = New-TestVaultFixture -ProfileText "version: 1`n"
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $targets = [string[]]@('Adventures/Synthetic Arc.md', 'Lore/Invented Town.md')
        $request = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets
    }

    AfterEach {
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before -Because 'selection and inspection must leave fixture bytes unchanged'
        Remove-TestVaultFixture -Fixture $fixture
    }

    Describe 'Production gate: no authorization provider' {
        It 'runs the authorization gate first and blocks inspection before root resolution or note access' {
            Set-TestDependencyReadiness -State ready
            Mock -ModuleName RuntimePreflight -CommandName Resolve-DmVaultRoot -MockWith { throw 'Vault root resolved before authorization.' }
            Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'Note read before authorization.' }
            $outcome = Invoke-DmInspect -Request $request
            Assert-NotCompleted -Outcome $outcome -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
            @($outcome.result.unchangedTargets.outcome | Select-Object -Unique) | Should -Be @('not attempted')
            Should -Invoke -ModuleName RuntimePreflight -CommandName Resolve-DmVaultRoot -Times 0 -Exactly -Scope It
            Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
        }

        It 'reports VAULT_AUTHORIZATION_UNPROVEN rather than VAULT_TARGET_INVALID for a missing root' {
            Set-TestDependencyReadiness -State ready
            $req = New-TestOperationRequest -VaultRoot (Join-Path -Path $fixture.ParentPath -ChildPath 'no-such-vault') -Targets $targets
            Assert-NotCompleted -Outcome (Invoke-DmInspect -Request $req) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
        }

        It 'refuses to resolve a root without a passed authorization gate' {
            $denied = [pscustomobject]@{ gate = 'vault-authorization'; passed = $false; result = $null; evidence = @() }
            { Resolve-DmVaultRoot -Gate $denied -VaultRoot $fixture.Root -Operation 'notes.inspect' } | Should -Throw
            $wrong = [pscustomobject]@{ gate = 'dependency-readiness'; passed = $true; result = $null; evidence = @() }
            { Resolve-DmVaultRoot -Gate $wrong -VaultRoot $fixture.Root -Operation 'notes.inspect' } | Should -Throw
        }
    }

    Describe 'Downstream tier: harness-injected provider' {
        BeforeEach {
            Set-TestDependencyReadiness -State ready
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        }

        Describe 'Inspection' {
            It 'reports existence, type, and byte fingerprints without content' {
                $outcome = Invoke-DmInspect -Request $request
                $r = $outcome.result
                $r.completionStatus | Should -BeExactly 'complete'
                $r.completionCode | Should -BeExactly 'OK'
                $r.changedTargets.Count | Should -Be 0
                @($r.unchangedTargets.path) | Should -Be $targets
                @($r.unchangedTargets.outcome | Select-Object -Unique) | Should -Be @('unchanged')
                (Test-DmResult -Result $r -RequestedTargets $targets).isValid | Should -BeTrue
                $outcome.inspection.Count | Should -Be 2
                for ($i = 0; $i -lt 2; $i++) {
                    $outcome.inspection[$i].path | Should -BeExactly $targets[$i]
                    $outcome.inspection[$i].exists | Should -BeTrue
                    $outcome.inspection[$i].itemType | Should -BeExactly 'file'
                    $outcome.inspection[$i].version | Should -BeExactly (Get-TestSha256 -Path $fixture.NotePaths[$i])
                    $outcome.inspection[$i].viaLink | Should -BeFalse
                }
                $json = $outcome | ConvertTo-Json -Depth 8
                $json | Should -Not -Match 'Invented adventure text|See \[\['
                $json | Should -Not -Match ([regex]::Escape(($fixture.ParentPath | ConvertTo-Json).Trim('"')))
            }

            It 'reports a missing target without guessing or creating it' {
                $t = [string[]]@('Adventures/Missing Note.md', 'New Folder/New Note.md')
                $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $t)
                $outcome.result.completionCode | Should -BeExactly 'OK'
                foreach ($entry in $outcome.inspection) {
                    $entry.exists | Should -BeFalse
                    $entry.itemType | Should -BeExactly 'missing'
                    $entry.version | Should -BeExactly 'absent'
                }
                [System.IO.Directory]::Exists((Join-Path -Path $fixture.Root -ChildPath 'New Folder')) | Should -BeFalse
            }

            It 'reports a folder target as a directory without a version' {
                $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets @('Lore'))
                $outcome.inspection[0].itemType | Should -BeExactly 'directory'
                $outcome.inspection[0].version | Should -BeNullOrEmpty
            }

            It 'completes a registered zero-target inspect request with an empty inspection' {
                Register-DmOperation -Name 'notes.empty-inspect' -Modes @('inspect') -FactChanging $false `
                    -MinTargets 0 -MaxTargets 0 | Out-Null
                try {
                    $emptyRequest = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'notes.empty-inspect' -Targets @()
                    $outcome = Invoke-DmInspect -Request $emptyRequest

                    $outcome.result.completionCode | Should -BeExactly 'OK'
                    $outcome.result.unchangedTargets | Should -BeNullOrEmpty
                    $outcome.inspection | Should -BeNullOrEmpty
                    (Test-DmResult -Result $outcome.result -RequestedTargets @()).isValid | Should -BeTrue
                }
                finally { Unregister-DmOperation -Name 'notes.empty-inspect' | Out-Null }
            }

            It 'rejects targets that resolve to the same file before reading or planning changes' {
                [System.IO.File]::WriteAllText(
                    (Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'),
                    'Synthetic local guidance.'
                )
                $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
                $aliasDirectory = Join-Path -Path $fixture.Root -ChildPath 'AdventureAlias'
                if ($null -eq (New-TestDirectoryLink -Path $aliasDirectory -Target (Join-Path -Path $fixture.Root -ChildPath 'Adventures'))) {
                    Set-ItResult -Skipped -Because 'directory links cannot be created here'
                    return
                }
                $duplicateTargets = [string[]]@('Adventures/Synthetic Arc.md', 'AdventureAlias/Synthetic Arc.md')
                try {
                    Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'duplicate target was read' }
                    $inspectOutcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $duplicateTargets)
                    $inspectOutcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
                    Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It

                    $previewRequest = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.replace-text' -Mode preview `
                        -Targets $duplicateTargets -Arguments ([ordered]@{ oldText = 'Invented'; newText = 'Revised' })
                    $previewPreflight = Invoke-DmPreflight -Request $previewRequest
                    $previewContext = Get-DmPreNoteContext -Preflight $previewPreflight
                    Mock -ModuleName ChangePreview -CommandName Read-DmVaultTargetBytes -MockWith { throw 'duplicate target was planned' }
                    $previewPlan = Get-DmChangePlan -Preflight $previewPreflight -Context $previewContext
                    $previewPlan.code | Should -BeExactly 'INVALID_REQUEST'
                    Should -Invoke -ModuleName ChangePreview -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
                }
                finally { Remove-TestLink -Path $aliasDirectory }
            }

            It 'rejects case-variant target aliases before inspection or change planning on Windows' {
                if (-not $IsWindows) {
                    Set-ItResult -Skipped -Because 'Windows path comparison is required for this regression'
                    return
                }
                [System.IO.File]::WriteAllText(
                    (Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'),
                    'Synthetic local guidance.'
                )
                $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
                $duplicateTargets = [string[]]@('Adventures/Synthetic Arc.md', 'adventures/synthetic arc.md')

                Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'duplicate target was read' }
                $inspectOutcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $duplicateTargets)
                Assert-NotCompleted -Outcome $inspectOutcome -Code 'INVALID_REQUEST' -Targets $duplicateTargets
                Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It

                $previewRequest = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.replace-text' -Mode preview `
                    -Targets $duplicateTargets -Arguments ([ordered]@{ oldText = 'Invented'; newText = 'Revised' })
                $previewPreflight = Invoke-DmPreflight -Request $previewRequest
                $previewContext = Get-DmPreNoteContext -Preflight $previewPreflight
                Mock -ModuleName ChangePreview -CommandName Read-DmVaultTargetBytes -MockWith { throw 'duplicate target was planned' }
                $previewPlan = Get-DmChangePlan -Preflight $previewPreflight -Context $previewContext
                $previewPlan.code | Should -BeExactly 'INVALID_REQUEST'
                Should -Invoke -ModuleName ChangePreview -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
            }

            It 'treats variable and home-directory markers as literal names' {
                $t = [string[]]@('$HOME/x.md', '%TEMP%/x.md', '~/x.md', '${HOME}/x.md')
                $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $t)
                $outcome.result.completionCode | Should -BeExactly 'OK'
                @($outcome.inspection.exists | Select-Object -Unique) | Should -Be @($false)
                @($outcome.inspection.resolvedTarget) | Should -Be $t -Because 'markers are literal names, never expanded'
            }

            It 'returns READ_FAILED at the target whose read fails, after earlier targets' {
                $t = [string[]]@('Lore/Invented Town.md', 'Adventures/Synthetic Arc.md')
                $lock = [System.IO.File]::Open($fixture.NotePaths[0], [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
                try { $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $t) }
                finally { $lock.Dispose() }
                $r = $outcome.result
                $r.completionStatus | Should -BeExactly 'not completed'
                $r.completionCode | Should -BeExactly 'READ_FAILED'
                @($r.unchangedTargets.outcome) | Should -Be @('unchanged', 'failed')
                $r.remainingWork | Should -Contain 'Inspect Lore/Invented Town.md after resolving the problem.'
                (Test-DmResult -Result $r -RequestedTargets $t).isValid | Should -BeTrue
                $r.errorDetails | ConvertTo-Json -Depth 5 | Should -Not -Match ([regex]::Escape(($fixture.ParentPath | ConvertTo-Json).Trim('"')))
            }

            It 'stops before target access when the dependency snapshot changes' {
                Mock -ModuleName VaultInspection -CommandName Test-DmProfileDependencyVersions -MockWith {
                    [pscustomobject]@{ passed = $false; code = 'TARGET_CONFLICT'; changedIdentities = @('.dmassist.yaml') }
                }
                Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'target read attempted' }
                $outcome = Invoke-DmInspect -Request $request
                Assert-NotCompleted -Outcome $outcome -Code 'TARGET_CONFLICT' -Targets $targets
                @($outcome.result.unchangedTargets.outcome | Select-Object -Unique) | Should -Be @('not attempted')
                $outcome.result.errorDetails.details.changedDependencies | Should -Contain '.dmassist.yaml'
                Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
            }

            It 'rechecks dependencies immediately before reading target files' {
                $global:DmInspectionDependencyChecks = 0
                Mock -ModuleName VaultInspection -CommandName Test-DmProfileDependencyVersions -MockWith {
                    $global:DmInspectionDependencyChecks++
                    [pscustomobject]@{
                        passed = ($global:DmInspectionDependencyChecks -eq 1)
                        code = if ($global:DmInspectionDependencyChecks -eq 1) { $null } else { 'TARGET_CONFLICT' }
                        changedIdentities = @('.dmassist.yaml')
                    }
                }
                Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'target read attempted' }
                $outcome = Invoke-DmInspect -Request $request
                Assert-NotCompleted -Outcome $outcome -Code 'TARGET_CONFLICT' -Targets $targets
                @($outcome.result.unchangedTargets.outcome | Select-Object -Unique) | Should -Be @('not attempted')
                $outcome.result.errorDetails.details.changedDependencies | Should -Contain '.dmassist.yaml'
                Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
                Remove-Variable -Name DmInspectionDependencyChecks -Scope Global
            }

            It 'returns TARGET_CONFLICT when dependencies change before inspection success' {
                $global:DmInspectionDependencyChecks = 0
                Mock -ModuleName VaultInspection -CommandName Test-DmProfileDependencyVersions -MockWith {
                    $global:DmInspectionDependencyChecks++
                    [pscustomobject]@{
                        passed = ($global:DmInspectionDependencyChecks -lt 3)
                        code = if ($global:DmInspectionDependencyChecks -lt 3) { $null } else { 'TARGET_CONFLICT' }
                        changedIdentities = @('.dmassist.yaml')
                    }
                }
                $outcome = Invoke-DmInspect -Request $request
                Assert-NotCompleted -Outcome $outcome -Code 'TARGET_CONFLICT' -Targets $targets
                @($outcome.result.remainingWork).Count | Should -Be $targets.Count
                $outcome.result.errorDetails.details.changedDependencies | Should -Contain '.dmassist.yaml'
                Remove-Variable -Name DmInspectionDependencyChecks -Scope Global
            }

            It 'reads notes when the vault directory is readable but denies delete access' {
                if (-not $IsWindows) {
                    Set-ItResult -Skipped -Because 'Windows ACLs are required for this permission regression'
                    return
                }
                $directoryPath = Join-Path -Path $fixture.Root -ChildPath 'Lore'
                $originalAcl = Get-Acl -LiteralPath $directoryPath
                try {
                    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                    $denyDelete = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $identity.User,
                        [System.Security.AccessControl.FileSystemRights]::Delete,
                        [System.Security.AccessControl.AccessControlType]::Deny
                    )
                    $restrictedAcl = Get-Acl -LiteralPath $directoryPath
                    [void]$restrictedAcl.AddAccessRule($denyDelete)
                    Set-Acl -LiteralPath $directoryPath -AclObject $restrictedAcl
                }
                catch {
                    Set-ItResult -Skipped -Because 'The test environment does not permit setting a directory ACL'
                    return
                }

                try {
                    $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets @('Lore/Invented Town.md'))
                    $outcome.result.completionCode | Should -BeExactly 'OK'
                    $outcome.inspection[0].version | Should -BeExactly (Get-TestSha256 -Path $fixture.NotePaths[1])
                }
                finally { Set-Acl -LiteralPath $directoryPath -AclObject $originalAcl }
            }

            It 'returns READ_FAILED before any read when a path component is inaccessible' {
                $real = & (Get-Module -Name VaultBoundary) { ${function:Get-DmFileSystemEntry} }
                Mock -ModuleName VaultBoundary -CommandName Get-DmFileSystemEntry -MockWith ({ param($Path) & $real -Path $Path }.GetNewClosure())
                Mock -ModuleName VaultBoundary -CommandName Get-DmFileSystemEntry -ParameterFilter { $Path.EndsWith('Lore') } -MockWith {
                    [pscustomobject]@{ state = 'inaccessible'; isDirectory = $false; linkTarget = $null }
                }
                Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'read attempted' }
                Assert-NotCompleted -Outcome (Invoke-DmInspect -Request $request) -Code 'READ_FAILED' -Targets $targets
                Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
            }

            It 'preserves a legal punctuated target in a blocked inspection result' {
                $t = [string[]]@('Scenes(/Locked.md')
                Mock -ModuleName VaultInspection -CommandName Resolve-DmVaultTarget -MockWith {
                    [pscustomobject]@{ code = 'READ_FAILED'; path = $Path; reason = 'The target component is unavailable.' }
                }
                Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'target read attempted' }

                $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $t)

                Assert-NotCompleted -Outcome $outcome -Code 'READ_FAILED' -Targets $t
                $outcome.result.errorDetails.details.target | Should -BeExactly $t[0]
                $outcome.result.unchangedTargets[0].outcome | Should -BeExactly 'not attempted'
                Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
            }

            It 'rejects a non-inspect mode for inspection' {
                $req = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.replace-text' -Mode 'preview' -Targets $targets -Arguments @{ oldText = 'Invented'; newText = 'Synthetic' }
                Assert-NotCompleted -Outcome (Invoke-DmInspect -Request $req) -Code 'INVALID_REQUEST' -Targets $targets
            }
        }

        Describe 'Working-directory independence' {
            It 'selects the same vault, campaign/group, operation, and result from every working directory' {
                $dirs = @($TestDrive, $fixture.OutsidePath, $fixture.Root, (Get-TestRepositoryRoot), [System.IO.Path]::GetTempPath())
                $runs = foreach ($dir in $dirs) {
                    Push-Location -LiteralPath $dir
                    try {
                        $pre = Invoke-DmPreflight -Request $request
                        $inspect = Invoke-DmInspect -Request $request
                        [pscustomobject]@{
                            selection  = ($pre.request | Select-Object operation, vaultRoot, campaignGroup, targets | ConvertTo-Json -Depth 5 -Compress)
                            canonical  = $pre.boundary.canonicalRoot
                            inspection = ($inspect | ConvertTo-Json -Depth 8 -Compress)
                        }
                    }
                    finally { Pop-Location }
                }
                @($runs.selection | Select-Object -Unique).Count | Should -Be 1
                @($runs.canonical | Select-Object -Unique).Count | Should -Be 1
                @($runs.inspection | Select-Object -Unique).Count | Should -Be 1
                $runs[0].canonical | Should -Be $fixture.Root
            }

            It 'never falls back to the current or plugin directory for a relative or missing root' {
                foreach ($dir in @($fixture.ParentPath, (Get-TestRepositoryRoot))) {
                    Push-Location -LiteralPath $dir
                    try {
                        $relative = New-TestOperationRequest -VaultRoot 'C:\placeholder' -Targets $targets
                        $relative['vaultRoot'] = 'vault'
                        Assert-NotCompleted -Outcome (Invoke-DmInspect -Request $relative) -Code 'INVALID_REQUEST' -Targets $targets
                        $missing = New-TestOperationRequest -VaultRoot 'C:\placeholder' -Targets $targets
                        $missing.Remove('vaultRoot')
                        Assert-NotCompleted -Outcome (Invoke-DmInspect -Request $missing) -Code 'INVALID_REQUEST' -Targets $targets
                    }
                    finally { Pop-Location }
                }
            }
        }

        Describe 'Explicit vault root selection' {
            It 'returns VAULT_TARGET_INVALID for a root that is <Case>' -ForEach @(
                @{ Case = 'missing'; Make = { param($f) Join-Path -Path $f.ParentPath -ChildPath 'no-such-vault' } }
                @{ Case = 'a file'; Make = { param($f) $f.NotePaths[0] } }
                @{ Case = 'ambiguous through a parent component'; Make = { param($f) [System.IO.Path]::Join($f.Root, '..', 'vault') } }
                @{ Case = 'ambiguous through a current-folder component'; Make = { param($f) [System.IO.Path]::Join($f.Root, '.') } }
                @{ Case = 'on a missing drive'; Make = {
                        param($f) $null = $f
                        $used = [System.IO.Directory]::GetLogicalDrives() | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() }
                        $free = [char[]]'ZYXWVUTSRQPONMLKJIHGFED' | Where-Object { [string]$_ -notin $used } | Select-Object -First 1
                        "$($free):\dmassist-no-such-vault"
                    }
                }
            ) {
                $root = & $Make $fixture
                if ($Case -like 'ambiguous*') {
                    # The harness canonicalizes lexically; authorize the exact string so only root resolution can refuse it.
                    Mock -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -ParameterFilter { $true } -MockWith {
                        param($Dependency, $VaultRoot)
                        $null = $VaultRoot
                        [pscustomobject]@{ dependencyId = $Dependency.dependencyId; vaultAuthorizationState = 'authorized'; evidence = 'test-only' }
                    }
                }
                else { Enable-TestAuthorizationProvider -VaultRoot $root }
                $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $root -Targets $targets)
                Assert-NotCompleted -Outcome $outcome -Code 'VAULT_TARGET_INVALID' -Targets $targets
                $outcome.result.errorDetails.message | Should -Not -Match ([regex]::Escape($fixture.ParentPath))
            }

            It 'resolves a linked root to its canonical folder' {
                $link = Join-Path -Path $fixture.ParentPath -ChildPath 'vault-link'
                $kind = New-TestDirectoryLink -Path $link -Target $fixture.Root
                if ($null -eq $kind) { Set-ItResult -Skipped -Because 'neither directory symbolic links nor junctions can be created here'; return }
                try {
                    Enable-TestAuthorizationProvider -VaultRoot $link
                    $pre = Invoke-DmPreflight -Request (New-TestOperationRequest -VaultRoot $link -Targets $targets)
                    $pre.passed | Should -BeTrue
                    $pre.boundary.canonicalRoot | Should -Be $fixture.Root
                    $pre.boundary.selectedRoot | Should -BeExactly $link
                    (Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $link -Targets $targets)).result.completionCode | Should -BeExactly 'OK'
                }
                finally { Remove-TestLink -Path $link }
            }
        }

        Describe 'Malformed requests' {
            It 'returns INVALID_REQUEST before readiness for <Case>' -ForEach @(
                @{ Case = 'an unknown top-level field'; Edit = { param($r) $r['vaultHint'] = 'x' } }
                @{ Case = 'a wrong-case field name'; Edit = { param($r) $v = $r['mode']; $r.Remove('mode'); $r['Mode'] = $v } }
                @{ Case = 'an unregistered operation'; Edit = { param($r) $r['operation'] = 'notes.teleport' } }
                @{ Case = 'an operation name with path syntax'; Edit = { param($r) $r['operation'] = '../notes.inspect' } }
                @{ Case = 'a mode the operation does not support'; Edit = { param($r) $r['mode'] = 'preview' } }
                @{ Case = 'an unknown argument'; Edit = { param($r) $r['arguments'] = @{ recurse = $true } } }
                @{ Case = 'non-object arguments'; Edit = { param($r) $r['arguments'] = 'oldText=x' } }
                @{ Case = 'missing arguments'; Edit = { param($r) $r.Remove('arguments') } }
                @{ Case = 'targets as a single string'; Edit = { param($r) $r['targets'] = 'Adventures/Synthetic Arc.md' } }
                @{ Case = 'a non-string target'; Edit = { param($r) $r['targets'] = @('Adventures/Synthetic Arc.md', 7) } }
                @{ Case = 'duplicate targets'; Edit = { param($r) $r['targets'] = @('Adventures/Synthetic Arc.md', 'Adventures/Synthetic Arc.md') } }
                @{ Case = 'no targets'; Edit = { param($r) $r['targets'] = @() } }
                @{ Case = 'missing targets'; Edit = { param($r) $r.Remove('targets') } }
                @{ Case = 'missing campaignGroup'; Edit = { param($r) $r.Remove('campaignGroup') } }
                @{ Case = 'campaignGroup without group'; Edit = { param($r) $r['campaignGroup'] = @{ campaign = 'Synthetic Campaign' } } }
                @{ Case = 'campaignGroup with an empty campaign'; Edit = { param($r) $r['campaignGroup'] = @{ campaign = ''; group = $null } } }
                @{ Case = 'a non-string contract version'; Edit = { param($r) $r['contractVersion'] = 1 } }
                @{ Case = 'a multi-line request id'; Edit = { param($r) $r['requestId'] = "a`nb" } }
                @{ Case = 'a home-relative vault root'; Edit = { param($r) $r['vaultRoot'] = '~\vault' } }
                @{ Case = 'a variable vault root'; Edit = { param($r) $r['vaultRoot'] = '$HOME\vault' } }
                @{ Case = 'a device-path vault root'; Edit = { param($r) $r['vaultRoot'] = '\\?\C:\vault' } }
                @{ Case = 'a wildcard vault root'; Edit = { param($r) $r['vaultRoot'] = 'C:\vault*' } }
                @{ Case = 'approvedPreviewId outside apply'; Edit = { param($r) $r['approvedPreviewId'] = 'sha256:' + ('a' * 64) } }
                @{ Case = 'declinedReviewId outside apply'; Edit = { param($r) $r['declinedReviewId'] = 'review-1' } }
                @{ Case = 'the removed encoding-conversion acknowledgment field'; Edit = { param($r) $r['allowEncodingConversion'] = $true } }
                @{ Case = 'reviewedVersions without approvedPreviewId'; Edit = { param($r) $r['reviewedVersions'] = @() } }
            ) {
                Set-TestDependencyReadiness -State ready
                $req = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets
                & $Edit $req
                $outcome = Invoke-DmInspect -Request $req
                $outcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
                $outcome.result.completionStatus | Should -BeExactly 'not completed'
                @($outcome.inspection).Count | Should -Be 0
                Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -Times 0 -Exactly -Scope It
            }

            It 'never echoes request values in problems' {
                $req = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets -Extra @{ operation = 'secret.operation-name'; requestId = "x`n" }
                $check = Test-DmOperationRequest -Request $req
                $check.code | Should -BeExactly 'INVALID_REQUEST'
                ($check.problems -join ' ') | Should -Not -Match 'secret\.operation-name'
            }
        }

        Describe 'Apply-mode approval fields' {
            BeforeEach {
                $digest = 'sha256:' + ('b' * 64)
                $apply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.replace-text' -Mode 'apply' -Targets $targets `
                    -Arguments ([ordered]@{ oldText = 'Invented'; newText = '' }) -Extra ([ordered]@{
                        approvedPreviewId          = $digest
                        reviewedVersions           = @(
                            @{ observedVersion = $digest; replacementVersion = $digest; conversionDecision = 'preserve' }
                            @{ path = 'Lore/Invented Town.md'; observedVersion = 'absent'; replacementVersion = $digest; conversionDecision = 'preserve' }
                        )
                        reviewedDependencyVersions = @(@{ identity = 'plugin:skills/vault-orientation/assets/dmassist.schema.json'; version = $digest })
                    })
            }

            It 'accepts a complete approved apply request and normalizes it' {
                $check = Test-DmOperationRequest -Request $apply
                $check.isValid | Should -BeTrue -Because ($check.problems -join ' ')
                $check.request.reviewedVersions[0].path | Should -BeExactly $targets[0]
                $check.request.PSObject.Properties.Name | Should -Not -Contain 'allowEncodingConversion'
                $check.request.arguments['newText'] | Should -BeExactly ''
                @($check.request.PSObject.Properties.Name) | Should -Be @('contractVersion', 'requestId', 'operation', 'vaultRoot', 'campaignGroup', 'mode', 'arguments', 'targets',
                    'approvedPreviewId', 'reviewedVersions', 'reviewedDependencyVersions', 'declinedReviewId')
            }

            It 'rejects <Case>' -ForEach @(
                @{ Case = 'a malformed approvedPreviewId'; Edit = { param($r) $r['approvedPreviewId'] = 'sha256:XYZ' } }
                @{ Case = 'approval without reviewedVersions'; Edit = { param($r) $r.Remove('reviewedVersions') } }
                @{ Case = 'approval without reviewedDependencyVersions'; Edit = { param($r) $r.Remove('reviewedDependencyVersions') } }
                @{ Case = 'too few reviewedVersions'; Edit = { param($r) $r['reviewedVersions'] = @($r['reviewedVersions'][0]) } }
                @{ Case = 'reviewedVersions out of targets order'; Edit = { param($r) $r['reviewedVersions'][0]['path'] = 'Lore/Invented Town.md' } }
                @{ Case = 'an unknown conversionDecision'; Edit = { param($r) $r['reviewedVersions'][0]['conversionDecision'] = 'convert' } }
                @{ Case = 'a malformed dependency version'; Edit = { param($r) $r['reviewedDependencyVersions'] = @(@{ identity = 'x'; version = 'v1' }) } }
                @{ Case = 'declinedReviewId with approvedPreviewId'; Edit = { param($r) $r['declinedReviewId'] = 'review-1' } }
                @{ Case = 'a removed conversion acknowledgment field'; Edit = { param($r) $r['allowEncodingConversion'] = $true } }
                @{ Case = 'a missing required argument'; Edit = { param($r) $r['arguments'] = @{ newText = 'x' } } }
                @{ Case = 'an empty oldText'; Edit = { param($r) $r['arguments'] = @{ oldText = ''; newText = 'x' } } }
                @{ Case = 'a non-string argument'; Edit = { param($r) $r['arguments'] = @{ oldText = 'a'; newText = 3 } } }
            ) {
                & $Edit $apply
                $check = Test-DmOperationRequest -Request $apply
                $check.isValid | Should -BeFalse
                $check.code | Should -BeExactly 'INVALID_REQUEST'
                $check.request | Should -BeNullOrEmpty
            }

            It 'accepts a declined review without approval' {
                foreach ($k in 'approvedPreviewId', 'reviewedVersions', 'reviewedDependencyVersions') { $apply.Remove($k) }
                $apply['declinedReviewId'] = 'review-1'
                (Test-DmOperationRequest -Request $apply).isValid | Should -BeTrue
            }
        }

        Describe 'Operation registry' {
            AfterEach { $null = Unregister-DmOperation -Name 'synthetic.lookup' }

            It 'registers the built-in operations' {
                $inspect = Get-DmOperation -Name 'notes.inspect'
                $inspect.modes | Should -Be @('inspect')
                $inspect.changeKind | Should -BeExactly 'read'
                $inspect.factChanging | Should -BeFalse
                $replace = Get-DmOperation -Name 'note.replace-text'
                $replace.modes | Should -Be @('preview', 'apply')
                $replace.changeKind | Should -BeExactly 'edit'
                @($replace.arguments.Keys) | Should -Be @('oldText', 'newText')
                & $replace.builder 'a-b-a' @{ oldText = 'a'; newText = 'c' } 'x.md' | Should -BeExactly 'c-b-c'
                & $replace.builder 'A-a' @{ oldText = 'a'; newText = '' } 'x.md' | Should -BeExactly 'A-'
            }

            It 'protects built-in operations' {
                { Register-DmOperation -Name 'notes.inspect' -Modes inspect -FactChanging $false -Force } | Should -Throw
                { Unregister-DmOperation -Name 'note.replace-text' } | Should -Throw
            }

            It 'validates registrations' {
                { Register-DmOperation -Name 'Bad Name' -Modes inspect -FactChanging $false } | Should -Throw
                { Register-DmOperation -Name 'synthetic.lookup' -Modes preview -FactChanging $false } | Should -Throw -Because 'a preview operation needs a builder'
                { Register-DmOperation -Name 'synthetic.lookup' -Modes inspect -FactChanging $false -ChangeKind 'teleport' } | Should -Throw
                { Register-DmOperation -Name 'synthetic.lookup' -Modes write -FactChanging $false } | Should -Throw
            }

            It 'accepts requests for a registered operation and rejects them after removal' {
                $null = Register-DmOperation -Name 'synthetic.lookup' -Modes inspect -FactChanging $false -AllowedArguments @{ depth = @{ type = 'integer'; required = $true } } -MaxTargets 1
                $req = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'synthetic.lookup' -Targets @('Lore/Invented Town.md') -Arguments @{ depth = 2 }
                (Test-DmOperationRequest -Request $req).isValid | Should -BeTrue
                (Invoke-DmInspect -Request $req).result.completionCode | Should -BeExactly 'OK'
                $req['arguments'] = @{ depth = '2' }
                (Test-DmOperationRequest -Request $req).code | Should -BeExactly 'INVALID_REQUEST'
                $req['arguments'] = @{ depth = 2 }
                $req['targets'] = $targets
                (Test-DmOperationRequest -Request $req).code | Should -BeExactly 'INVALID_REQUEST' -Because 'MaxTargets is 1'
                Unregister-DmOperation -Name 'synthetic.lookup' | Should -BeTrue
                $req['targets'] = @('Lore/Invented Town.md')
                (Test-DmOperationRequest -Request $req).code | Should -BeExactly 'INVALID_REQUEST'
            }
        }

        Describe 'Forbidden lexical paths' {
            It 'returns PATH_INVALID before readiness for <Case>' -ForEach @(
                @{ Case = 'an absolute Windows path'; Target = 'C:/vault/x.md' }
                @{ Case = 'a leading slash'; Target = '/Adventures/x.md' }
                @{ Case = 'a UNC-like path'; Target = '//server/share/x.md' }
                @{ Case = 'a backslash separator'; Target = 'Adventures\x.md' }
                @{ Case = 'a parent component'; Target = 'Adventures/../../outside/secret.md' }
                @{ Case = 'a current-folder component'; Target = 'Adventures/./x.md' }
                @{ Case = 'an empty component'; Target = 'Adventures//x.md' }
                @{ Case = 'URI syntax'; Target = 'file:///etc/passwd' }
                @{ Case = 'an alternate data stream'; Target = 'Adventures/x.md:secret' }
                @{ Case = 'a wildcard'; Target = 'Adventures/*.md' }
                @{ Case = 'a bracket wildcard'; Target = 'Adventures/[ab].md' }
                @{ Case = 'a NUL character'; Target = "Adventures/x`0.md" }
                @{ Case = 'a control character'; Target = "Adventures/x`t.md" }
                @{ Case = 'a trailing dot'; Target = 'Adventures/x.' }
                @{ Case = 'a reserved device name'; Target = 'Adventures/CON.md' }
                @{ Case = 'an empty path'; Target = '' }
            ) {
                $t = [string[]]@($Target)
                $outcome = Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $fixture.Root -Targets $t)
                $outcome.result.completionCode | Should -BeExactly 'PATH_INVALID'
                $outcome.result.completionStatus | Should -BeExactly 'not completed'
                @($outcome.inspection).Count | Should -Be 0
                Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -Times 0 -Exactly -Scope It
                (Test-DmVaultRelativePath -Path $Target).code | Should -BeExactly 'PATH_INVALID'
                if ($Target.Length -gt 0) { (Test-DmVaultRelativePath -Path $Target).reason | Should -Not -Match ([regex]::Escape($Target)) }
            }

            It 'accepts ordinary vault-relative names' {
                foreach ($p in @('Adventures/Synthetic Arc.md', 'Lore/Invented Town.md', 'a/b/c d-e_f (1).md', '.obsidian/app.json', 'Ünïcødé/Ñote.md')) {
                    (Test-DmVaultRelativePath -Path $p).isValid | Should -BeTrue -Because $p
                }
            }
        }
    }
}

Describe 'Symbolic links, junctions, and recheck' {
    BeforeEach {
        Set-TestDependencyReadiness -State ready
        $fixture = New-TestVaultFixture -ProfileText "version: 1`n"
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        $links = [System.Collections.Generic.List[string]]::new()
        $root = $fixture.Root
        $addDirLink = {
            param([string]$Name, [string]$Target)
            $path = Join-Path -Path $root -ChildPath $Name
            $kind = New-TestDirectoryLink -Path $path -Target $Target
            if ($null -ne $kind) { $links.Add($path) }
            $kind
        }
        $addFileLink = {
            param([string]$Name, [string]$Target)
            $path = Join-Path -Path $root -ChildPath $Name
            $ok = New-TestFileLink -Path $path -Target $Target
            if ($ok) { $links.Add($path) }
            $ok
        }
        $inspect = { param([string[]]$Paths) Invoke-DmInspect -Request (New-TestOperationRequest -VaultRoot $root -Targets $Paths) }
        $lockOutside = { [System.IO.File]::Open((Join-Path -Path $fixture.OutsidePath -ChildPath 'secret.md'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None) }
    }

    AfterEach {
        for ($i = $links.Count - 1; $i -ge 0; $i--) { Remove-TestLink -Path $links[$i] }
        Remove-TestVaultFixture -Fixture $fixture
    }

    It 'follows an in-vault intermediate directory link' {
        if ($null -eq (& $addDirLink 'Linked' (Join-Path -Path $root -ChildPath 'Adventures'))) { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        $before = Get-LinkSafeSnapshot -Path $fixture.ParentPath
        $outcome = & $inspect @('Linked/Synthetic Arc.md')
        $outcome.result.completionCode | Should -BeExactly 'OK'
        $outcome.inspection[0].viaLink | Should -BeTrue
        $outcome.inspection[0].resolvedTarget | Should -BeExactly 'Adventures/Synthetic Arc.md'
        $outcome.inspection[0].version | Should -BeExactly (Get-TestSha256 -Path $fixture.NotePaths[0])
        Get-LinkSafeSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'follows an in-vault leaf directory link' {
        if ($null -eq (& $addDirLink 'Linked' (Join-Path -Path $root -ChildPath 'Lore'))) { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        $outcome = & $inspect @('Linked')
        $outcome.result.completionCode | Should -BeExactly 'OK'
        $outcome.inspection[0].itemType | Should -BeExactly 'directory'
        $outcome.inspection[0].resolvedTarget | Should -BeExactly 'Lore'
    }

    It 'returns PATH_OUTSIDE_VAULT for an escaping <Case> directory link without reading outside' -ForEach @(
        @{ Case = 'intermediate'; Target = 'Escape/secret.md' }
        @{ Case = 'leaf'; Target = 'Escape' }
    ) {
        if ($null -eq (& $addDirLink 'Escape' $fixture.OutsidePath)) { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        $before = Get-LinkSafeSnapshot -Path $fixture.ParentPath
        $lock = & $lockOutside
        try { $outcome = & $inspect @($Target) } finally { $lock.Dispose() }
        Assert-NotCompleted -Outcome $outcome -Code 'PATH_OUTSIDE_VAULT' -Targets @($Target)
        $outcome.result | ConvertTo-Json -Depth 8 | Should -Not -Match 'Synthetic outside-boundary'
        Get-LinkSafeSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'refuses every target when any target escapes, before reading any of them' {
        if ($null -eq (& $addDirLink 'Escape' $fixture.OutsidePath)) { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith { throw 'read attempted' }
        $t = [string[]]@('Adventures/Synthetic Arc.md', 'Escape/secret.md')
        $outcome = & $inspect $t
        Assert-NotCompleted -Outcome $outcome -Code 'PATH_OUTSIDE_VAULT' -Targets $t
        @($outcome.result.unchangedTargets.outcome | Select-Object -Unique) | Should -Be @('not attempted')
        Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
    }

    It 'returns PATH_OUTSIDE_VAULT for a cyclic link chain' {
        $loopA = Join-Path -Path $root -ChildPath 'LoopA'
        $loopB = Join-Path -Path $root -ChildPath 'LoopB'
        [void][System.IO.Directory]::CreateDirectory($loopB)
        if ($null -eq (& $addDirLink 'LoopA' $loopB)) { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        [System.IO.Directory]::Delete($loopB)
        if ($null -eq (& $addDirLink 'LoopB' $loopA)) { Set-ItResult -Skipped -Because 'a second directory link cannot be created here'; return }
        $before = Get-LinkSafeSnapshot -Path $fixture.ParentPath
        foreach ($t in @('LoopA/Synthetic Arc.md', 'LoopB', 'LoopA/x/y.md')) {
            Assert-NotCompleted -Outcome (& $inspect @($t)) -Code 'PATH_OUTSIDE_VAULT' -Targets @($t)
        }
        Get-LinkSafeSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'follows an in-vault leaf file symbolic link' {
        if (-not (& $addFileLink 'Alias.md' $fixture.NotePaths[1])) { Set-ItResult -Skipped -Because $script:FileLinkSkipReason; return }
        $outcome = & $inspect @('Alias.md')
        $outcome.result.completionCode | Should -BeExactly 'OK'
        $outcome.inspection[0].resolvedTarget | Should -BeExactly 'Lore/Invented Town.md'
    }

    It 'rejects an outside directory swapped in after the boundary confirmation' {
        $probe = Join-Path -Path $root -ChildPath 'DirectoryLinkProbe'
        if ($null -eq (New-TestDirectoryLink -Path $probe -Target $fixture.OutsidePath)) {
            Set-ItResult -Skipped -Because 'directory links cannot be created here'
            return
        }
        Remove-TestLink -Path $probe
        $raceDirectory = Join-Path -Path $root -ChildPath 'ReadRace'
        [void][System.IO.Directory]::CreateDirectory($raceDirectory)
        $targetPath = Join-Path -Path $raceDirectory -ChildPath 'secret.md'
        [System.IO.File]::WriteAllText($targetPath, 'Synthetic inside content.')
        $boundary = (Invoke-DmPreflight -Request (New-TestOperationRequest -VaultRoot $root -Targets @('ReadRace/secret.md'))).boundary
        $resolution = Resolve-DmVaultTarget -Boundary $boundary -Path 'ReadRace/secret.md'
        $resolution.status | Should -BeExactly 'resolved'
        $global:DmReadRaceDirectory = $raceDirectory
        $global:DmReadRaceOutside = $fixture.OutsidePath
        $global:DmReadRaceCount = 0
        Mock -ModuleName VaultBoundary -CommandName Confirm-DmVaultTarget -MockWith {
            if ($global:DmReadRaceCount -eq 0) {
                [System.IO.Directory]::Delete($global:DmReadRaceDirectory, $true)
                $kind = New-TestDirectoryLink -Path $global:DmReadRaceDirectory -Target $global:DmReadRaceOutside
                if ($null -eq $kind) { throw 'A directory link could not be created for the race test.' }
            }
            $global:DmReadRaceCount++
            [pscustomobject]@{ confirmed = $true; code = $null; reason = ''; resolution = $Resolution }
        }
        try {
            $read = Read-DmVaultTargetBytes -Boundary $boundary -Resolution $resolution
            $read.ok | Should -BeFalse
            $read.code | Should -BeExactly 'PATH_OUTSIDE_VAULT'
            $read.bytes | Should -BeNullOrEmpty
        }
        finally {
            if ([System.IO.Directory]::Exists($raceDirectory)) { Remove-TestLink -Path $raceDirectory }
            if ([System.IO.Directory]::Exists($raceDirectory)) { [System.IO.Directory]::Delete($raceDirectory, $true) }
            Remove-Variable -Name DmReadRaceDirectory, DmReadRaceOutside, DmReadRaceCount -Scope Global
        }
    }

    It 'rejects an outside leaf link swapped in immediately before the handle open' {
        $probe = Join-Path -Path $root -ChildPath 'LinkProbe.md'
        if (-not (New-TestFileLink -Path $probe -Target (Join-Path -Path $fixture.OutsidePath -ChildPath 'secret.md'))) {
            Set-ItResult -Skipped -Because $script:FileLinkSkipReason
            return
        }
        Remove-TestLink -Path $probe
        $path = $fixture.NotePaths[0]
        $original = [System.IO.File]::ReadAllBytes($path)
        $boundary = (Invoke-DmPreflight -Request (New-TestOperationRequest -VaultRoot $root -Targets @('Adventures/Synthetic Arc.md'))).boundary
        $resolution = Resolve-DmVaultTarget -Boundary $boundary -Path 'Adventures/Synthetic Arc.md'
        $global:DmReadRaceLeaf = $path
        $global:DmReadRaceOutside = Join-Path -Path $fixture.OutsidePath -ChildPath 'secret.md'
        Mock -ModuleName VaultBoundary -CommandName Read-DmVaultFileHandleSnapshot -MockWith {
            [System.IO.File]::Delete($global:DmReadRaceLeaf)
            [void][System.IO.File]::CreateSymbolicLink($global:DmReadRaceLeaf, $global:DmReadRaceOutside)
            [DmAssistant.IO.DirectoryLease]::ReadFileSnapshot($Path, $Root, $ExpectedPath)
        }
        try {
            $read = Read-DmVaultTargetBytes -Boundary $boundary -Resolution $resolution
            $read.ok | Should -BeFalse
            $read.code | Should -BeExactly 'PATH_OUTSIDE_VAULT'
            $read.bytes | Should -BeNullOrEmpty
        }
        finally {
            if ([System.IO.File]::Exists($path)) { Remove-TestLink -Path $path }
            [System.IO.File]::WriteAllBytes($path, $original)
            Remove-Variable -Name DmReadRaceLeaf, DmReadRaceOutside -Scope Global
        }
    }

    It 'returns PATH_OUTSIDE_VAULT for an escaping leaf file symbolic link (<Case>)' -ForEach @(
        @{ Case = 'absolute target'; Relative = $false }
        @{ Case = 'relative target'; Relative = $true }
    ) {
        $target = if ($Relative) { '../outside/secret.md' } else { Join-Path -Path $fixture.OutsidePath -ChildPath 'secret.md' }
        if (-not (& $addFileLink 'Leak.md' $target)) { Set-ItResult -Skipped -Because $script:FileLinkSkipReason; return }
        $lock = & $lockOutside
        try { $outcome = & $inspect @('Leak.md') } finally { $lock.Dispose() }
        Assert-NotCompleted -Outcome $outcome -Code 'PATH_OUTSIDE_VAULT' -Targets @('Leak.md')
    }

    It 'returns PATH_OUTSIDE_VAULT for a cyclic file symbolic link chain' {
        if (-not (& $addFileLink 'Cycle1.md' 'Cycle2.md')) { Set-ItResult -Skipped -Because $script:FileLinkSkipReason; return }
        if (-not (& $addFileLink 'Cycle2.md' 'Cycle1.md')) { Set-ItResult -Skipped -Because $script:FileLinkSkipReason; return }
        Assert-NotCompleted -Outcome (& $inspect @('Cycle1.md')) -Code 'PATH_OUTSIDE_VAULT' -Targets @('Cycle1.md')
    }

    It 'rechecks the boundary before access: <Case>' -ForEach @(
        @{ Case = 'a folder swapped for an escaping link'; Escape = $true; Code = 'PATH_OUTSIDE_VAULT' }
        @{ Case = 'a folder swapped for an in-vault link'; Escape = $false; Code = 'TARGET_CONFLICT' }
    ) {
        $swap = Join-Path -Path $root -ChildPath 'Swap'
        [void][System.IO.Directory]::CreateDirectory($swap)
        [System.IO.File]::Copy($fixture.NotePaths[0], (Join-Path -Path $swap -ChildPath 'secret.md'))
        $pre = Invoke-DmPreflight -Request (New-TestOperationRequest -VaultRoot $root -Targets @('Swap/secret.md'))
        $pre.passed | Should -BeTrue
        $resolution = Resolve-DmVaultTarget -Boundary $pre.boundary -Path 'Swap/secret.md'
        $resolution.status | Should -BeExactly 'resolved'
        (Confirm-DmVaultTarget -Boundary $pre.boundary -Resolution $resolution).confirmed | Should -BeTrue
        [System.IO.Directory]::Delete($swap, $true)
        $swapTarget = if ($Escape) { $fixture.OutsidePath } else { [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $root -ChildPath 'Other')); [System.IO.File]::Copy($fixture.NotePaths[0], (Join-Path -Path $root -ChildPath 'Other\secret.md')); Join-Path -Path $root -ChildPath 'Other' }
        if ($null -eq (& $addDirLink 'Swap' $swapTarget)) { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
        $check = Confirm-DmVaultTarget -Boundary $pre.boundary -Resolution $resolution
        $check.confirmed | Should -BeFalse
        $check.code | Should -BeExactly $Code
        $read = Read-DmVaultTargetBytes -Boundary $pre.boundary -Resolution $resolution
        $read.ok | Should -BeFalse
        $read.code | Should -BeExactly $Code
        $read.bytes | Should -BeNullOrEmpty
    }

    It 'detects a vault root that moves after resolution' {
        $pre = Invoke-DmPreflight -Request (New-TestOperationRequest -VaultRoot $root -Targets @('Lore/Invented Town.md'))
        $resolution = Resolve-DmVaultTarget -Boundary $pre.boundary -Path 'Lore/Invented Town.md'
        $moved = [pscustomobject]@{ selectedRoot = $fixture.OutsidePath; canonicalRoot = $pre.boundary.canonicalRoot; comparison = $pre.boundary.comparison }
        (Confirm-DmVaultTarget -Boundary $moved -Resolution $resolution).code | Should -BeExactly 'PATH_OUTSIDE_VAULT'
    }

    It 'compares containment on component boundaries' {
        Test-DmPathWithinRoot -Root 'C:\Vault' -Path 'C:\Vault\Notes\a.md' | Should -BeTrue
        Test-DmPathWithinRoot -Root 'C:\Vault' -Path 'C:\Vault' | Should -BeTrue
        Test-DmPathWithinRoot -Root 'C:\Vault' -Path 'C:\Vault2\a.md' | Should -BeFalse
        Test-DmPathWithinRoot -Root 'C:\Vault\' -Path 'C:\VaultX' | Should -BeFalse
        Test-DmPathWithinRoot -Root 'C:\' -Path 'C:\anything' | Should -BeTrue
        if ($IsWindows) { Test-DmPathWithinRoot -Root 'C:\Vault' -Path 'c:\vault\NOTES' | Should -BeTrue }
    }
}
