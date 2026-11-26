Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')

# MCP checks belong to the calling skill. These gates consume its explicit
# confirmations; they do not independently authenticate an active MCP session.
$script:DmReadinessStates = @('ready', 'missing', 'incompatible', 'unknown')

function Get-DmDependencyInventoryPath {
    <#
    .SYNOPSIS
    Resolves the installed skill's dependency inventory asset.
    #>
    $assets = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'assets'
    Join-Path -Path $assets -ChildPath 'runtime-dependencies.json'
}

function Get-DmDependencyInventoryVersion {
    <#
    .SYNOPSIS
    Fingerprints the installed dependency inventory for change detection.
    .DESCRIPTION
    Returns the plugin resource identity and SHA-256 version. Throws when the
    inventory is missing or unreadable.
    #>
    [CmdletBinding()]
    param()
    try {
        $bytes = [System.IO.File]::ReadAllBytes((Get-DmDependencyInventoryPath))
    }
    catch {
        throw [System.IO.FileNotFoundException]::new('The runtime dependency inventory resource is missing or unreadable.')
    }
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    [pscustomobject][ordered]@{
        identity = 'plugin:skills/vault-orientation/assets/runtime-dependencies.json'
        version  = 'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
    }
}

function Get-DmDependencyInventory {
    <#
    .SYNOPSIS
    Loads and validates the packaged runtime dependency inventory.
    .DESCRIPTION
    Returns the declared runtime dependencies. Throws
    [System.IO.FileNotFoundException] when the inventory asset is missing or
    unreadable and [System.IO.InvalidDataException] when it is malformed.
    #>
    [CmdletBinding()]
    param()
    $path = Get-DmDependencyInventoryPath
    try {
        $text = [System.IO.File]::ReadAllText($path)
    }
    catch {
        throw [System.IO.FileNotFoundException]::new('The runtime dependency inventory resource is missing or unreadable.')
    }
    try {
        $data = $text | ConvertFrom-Json -Depth 8 -ErrorAction Stop
    }
    catch {
        throw [System.IO.InvalidDataException]::new('The runtime dependency inventory resource is malformed.')
    }
    if ($null -eq $data -or -not $data.PSObject.Properties['inventoryVersion'] -or $data.inventoryVersion -ne 2 -or
        -not $data.PSObject.Properties['dependencies'] -or $data.dependencies -isnot [array] -or $data.dependencies.Count -eq 0) {
        throw [System.IO.InvalidDataException]::new('The runtime dependency inventory resource is incompatible.')
    }
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $data.dependencies) {
        $valid = $entry -is [System.Management.Automation.PSCustomObject] -and
            $entry.PSObject.Properties['dependencyId'] -and [string]$entry.dependencyId -cmatch '^[a-z0-9][a-z0-9-]{0,63}$' -and
            $entry.PSObject.Properties['type'] -and $entry.type -ceq 'mcp-server' -and
            $entry.PSObject.Properties['minimumVersion'] -and $null -ne ([string]$entry.minimumVersion -as [version]) -and
            $entry.PSObject.Properties['requiredTools'] -and $entry.requiredTools -is [array] -and $entry.requiredTools.Count -gt 0 -and
            $ids.Add([string]$entry.dependencyId)
        if ($valid) {
            $tools = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($tool in $entry.requiredTools) {
                if ($tool -isnot [string] -or $tool -cnotmatch '^[A-Za-z0-9_.-]+$' -or -not $tools.Add($tool)) {
                    $valid = $false
                    break
                }
            }
        }
        if (-not $valid) {
            throw [System.IO.InvalidDataException]::new('The runtime dependency inventory resource contains an incompatible entry.')
        }
        $entry
    }
}

function Get-DmDependencyReadiness {
    <#
    .SYNOPSIS
    Consumes the caller's confirmation that every declared dependency is ready.
    .DESCRIPTION
    The calling skill must check the live version and tools against the
    installed inventory before supplying this confirmation. No CLI subprocess
    or MCP configuration lookup is used.
    .PARAMETER Dependency
    Inventory entry containing dependencyId, type, and compatibility requirements.
    .PARAMETER CallerPreflight
    Normalized caller confirmation, not an independently verified credential.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dependency, [AllowNull()]$CallerPreflight)
    $id = [string]$Dependency.dependencyId
    $new = {
        param([string]$State, [string]$Evidence)
        [pscustomobject][ordered]@{ dependencyId = $id; readinessState = $State; evidence = $Evidence }
    }
    if ($id -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or $Dependency.type -cne 'mcp-server') {
        return (& $new 'unknown' 'Unsupported inventory entry; readiness cannot be checked.')
    }
    if ($null -eq $CallerPreflight) {
        return (& $new 'unknown' 'The calling skill has not supplied its live dependency-check confirmation.')
    }
    if (-not $CallerPreflight.dependenciesReady) {
        return (& $new 'unknown' 'The calling skill did not confirm that all required dependencies are ready.')
    }
    & $new 'ready' 'Caller-confirmed live dependency checks; not independently verified by PowerShell.'
}

function ConvertTo-DmComparableVaultRoot {
    <#
    .SYNOPSIS
    Normalizes a caller-supplied root for lexical comparison without vault access.
    .PARAMETER Path
    Validated absolute root, possibly using the Windows extended-path prefix.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if ($IsWindows) {
        if ($Path.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) { $Path = '\\' + $Path.Substring(8) }
        elseif ($Path.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) { $Path = $Path.Substring(4) }
    }
    [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-DmVaultAuthorization {
    <#
    .SYNOPSIS
    Consumes the caller's exact-vault authorization confirmation.
    .DESCRIPTION
    The caller checks get_server_info in the active MCP session. This function
    only binds its explicit confirmation to the selected root, without vault
    access or independent MCP verification.
    .PARAMETER Dependency
    Declared dependency for which authorization is required.
    .PARAMETER VaultRoot
    Explicit vault root to authorize; the path alone is never authorization.
    .PARAMETER CallerPreflight
    Normalized, vault-scoped confirmation supplied by the calling skill.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Dependency,
        [Parameter(Mandatory)][AllowEmptyString()][string]$VaultRoot,
        [AllowNull()]$CallerPreflight
    )
    $state = 'unknown'
    if ($null -ne $CallerPreflight) {
        $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        $sameRoot = [string]::Equals((ConvertTo-DmComparableVaultRoot -Path $VaultRoot),
            (ConvertTo-DmComparableVaultRoot -Path $CallerPreflight.vaultRoot), $comparison)
        $state = if ($sameRoot -and $CallerPreflight.vaultAuthorized) { 'authorized' } else { 'not authorized' }
    }
    [pscustomobject][ordered]@{
        dependencyId            = [string]$Dependency.dependencyId
        vaultAuthorizationState = $state
        evidence                = 'Caller-confirmed exact-vault check; not independently verified by PowerShell.'
    }
}

function Test-DmDependencyReadiness {
    <#
    .SYNOPSIS
    Gates an operation on readiness of all declared dependencies.
    .DESCRIPTION
    Checks every declared dependency's readiness. Returns a gate outcome
    (New-DmGateOutcome). Any state other than 'ready' blocks with
    PREREQUISITE_MISSING; an unavailable inventory blocks with
    RESOURCE_MISSING or RESOURCE_INCOMPATIBLE.
    .PARAMETER Operation
    Operation identifier included in a blocked result.
    .PARAMETER Targets
    Requested vault-relative targets reported as not attempted on failure.
    .PARAMETER CallerPreflight
    Normalized caller confirmation of live MCP checks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [AllowEmptyCollection()][string[]]$Targets = @(),
        [AllowNull()]$CallerPreflight
    )
    $gate = 'dependency-readiness'
    try {
        $inventory = @(Get-DmDependencyInventory)
    }
    catch [System.IO.FileNotFoundException] {
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'RESOURCE_MISSING' -Targets $Targets `
            -Message 'The plugin runtime dependency inventory is missing or unreadable; reinstall the plugin.' `
            -RemainingWork @('Reinstall the plugin so its runtime dependency inventory is available.') -Detail ([ordered]@{ resource = 'runtime-dependencies.json' })
        return (New-DmGateOutcome -Gate $gate -Passed $false -Result $result)
    }
    catch {
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'RESOURCE_INCOMPATIBLE' -Targets $Targets `
            -Message 'The plugin runtime dependency inventory is incompatible; reinstall the plugin.' `
            -RemainingWork @('Reinstall the plugin so its runtime dependency inventory is valid.') -Detail ([ordered]@{ resource = 'runtime-dependencies.json' })
        return (New-DmGateOutcome -Gate $gate -Passed $false -Result $result)
    }

    $evidence = [System.Collections.Generic.List[object]]::new()
    foreach ($dependency in $inventory) {
        $id = [string]$dependency.dependencyId
        $state = 'unknown'
        $detail = 'Readiness check failed.'
        try {
            $probe = Get-DmDependencyReadiness -Dependency $dependency -CallerPreflight $CallerPreflight
            if ($null -ne $probe -and $probe.PSObject.Properties['readinessState'] -and [string]$probe.readinessState -cin $script:DmReadinessStates) {
                $state = [string]$probe.readinessState
                if ($probe.PSObject.Properties['evidence'] -and (Test-DmSafeText -Text ([string]$probe.evidence))) { $detail = [string]$probe.evidence }
            }
        }
        catch {
            $state = 'unknown'
        }
        $evidence.Add((New-DmEvidence -Gate $gate -Subject $id -State $state -Detail $detail))
        if ($state -cne 'ready') {
            $requirement = "$id $($dependency.minimumVersion) or later exposing $($dependency.requiredTools -join ' and ')"
            $message = switch ($state) {
                'missing' { "Required dependency $requirement is not available. $detail" }
                'incompatible' { "Required dependency $id is incompatible; $requirement is required." }
                default { "Readiness of required dependency $requirement could not be confirmed. $detail Unknown readiness is not success." }
            }
            $remaining = if ($state -ceq 'unknown') {
                "The calling skill must check $requirement in the active session and supply callerPreflight. PowerShell does not independently verify MCP readiness."
            }
            else {
                "Make $requirement available, then repeat the calling skill's live checks and supply callerPreflight."
            }
            $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'PREREQUISITE_MISSING' -Targets $Targets -Message $message `
                -RemainingWork @($remaining) `
                -Detail ([ordered]@{ dependencyId = $id; readinessState = $state; minimumVersion = [string]$dependency.minimumVersion; requiredTools = [string[]]$dependency.requiredTools })
            return (New-DmGateOutcome -Gate $gate -Passed $false -Result $result -Evidence $evidence.ToArray())
        }
    }
    New-DmGateOutcome -Gate $gate -Passed $true -Result $null -Evidence $evidence.ToArray()
}

function Test-DmVaultAuthorization {
    <#
    .SYNOPSIS
    Requires caller-confirmed exact-vault authorization for every declared dependency.
    .DESCRIPTION
    Caller-confirmed exact-vault authorization for every declared dependency. Returns a
    gate outcome; anything other than 'authorized' for every dependency blocks
    with VAULT_AUTHORIZATION_UNPROVEN before any profile, guidance, or note
    access. Never reads the vault.
    .PARAMETER Operation
    Operation identifier included in a blocked result.
    .PARAMETER VaultRoot
    Explicit vault root for the authorization handoff.
    .PARAMETER Targets
    Requested vault-relative targets reported as not attempted if blocked.
    .PARAMETER CallerPreflight
    Normalized caller confirmation bound to the selected vault.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [Parameter(Mandatory)][AllowEmptyString()][string]$VaultRoot,
        [AllowEmptyCollection()][string[]]$Targets = @(),
        [AllowNull()]$CallerPreflight
    )
    $gate = 'vault-authorization'
    $evidence = [System.Collections.Generic.List[object]]::new()
    $inventory = @()
    try { $inventory = @(Get-DmDependencyInventory) } catch { $inventory = @() }
    $blocked = $inventory.Count -eq 0
    $blockedId = ''
    $blockedState = 'unknown'
    foreach ($dependency in $inventory) {
        $id = [string]$dependency.dependencyId
        $state = 'unknown'
        try {
            $answer = Get-DmVaultAuthorization -Dependency $dependency -VaultRoot $VaultRoot -CallerPreflight $CallerPreflight
            if ($null -ne $answer -and $answer.PSObject.Properties['vaultAuthorizationState'] -and [string]$answer.vaultAuthorizationState -cin @('authorized', 'not authorized', 'unknown')) {
                $state = [string]$answer.vaultAuthorizationState
            }
        }
        catch {
            $state = 'unknown'
        }
        $evidence.Add((New-DmEvidence -Gate $gate -Subject $id -State $state -Detail 'Caller confirmation; PowerShell does not independently verify MCP authorization.'))
        if ($state -cne 'authorized') {
            $blocked = $true
            $blockedId = $id
            $blockedState = $state
            break
        }
    }
    if ($blocked) {
        $detail = [ordered]@{ dependencyId = $blockedId; vaultAuthorizationState = $blockedState }
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $Targets `
            -Message 'The caller did not confirm authorization for this exact vault, so no profile, guidance, or campaign note was read and nothing was written.' `
            -RemainingWork @('The calling skill must check get_server_info in the active session and supply callerPreflight for this exact vault. This is a caller precondition, not independent PowerShell authorization.') `
            -Detail $detail
        return (New-DmGateOutcome -Gate $gate -Passed $false -Result $result -Evidence $evidence.ToArray())
    }
    New-DmGateOutcome -Gate $gate -Passed $true -Result $null -Evidence $evidence.ToArray()
}

Export-ModuleMember -Function Get-DmDependencyInventory, Get-DmDependencyInventoryVersion, Test-DmDependencyReadiness, Test-DmVaultAuthorization
