Set-StrictMode -Version Latest

# Lexical validation of vault-relative paths (contract section 5, step 1).
# Paths are data: nothing is expanded (variables, home-directory markers,
# Obsidian links, or wildcards) and nothing touches the filesystem.

$script:DmWindowsReservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')

function New-DmPathCheck {
    <#
    .SYNOPSIS
    Creates a lexical path-validation result.
    .PARAMETER IsValid
    Whether the path passed validation.
    .PARAMETER Reason
    Safe explanation of a failed check, without echoing the path.
    .PARAMETER Components
    Parsed path components for a valid path.
    #>
    param([bool]$IsValid, [string]$Reason, [string[]]$Components = @())
    [pscustomobject][ordered]@{
        isValid    = $IsValid
        code       = $(if ($IsValid) { $null } else { 'PATH_INVALID' })
        reason     = $Reason
        components = [string[]]$Components
    }
}

function Test-DmVaultRelativePath {
    <#
    .SYNOPSIS
    Validates the lexical form of a vault-relative path without filesystem access.
    .DESCRIPTION
    Validates one vault-relative path lexically. Returns
    [pscustomobject]@{ isValid; code ($null or 'PATH_INVALID'); reason; components }.
    A valid path is a non-empty string of '/'-separated components with no
    leading '/', backslash, drive or URI syntax (':'), NUL/control character,
    wildcard ('*', '?', '[', ']'), empty, '.', or '..' component. Components
    that Windows would silently alias (trailing '.' or space, reserved device
    names) and characters that are invalid in Windows file names are also
    rejected. The reason never echoes the path.
    .PARAMETER Path
    Candidate slash-separated vault-relative path, treated as literal data.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Path)

    if ($Path -isnot [string]) { return (New-DmPathCheck -IsValid $false -Reason 'The path must be a string.') }
    if ($Path.Length -eq 0) { return (New-DmPathCheck -IsValid $false -Reason 'The path must not be empty.') }
    foreach ($ch in $Path.ToCharArray()) {
        $code = [int]$ch
        if ($code -lt 0x20 -or ($code -ge 0x7F -and $code -le 0x9F)) {
            return (New-DmPathCheck -IsValid $false -Reason 'The path contains a NUL or control character.')
        }
    }
    if ($Path.StartsWith('/')) { return (New-DmPathCheck -IsValid $false -Reason 'The path must be vault-relative; a leading / is not allowed.') }
    if ($Path.Contains('\')) { return (New-DmPathCheck -IsValid $false -Reason 'The path must use / separators; backslashes are not allowed.') }
    if ($Path.Contains(':')) { return (New-DmPathCheck -IsValid $false -Reason 'Drive, URI, and stream syntax (:) is not allowed in a vault-relative path.') }
    if ($Path.IndexOfAny([char[]]@('*', '?', '[', ']')) -ge 0) { return (New-DmPathCheck -IsValid $false -Reason 'Wildcard syntax is not allowed in a vault-relative path.') }
    if ($Path.IndexOfAny([char[]]@('<', '>', '|', '"')) -ge 0) { return (New-DmPathCheck -IsValid $false -Reason 'The path contains a character that is not valid in a file name.') }

    $components = $Path.Split('/')
    foreach ($component in $components) {
        if ($component.Length -eq 0) { return (New-DmPathCheck -IsValid $false -Reason 'The path contains an empty component.') }
        if ($component -ceq '.' -or $component -ceq '..') { return (New-DmPathCheck -IsValid $false -Reason 'The path must not contain . or .. components.') }
        if ($component.EndsWith('.') -or $component.EndsWith(' ')) {
            return (New-DmPathCheck -IsValid $false -Reason 'A path component must not end with a dot or a space.')
        }
        $stem = $component.Split('.')[0].TrimEnd(' ')
        if ($stem -in $script:DmWindowsReservedNames) {
            return (New-DmPathCheck -IsValid $false -Reason 'A path component uses a reserved device name.')
        }
    }
    New-DmPathCheck -IsValid $true -Reason '' -Components $components
}

Export-ModuleMember -Function Test-DmVaultRelativePath
