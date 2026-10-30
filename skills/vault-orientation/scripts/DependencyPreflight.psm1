Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')

# Feature 001 dependency-readiness adapter and exact-vault authorization
# handoff. Readiness and authorization are separate checks: a ready
# dependency never implies that the exact vault is authorized.

$script:DmProbeTimeoutMilliseconds = 20000
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
    Probes whether a declared dependency is configured in Copilot CLI.
    .DESCRIPTION
    Internal production readiness probe. Confirms only whether the dependency
    is configured in Copilot CLI, using a constant argument list and a fixed
    working directory inside the plugin. The probe output is discarded because
    it may contain vault paths. A script cannot observe the server version or
    the tools exposed to the active session, so a configured server is
    'unknown', never 'ready'.
    .PARAMETER Dependency
    Inventory entry containing dependencyId, type, and compatibility requirements.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dependency)
    $id = [string]$Dependency.dependencyId
    $new = {
        param([string]$State, [string]$Evidence)
        [pscustomobject][ordered]@{ dependencyId = $id; readinessState = $State; evidence = $Evidence }
    }
    if ($id -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or $Dependency.type -cne 'mcp-server') {
        return (& $new 'unknown' 'Unsupported inventory entry; readiness cannot be checked.')
    }
    $copilot = Get-Command -Name 'copilot' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $copilot) {
        return (& $new 'missing' 'Copilot CLI was not found, so the MCP server configuration cannot be checked.')
    }
    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($copilot.Source)
        foreach ($argument in @('mcp', 'get', $id)) { $startInfo.ArgumentList.Add($argument) }
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $PSScriptRoot
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($script:DmProbeTimeoutMilliseconds)) {
            try { $process.Kill($true) } catch { $null = $_ }
            return (& $new 'unknown' 'The Copilot CLI MCP configuration check timed out.')
        }
        $process.WaitForExit()
        $null = $stdout.Result, $stderr.Result
        if ($process.ExitCode -ne 0) {
            return (& $new 'unknown' 'The MCP configuration could not be confirmed under the dependency name; the configured server may use a different name.')
        }
        return (& $new 'unknown' 'The MCP server is configured, but its version and tool exposure must be confirmed in the active Copilot CLI session.')
    }
    catch {
        return (& $new 'unknown' 'The Copilot CLI MCP configuration check could not run.')
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
    }
}

function Get-DmVaultAuthorization {
    <#
    .SYNOPSIS
    Reports the production exact-vault authorization handoff state.
    .DESCRIPTION
    Internal exact-vault authorization handoff. Feature 001 defines the
    note-content-free get_server_info signal, but this runtime cannot verify
    the active session's response. Production therefore reports 'unknown'.
    It accepts no assertion from request fields, paths, environment variables,
    configuration, or the profile, and reads nothing from the vault.
    .PARAMETER Dependency
    Declared dependency for which authorization is required.
    .PARAMETER VaultRoot
    Explicit vault root to authorize; the path alone is never authorization.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Dependency,
        [Parameter(Mandatory)][AllowEmptyString()][string]$VaultRoot
    )
    $null = $VaultRoot
    [pscustomobject][ordered]@{
        dependencyId            = [string]$Dependency.dependencyId
        vaultAuthorizationState = 'unknown'
        evidence                = 'The runtime cannot verify the active session Resolver authorization response.'
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [AllowEmptyCollection()][string[]]$Targets = @()
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
            $probe = Get-DmDependencyReadiness -Dependency $dependency
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
                "Check $requirement in the active Copilot CLI session. Script-backed work remains blocked until a trusted runtime readiness and authorization handoff is available."
            }
            else {
                "Install and configure $requirement in Copilot CLI yourself. Script-backed work remains blocked until a trusted runtime readiness and authorization handoff is available."
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
    Requires verified exact-vault authorization for every declared dependency.
    .DESCRIPTION
    Exact-vault authorization handoff for every declared dependency. Returns a
    gate outcome; anything other than 'authorized' for every dependency blocks
    with VAULT_AUTHORIZATION_UNPROVEN before any profile, guidance, or note
    access. Never reads the vault.
    .PARAMETER Operation
    Operation identifier included in a blocked result.
    .PARAMETER VaultRoot
    Explicit vault root for the authorization handoff.
    .PARAMETER Targets
    Requested vault-relative targets reported as not attempted if blocked.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [Parameter(Mandatory)][AllowEmptyString()][string]$VaultRoot,
        [AllowEmptyCollection()][string[]]$Targets = @()
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
            $answer = Get-DmVaultAuthorization -Dependency $dependency -VaultRoot $VaultRoot
            if ($null -ne $answer -and $answer.PSObject.Properties['vaultAuthorizationState'] -and [string]$answer.vaultAuthorizationState -cin @('authorized', 'not authorized', 'unknown')) {
                $state = [string]$answer.vaultAuthorizationState
            }
        }
        catch {
            $state = 'unknown'
        }
        $evidence.Add((New-DmEvidence -Gate $gate -Subject $id -State $state))
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
            -Message 'Exact-vault authorization could not be verified by the PowerShell runtime, so no profile, guidance, or campaign note was read and nothing was written.' `
            -RemainingWork @('A verified handoff from the active session Resolver is required before script-backed vault access. Read-only assistance that does not need the vault remains available.') `
            -Detail $detail
        return (New-DmGateOutcome -Gate $gate -Passed $false -Result $result -Evidence $evidence.ToArray())
    }
    New-DmGateOutcome -Gate $gate -Passed $true -Result $null -Evidence $evidence.ToArray()
}

Export-ModuleMember -Function Get-DmDependencyInventory, Get-DmDependencyInventoryVersion, Test-DmDependencyReadiness, Test-DmVaultAuthorization
