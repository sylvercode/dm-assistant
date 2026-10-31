# Proposed seams for the pending write modules: Invoke-DmApplyNoteChanges consumes
# ordered target records; Invoke-DmSafeNoteWrite performs one checked atomic write.
BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, VaultBoundary, SafeNoteWriter, ApplyNoteChanges

    function Get-TestBytesVersion {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
        'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
    }

    function New-TestApplyTarget {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$ReplacementText
        )
        $resolution = Resolve-DmVaultTarget -Boundary $Fixture.Boundary -Path $Path
        $currentBytes = [System.IO.File]::ReadAllBytes($resolution.resolvedPath)
        $replacementBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($ReplacementText)
        [pscustomobject][ordered]@{
            path              = $Path
            resolution        = $resolution
            observedVersion   = Get-TestBytesVersion -Bytes $currentBytes
            replacementVersion = Get-TestBytesVersion -Bytes $replacementBytes
            replacementBytes = $replacementBytes
        }
    }

    function Initialize-TestAtomicFixture {
        $notes = [ordered]@{
            'Atomic/First.md'  = "# First`nOriginal first note.`n"
            'Atomic/Second.md' = "# Second`nOriginal second note.`n"
            'Atomic/Third.md'  = "# Third`nOriginal third note.`n"
        }
        $script:AtomicFixture = New-TestVaultFixture -ParentPath (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))) -Notes $notes
        $canonicalRoot = [System.IO.Path]::GetFullPath($script:AtomicFixture.Root)
        if ($canonicalRoot.Length -gt [System.IO.Path]::GetPathRoot($canonicalRoot).Length) {
            $canonicalRoot = $canonicalRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        }
        $script:AtomicFixture | Add-Member -NotePropertyName Boundary -NotePropertyValue ([pscustomobject][ordered]@{
            selectedRoot  = $script:AtomicFixture.Root
            canonicalRoot = $canonicalRoot
            comparison    = [System.StringComparison]::OrdinalIgnoreCase
        })
    }

    function Clear-TestAtomicFixture {
        if ($null -ne $script:AtomicFixture) {
            Remove-TestVaultFixture -Fixture $script:AtomicFixture
            $script:AtomicFixture = $null
        }
    }
}

Describe 'Atomic note writes and boundary rechecks' {
    BeforeEach { Initialize-TestAtomicFixture }
    AfterEach { Clear-TestAtomicFixture }

    It 'detects a target changed after preview at the immediate pre-write version check' {
        $target = New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nReviewed replacement.`n"
        $replacementBytes = [byte[]]$target.replacementBytes
        Mock -ModuleName SafeNoteWriter -CommandName Read-DmVaultTargetBytes -MockWith {
            $changedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes("# First`nChanged after preview.`n")
            [System.IO.File]::WriteAllBytes($Resolution.resolvedPath, $changedBytes)
            $hash = [System.Security.Cryptography.SHA256]::HashData($changedBytes)
            [pscustomobject][ordered]@{
                ok      = $true
                code    = $null
                reason  = ''
                bytes   = $changedBytes
                version = 'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
            }
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $script:AtomicFixture.Boundary -Targets @($target) -Operation 'note.replace-text'

        $result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
        $result.completionStatus | Should -BeExactly 'not completed'
        @($result.changedTargets).Count | Should -Be 0
        @($result.unchangedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @('Atomic/First.md:conflict')
        @($result.remainingWork) | Should -Be @('Atomic/First.md')
        [System.IO.File]::ReadAllBytes($target.resolution.resolvedPath) | Should -Be ([System.Text.UTF8Encoding]::new($false).GetBytes("# First`nChanged after preview.`n"))
    }

    It 'reports an escape discovered by the final boundary recheck without writing' {
        $target = New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nMust not be written.`n"
        Mock -ModuleName SafeNoteWriter -CommandName Read-DmVaultTargetBytes -MockWith {
            [pscustomobject][ordered]@{
                ok = $false
                code = 'PATH_OUTSIDE_VAULT'
                reason = 'The target resolves outside the vault.'
                bytes = $null
                version = $null
            }
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $script:AtomicFixture.Boundary -Targets @($target) -Operation 'note.replace-text'

        $result.completionCode | Should -BeExactly 'PATH_OUTSIDE_VAULT'
        $result.completionStatus | Should -BeExactly 'not completed'
        @($result.changedTargets).Count | Should -Be 0
        @($result.unchangedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @('Atomic/First.md:conflict')
        @($result.remainingWork) | Should -Be @('Atomic/First.md')
        [System.IO.File]::ReadAllText($target.resolution.resolvedPath) | Should -BeExactly "# First`nOriginal first note.`n"
    }

    It 'leaves the live note byte-for-byte unchanged when atomic replacement cannot proceed' {
        $target = New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nComplete replacement.`n"
        $original = [System.IO.File]::ReadAllBytes($target.resolution.resolvedPath)
        $lock = [System.IO.File]::Open(
            $target.resolution.resolvedPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $outcome = Invoke-DmSafeNoteWrite -Boundary $script:AtomicFixture.Boundary -Target $target
        }
        finally {
            $lock.Dispose()
        }

        $outcome.ok | Should -BeFalse
        $outcome.code | Should -BeExactly 'WRITE_FAILED'
        [System.IO.File]::ReadAllBytes($target.resolution.resolvedPath) | Should -Be $original
    }

    It 'holds the verified directory chain against rename while staging is active' {
        $target = New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nReplacement.`n"
        $directory = Join-Path $script:AtomicFixture.Root 'Atomic'
        $renamed = Join-Path $script:AtomicFixture.Root 'Atomic-renamed'
        $lease = Open-DmVaultDirectoryLease -Boundary $script:AtomicFixture.Boundary -Resolution $target.resolution
        try {
            { [System.IO.Directory]::Move($directory, $renamed) } | Should -Throw
            Test-Path -LiteralPath $directory | Should -BeTrue
        }
        finally { $lease.Dispose() }
    }

    It 'preserves the target access rules through atomic replacement' {
        $target = New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nACL-preserving replacement.`n"
        $before = Get-DmFileAccessFingerprint -Path $target.resolution.resolvedPath
        $rights = [System.Security.Principal.NTAccount]
        $beforeRules = @($before.security.GetAccessRules($true, $true, $rights) | ForEach-Object {
            "$($_.IdentityReference.Value)|$($_.AccessControlType)|$($_.FileSystemRights)|$($_.InheritanceFlags)|$($_.PropagationFlags)|$($_.IsInherited)"
        } | Sort-Object)

        $outcome = Invoke-DmSafeNoteWrite -Boundary $script:AtomicFixture.Boundary -Target $target

        $outcome.ok | Should -BeTrue
        $after = Get-DmFileAccessFingerprint -Path $target.resolution.resolvedPath
        $afterRules = @($after.security.GetAccessRules($true, $true, $rights) | ForEach-Object {
            "$($_.IdentityReference.Value)|$($_.AccessControlType)|$($_.FileSystemRights)|$($_.InheritanceFlags)|$($_.PropagationFlags)|$($_.IsInherited)"
        } | Sort-Object)
        $afterRules | Should -Be $beforeRules
    }

    It 'uses a short staging filename for long target leaves' {
        $leaf = ('n' * 230) + '.md'
        $fullPath = Join-Path $script:AtomicFixture.Root $leaf
        [System.IO.File]::WriteAllText($fullPath, "Original long target.`n", [System.Text.UTF8Encoding]::new($false))
        $resolution = Resolve-DmVaultTarget -Boundary $script:AtomicFixture.Boundary -Path $leaf
        $original = [System.IO.File]::ReadAllBytes($fullPath)
        $replacement = [System.Text.UTF8Encoding]::new($false).GetBytes("Replacement long target.`n")
        $target = [pscustomobject][ordered]@{
            path = $leaf
            resolution = $resolution
            observedVersion = Get-TestBytesVersion -Bytes $original
            replacementBytes = $replacement
        }

        $outcome = Invoke-DmSafeNoteWrite -Boundary $script:AtomicFixture.Boundary -Target $target

        $outcome.ok | Should -BeTrue
        [System.IO.File]::ReadAllText($fullPath) | Should -BeExactly "Replacement long target.`n"
    }

    It 'rechecks the target after dependency reads and immediately before replacement' {
        $target = New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nApproved replacement.`n"
        $expectedDependencies = Get-DmCurrentChangeDependencyVersions -Boundary $script:AtomicFixture.Boundary -Profile $null
        Mock -ModuleName SafeNoteWriter -CommandName Get-DmCurrentChangeDependencyVersions -MockWith {
            $changed = [System.Text.UTF8Encoding]::new($false).GetBytes("# First`nChanged during dependency read.`n")
            [System.IO.File]::WriteAllBytes($target.resolution.resolvedPath, $changed)
            $expectedDependencies
        }

        $outcome = Invoke-DmSafeNoteWrite -Boundary $script:AtomicFixture.Boundary -Target $target -ExpectedDependencies $expectedDependencies

        $outcome.code | Should -BeExactly 'TARGET_CONFLICT'
        [System.IO.File]::ReadAllText($target.resolution.resolvedPath) | Should -BeExactly "# First`nChanged during dependency read.`n"
    }
}

Describe 'Deterministic multi-target apply results' {
    BeforeEach { Initialize-TestAtomicFixture }
    AfterEach { Clear-TestAtomicFixture }

    It 'stops on the first failure, marks later targets not attempted, and reports no partial completion without an earlier write' {
        $targets = @(
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nNew first.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Second.md' -ReplacementText "# Second`nNew second.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Third.md' -ReplacementText "# Third`nNew third.`n")
        )
        Mock -ModuleName ApplyNoteChanges -CommandName Invoke-DmSafeNoteWrite -MockWith {
            [pscustomobject][ordered]@{ ok = $false; code = 'WRITE_FAILED'; reason = 'Synthetic replacement failure.' }
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $script:AtomicFixture.Boundary -Targets $targets -Operation 'note.replace-text'

        $result.completionCode | Should -BeExactly 'WRITE_FAILED'
        $result.completionStatus | Should -BeExactly 'not completed'
        @($result.changedTargets).Count | Should -Be 0
        @($result.unchangedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @(
            'Atomic/First.md:failed',
            'Atomic/Second.md:not attempted',
            'Atomic/Third.md:not attempted'
        )
        @($result.remainingWork) | Should -Be @('Atomic/First.md', 'Atomic/Second.md', 'Atomic/Third.md')
    }

    It 'reports interruption as not completed when no target changed first' {
        $targets = @(
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nInterrupted first.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Second.md' -ReplacementText "# Second`nMust not run.`n")
        )
        Mock -ModuleName ApplyNoteChanges -CommandName Invoke-DmSafeNoteWrite -MockWith {
            throw [System.OperationCanceledException]::new('Synthetic interruption.')
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $script:AtomicFixture.Boundary -Targets $targets -Operation 'note.replace-text'

        $result.completionCode | Should -BeExactly 'INTERRUPTED'
        $result.completionStatus | Should -BeExactly 'not completed'
        @($result.changedTargets).Count | Should -Be 0
        @($result.unchangedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @(
            'Atomic/First.md:failed',
            'Atomic/Second.md:not attempted'
        )
        @($result.remainingWork) | Should -Be @('Atomic/First.md', 'Atomic/Second.md')
    }

    It 'retains earlier writes without rollback and reports exact partial failure work' {
        $targets = @(
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nApplied first.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Second.md' -ReplacementText "# Second`nFailed second.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Third.md' -ReplacementText "# Third`nMust not run.`n")
        )
        Mock -ModuleName ApplyNoteChanges -CommandName Invoke-DmSafeNoteWrite -MockWith {
            if ($Target.path -ceq 'Atomic/First.md') {
                [System.IO.File]::WriteAllBytes($Target.resolution.resolvedPath, [byte[]]$Target.replacementBytes)
                return [pscustomobject][ordered]@{ ok = $true; code = $null; reason = '' }
            }
            [pscustomobject][ordered]@{ ok = $false; code = 'WRITE_FAILED'; reason = 'Synthetic replacement failure.' }
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $script:AtomicFixture.Boundary -Targets $targets -Operation 'note.replace-text'

        $result.completionCode | Should -BeExactly 'WRITE_FAILED'
        $result.completionStatus | Should -BeExactly 'partially completed'
        @($result.changedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @('Atomic/First.md:written')
        @($result.unchangedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @(
            'Atomic/Second.md:failed',
            'Atomic/Third.md:not attempted'
        )
        @($result.remainingWork) | Should -Be @('Atomic/Second.md', 'Atomic/Third.md')
        [System.IO.File]::ReadAllText($targets[0].resolution.resolvedPath) | Should -BeExactly "# First`nApplied first.`n"
        [System.IO.File]::ReadAllText($targets[1].resolution.resolvedPath) | Should -BeExactly "# Second`nOriginal second note.`n"
        [System.IO.File]::ReadAllText($targets[2].resolution.resolvedPath) | Should -BeExactly "# Third`nOriginal third note.`n"
    }

    It 'stops on interruption, preserves completed notes, and reports only unfinished work as remaining' {
        $targets = @(
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/First.md' -ReplacementText "# First`nApplied before interruption.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Second.md' -ReplacementText "# Second`nInterrupted.`n"),
            (New-TestApplyTarget -Fixture $script:AtomicFixture -Path 'Atomic/Third.md' -ReplacementText "# Third`nMust not run.`n")
        )
        Mock -ModuleName ApplyNoteChanges -CommandName Invoke-DmSafeNoteWrite -MockWith {
            if ($Target.path -ceq 'Atomic/First.md') {
                [System.IO.File]::WriteAllBytes($Target.resolution.resolvedPath, [byte[]]$Target.replacementBytes)
                return [pscustomobject][ordered]@{ ok = $true; code = $null; reason = '' }
            }
            throw [System.OperationCanceledException]::new('Synthetic interruption.')
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $script:AtomicFixture.Boundary -Targets $targets -Operation 'note.replace-text'

        $result.completionCode | Should -BeExactly 'INTERRUPTED'
        $result.completionStatus | Should -BeExactly 'partially completed'
        @($result.changedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @('Atomic/First.md:written')
        @($result.unchangedTargets | ForEach-Object { "$($_.path):$($_.outcome)" }) | Should -Be @(
            'Atomic/Second.md:failed',
            'Atomic/Third.md:not attempted'
        )
        @($result.remainingWork) | Should -Be @('Atomic/Second.md', 'Atomic/Third.md')
        [System.IO.File]::ReadAllText($targets[0].resolution.resolvedPath) | Should -BeExactly "# First`nApplied before interruption.`n"
        [System.IO.File]::ReadAllText($targets[1].resolution.resolvedPath) | Should -BeExactly "# Second`nOriginal second note.`n"
        [System.IO.File]::ReadAllText($targets[2].resolution.resolvedPath) | Should -BeExactly "# Third`nOriginal third note.`n"
    }
}
