Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DependencyPreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimePreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultConfiguration.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'OperationRequest.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PluginResources.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'SafeNoteWriter.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'OperationDiagnostics.psm1')

function ConvertTo-DmJcsString {
    <#
    .SYNOPSIS
    Encodes a string as a JSON Canonicalization Scheme string.
    .PARAMETER Value
    String to escape and surround with JSON quotation marks.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        if ($code -eq 0x22) {
            [void]$builder.Append('\"')
        }
        elseif ($code -eq 0x5C) {
            [void]$builder.Append('\\')
        }
        elseif ($code -eq 0x08) {
            [void]$builder.Append('\b')
        }
        elseif ($code -eq 0x09) {
            [void]$builder.Append('\t')
        }
        elseif ($code -eq 0x0A) {
            [void]$builder.Append('\n')
        }
        elseif ($code -eq 0x0C) {
            [void]$builder.Append('\f')
        }
        elseif ($code -eq 0x0D) {
            [void]$builder.Append('\r')
        }
        elseif ($code -lt 0x20) {
            [void]$builder.Append('\u')
            [void]$builder.Append($code.ToString('x4', [System.Globalization.CultureInfo]::InvariantCulture))
        }
        else {
            [void]$builder.Append($character)
        }
    }
    [void]$builder.Append('"')
    $builder.ToString()
}

function ConvertTo-DmJcsValue {
    <#
    .SYNOPSIS
    Serializes supported values deterministically for canonical JSON.
    .DESCRIPTION
    Object keys are sorted ordinally; unsupported value types are rejected.
    .PARAMETER Value
    Null, string, Boolean, integer, list, dictionary, or custom object to serialize.
    #>
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-DmJcsString -Value $Value) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]) {
        return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture))
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $Value.Keys) {
            if ($key -isnot [string]) { throw [System.ArgumentException]::new('JCS object keys must be strings.') }
            $keys.Add($key)
        }
        $sortedKeys = [string[]]$keys.ToArray()
        [System.Array]::Sort($sortedKeys, [System.StringComparer]::Ordinal)
        $members = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $sortedKeys) {
            $members.Add((ConvertTo-DmJcsString -Value $key) + ':' + (ConvertTo-DmJcsValue -Value $Value[$key]))
        }
        return '{' + ($members -join ',') + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')) {
                if ($map.ContainsKey($property.Name)) { throw [System.ArgumentException]::new('JCS object keys must be unique.') }
                $map.Add($property.Name, $property.Value)
            }
        }
        return (ConvertTo-DmJcsValue -Value $map)
    }
    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        $elements = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { $elements.Add((ConvertTo-DmJcsValue -Value $item)) }
        return '[' + ($elements -join ',') + ']'
    }
    throw [System.ArgumentException]::new('JCS values must contain only objects, arrays, strings, booleans, null, and integers.')
}

function ConvertTo-DmJcsJson {
    <#
    .SYNOPSIS
    Produces canonical JSON for the supported preview-digest value types.
    .PARAMETER Value
    Value to serialize, including null and nested supported values.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Value)
    ConvertTo-DmJcsValue -Value $Value
}

function Get-DmSha256Hex {
    <#
    .SYNOPSIS
    Computes the lowercase SHA-256 hexadecimal digest of bytes.
    .PARAMETER Bytes
    Exact byte sequence to hash; an empty sequence is valid.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-DmRuntimeVersion {
    <#
    .SYNOPSIS
    Fingerprints the installed plugin version, runtime modules, and inventory.
    .DESCRIPTION
    The returned version changes when the manifest version, any module byte,
    or the dependency inventory changes, invalidating earlier previews.
    #>
    [CmdletBinding()]
    param()

    $repositoryRoot = [System.IO.Path]::GetDirectoryName(
        [System.IO.Path]::GetDirectoryName(
            [System.IO.Path]::GetDirectoryName($PSScriptRoot)
        )
    )
    $manifestPath = [System.IO.Path]::Combine($repositoryRoot, 'plugin.json')
    $manifestText = [System.IO.File]::ReadAllText($manifestPath, [System.Text.UTF8Encoding]::new($false, $true))
    $manifest = $manifestText | ConvertFrom-Json -Depth 16 -ErrorAction Stop
    if ($null -eq $manifest -or $manifest.version -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest.version)) {
        throw [System.IO.InvalidDataException]::new('The installed plugin version is unavailable.')
    }

    $modules = [System.IO.Directory]::GetFiles($PSScriptRoot, '*.psm1', [System.IO.SearchOption]::TopDirectoryOnly)
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $modules) {
        $name = [System.IO.Path]::GetFileName($path)
        $identity = 'skills/vault-orientation/scripts/' + $name
        $entries.Add([pscustomobject][ordered]@{ identity = $identity; version = 'sha256:' + (Get-DmSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($path))) })
    }
    $entries.Add((Get-DmDependencyInventoryVersion))
    $orderedEntries = [object[]]$entries.ToArray()
    [Array]::Sort($orderedEntries, [System.Comparison[object]]{
            param($left, $right)
            [System.StringComparer]::Ordinal.Compare([string]$left.identity, [string]$right.identity)
        })
    $canonical = ConvertTo-DmJcsJson -Value $orderedEntries
    $fingerprint = 'sha256:' + (Get-DmSha256Hex -Bytes ([System.Text.UTF8Encoding]::new($false, $true).GetBytes($canonical)))
    [string]$manifest.version + ':' + $fingerprint
}

function Get-DmPreviewDigest {
    <#
    .SYNOPSIS
    Computes the deterministic identifier for an exact reviewed preview.
    .DESCRIPTION
    The digest binds request scope, target and replacement versions, encoding
    decisions, dependencies, the canonical vault root, and runtime version.
    .PARAMETER Request
    Normalized operation request whose scope and arguments are bound.
    .PARAMETER ReviewedVersions
    Ordered target paths, observed versions, replacement versions, and decisions.
    .PARAMETER ReviewedDependencyVersions
    Ordered identities and versions of dependencies used by the preview.
    .PARAMETER RuntimeVersion
    Installed runtime fingerprint used to construct the preview.
    .PARAMETER CanonicalVaultRoot
    Resolved root to bind; when omitted, uses the request's explicit vaultRoot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][object[]]$ReviewedVersions,
        [Parameter(Mandatory)][object[]]$ReviewedDependencyVersions,
        [Parameter(Mandatory)][string]$RuntimeVersion,
        [string]$CanonicalVaultRoot
    )

    if ([string]::IsNullOrWhiteSpace($CanonicalVaultRoot)) { $CanonicalVaultRoot = [string]$Request.vaultRoot }
    $targets = [string[]]$Request.targets
    $digestTargetVersions = [System.Collections.Generic.List[object]]::new()
    foreach ($version in $ReviewedVersions) {
        $digestTargetVersions.Add([pscustomobject][ordered]@{
                path = [string]$version.path
                observedVersion = [string]$version.observedVersion
                replacementVersion = [string]$version.replacementVersion
                conversionDecision = [string]$version.conversionDecision
            })
    }
    $dependencies = [System.Collections.Generic.List[object]]::new()
    foreach ($dependency in $ReviewedDependencyVersions) {
        $dependencies.Add([pscustomobject][ordered]@{ identity = [string]$dependency.identity; version = [string]$dependency.version })
    }
    $digestInput = [pscustomobject][ordered]@{
        contractVersion = [string]$Request.contractVersion
        runtimeVersion = $RuntimeVersion
        operation = [string]$Request.operation
        vaultRoot = $CanonicalVaultRoot
        campaignGroup = $Request.campaignGroup
        targets = $targets
        arguments = $Request.arguments
        reviewedVersions = $digestTargetVersions.ToArray()
        reviewedDependencyVersions = $dependencies.ToArray()
    }
    $canonical = ConvertTo-DmJcsJson -Value $digestInput
    'sha256:' + (Get-DmSha256Hex -Bytes ([System.Text.UTF8Encoding]::new($false, $true).GetBytes($canonical)))
}

function New-DmChangeEntryResult {
    <#
    .SYNOPSIS
    Builds a sanitized result for a preview or change-planning entry point.
    .PARAMETER Operation
    Operation identifier; an empty value is reported as unknown.
    .PARAMETER State
    Entry-point state passed to the shared result adapter.
    .PARAMETER Code
    Stable completion code for the result.
    .PARAMETER Targets
    Ordered requested vault-relative targets.
    .PARAMETER ChangedTargets
    Target records or paths changed by the operation.
    .PARAMETER UnchangedTargets
    Target records or paths that were not changed.
    .PARAMETER RemainingWork
    Work items remaining after an incomplete operation.
    .PARAMETER Message
    Untrusted caller message; incomplete diagnostics use a fixed safe message.
    .PARAMETER Details
    Untrusted details from which only a safe target may be retained.
    #>
    param(
        [string]$Operation,
        [string]$State,
        [string]$Code,
        [string[]]$Targets = @(),
        [object[]]$ChangedTargets = @(),
        [object[]]$UnchangedTargets = @(),
        [object[]]$RemainingWork = @(),
        [string]$Message,
        [System.Collections.IDictionary]$Details
    )
    $arguments = @{
        Operation = $(if ([string]::IsNullOrEmpty($Operation)) { 'unknown' } else { $Operation })
        State = $State
        CompletionCode = $Code
        Targets = $Targets
        ChangedTargets = $ChangedTargets
        UnchangedTargets = $UnchangedTargets
        RemainingWork = $RemainingWork
    }
    if ($State -cne 'Complete') {
        $diagnostic = New-DmSafeDiagnostic -Code $Code -Message $Message -Details $Details
        $arguments.Message = [string]$diagnostic.message
        if ($diagnostic.PSObject.Properties['details']) {
            $arguments.Details = [ordered]@{ target = [string]$diagnostic.details.target }
        }
    }
    New-DmEntryPointResult @arguments
}

function Get-DmChangeClassification {
    <#
    .SYNOPSIS
    Classifies a registered change and determines whether approval is required.
    .PARAMETER Registration
    Registered operation metadata, including change kind and fact-changing status.
    .PARAMETER TargetCount
    Number of requested targets; multiple targets require approval.
    #>
    param([Parameter(Mandatory)]$Registration, [Parameter(Mandatory)][int]$TargetCount)
    $requiresApproval = $Registration.factChanging -or $Registration.changeKind -cne 'edit' -or $TargetCount -gt 1
    [pscustomobject][ordered]@{
        requiresApproval = [bool]$requiresApproval
        proposedOperation = switch ([string]$Registration.changeKind) {
            'edit' { 'replace content' }
            'delete' { 'delete' }
            'reorganize' { 'reorganize' }
            'read' { 'read' }
            default { 'unclassified change' }
        }
    }
}

function Get-DmChangePlan {
    <#
    .SYNOPSIS
    Builds a read-only change plan and fingerprints its targets and dependencies.
    .DESCRIPTION
    Requires successful preflight and context. Unsafe encoding or stale inputs
    produce a blocked result rather than an applicable plan.
    .PARAMETER Preflight
    Successful preflight outcome containing the normalized request and boundary.
    .PARAMETER Context
    Successful pre-note context with profile and dependency versions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Preflight,
        [Parameter(Mandatory)]$Context
    )

    $request = $Preflight.request
    $targets = [string[]]$request.targets
    $operation = [string]$request.operation
    $registration = Get-DmOperation -Name $operation
    if ($null -eq $registration -or $null -eq $registration.builder) {
        $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'INVALID_REQUEST' -Targets $targets `
            -RemainingWork @('Select a registered change operation, then retry.') -Message 'The registered operation cannot construct a change.'
        return [pscustomobject][ordered]@{ ok = $false; code = 'INVALID_REQUEST'; result = $result; plan = @() }
    }

    try {
        $dependencies = Get-DmCurrentChangeDependencyVersions -Boundary $Preflight.boundary -Profile $Context.profile
        $inventory = Get-DmDependencyInventoryVersion
    }
    catch {
        $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'TARGET_CONFLICT' -Targets $targets `
            -RemainingWork @('Revalidate the profile and installed references, then retry.') -Message 'A profile, reference, or installed resource could not be revalidated.'
        return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; result = $result; plan = @() }
    }

    $contextDependencies = [System.Collections.Generic.List[object]]::new()
    foreach ($dependency in @($Context.dependencyVersions)) {
        $contextDependencies.Add([pscustomobject][ordered]@{ identity = [string]$dependency.identity; version = [string]$dependency.version })
    }
    $contextDependencies.Add($inventory)
    $shared = Get-DmSharedReferenceResource -Operation $operation -Targets $targets
    if (-not $shared.passed) {
        return [pscustomobject][ordered]@{ ok = $false; code = [string]$shared.result.completionCode; result = $shared.result; plan = @() }
    }
    $contextDependencies.Add([pscustomobject][ordered]@{ identity = [string]$shared.resource.identity; version = [string]$shared.resource.version })
    $contextSnapshot = [object[]]$contextDependencies.ToArray()
    [Array]::Sort($contextSnapshot, [System.Comparison[object]]{
            param($left, $right)
            [System.StringComparer]::Ordinal.Compare([string]$left.identity, [string]$right.identity)
        })
    $contextDependencyCheck = Test-DmChangeDependencyVersions -Current $dependencies -Expected $contextSnapshot
    if (-not $contextDependencyCheck.matches) {
        $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'TARGET_CONFLICT' -Targets $targets `
            -RemainingWork @('Revalidate the profile and installed references, then retry.') -Message 'A profile, reference, or installed resource changed during preflight.'
        return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; result = $result; plan = @() }
    }

    $resolutions = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $targets.Count; $i++) {
        $resolution = Resolve-DmVaultTarget -Boundary $Preflight.boundary -Path $targets[$i]
        if ($null -ne $resolution.code -or -not $resolution.exists -or $resolution.itemType -cne 'file') {
            $code = if ($null -ne $resolution.code) { [string]$resolution.code } else { 'READ_FAILED' }
            $outcomes = [System.Collections.Generic.List[object]]::new()
            for ($j = 0; $j -lt $targets.Count; $j++) {
                $outcome = if ($j -lt $i) { 'unchanged' } elseif ($j -eq $i) { 'failed' } else { 'not attempted' }
                $outcomes.Add((New-DmTargetRecord -Path $targets[$j] -Outcome $outcome))
            }
            $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code $code -Targets $targets -UnchangedTargets $outcomes.ToArray() `
                -RemainingWork @("Review target $($targets[$i]) and retry the operation.") -Message 'A target could not be resolved as an existing note file.' `
                -Details ([ordered]@{ target = $targets[$i] })
            return [pscustomobject][ordered]@{ ok = $false; code = $code; result = $result; plan = @() }
        }
        $resolutions.Add($resolution)
    }

    $plan = [System.Collections.Generic.List[object]]::new()
    $encodingFailureIndex = -1
    $classification = Get-DmChangeClassification -Registration $registration -TargetCount $targets.Count
    for ($i = 0; $i -lt $resolutions.Count; $i++) {
        $read = Read-DmVaultTargetBytes -Boundary $Preflight.boundary -Resolution $resolutions[$i]
        if (-not $read.ok) {
            $outcomes = [System.Collections.Generic.List[object]]::new()
            for ($j = 0; $j -lt $targets.Count; $j++) {
                $outcome = if ($j -lt $i) { 'unchanged' } elseif ($j -eq $i -and $read.code -ceq 'TARGET_CONFLICT') { 'conflict' } elseif ($j -eq $i) { 'failed' } else { 'not attempted' }
                $outcomes.Add((New-DmTargetRecord -Path $targets[$j] -Outcome $outcome))
            }
            $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code ([string]$read.code) -Targets $targets -UnchangedTargets $outcomes.ToArray() `
                -RemainingWork @("Review target $($targets[$i]) and retry the operation.") -Message 'A target could not be read safely.' `
                -Details ([ordered]@{ target = $targets[$i] })
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$read.code; result = $result; plan = @() }
        }

        $decoded = ConvertFrom-DmNoteBytes -Bytes ([byte[]]$read.bytes)
        if (-not $decoded.ok) {
            if ($encodingFailureIndex -lt 0) { $encodingFailureIndex = $i }
            $plan.Add([pscustomobject][ordered]@{
                    path = $targets[$i]
                    resolution = $resolutions[$i]
                    observedVersion = [string]$read.version
                    replacementVersion = 'absent'
                    conversionDecision = 'undecodable-no-write'
                    replacementBytes = $null
                    unchanged = $true
                    proposedOperation = [string]$classification.proposedOperation
                })
            $read.bytes = $null
            continue
        }

        try {
            $replacementText = & $registration.builder ([string]$decoded.text) $request.arguments ([string]$targets[$i])
            if ($replacementText -isnot [string]) { throw [System.InvalidOperationException]::new('The registered operation did not return text.') }
        }
        catch {
            $outcomes = [System.Collections.Generic.List[object]]::new()
            for ($j = 0; $j -lt $targets.Count; $j++) {
                $outcome = if ($j -lt $i) { 'unchanged' } elseif ($j -eq $i) { 'failed' } else { 'not attempted' }
                $outcomes.Add((New-DmTargetRecord -Path $targets[$j] -Outcome $outcome))
            }
            $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'OPERATION_FAILED' -Targets $targets -UnchangedTargets $outcomes.ToArray() `
                -RemainingWork @("Revalidate the operation for target $($targets[$i]), then retry.") -Message 'The registered operation could not prepare a complete replacement.'
            return [pscustomobject][ordered]@{ ok = $false; code = 'OPERATION_FAILED'; result = $result; plan = @() }
        }

        $prepared = ConvertTo-DmPreparedNote -OriginalBytes ([byte[]]$read.bytes) -ReplacementText $replacementText
        if (-not $prepared.ok) {
            $outcomes = [System.Collections.Generic.List[object]]::new()
            for ($j = 0; $j -lt $targets.Count; $j++) {
                $outcome = if ($j -lt $i) { 'unchanged' } elseif ($j -eq $i) { 'failed' } else { 'not attempted' }
                $outcomes.Add((New-DmTargetRecord -Path $targets[$j] -Outcome $outcome))
            }
            $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code ([string]$prepared.code) -Targets $targets -UnchangedTargets $outcomes.ToArray() `
                -RemainingWork @("Use reliably decodable text for target $($targets[$i]), then retry.") -Message ([string]$prepared.message) `
                -Details ([ordered]@{ target = $targets[$i] })
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$prepared.code; result = $result; plan = @() }
        }

        $plan.Add([pscustomobject][ordered]@{
                path = $targets[$i]
                resolution = $resolutions[$i]
                observedVersion = [string]$read.version
                replacementVersion = Get-DmByteFingerprint -Bytes ([byte[]]$prepared.bytes)
                conversionDecision = [string]$prepared.conversionDecision
                replacementBytes = [byte[]]$prepared.bytes
                unchanged = [System.Linq.Enumerable]::SequenceEqual([byte[]]$read.bytes, [byte[]]$prepared.bytes)
                proposedOperation = [string]$classification.proposedOperation
            })
        $read.bytes = $null
    }

    $runtimeVersion = $null
    try { $runtimeVersion = Get-DmRuntimeVersion }
    catch {
        $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'OPERATION_FAILED' -Targets $targets `
            -RemainingWork @('Repair the installed runtime manifest or module files, then retry.') -Message 'The installed runtime version could not be fingerprinted.'
        return [pscustomobject][ordered]@{ ok = $false; code = 'OPERATION_FAILED'; result = $result; plan = @() }
    }
    $finalPlan = [object[]]$plan.ToArray()
    if ($encodingFailureIndex -ge 0) {
        $failedIndex = $encodingFailureIndex
        $records = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $targets.Count; $i++) {
            $outcome = if ($i -lt $failedIndex) { 'unchanged' } elseif ($i -eq $failedIndex) { 'failed' } else { 'unchanged' }
            $records.Add((New-DmTargetRecord -Path $targets[$i] -Outcome $outcome))
        }
        $remaining = [string[]]@(for ($i = 0; $i -lt $targets.Count; $i++) { "Replace or repair target $($targets[$i]) using reliably decodable text, then retry." })
        $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'ENCODING_UNSAFE' -Targets $targets -UnchangedTargets $records.ToArray() `
            -RemainingWork $remaining -Message 'At least one target cannot be decoded strictly as supported Unicode.' `
            -Details ([ordered]@{ target = $targets[$failedIndex] })
        return [pscustomobject][ordered]@{
            ok = $false; code = 'ENCODING_UNSAFE'; result = $result; request = $request; registration = $registration
            requiresApproval = [bool]$classification.requiresApproval; plan = $finalPlan
            dependencies = [object[]]$dependencies; runtimeVersion = [string]$runtimeVersion
        }
    }
    [pscustomobject][ordered]@{
        ok = $true
        code = $null
        result = $null
        request = $request
        registration = $registration
        requiresApproval = [bool]$classification.requiresApproval
        plan = [object[]]$plan.ToArray()
        dependencies = [object[]]$dependencies
        runtimeVersion = [string]$runtimeVersion
    }
}

function Invoke-DmPreview {
    <#
    .SYNOPSIS
    Generates a stateless, read-only preview of a registered change.
    .DESCRIPTION
    Read-only, stateless preview entry point. Returns
    [pscustomobject]@{ result; preview }; the preview contains only target
    metadata, versions, conversion decisions, dependency versions and digest.
    .PARAMETER Request
    Explicit contract request in preview mode, including targets and arguments.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Request)

    $operation = ''
    try {
        $preflight = Invoke-DmPreflight -Request $Request
        $operation = [string]$preflight.operation
        if (-not $preflight.passed) { return [pscustomobject][ordered]@{ result = $preflight.result; preview = $null } }
        if ($preflight.request.mode -cne 'preview') {
            $result = New-DmChangeEntryResult -Operation $operation -State Blocked -Code 'INVALID_REQUEST' -Targets $preflight.targets `
                -RemainingWork @('Send a preview-mode request, then retry.') -Message 'Preview generation requires mode preview.'
            return [pscustomobject][ordered]@{ result = $result; preview = $null }
        }

        $context = Get-DmPreNoteContext -Preflight $preflight
        if (-not $context.passed) { return [pscustomobject][ordered]@{ result = $context.result; preview = $null } }
        $changePlan = Get-DmChangePlan -Preflight $preflight -Context $context
        if (-not $changePlan.ok) {
            return [pscustomobject][ordered]@{ result = $changePlan.result; preview = $null }
        }

        $reviewedVersions = [System.Collections.Generic.List[object]]::new()
        $previewTargets = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $changePlan.plan) {
            $reviewedVersions.Add([pscustomobject][ordered]@{
                    path = [string]$entry.path
                    observedVersion = [string]$entry.observedVersion
                    replacementVersion = [string]$entry.replacementVersion
                    conversionDecision = [string]$entry.conversionDecision
                })
            $previewTargets.Add([pscustomobject][ordered]@{
                    path = [string]$entry.path
                    proposedOperation = [string]$entry.proposedOperation
                    observedVersion = [string]$entry.observedVersion
                    replacementVersion = [string]$entry.replacementVersion
                    conversionDecision = [string]$entry.conversionDecision
                })
        }
        $digest = Get-DmPreviewDigest -Request $preflight.request -ReviewedVersions $reviewedVersions.ToArray() `
            -ReviewedDependencyVersions ([object[]]$changePlan.dependencies) -RuntimeVersion ([string]$changePlan.runtimeVersion) `
            -CanonicalVaultRoot ([string]$preflight.boundary.canonicalRoot)
        $preview = [pscustomobject][ordered]@{
            previewId = $digest
            runtimeVersion = [string]$changePlan.runtimeVersion
            operation = $operation
            targets = [object[]]$previewTargets.ToArray()
            reviewedVersions = [object[]]$reviewedVersions.ToArray()
            reviewedDependencyVersions = [object[]]$changePlan.dependencies
            dependencyVersions = [object[]]$changePlan.dependencies
            requiresApproval = [bool]$changePlan.requiresApproval
        }
        $result = if ($changePlan.ok) {
            New-DmChangeEntryResult -Operation $operation -State Complete -Code 'OK' -Targets $preflight.targets -UnchangedTargets $preflight.targets
        }
        else { $changePlan.result }
        [pscustomobject][ordered]@{ result = $result; preview = $preview }
    }
    catch {
        $result = New-DmChangeEntryResult -Operation $operation -State Failure -Code 'OPERATION_FAILED' -Targets @() `
            -RemainingWork @('Review the request and retry the preview.') -Message 'Preview generation failed without changing any target.'
        [pscustomobject][ordered]@{ result = $result; preview = $null }
    }
}

Export-ModuleMember -Function ConvertTo-DmJcsJson, Get-DmRuntimeVersion, Get-DmPreviewDigest, Get-DmChangePlan, New-DmChangeEntryResult, Invoke-DmPreview
