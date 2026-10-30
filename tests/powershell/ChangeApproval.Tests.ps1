BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, PluginResources, VaultConfiguration, SafeNoteWriter, ChangePreview, ApplyNoteChanges

    function New-ChangeApprovalFixture {
        param(
            [System.Collections.IDictionary]$Notes,
            [string]$GuidancePath = '.dmassist-guidance.md',
            [string]$TemplatePath = '.dmassist-templates/adventure.md'
        )
        $profile = @"
version: 1
guidance:
  path: "$GuidancePath"
templates:
  adventure: "$TemplatePath"
"@
        $fixture = New-TestVaultFixture -ProfileText $profile -Notes $Notes
        $guidanceFullPath = Join-Path -Path $fixture.Root -ChildPath ($GuidancePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $templateFullPath = Join-Path -Path $fixture.Root -ChildPath ($TemplatePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($guidanceFullPath))
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($templateFullPath))
        [System.IO.File]::WriteAllText($guidanceFullPath, "Synthetic local guidance.`n", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($templateFullPath, "# Synthetic template`n", [System.Text.UTF8Encoding]::new($false))
        $fixture | Add-Member -NotePropertyName GuidancePath -NotePropertyValue $guidanceFullPath
        $fixture | Add-Member -NotePropertyName TemplatePath -NotePropertyValue $templateFullPath
        $fixture
    }

    function New-TextEditRequest {
        param(
            [Parameter(Mandatory)][string]$VaultRoot,
            [string[]]$Targets = @('Adventures/Synthetic Arc.md'),
            [string]$OldText = 'marker',
            [string]$NewText = 'replacement'
        )
        New-TestOperationRequest -VaultRoot $VaultRoot -Operation 'note.replace-text' -Mode preview -Targets $Targets `
            -Arguments ([ordered]@{ oldText = $OldText; newText = $NewText })
    }

    function Get-ReviewedVersionsFromPreview {
        param([Parameter(Mandatory)]$Preview)
        if ($null -ne $Preview.PSObject.Properties['reviewedVersions']) {
            return , [object[]]@($Preview.reviewedVersions)
        }
        [object[]]@($Preview.targets | ForEach-Object {
            [pscustomobject][ordered]@{
                path               = $_.path
                observedVersion    = $_.observedVersion
                replacementVersion = $_.replacementVersion
                conversionDecision = $_.conversionDecision
            }
        })
    }

    function Get-ReviewedDependenciesFromPreview {
        param([Parameter(Mandatory)]$Preview)
        if ($null -ne $Preview.PSObject.Properties['reviewedDependencyVersions']) {
            return , [object[]]@($Preview.reviewedDependencyVersions)
        }
        if ($null -ne $Preview.PSObject.Properties['dependencyVersions']) {
            return , [object[]]@($Preview.dependencyVersions)
        }
        throw 'A preview must expose the dependency versions carried by approval.'
    }

    function New-ApprovedApplyRequest {
        param(
            [Parameter(Mandatory)][System.Collections.IDictionary]$PreviewRequest,
            [Parameter(Mandatory)]$Preview
        )
        $request = [ordered]@{}
        foreach ($key in $PreviewRequest.Keys) { $request[$key] = $PreviewRequest[$key] }
        $request.mode = 'apply'
        $request.requestId = 'test-' + [guid]::NewGuid().ToString('N')
        $request.approvedPreviewId = $Preview.previewId
        $request.reviewedVersions = Get-ReviewedVersionsFromPreview -Preview $Preview
        $request.reviewedDependencyVersions = Get-ReviewedDependenciesFromPreview -Preview $Preview
        $request
    }

    function Assert-Completion {
        param(
            [Parameter(Mandatory)]$Outcome,
            [Parameter(Mandatory)][string]$Code,
            [Parameter(Mandatory)][string]$Status
        )
        $Outcome.result.completionCode | Should -BeExactly $Code
        $Outcome.result.completionStatus | Should -BeExactly $Status
    }

    function Register-TestChangingOperation {
        Register-DmOperation -Name 'test.fact-changing' -Modes @('preview', 'apply') -FactChanging $true `
            -ChangeKind edit -AllowedArguments @{} -Builder {
            param($CurrentText, $Arguments, $TargetPath)
            $null = $Arguments
            $null = $TargetPath
            ([string]$CurrentText) + "`nSynthetic fact change."
        }
    }

    function Set-TestDependencyInventoryFixture {
        $source = Join-Path -Path (Get-TestRepositoryRoot) -ChildPath 'skills\vault-orientation\assets\runtime-dependencies.json'
        $global:DmApprovalInventoryPath = Join-Path -Path $TestDrive -ChildPath ('inventory-' + [guid]::NewGuid().ToString('N') + '.json')
        [System.IO.File]::Copy($source, $global:DmApprovalInventoryPath)
        Mock -ModuleName DependencyPreflight -CommandName Get-DmDependencyInventoryPath -MockWith { $global:DmApprovalInventoryPath }
    }

    function Invoke-PreviewInFreshProcess {
        param(
            [Parameter(Mandatory)][string]$VaultRoot,
            [Parameter(Mandatory)][string]$HarnessPath
        )

        $scriptPath = Join-Path -Path $TestDrive -ChildPath ('DigestChild-' + [guid]::NewGuid().ToString('N') + '.Tests.ps1')
        $runnerPath = Join-Path -Path $TestDrive -ChildPath ('DigestRunner-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $outputPath = Join-Path -Path $TestDrive -ChildPath ('Digest-' + [guid]::NewGuid().ToString('N') + '.txt')
        $childTest = @'
BeforeAll {
    Import-Module -Name $env:DMASSIST_TEST_HARNESS -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, PluginResources, VaultConfiguration, SafeNoteWriter, ChangePreview, ApplyNoteChanges
}
Describe 'Independent preview digest process' {
    It 'writes the synthetic preview id for comparison' {
        Set-TestDependencyReadiness -State ready
        Enable-TestAuthorizationProvider -VaultRoot $env:DMASSIST_TEST_VAULT
        $request = New-TestOperationRequest -VaultRoot $env:DMASSIST_TEST_VAULT -Operation 'note.replace-text' -Mode preview `
            -Targets @('Adventures/Synthetic Arc.md') -Arguments ([ordered]@{ oldText = 'marker'; newText = 'replacement' })
        $outcome = Invoke-DmPreview -Request $request
        $outcome.result.completionCode | Should -BeExactly 'OK'
        [System.IO.File]::WriteAllText($env:DMASSIST_TEST_OUTPUT, [string]$outcome.preview.previewId)
    }
}
'@
        $runner = @'
Import-Module Pester -RequiredVersion 6.2.0
$configuration = New-PesterConfiguration
$configuration.Run.Path = @($env:DMASSIST_TEST_SCRIPT)
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { exit 1 }
'@
        [System.IO.File]::WriteAllText($scriptPath, $childTest, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($runnerPath, $runner, [System.Text.UTF8Encoding]::new($false))

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = [System.Environment]::ProcessPath
        $startInfo.UseShellExecute = $false
        $startInfo.ArgumentList.Add('-NoProfile')
        $startInfo.ArgumentList.Add('-File')
        $startInfo.ArgumentList.Add($runnerPath)
        $startInfo.Environment['DMASSIST_TEST_SCRIPT'] = $scriptPath
        $startInfo.Environment['DMASSIST_TEST_HARNESS'] = $HarnessPath
        $startInfo.Environment['DMASSIST_TEST_VAULT'] = $VaultRoot
        $startInfo.Environment['DMASSIST_TEST_OUTPUT'] = $outputPath
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.WaitForExit()
        $process.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($outputPath)
    }
}

Describe 'Synthetic preview and approval safety' {
    BeforeEach {
        $notes = [ordered]@{
            'Adventures/Synthetic Arc.md' = "# Synthetic Arc`nmarker is synthetic text.`n"
            'Lore/Invented Town.md'       = "# Invented Town`nmarker is synthetic text.`n"
            'Rules/Optional Rule.md'      = "# Optional Rule`nmarker is synthetic text.`n"
        }
        $fixture = New-ChangeApprovalFixture -Notes $notes
        Set-TestDependencyReadiness -State ready
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
    }

    AfterEach {
        Remove-TestVaultFixture -Fixture $fixture
        Remove-Variable -Name DmApprovalInventoryPath -Scope Global -ErrorAction SilentlyContinue
    }

    It 'keeps preview read-only and carries versioned effects without note content' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath

        $outcome = Invoke-DmPreview -Request $request

        Assert-Completion -Outcome $outcome -Code 'OK' -Status 'complete'
        $outcome.preview.previewId | Should -Match '^sha256:[0-9a-f]{64}$'
        $outcome.preview.targets.Count | Should -Be 1
        $outcome.preview.targets[0].path | Should -BeExactly 'Adventures/Synthetic Arc.md'
        $outcome.preview.targets[0].observedVersion | Should -Match '^(absent|sha256:[0-9a-f]{64})$'
        $outcome.preview.targets[0].replacementVersion | Should -Match '^(absent|sha256:[0-9a-f]{64})$'
        $outcome.preview.targets[0].conversionDecision | Should -BeExactly 'preserve'
        ($outcome | ConvertTo-Json -Depth 12 -Compress) | Should -Not -Match 'marker is synthetic text'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'requires approval for a multi-note edit and accepts only its exact preview' {
        $targets = [string[]]@('Adventures/Synthetic Arc.md', 'Lore/Invented Town.md')
        $request = New-TextEditRequest -VaultRoot $fixture.Root -Targets $targets
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $previewOutcome = Invoke-DmPreview -Request $request
        $previewOutcome.result.completionCode | Should -BeExactly 'OK'

        $unapproved = [ordered]@{}
        foreach ($key in $request.Keys) { $unapproved[$key] = $request[$key] }
        $unapproved.mode = 'apply'
        Assert-Completion -Outcome (Invoke-DmApply -Request $unapproved) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before

        $wrongApproval = New-ApprovedApplyRequest -PreviewRequest $request -Preview $previewOutcome.preview
        $wrongApproval.approvedPreviewId = 'sha256:' + ('0' * 64)
        Assert-Completion -Outcome (Invoke-DmApply -Request $wrongApproval) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before

        $approved = New-ApprovedApplyRequest -PreviewRequest $request -Preview $previewOutcome.preview
        $applied = Invoke-DmApply -Request $approved
        Assert-Completion -Outcome $applied -Code 'OK' -Status 'complete'
        @($applied.result.changedTargets.path) | Should -Be $targets
        Get-Content -LiteralPath $fixture.NotePaths[0] -Raw | Should -Match 'replacement'
        Get-Content -LiteralPath $fixture.NotePaths[1] -Raw | Should -Match 'replacement'
        (Test-DmResult -Result $applied.result -RequestedTargets $targets).isValid | Should -BeTrue
        $before | Should -Not -Be (Get-TestVaultSnapshot -Path $fixture.ParentPath)
    }

    It 'applies a single named-note text edit without requiring approval' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $apply = [ordered]@{}
        foreach ($key in $request.Keys) { $apply[$key] = $request[$key] }
        $apply.mode = 'apply'

        $outcome = Invoke-DmApply -Request $apply

        Assert-Completion -Outcome $outcome -Code 'OK' -Status 'complete'
        $outcome.result.changedTargets[0].path | Should -BeExactly 'Adventures/Synthetic Arc.md'
        [System.IO.File]::ReadAllText($fixture.NotePaths[0]) | Should -Match 'replacement'
    }

    It 'requires approval for a single-target operation declared fact-changing' {
        $null = Register-TestChangingOperation
        try {
            $request = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'test.fact-changing' -Mode preview `
                -Targets @('Adventures/Synthetic Arc.md') -Arguments ([ordered]@{})
            $preview = Invoke-DmPreview -Request $request
            $preview.result.completionCode | Should -BeExactly 'OK'
            $apply = [ordered]@{}
            foreach ($key in $request.Keys) { $apply[$key] = $request[$key] }
            $apply.mode = 'apply'
            Assert-Completion -Outcome (Invoke-DmApply -Request $apply) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
        }
        finally {
            Unregister-DmOperation -Name 'test.fact-changing'
        }
    }

    It 'rejects approval when request arguments or target scope change' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $preview = (Invoke-DmPreview -Request $request).preview
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath

        $changedArguments = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        $changedArguments.arguments['newText'] = 'different replacement'
        Assert-Completion -Outcome (Invoke-DmApply -Request $changedArguments) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'

        $changedTarget = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        $changedTarget.targets = [string[]]@('Lore/Invented Town.md')
        $changedTarget.reviewedVersions = @(
            [pscustomobject][ordered]@{
                path               = 'Lore/Invented Town.md'
                observedVersion    = $preview.targets[0].observedVersion
                replacementVersion = $preview.targets[0].replacementVersion
                conversionDecision = $preview.targets[0].conversionDecision
            }
        )
        Assert-Completion -Outcome (Invoke-DmApply -Request $changedTarget) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'returns TARGET_CONFLICT without writing when the reviewed target changes' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $preview = (Invoke-DmPreview -Request $request).preview
        $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        [System.IO.File]::AppendAllText($fixture.NotePaths[0], "External synthetic update.`n")
        $current = [System.IO.File]::ReadAllBytes($fixture.NotePaths[0])

        $outcome = Invoke-DmApply -Request $apply

        Assert-Completion -Outcome $outcome -Code 'TARGET_CONFLICT' -Status 'not completed'
        [System.IO.File]::ReadAllBytes($fixture.NotePaths[0]) | Should -Be $current
    }

    It 'returns TARGET_CONFLICT when the profile or guidance changes' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $preview = (Invoke-DmPreview -Request $request).preview
        $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview

        foreach ($dependency in @('profile', 'guidance')) {
            $beforeTarget = [System.IO.File]::ReadAllBytes($fixture.NotePaths[0])
            switch ($dependency) {
                'profile' {
                    $profile = "version: 1`nguidance:`n  path: .dmassist-guidance.md`ntemplates:`n  adventure: .dmassist-templates/adventure.md`nparty:`n  note: Lore/Invented Town.md`n"
                    [System.IO.File]::WriteAllText($fixture.ProfilePath, $profile, [System.Text.UTF8Encoding]::new($false))
                }
                'guidance' { [System.IO.File]::AppendAllText($fixture.GuidancePath, "Changed synthetic guidance.`n") }
                'template' { [System.IO.File]::AppendAllText($fixture.TemplatePath, "Changed synthetic template.`n") }
            }
            $outcome = Invoke-DmApply -Request $apply
            Assert-Completion -Outcome $outcome -Code 'TARGET_CONFLICT' -Status 'not completed'
            [System.IO.File]::ReadAllBytes($fixture.NotePaths[0]) | Should -Be $beforeTarget

            # A fresh preview binds the next dependency mutation independently.
            $request = New-TextEditRequest -VaultRoot $fixture.Root
            $preview = (Invoke-DmPreview -Request $request).preview
            $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        }
    }

    It 'does not invalidate a text replacement for an unrelated configured template change' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $preview = (Invoke-DmPreview -Request $request).preview
        $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        [System.IO.File]::AppendAllText($fixture.TemplatePath, "Unrelated synthetic template update.`n")

        $outcome = Invoke-DmApply -Request $apply

        Assert-Completion -Outcome $outcome -Code 'OK' -Status 'complete'
    }

    It 'invalidates approval when runtimeVersion changes after preview' {
        $state = [pscustomobject]@{ Version = 'synthetic-runtime-before' }
        $runtimeVersionMock = { $state.Version }.GetNewClosure()
        Mock -ModuleName ChangePreview -CommandName Get-DmRuntimeVersion -MockWith $runtimeVersionMock
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $preview = (Invoke-DmPreview -Request $request).preview
        $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        $state.Version = 'synthetic-runtime-after'

        Assert-Completion -Outcome (Invoke-DmApply -Request $apply) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'invalidates approval when the Resolver inventory changes after preview' {
        Set-TestDependencyInventoryFixture
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $preview = (Invoke-DmPreview -Request $request).preview
        $inventory = @($preview.dependencyVersions | Where-Object {
                $_.identity -ceq 'plugin:skills/vault-orientation/assets/runtime-dependencies.json'
            })
        $inventory.Count | Should -Be 1
        $inventory[0].version | Should -Match '^sha256:[0-9a-f]{64}$'
        $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        [System.IO.File]::AppendAllText($global:DmApprovalInventoryPath, "`n")

        Assert-Completion -Outcome (Invoke-DmApply -Request $apply) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'detects a Resolver inventory change at the immediate pre-write check' {
        Set-TestDependencyInventoryFixture
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $preview = (Invoke-DmPreview -Request $request).preview
        $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview
        Mock -ModuleName SafeNoteWriter -CommandName Read-DmVaultTargetBytes -MockWith {
            [System.IO.File]::AppendAllText($global:DmApprovalInventoryPath, "`n")
            VaultBoundary\Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $Resolution
        }

        Assert-Completion -Outcome (Invoke-DmApply -Request $apply) -Code 'TARGET_CONFLICT' -Status 'not completed'
        Should -Invoke -ModuleName SafeNoteWriter -CommandName Read-DmVaultTargetBytes -Times 2 -Exactly -Scope It
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'rejects a rebuilt replacement whose bytes no longer match the reviewed replacementVersion' {
        $state = [pscustomobject]@{ Invocations = 0 }
        $builder = {
            param($CurrentText, $Arguments, $TargetPath)
            $null = $Arguments
            $null = $TargetPath
            $state.Invocations++
            ([string]$CurrentText) + "`nSynthetic rebuild $($state.Invocations)."
        }.GetNewClosure()
        $null = Register-DmOperation -Name 'test.variable-replacement' -Modes @('preview', 'apply') -FactChanging $false `
            -ChangeKind edit -AllowedArguments @{} -Builder $builder
        try {
            $request = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'test.variable-replacement' -Mode preview `
                -Targets @('Adventures/Synthetic Arc.md') -Arguments ([ordered]@{})
            $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
            $preview = (Invoke-DmPreview -Request $request).preview
            $apply = New-ApprovedApplyRequest -PreviewRequest $request -Preview $preview

            Assert-Completion -Outcome (Invoke-DmApply -Request $apply) -Code 'CONFIRMATION_REQUIRED' -Status 'not completed'
            $state.Invocations | Should -BeGreaterThan 1
            Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
        }
        finally {
            Unregister-DmOperation -Name 'test.variable-replacement'
        }
    }

    It 'produces the same previewId from two separate PowerShell processes' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $parentId = (Invoke-DmPreview -Request $request).preview.previewId
        $harnessPath = Join-Path -Path (Get-TestRepositoryRoot) -ChildPath 'tests\powershell\TestHarness.psm1'

        $firstChildId = Invoke-PreviewInFreshProcess -VaultRoot $fixture.Root -HarnessPath $harnessPath
        $secondChildId = Invoke-PreviewInFreshProcess -VaultRoot $fixture.Root -HarnessPath $harnessPath

        $firstChildId | Should -BeExactly $parentId
        $secondChildId | Should -BeExactly $parentId
    }

    It 'rejects the removed encoding-conversion acknowledgment field' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root
        $request.allowEncodingConversion = $true
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath

        Assert-Completion -Outcome (Invoke-DmPreview -Request $request) -Code 'INVALID_REQUEST' -Status 'not completed'
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
    }

    It 'returns USER_CANCELLED with zero writes when a preview is declined or withdrawn' {
        $request = New-TextEditRequest -VaultRoot $fixture.Root -Targets @('Adventures/Synthetic Arc.md', 'Lore/Invented Town.md')
        $preview = (Invoke-DmPreview -Request $request).preview
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        foreach ($reviewId in @($preview.previewId, 'synthetic-withdrawal-id')) {
            $declined = [ordered]@{}
            foreach ($key in $request.Keys) { $declined[$key] = $request[$key] }
            $declined.mode = 'apply'
            $declined.requestId = 'test-' + [guid]::NewGuid().ToString('N')
            $declined.declinedReviewId = $reviewId
            Assert-Completion -Outcome (Invoke-DmApply -Request $declined) -Code 'USER_CANCELLED' -Status 'not completed'
            Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before
        }
    }
}
