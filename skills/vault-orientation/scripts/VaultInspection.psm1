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
    $remaining = @(for ($i = $FailedIndex; $i -lt $Targets.Count; $i++) { "Inspect $($Targets[$i]) after resolving the problem." })
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
    $context = Get-DmPreNoteContext -Preflight $preflight
    if (-not $context.passed) { return (New-DmInspectionOutcome -Result $context.result) }
    $boundary = $preflight.boundary

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

    $inspection = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $resolutions.Count; $i++) {
        $resolution = $resolutions[$i]
        $version = $null
        if ($resolution.itemType -ceq 'file') {
            $read = Read-DmVaultTargetBytes -Boundary $boundary -Resolution $resolution
            if (-not $read.ok) {
                $result = New-DmInspectionFailure -Operation $operation -Code $read.code -Message "Inspection stopped: $($read.reason)" -Targets $targets -FailedIndex $i -Reason $read.reason
                return (New-DmInspectionOutcome -Result $result)
            }
            $version = $read.version
            $read.bytes = $null
        }
        else {
            $check = Confirm-DmVaultTarget -Boundary $boundary -Resolution $resolution
            if (-not $check.confirmed) {
                $result = New-DmInspectionFailure -Operation $operation -Code $check.code -Message "Inspection stopped: $($check.reason)" -Targets $targets -FailedIndex $i -Reason $check.reason
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
    $result = New-DmEntryPointResult -Operation $operation -State Complete -CompletionCode 'OK' -UnchangedTargets $targets -Targets $targets
    New-DmInspectionOutcome -Result $result -Inspection $inspection.ToArray()
}

Export-ModuleMember -Function Invoke-DmInspect
