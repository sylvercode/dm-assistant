Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimePreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultConfiguration.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'OperationRequest.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'SafeNoteWriter.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ChangePreview.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'OperationDiagnostics.psm1')

function New-DmApplyBlockedResult {
    <#
    .SYNOPSIS
    Creates a sanitized result for an apply operation blocked before writing.
    .PARAMETER Operation
    Operation identifier; a blank value is reported as unknown.
    .PARAMETER Code
    Stable completion code explaining the block.
    .PARAMETER Targets
    Ordered requested vault-relative targets.
    .PARAMETER Message
    Untrusted caller message; the result uses a fixed safe diagnostic.
    .PARAMETER RemainingWork
    Work items required before the operation can complete.
    .PARAMETER Details
    Untrusted details from which only a safe target may be retained.
    .PARAMETER UnchangedTargets
    Optional explicit outcomes for targets that were not changed.
    #>
    param(
        [string]$Operation,
        [string]$Code,
        [string[]]$Targets = @(),
        [string]$Message,
        [string[]]$RemainingWork = @(),
        [System.Collections.IDictionary]$Details,
        [object[]]$UnchangedTargets
    )
    $arguments = @{
        Operation = $(if ([string]::IsNullOrWhiteSpace($Operation)) { 'unknown' } else { $Operation })
        State = 'Blocked'
        CompletionCode = $Code
        Targets = $Targets
        RemainingWork = $RemainingWork
        Message = $Message
    }
    if ($PSBoundParameters.ContainsKey('UnchangedTargets')) { $arguments.UnchangedTargets = $UnchangedTargets }
    $diagnostic = New-DmSafeDiagnostic -Code $Code -Message $Message -Details $Details
    $arguments.Message = [string]$diagnostic.message
    if ($diagnostic.PSObject.Properties['details']) {
        $safeDetails = [ordered]@{}
        if ($diagnostic.details.PSObject.Properties['target']) {
            $safeDetails.target = [string]$diagnostic.details.target
        }
        if ($diagnostic.details.PSObject.Properties['changedDependencies']) {
            $safeDetails.changedDependencies = [string[]]$diagnostic.details.changedDependencies
        }
        $arguments.Details = $safeDetails
    }
    New-DmEntryPointResult @arguments
}

function New-DmApplyPlanFailure {
    <#
    .SYNOPSIS
    Reports an apply-plan failure without writing any target.
    .PARAMETER Operation
    Operation identifier for the result.
    .PARAMETER Code
    Specific failure or conflict completion code.
    .PARAMETER Targets
    Ordered requested vault-relative targets.
    .PARAMETER FailureIndex
    Index of the failed target; later targets are marked not attempted.
    .PARAMETER Message
    Untrusted failure message passed to diagnostic sanitization.
    #>
    param(
        [string]$Operation,
        [string]$Code,
        [string[]]$Targets,
        [int]$FailureIndex,
        [string]$Message
    )
    $records = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        $outcome = if ($i -lt $FailureIndex) { 'unchanged' } elseif ($i -eq $FailureIndex -and $Code -ceq 'TARGET_CONFLICT') { 'conflict' } elseif ($i -eq $FailureIndex) { 'failed' } else { 'not attempted' }
        $records.Add((New-DmTargetRecord -Path $Targets[$i] -Outcome $outcome))
    }
    $remaining = [string[]]@(for ($i = $FailureIndex; $i -lt $Targets.Count; $i++) { "Apply the change to $($Targets[$i]) after resolving the problem." })
    New-DmApplyBlockedResult -Operation $Operation -Code $Code -Targets $Targets -UnchangedTargets $records.ToArray() `
        -RemainingWork $remaining -Message $Message -Details ([ordered]@{ target = $Targets[$FailureIndex] })
}

function Test-DmApprovedTargetVersions {
    <#
    .SYNOPSIS
    Rechecks approved targets against the versions observed in the preview.
    .PARAMETER Preflight
    Successful preflight containing the request and authorized boundary.
    .PARAMETER ReviewedVersions
    Target-version records in request order, including observedVersion.
    #>
    param(
        [Parameter(Mandatory)]$Preflight,
        [Parameter(Mandatory)][object[]]$ReviewedVersions
    )
    for ($i = 0; $i -lt $Preflight.request.targets.Count; $i++) {
        $path = [string]$Preflight.request.targets[$i]
        $resolution = Resolve-DmVaultTarget -Boundary $Preflight.boundary -Path $path
        if ($null -ne $resolution.code) {
            return [pscustomobject][ordered]@{ passed = $false; code = [string]$resolution.code; index = $i; message = 'A reviewed target no longer resolves inside the selected vault.' }
        }
        if (-not $resolution.exists -or $resolution.itemType -cne 'file') {
            return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; index = $i; message = 'A reviewed target is no longer an existing note file.' }
        }
        $read = Read-DmVaultTargetBytes -Boundary $Preflight.boundary -Resolution $resolution
        if (-not $read.ok) {
            return [pscustomobject][ordered]@{ passed = $false; code = [string]$read.code; index = $i; message = 'A reviewed target could not be revalidated.' }
        }
        if ([string]$read.version -cne [string]$ReviewedVersions[$i].observedVersion) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; index = $i; message = 'A reviewed target changed after preview.' }
        }
    }
    [pscustomobject][ordered]@{ passed = $true; code = $null; index = -1; message = '' }
}

function Test-DmApprovedDependencyVersions {
    <#
    .SYNOPSIS
    Revalidates previewed profile, reference, and installed-resource versions.
    .PARAMETER Preflight
    Successful preflight containing the vault boundary.
    .PARAMETER Context
    Established pre-note context and its profile dependencies.
    .PARAMETER ReviewedDependencyVersions
    Ordered dependency identities and versions carried from the approved preview.
    #>
    param(
        [Parameter(Mandatory)]$Preflight,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][object[]]$ReviewedDependencyVersions
    )
    $expectedProfileVersions = [System.Collections.Generic.List[object]]::new()
    foreach ($contextDependency in @($Context.dependencyVersions)) {
        $expected = $null
        foreach ($reviewed in $ReviewedDependencyVersions) {
            if ([string]$reviewed.identity -ceq [string]$contextDependency.identity) { $expected = $reviewed; break }
        }
        if ($null -eq $expected) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changed = @([string]$contextDependency.identity); message = 'The reviewed dependency set is incomplete.' }
        }
        $expectedProfileVersions.Add($expected)
    }
    if ($null -ne $Context.profile) {
        $profileCheck = Test-DmProfileDependencyVersions -Boundary $Preflight.boundary -Profile $Context.profile -ReviewedVersions $expectedProfileVersions.ToArray()
        if (-not $profileCheck.passed) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changed = [string[]]$profileCheck.changedIdentities; message = 'A reviewed profile or reference changed after preview.' }
        }
    }

    try { $current = Get-DmCurrentChangeDependencyVersions -Boundary $Preflight.boundary -Profile $Context.profile }
    catch {
        return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changed = @(); message = 'A reviewed profile, reference, or installed resource could not be revalidated.' }
    }
    $comparison = Test-DmChangeDependencyVersions -Current $current -Expected $ReviewedDependencyVersions
    if (-not $comparison.matches) {
        return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changed = [string[]]$comparison.changedIdentities; message = 'A reviewed profile, reference, or installed resource changed after preview.' }
    }
    [pscustomobject][ordered]@{ passed = $true; code = $null; changed = @(); message = '' }
}

function Invoke-DmApplyNoteChanges {
    <#
    .SYNOPSIS
    Applies prepared note changes in order, stopping at the first failure.
    .DESCRIPTION
    Earlier successful writes remain in place and later targets are not
    attempted; the result reports exact changed and unchanged targets.
    .PARAMETER Boundary
    Canonical authorized vault boundary for target rechecks.
    .PARAMETER Targets
    Ordered prepared targets with resolutions, observed versions, and replacement bytes.
    .PARAMETER Operation
    Operation identifier for the result.
    .PARAMETER ExpectedDependencies
    Optional approved or previously observed dependency-version snapshot.
    .PARAMETER Profile
    Validated profile used for dependency revalidation, or null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][object[]]$Targets,
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$ExpectedDependencies,
        [AllowNull()]$Profile
    )

    $changed = [System.Collections.Generic.List[object]]::new()
    $unchanged = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        $target = $Targets[$i]
        $path = [string]$target.path
        if ($target.PSObject.Properties['unchanged'] -and $target.unchanged) {
            $unchanged.Add((New-DmTargetRecord -Path $path -Outcome 'unchanged'))
            continue
        }

        try {
            $writerArguments = @{ Boundary = $Boundary; Target = $target; Profile = $Profile }
            if ($PSBoundParameters.ContainsKey('ExpectedDependencies') -and $null -ne $ExpectedDependencies) {
                $writerArguments.ExpectedDependencies = $ExpectedDependencies
            }
            $write = Invoke-DmSafeNoteWrite @writerArguments
        }
        catch [System.Management.Automation.PipelineStoppedException] {
            $write = [pscustomobject][ordered]@{ ok = $false; code = 'INTERRUPTED'; reason = 'The operation was interrupted.' }
        }
        catch [System.OperationCanceledException] {
            $write = [pscustomobject][ordered]@{ ok = $false; code = 'INTERRUPTED'; reason = 'The operation was interrupted.' }
        }
        catch {
            $write = [pscustomobject][ordered]@{ ok = $false; code = 'WRITE_FAILED'; reason = 'The target could not be atomically replaced.' }
        }

        if (-not $write.ok) {
            $code = [string]$write.code
            if ([string]::IsNullOrWhiteSpace($code)) { $code = 'WRITE_FAILED' }
            $failedOutcome = if ($code -cin @('TARGET_CONFLICT', 'PATH_OUTSIDE_VAULT')) { 'conflict' } else { 'failed' }
            $unchanged.Add((New-DmTargetRecord -Path $path -Outcome $failedOutcome))
            for ($j = $i + 1; $j -lt $Targets.Count; $j++) {
                $unchanged.Add((New-DmTargetRecord -Path ([string]$Targets[$j].path) -Outcome 'not attempted'))
            }
            $remaining = [string[]]@(for ($j = $i; $j -lt $Targets.Count; $j++) { [string]$Targets[$j].path })
            $details = [ordered]@{ target = $path }
            $diagnostic = New-DmSafeDiagnostic -Code $code -Message ([string]$write.reason) -Details $details
            return (New-DmEntryPointResult -Operation $Operation -State Failure -CompletionCode $code -Targets ([string[]]@($Targets | ForEach-Object { [string]$_.path })) `
                -ChangedTargets $changed.ToArray() -UnchangedTargets $unchanged.ToArray() -RemainingWork $remaining `
                -Message ([string]$diagnostic.message) -Details $(if ($diagnostic.PSObject.Properties['details']) { [ordered]@{ target = [string]$diagnostic.details.target } } else { $null }))
        }
        $changed.Add((New-DmTargetRecord -Path $path -Outcome 'written'))
    }

    $allPaths = [string[]]@($Targets | ForEach-Object { [string]$_.path })
    $completionCode = if ($changed.Count -gt 0) { 'OK' } else { 'NO_CHANGES' }
    New-DmEntryPointResult -Operation $Operation -State Complete -CompletionCode $completionCode -Targets $allPaths `
        -ChangedTargets $changed.ToArray() -UnchangedTargets $unchanged.ToArray()
}

function Invoke-DmApply {
    <#
    .SYNOPSIS
    Applies a registered operation after required review and safety checks.
    .DESCRIPTION
    Applies registered operation replacements in request order. Returns
    [pscustomobject]@{ result; applied }; every result is built by the shared
    New-DmEntryPointResult adapter.
    .PARAMETER Request
    Explicit contract request in apply mode, including reviewed preview data
    when approval is required.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Request)

    $operation = ''
    $targets = [string[]]@()
    try {
        $preflight = Invoke-DmPreflight -Request $Request
        $operation = [string]$preflight.operation
        $targets = [string[]]$preflight.targets
        if (-not $preflight.passed) { return [pscustomobject][ordered]@{ result = $preflight.result; applied = @() } }
        if ($preflight.request.mode -cne 'apply') {
            $result = New-DmApplyBlockedResult -Operation $operation -Code 'INVALID_REQUEST' -Targets $targets `
                -RemainingWork @('Send an apply-mode request, then retry.') -Message 'Applying changes requires mode apply.'
            return [pscustomobject][ordered]@{ result = $result; applied = @() }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$preflight.request.declinedReviewId)) {
            $result = New-DmApplyBlockedResult -Operation $operation -Code 'USER_CANCELLED' -Targets $targets `
                -UnchangedTargets ([object[]]$targets) -RemainingWork @('No changes were made because the review was declined or withdrawn.') `
                -Message 'The requested review was declined; no target was changed.'
            return [pscustomobject][ordered]@{ result = $result; applied = @() }
        }

        $registration = Get-DmOperation -Name $operation
        $requiresApproval = $null -eq $registration -or $registration.factChanging -or
            $registration.changeKind -cne 'edit' -or $targets.Count -gt 1
        if ($requiresApproval -and [string]::IsNullOrWhiteSpace([string]$preflight.request.approvedPreviewId)) {
            $result = New-DmApplyBlockedResult -Operation $operation -Code 'CONFIRMATION_REQUIRED' -Targets $targets `
                -RemainingWork @('Review the exact preview and submit its previewId and reviewed versions to apply.') `
                -Message 'This change requires approval of an exact current preview.'
            return [pscustomobject][ordered]@{ result = $result; applied = @() }
        }

        $runtimeVersion = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$preflight.request.approvedPreviewId)) {
            try { $runtimeVersion = Get-DmRuntimeVersion }
            catch {
                $result = New-DmApplyBlockedResult -Operation $operation -Code 'CONFIRMATION_REQUIRED' -Targets $targets `
                    -RemainingWork @('Rebuild or repair the installed runtime, preview the change again, and retry.') `
                    -Message 'The runtime version for the approved preview could not be verified.'
                return [pscustomobject][ordered]@{ result = $result; applied = @() }
            }
            $digest = Get-DmPreviewDigest -Request $preflight.request -ReviewedVersions ([object[]]$preflight.request.reviewedVersions) `
                -ReviewedDependencyVersions ([object[]]$preflight.request.reviewedDependencyVersions) -RuntimeVersion $runtimeVersion `
                -CanonicalVaultRoot ([string]$preflight.boundary.canonicalRoot)
            if ($digest -cne [string]$preflight.request.approvedPreviewId) {
                $result = New-DmApplyBlockedResult -Operation $operation -Code 'CONFIRMATION_REQUIRED' -Targets $targets `
                    -RemainingWork @('Review the current request and preview it again before applying.') `
                    -Message 'The approval does not match the exact current request, runtime, and reviewed changes.'
                return [pscustomobject][ordered]@{ result = $result; applied = @() }
            }
        }

        $context = Get-DmPreNoteContext -Preflight $preflight
        if (-not $context.passed) { return [pscustomobject][ordered]@{ result = $context.result; applied = @() } }

        if (-not [string]::IsNullOrWhiteSpace([string]$preflight.request.approvedPreviewId)) {
            $dependencyCheck = Test-DmApprovedDependencyVersions -Preflight $preflight -Context $context `
                -ReviewedDependencyVersions ([object[]]$preflight.request.reviewedDependencyVersions)
            if (-not $dependencyCheck.passed) {
                $details = [ordered]@{}
                if ($dependencyCheck.changed.Count -gt 0) { $details.changedDependencies = [string[]]$dependencyCheck.changed }
                $result = New-DmApplyBlockedResult -Operation $operation -Code 'TARGET_CONFLICT' -Targets $targets `
                    -RemainingWork @('Revalidate the changed profile, reference, or installed resource and preview again.') `
                    -Message ([string]$dependencyCheck.message) -Details $details
                return [pscustomobject][ordered]@{ result = $result; applied = @() }
            }

            $targetCheck = Test-DmApprovedTargetVersions -Preflight $preflight -ReviewedVersions ([object[]]$preflight.request.reviewedVersions)
            if (-not $targetCheck.passed) {
                $result = New-DmApplyPlanFailure -Operation $operation -Code ([string]$targetCheck.code) -Targets $targets `
                    -FailureIndex ([int]$targetCheck.index) -Message ([string]$targetCheck.message)
                return [pscustomobject][ordered]@{ result = $result; applied = @() }
            }
        }

        $changePlan = Get-DmChangePlan -Preflight $preflight -Context $context
        if (-not $changePlan.ok) { return [pscustomobject][ordered]@{ result = $changePlan.result; applied = @() } }

        if (-not [string]::IsNullOrWhiteSpace([string]$preflight.request.approvedPreviewId)) {
            $currentTargets = [object[]]$changePlan.plan
            $reviewedTargets = [object[]]$preflight.request.reviewedVersions
            for ($i = 0; $i -lt $currentTargets.Count; $i++) {
                if ([string]$currentTargets[$i].observedVersion -cne [string]$reviewedTargets[$i].observedVersion) {
                    $result = New-DmApplyPlanFailure -Operation $operation -Code 'TARGET_CONFLICT' -Targets $targets -FailureIndex $i `
                        -Message 'A reviewed target changed after the approval digest was checked.'
                    return [pscustomobject][ordered]@{ result = $result; applied = @() }
                }
            }
            $dependenciesMatch = Test-DmChangeDependencyVersions -Current ([object[]]$changePlan.dependencies) `
                -Expected ([object[]]$preflight.request.reviewedDependencyVersions)
            if (-not $dependenciesMatch.matches) {
                $details = [ordered]@{ changedDependencies = [string[]]$dependenciesMatch.changedIdentities }
                $result = New-DmApplyBlockedResult -Operation $operation -Code 'TARGET_CONFLICT' -Targets $targets `
                    -RemainingWork @('Revalidate the changed profile, reference, or installed resource and preview again.') `
                    -Message 'A reviewed profile, reference, or installed resource changed after preview.' -Details $details
                return [pscustomobject][ordered]@{ result = $result; applied = @() }
            }
            for ($i = 0; $i -lt $currentTargets.Count; $i++) {
                if ([string]$currentTargets[$i].replacementVersion -cne [string]$reviewedTargets[$i].replacementVersion -or
                    [string]$currentTargets[$i].conversionDecision -cne [string]$reviewedTargets[$i].conversionDecision) {
                    $result = New-DmApplyPlanFailure -Operation $operation -Code 'CONFIRMATION_REQUIRED' -Targets $targets -FailureIndex $i `
                        -Message 'The rebuilt replacement differs from the exact reviewed preview.'
                    return [pscustomobject][ordered]@{ result = $result; applied = @() }
                }
            }
        }

        $result = Invoke-DmApplyNoteChanges -Boundary $preflight.boundary -Targets ([object[]]$changePlan.plan) -Operation $operation `
            -ExpectedDependencies ([object[]]$changePlan.dependencies) -Profile $context.profile
        $planByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($entry in $changePlan.plan) { $planByPath[[string]$entry.path] = $entry }
        $applied = [System.Collections.Generic.List[object]]::new()
        foreach ($target in $result.changedTargets) {
            $planEntry = $planByPath[[string]$target.path]
            $applied.Add([pscustomobject][ordered]@{ path = [string]$target.path; outcome = 'written'; version = [string]$planEntry.replacementVersion })
        }
        [pscustomobject][ordered]@{ result = $result; applied = [object[]]$applied.ToArray() }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        $result = New-DmApplyBlockedResult -Operation $operation -Code 'INTERRUPTED' -Targets $targets `
            -RemainingWork @('The operation was interrupted; inspect the reported target outcomes before retrying.') `
            -Message 'The operation was interrupted.'
        [pscustomobject][ordered]@{ result = $result; applied = @() }
    }
    catch {
        $result = New-DmApplyBlockedResult -Operation $operation -Code 'OPERATION_FAILED' -Targets $targets `
            -RemainingWork @('Review the request and current target state before retrying.') `
            -Message 'The apply operation failed safely; inspect the target outcomes before retrying.'
        [pscustomobject][ordered]@{ result = $result; applied = @() }
    }
}

Export-ModuleMember -Function Invoke-DmApply, Invoke-DmApplyNoteChanges
