Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimePreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultConfiguration.psm1')

# Read-only inspection of explicit vault-relative targets. Runs only after the
# full preflight (runtime, request shape, readiness, exact-vault
# authorization, canonical root) and never creates, changes, or deletes a
# file. Results report existence, type, and a byte fingerprint, never content.

function New-DmInspectionOutcome {
    <#
    .SYNOPSIS
    Combines an operation result with ordered inspection records.
    .PARAMETER Result
    Shared contract result for the inspection.
    .PARAMETER Inspection
    Optional target-inspection records; empty when inspection did not complete.
    #>
    param($Result, [object[]]$Inspection = @())
    [pscustomobject][ordered]@{ result = $Result; inspection = [object[]]$Inspection }
}

function New-DmInspectionFailure {
    <#
    .SYNOPSIS
    Builds a failed inspection result with exact target outcomes.
    .PARAMETER Operation
    Operation identifier for the result.
    .PARAMETER Code
    Specific completion code for the failed access.
    .PARAMETER Message
    Safe diagnostic message for the failure.
    .PARAMETER Targets
    Ordered requested vault-relative targets.
    .PARAMETER FailedIndex
    Index of the failed target; subsequent targets are not attempted.
    .PARAMETER Reason
    Safe reason describing the failed path or read check.
    #>
    param([string]$Operation, [string]$Code, [string]$Message, [string[]]$Targets, [int]$FailedIndex, [string]$Reason)
    $records = for ($i = 0; $i -lt $Targets.Count; $i++) {
        $outcome = if ($i -lt $FailedIndex) { 'unchanged' } elseif ($i -eq $FailedIndex) { 'failed' } else { 'not attempted' }
        New-DmTargetRecord -Path $Targets[$i] -Outcome $outcome
    }
    $remaining = @(for ($i = 0; $i -lt $Targets.Count; $i++) { "Inspect $($Targets[$i]) after resolving the problem." })
    New-DmEntryPointResult -Operation $Operation -State Failure -CompletionCode $Code -Targets $Targets -UnchangedTargets @($records) `
        -RemainingWork $remaining -Message $Message -Details ([ordered]@{ target = $Targets[$FailedIndex]; reason = $Reason })
}

function Invoke-DmInspect {
    <#
    .SYNOPSIS
    Inspects explicit vault targets without changing them.
    .DESCRIPTION
    Read-only inspect entry point for one contract section 2 request in
    'inspect' mode. Returns [pscustomobject]@{ result; inspection } where
    result is the contract result and inspection holds, for each target in
    request order, [pscustomobject]@{ path; exists; itemType (file,
    directory, missing); version ('sha256:<hex>' of the file bytes, 'absent'
    for a missing target, $null for a directory); viaLink; resolvedTarget
    (vault-relative path after link resolution, or $null) }. inspection is
    empty unless every target was inspected. A missing target is reported,
    never guessed or created. Completes with OK; a blocked gate returns its
    code; an escaping or uncontainable target returns PATH_OUTSIDE_VAULT and
    an inaccessible component or failed read returns READ_FAILED, before or
    at that target's access.
    .PARAMETER Request
    Explicit contract request in inspect mode, including the vault and targets.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Request)

    $preflight = Invoke-DmPreflight -Request $Request
    if (-not $preflight.passed) { return (New-DmInspectionOutcome -Result $preflight.result) }
    $request = $preflight.request
    $operation = [string]$request.operation
    $targets = [string[]]$request.targets
    if ($request.mode -cne 'inspect') {
        $result = New-DmBlockedResult -Operation $operation -CompletionCode 'INVALID_REQUEST' -Targets $targets `
            -Message 'Inspection requires mode inspect.' -RemainingWork @('Send an inspect-mode request, then retry.') -Detail ([ordered]@{ mode = [string]$request.mode })
        return (New-DmInspectionOutcome -Result $result)
    }
    try { $context = Get-DmPreNoteContext -Preflight $preflight }
    catch {
        $result = New-DmBlockedResult -Operation $operation -CompletionCode 'TARGET_CONFLICT' -Targets $targets `
            -Message 'A required profile or guidance dependency could not be verified; nothing was read.' `
            -RemainingWork @('Revalidate the profile and local guidance, then retry.')
        return (New-DmInspectionOutcome -Result $result)
    }
    if (-not $context.passed) { return (New-DmInspectionOutcome -Result $context.result) }
    $boundary = $preflight.boundary
    $dependencyCheck = Test-DmProfileDependencyVersions -Boundary $boundary -Profile $context.profile -ReviewedVersions ([object[]]$context.dependencyVersions)
    if (-not $dependencyCheck.passed) {
        $result = New-DmBlockedResult -Operation $operation -CompletionCode 'TARGET_CONFLICT' -Targets $targets `
            -RemainingWork @($targets | ForEach-Object { "Inspect $_ again after revalidating the profile and guidance." }) `
            -Message 'The profile or required guidance changed after inspection context was loaded; no inspection result was returned.' `
            -Detail ([ordered]@{ changedDependencies = [string[]]$dependencyCheck.changedIdentities })
        return (New-DmInspectionOutcome -Result $result)
    }

    # Resolve every target before any access so an escape or inaccessible path stops the whole request first.
    $resolutions = foreach ($target in $targets) { Resolve-DmVaultTarget -Boundary $boundary -Path $target }
    $resolutions = @($resolutions)
    for ($i = 0; $i -lt $resolutions.Count; $i++) {
        $resolution = $resolutions[$i]
        if ($null -ne $resolution.code) {
            $message = switch ($resolution.code) {
                'PATH_OUTSIDE_VAULT' { 'A target resolves outside the vault or its containment cannot be proven; nothing was read.' }
                'READ_FAILED' { 'A target path component is inaccessible; nothing was read.' }
                default { 'A target is not a valid vault-relative path; nothing was read.' }
            }
            $result = New-DmBlockedResult -Operation $operation -CompletionCode $resolution.code -Targets $targets -Message $message `
                -RemainingWork @('Correct or remove the affected target, then retry.') -Detail ([ordered]@{ target = $resolution.path; reason = $resolution.reason })
            return (New-DmInspectionOutcome -Result $result)
        }
    }
    $uniqueTargets = Test-DmUniqueResolvedTargets -Boundary $boundary -Resolutions ([object[]]$resolutions)
    if (-not $uniqueTargets.isUnique) {
        $result = New-DmBlockedResult -Operation $operation -CompletionCode 'INVALID_REQUEST' -Targets $targets `
            -RemainingWork @('Send each resolved vault target only once, then retry.') `
            -Message 'Two or more requested targets resolve to the same vault path.' `
            -Detail ([ordered]@{ target = $uniqueTargets.duplicatePath })
        return (New-DmInspectionOutcome -Result $result)
    }

    $dependencyCheck = Test-DmProfileDependencyVersions -Boundary $boundary -Profile $context.profile -ReviewedVersions ([object[]]$context.dependencyVersions)
    if (-not $dependencyCheck.passed) {
        $result = New-DmBlockedResult -Operation $operation -CompletionCode 'TARGET_CONFLICT' -Targets $targets `
            -RemainingWork @($targets | ForEach-Object { "Inspect $_ again after revalidating the profile and guidance." }) `
            -Message 'The profile or required guidance changed before target inspection; no inspection result was returned.' `
            -Detail ([ordered]@{ changedDependencies = [string[]]$dependencyCheck.changedIdentities })
        return (New-DmInspectionOutcome -Result $result)
    }

    $inspection = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $resolutions.Count; $i++) {
        $resolution = $resolutions[$i]
        $version = $null
        if ($resolution.itemType -ceq 'file') {
            try { $read = Read-DmVaultTargetBytes -Boundary $boundary -Resolution $resolution }
            catch {
                $result = New-DmInspectionFailure -Operation $operation -Code 'READ_FAILED' `
                    -Message 'Inspection stopped because the requested target could not be read.' `
                    -Targets $targets -FailedIndex $i -Reason 'The target read failed.'
                return (New-DmInspectionOutcome -Result $result)
            }
            if (-not $read.ok) {
                $result = New-DmInspectionFailure -Operation $operation -Code $read.code `
                    -Message 'Inspection stopped because the requested target could not be read.' `
                    -Targets $targets -FailedIndex $i -Reason 'The target read failed.'
                return (New-DmInspectionOutcome -Result $result)
            }
            $version = $read.version
            $read.bytes = $null
        }
        else {
            try { $check = Confirm-DmVaultTarget -Boundary $boundary -Resolution $resolution }
            catch {
                $result = New-DmInspectionFailure -Operation $operation -Code 'READ_FAILED' `
                    -Message 'Inspection stopped because the requested target could not be confirmed.' `
                    -Targets $targets -FailedIndex $i -Reason 'The target confirmation failed.'
                return (New-DmInspectionOutcome -Result $result)
            }
            if (-not $check.confirmed) {
                $result = New-DmInspectionFailure -Operation $operation -Code $check.code `
                    -Message 'Inspection stopped because the requested target could not be confirmed.' `
                    -Targets $targets -FailedIndex $i -Reason 'The target confirmation failed.'
                return (New-DmInspectionOutcome -Result $result)
            }
            if (-not $resolution.exists) { $version = 'absent' }
        }
        $inspection.Add([pscustomobject][ordered]@{
                path           = $resolution.path
                exists         = $resolution.exists
                itemType       = $resolution.itemType
                version        = $version
                viaLink        = $resolution.viaLink
                resolvedTarget = $resolution.resolvedRelativePath
            })
    }
    $dependencyCheck = Test-DmProfileDependencyVersions -Boundary $boundary -Profile $context.profile -ReviewedVersions ([object[]]$context.dependencyVersions)
    if (-not $dependencyCheck.passed) {
        $result = New-DmEntryPointResult -Operation $operation -State Failure -CompletionCode 'TARGET_CONFLICT' -Targets $targets `
            -UnchangedTargets $targets -RemainingWork @($targets | ForEach-Object { "Inspect $_ again after revalidating the profile and guidance." }) `
            -Message 'The profile or required guidance changed during inspection; no inspection result was returned.' `
            -Details ([ordered]@{ changedDependencies = [string[]]$dependencyCheck.changedIdentities })
        return (New-DmInspectionOutcome -Result $result)
    }
    $result = New-DmEntryPointResult -Operation $operation -State Complete -CompletionCode 'OK' -UnchangedTargets $targets -Targets $targets
    New-DmInspectionOutcome -Result $result -Inspection $inspection.ToArray()
}

Export-ModuleMember -Function Invoke-DmInspect
