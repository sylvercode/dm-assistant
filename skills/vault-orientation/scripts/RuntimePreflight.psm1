Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DependencyPreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'OperationRequest.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')

# Runtime prerequisite check and the ordered preflight entry point
# (contract section 3): runtime -> request shape -> dependency readiness ->
# exact-vault authorization -> canonical vault root. Every gate runs before any
# profile, guidance, or note access. Nothing here installs or updates anything
# or reads vault file content; only after authorization does root resolution
# read folder metadata along the selected root path.

$script:DmSupportedRuntime = [pscustomobject][ordered]@{
    operatingSystems  = @('Windows')
    powerShellVersion = [version]'7.6.9'
    edition           = 'Core'
    modules           = @([pscustomobject][ordered]@{ name = 'powershell-yaml'; version = '0.4.12' })
    documentation     = 'docs/powershell-runtime-support.md'
}

function Get-DmRuntimeSupportMatrix {
    <#
    .SYNOPSIS
    Returns a deep copy of the release's accepted runtime, operating system, and module versions.
    #>
    [CmdletBinding()]
    param()
    [pscustomobject][ordered]@{
        operatingSystems  = [string[]]$script:DmSupportedRuntime.operatingSystems.Clone()
        powerShellVersion = [version]$script:DmSupportedRuntime.powerShellVersion.ToString()
        edition           = [string]$script:DmSupportedRuntime.edition
        modules           = [object[]]@($script:DmSupportedRuntime.modules | ForEach-Object {
                [pscustomobject][ordered]@{
                    name    = [string]$_.name
                    version = [string]$_.version
                }
            })
        documentation     = [string]$script:DmSupportedRuntime.documentation
    }
}

function Get-DmRuntimeEnvironment {
    <#
    .SYNOPSIS
    Reports the running PowerShell version, edition, and operating system.
    .DESCRIPTION
    Reads no environment variables or vault content.
    #>
    $os = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } elseif ($IsLinux) { 'Linux' } else { 'Unknown' }
    $rawVersion = [string]$PSVersionTable.PSVersion
    $gitCommitId = [string]$PSVersionTable.GitCommitId
    $isPrerelease = $rawVersion.Contains('-') -or $gitCommitId -match '(?i)-(?:preview|alpha|beta|rc)(?:[.-]|$)'
    [pscustomobject][ordered]@{
        powerShellVersion = [version]$rawVersion.Split('-')[0]
        edition           = [string]$PSVersionTable.PSEdition
        operatingSystem   = $os
        isPrerelease      = $isPrerelease
    }
}

function Get-DmInstalledModuleVersion {
    <#
    .SYNOPSIS
    Lists locally available versions of a PowerShell module without installing it.
    .PARAMETER Name
    Module name to query.
    #>
    param([Parameter(Mandatory)][string]$Name)
    @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Version.ToString() })
}

function Test-DmRequiredModuleImport {
    <#
    .SYNOPSIS
    Imports the exact required module version to verify it is loadable.
    .PARAMETER Name
    Required PowerShell module name.
    .PARAMETER Version
    Exact required module version.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][version]$Version)
    $loaded = @(Get-Module -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.Version -eq $Version })
    if ($loaded.Count -gt 0) { return $true }
    $null = Import-Module -Name $Name -RequiredVersion $Version -PassThru -ErrorAction Stop
    $loaded = @(Get-Module -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.Version -eq $Version })
    $loaded.Count -gt 0
}

function Test-DmRuntimePrerequisite {
    <#
    .SYNOPSIS
    Checks the selected runtime and module prerequisites without changing them.
    .DESCRIPTION
    Checks the exact supported runtime: OS, PowerShell edition and version,
    and required module versions. Returns a gate outcome; any mismatch blocks
    with PREREQUISITE_MISSING. Never installs or updates anything.
    .PARAMETER Operation
    Operation identifier included in a blocked result.
    .PARAMETER Targets
    Requested vault-relative targets to report as not attempted on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [AllowEmptyCollection()][string[]]$Targets = @()
    )
    $gate = 'runtime-prerequisite'
    $support = Get-DmRuntimeSupportMatrix
    $evidence = [System.Collections.Generic.List[object]]::new()
    $block = {
        param([string]$Message, [System.Collections.IDictionary]$Detail)
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'PREREQUISITE_MISSING' -Targets $Targets -Message $Message `
            -RemainingWork @("Provision the supported runtime yourself as described in $($support.documentation), then retry.") -Detail $Detail
        New-DmGateOutcome -Gate $gate -Passed $false -Result $result -Evidence $evidence.ToArray()
    }

    try { $environment = Get-DmRuntimeEnvironment } catch { $environment = $null }
    if ($null -eq $environment) {
        return (& $block 'The PowerShell runtime could not be identified.' ([ordered]@{ requirement = 'runtime' }))
    }
    $os = [string]$environment.operatingSystem
    $version = $environment.powerShellVersion -as [version]
    $edition = [string]$environment.edition

    $osSupported = $os -cin $support.operatingSystems
    $evidence.Add((New-DmEvidence -Gate $gate -Subject 'operatingSystem' -State $(if ($osSupported) { 'supported' } else { 'unsupported' }) -Detail $os))
    if (-not $osSupported) {
        return (& $block "Operating system '$os' is not supported; supported: $($support.operatingSystems -join ', ')." ([ordered]@{ requirement = 'operatingSystem'; observed = $os }))
    }

    $isPrerelease = $false
    $prereleaseProperty = $environment.PSObject.Properties['isPrerelease']
    if ($null -ne $prereleaseProperty) { $isPrerelease = [bool]$prereleaseProperty.Value }
    $psSupported = $null -ne $version -and $version -eq $support.powerShellVersion -and $edition -ceq $support.edition -and -not $isPrerelease
    $observedPs = "$edition $version"
    $evidence.Add((New-DmEvidence -Gate $gate -Subject 'powershell' -State $(if ($psSupported) { 'supported' } else { 'unsupported' }) -Detail $observedPs))
    if (-not $psSupported) {
        return (& $block "PowerShell $observedPs is not supported; PowerShell $($support.edition) $($support.powerShellVersion) is required." `
                ([ordered]@{ requirement = 'powershell'; observed = $observedPs; required = "$($support.edition) $($support.powerShellVersion)" }))
    }

    foreach ($module in $support.modules) {
        $available = @()
        try { $available = @(Get-DmInstalledModuleVersion -Name $module.name) } catch { $available = @() }
        $versionAvailable = $module.version -cin @($available | ForEach-Object { [string]$_ })
        $importable = $false
        if ($versionAvailable) {
            try { $importable = Test-DmRequiredModuleImport -Name $module.name -Version ([version]$module.version) }
            catch { $importable = $false }
        }
        $present = $versionAvailable -and $importable
        $evidence.Add((New-DmEvidence -Gate $gate -Subject $module.name -State $(if ($present) { 'supported' } else { 'missing' }) -Detail ($available -join ', ')))
        if (-not $present) {
            return (& $block "Required module $($module.name) $($module.version) is unavailable or could not be imported." `
                    ([ordered]@{ requirement = 'module'; module = $module.name; required = $module.version }))
        }
    }
    New-DmGateOutcome -Gate $gate -Passed $true -Result $null -Evidence $evidence.ToArray()
}

function Get-DmRequestField {
    <#
    .SYNOPSIS
    Retrieves a named field from a request dictionary or custom object.
    .PARAMETER Request
    Request object from which to retrieve the field.
    .PARAMETER Name
    Field name to look up.
    #>
    param($Request, [string]$Name)
    if ($Request -is [System.Collections.IDictionary]) {
        if ($Request.Contains($Name)) { return , $Request[$Name] }
        return $null
    }
    if ($Request -is [System.Management.Automation.PSCustomObject]) {
        $property = $Request.PSObject.Properties[$Name]
        if ($null -ne $property) { return , $property.Value }
    }
    $null
}

function Test-DmRequestObject {
    <#
    .SYNOPSIS
    Checks whether a request is a dictionary or custom object.
    .PARAMETER Request
    Candidate request value.
    #>
    param($Request)
    $Request -is [System.Collections.IDictionary] -or $Request -is [System.Management.Automation.PSCustomObject]
}

function Get-DmRequestTarget {
    <#
    .SYNOPSIS
    Extracts safe target names for a blocked result.
    .DESCRIPTION
    Returns only a distinct list of lexically valid vault-relative strings;
    malformed target collections produce an empty list.
    .PARAMETER Request
    Untrusted request object containing the targets field.
    #>
    param($Request)
    if (-not (Test-DmRequestObject -Request $Request)) { return , [string[]]@() }
    $raw = Get-DmRequestField -Request $Request -Name 'targets'
    if ($null -eq $raw -or $raw -is [string] -or $raw -isnot [System.Collections.IList]) { return , [string[]]@() }
    $items = @($raw)
    foreach ($item in $items) {
        if ($item -isnot [string] -or -not (Test-DmVaultRelativePath -Path $item).isValid) { return , [string[]]@() }
    }
    $distinct = [System.Collections.Generic.HashSet[string]]::new([string[]]$items, [System.StringComparer]::Ordinal)
    if ($distinct.Count -ne $items.Count) { return , [string[]]@() }
    , [string[]]$items
}
function Invoke-DmPreflight {
    <#
    .SYNOPSIS
    Runs ordered prerequisite, request, dependency, authorization, and root gates.
    .DESCRIPTION
    Ordered preflight for one operation request (hashtable or pscustomobject):
    runtime prerequisites -> request shape (OperationRequest; INVALID_REQUEST,
    then PATH_INVALID for lexically invalid targets) -> dependency readiness ->
    exact-vault authorization -> canonical vault-root resolution
    (VAULT_TARGET_INVALID). Returns [pscustomobject]@{ passed; result;
    evidence; operation; vaultRoot; targets; request; boundary }. When passed
    is $false, result is the contract result to return and nothing was read
    from or written to the vault. When passed is $true, result is $null,
    request is the normalized request, boundary is the VaultBoundary root
    boundary, and the caller may continue with profile and guidance loading.
    .PARAMETER Request
    Explicit operation request as a dictionary or custom object; invalid input
    is returned as a blocked result.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Request)

    $operationField = Get-DmRequestField -Request $Request -Name 'operation'
    $operationRegistration = if ($operationField -is [string]) { Get-DmOperation -Name $operationField } else { $null }
    $operation = if ($null -ne $operationRegistration) { [string]$operationField } else { 'unknown' }
    $vaultRootField = Get-DmRequestField -Request $Request -Name 'vaultRoot'
    $vaultRoot = if ($vaultRootField -is [string]) { $vaultRootField } else { '' }
    $targets = Get-DmRequestTarget -Request $Request
    $evidence = [System.Collections.Generic.List[object]]::new()
    $normalized = $null
    $boundary = $null
    $finish = {
        param([bool]$Passed, $Result)
        [pscustomobject][ordered]@{
            passed    = $Passed
            result    = $Result
            evidence  = $evidence.ToArray()
            operation = $operation
            vaultRoot = $vaultRoot
            targets   = $targets
            request   = $(if ($Passed) { $normalized } else { $null })
            boundary  = $(if ($Passed) { $boundary } else { $null })
        }
    }

    $runtime = Test-DmRuntimePrerequisite -Operation $operation -Targets $targets
    $evidence.AddRange([object[]]$runtime.evidence)
    if (-not $runtime.passed) { return (& $finish $false $runtime.result) }

    $shape = Test-DmOperationRequest -Request $Request
    $evidence.Add((New-DmEvidence -Gate 'request-shape' -Subject 'request' -State $(if ($shape.isValid) { 'valid' } else { [string]$shape.code })))
    if (-not $shape.isValid) {
        $problems = [string[]]$shape.problems
        if ($shape.code -ceq 'PATH_INVALID') {
            $result = New-DmBlockedResult -Operation $operation -CompletionCode 'PATH_INVALID' -Targets $targets `
                -Message "A target is not a valid vault-relative path: $($problems -join ' ')" -RemainingWork @('Correct the target paths, then retry.') `
                -Detail ([ordered]@{ problems = $problems })
        }
        else {
            $result = New-DmBlockedResult -Operation $operation -CompletionCode 'INVALID_REQUEST' -Targets $targets `
                -Message "The operation request is invalid: $($problems -join ' ')" -RemainingWork @('Correct the operation request, then retry.') `
                -Detail ([ordered]@{ problems = $problems })
        }
        return (& $finish $false $result)
    }
    $normalized = $shape.request

    $readiness = Test-DmDependencyReadiness -Operation $operation -Targets $targets
    $evidence.AddRange([object[]]$readiness.evidence)
    if (-not $readiness.passed) { return (& $finish $false $readiness.result) }

    $authorization = Test-DmVaultAuthorization -Operation $operation -VaultRoot $vaultRoot -Targets $targets
    $evidence.AddRange([object[]]$authorization.evidence)
    if (-not $authorization.passed) { return (& $finish $false $authorization.result) }

    $root = Resolve-DmVaultRoot -Gate $authorization -VaultRoot $vaultRoot -Operation $operation -Targets $targets
    $evidence.AddRange([object[]]$root.evidence)
    if (-not $root.passed) { return (& $finish $false $root.result) }
    $boundary = $root.boundary

    & $finish $true $null
}
Export-ModuleMember -Function Get-DmRuntimeSupportMatrix, Test-DmRuntimePrerequisite, Invoke-DmPreflight
