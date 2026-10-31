Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')

# Diagnostics are built from stable codes and fixed messages. Caller-supplied
# exception text and detail fields are never copied into the result.
$script:DmDiagnosticMessages = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
foreach ($entry in @(
        @('OK', 'The operation completed.'),
        @('NO_CHANGES', 'The operation completed without changing any targets.'),
        @('PREREQUISITE_MISSING', 'A required runtime or dependency is unavailable.'),
        @('VAULT_AUTHORIZATION_UNPROVEN', 'Exact-vault authorization could not be verified.'),
        @('VAULT_TARGET_INVALID', 'The selected vault target is unavailable or invalid.'),
        @('INVALID_REQUEST', 'The operation request is invalid.'),
        @('PATH_INVALID', 'A supplied path is not a valid vault-relative path.'),
        @('PATH_OUTSIDE_VAULT', 'A target could not be verified inside the vault.'),
        @('RESOURCE_MISSING', 'A required plugin resource is unavailable.'),
        @('RESOURCE_INCOMPATIBLE', 'A required plugin resource is incompatible.'),
        @('PROFILE_PARSE_INVALID', 'The vault profile could not be parsed.'),
        @('PROFILE_NORMALIZATION_INVALID', 'The vault profile contains unsupported values.'),
        @('PROFILE_SCHEMA_INVALID', 'The vault profile does not match the required schema.'),
        @('PROFILE_FILESYSTEM_INVALID', 'A configured vault location is unavailable or invalid.'),
        @('REFERENCE_UNAVAILABLE', 'A configured reference needed for this operation is unavailable.'),
        @('AMBIGUOUS_CONTEXT', 'The operation context is ambiguous and requires direction.'),
        @('CONFIRMATION_REQUIRED', 'The proposed changes require confirmation.'),
        @('USER_CANCELLED', 'The operation was cancelled before changes were applied.'),
        @('ENCODING_UNSAFE', 'The target encoding could not be decoded safely.'),
        @('TARGET_CONFLICT', 'A target or dependency changed and must be reviewed again.'),
        @('READ_FAILED', 'The requested data could not be read.'),
        @('WRITE_FAILED', 'The requested changes could not be written.'),
        @('INTERRUPTED', 'The operation was interrupted.'),
        @('OPERATION_FAILED', 'The operation could not be completed.')
    )) {
    $script:DmDiagnosticMessages.Add($entry[0], $entry[1])
}

function Get-DmDiagnosticField {
    <#
    .SYNOPSIS
    Retrieves a named field from an untrusted diagnostic object.
    .PARAMETER Object
    Optional dictionary or custom object containing diagnostic data.
    .PARAMETER Name
    Field name to retrieve.
    #>
    param([AllowNull()]$Object, [Parameter(Mandatory)][string]$Name)
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ($key -is [string] -and $key -ceq $Name) { return , $Object[$key] }
        }
    }
    elseif ($Object -is [System.Management.Automation.PSCustomObject]) {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return , $property.Value }
    }
    $null
}

function New-DmSafeDiagnostic {
    <#
    .SYNOPSIS
    Creates sanitized error details for a stable completion code.
    .DESCRIPTION
    Creates contract-shaped error details from a stable code. The optional
    caller message and detail object are treated as untrusted and never echoed;
    only validated vault-relative targets and dependency identities may be
    retained from details.
    .PARAMETER Code
    Known completion code used to select the fixed safe message.
    .PARAMETER Message
    Untrusted caller message; accepted for compatibility but never copied.
    .PARAMETER Details
    Untrusted detail object; only validated targets and dependency identities
    are retained.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Code,
        [AllowNull()][AllowEmptyString()][string]$Message,
        [AllowNull()]$Details
    )

    $completionCodes = Get-DmCompletionCode
    if (-not $completionCodes.Contains($Code) -or -not $script:DmDiagnosticMessages.Contains($Code)) {
        throw [System.ArgumentException]::new('A diagnostic requires a known contract completion code.')
    }

    $result = [ordered]@{
        code    = $Code
        message = [string]$script:DmDiagnosticMessages[$Code]
    }
    $safeDetails = [ordered]@{}
    $target = Get-DmDiagnosticField -Object $Details -Name 'target'
    if ($target -is [string] -and $target.Length -le 512 -and
        (Test-DmVaultRelativeText -Path $target)) {
        $safeDetails.target = $target
    }
    $changedDependencies = Get-DmDiagnosticField -Object $Details -Name 'changedDependencies'
    if ($changedDependencies -is [System.Collections.IList] -and $changedDependencies.Count -gt 0 -and
        (Test-DmSafeDiagnosticValue -Value $changedDependencies -FieldName 'changedDependencies')) {
        $safeDetails.changedDependencies = [string[]]$changedDependencies
    }
    if ($safeDetails.Count -gt 0) { $result['details'] = [pscustomobject]$safeDetails }
    [pscustomobject]$result
}

Export-ModuleMember -Function New-DmSafeDiagnostic
