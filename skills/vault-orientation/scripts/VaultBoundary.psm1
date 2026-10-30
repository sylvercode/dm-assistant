Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')

# Canonical vault-root resolution (only after the exact-vault authorization
# gate) and component-aware target containment (contract section 5). Every
# path component is examined with .NET filesystem APIs that do not follow
# links; symbolic links and junctions are resolved one hop at a time so an
# escaping or cyclic chain is refused before the target is accessed. No
# external shell command runs, no directory is created, and no replacement
# target is inferred.

$script:DmMaxLinkHops = 40
$script:DmSeparator = [System.IO.Path]::DirectorySeparatorChar

function Get-DmPathComparison {
    <#
    .SYNOPSIS
    Returns the operating-system-specific comparison used for vault paths.
    #>
    if ($IsLinux) { return [System.StringComparison]::Ordinal }
    [System.StringComparison]::OrdinalIgnoreCase
}

function ConvertTo-DmNativeSeparator {
    <#
    .SYNOPSIS
    Converts slash separators to native separators on Windows.
    .PARAMETER Path
    Path string whose separators should be normalized.
    #>
    param([string]$Path)
    if ($IsWindows) { return $Path.Replace('/', '\') }
    $Path
}

function Split-DmPathComponent {
    <#
    .SYNOPSIS
    Splits a path into nonempty native path components.
    .PARAMETER Path
    Path string to split.
    #>
    param([string]$Path)
    [char[]]$separators = if ($IsWindows) { '\', '/' } else { '/' }
    [string[]]$Path.Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries)
}

function Get-DmExceptionKind {
    <#
    .SYNOPSIS
    Classifies a filesystem error as missing or inaccessible.
    .PARAMETER ErrorRecord
    PowerShell error record whose exception chain is inspected.
    #>
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.IO.FileNotFoundException] -or $exception -is [System.IO.DirectoryNotFoundException]) { return 'missing' }
        if ($exception -is [System.UnauthorizedAccessException] -or $exception -is [System.IO.IOException] -or $exception -is [System.Security.SecurityException]) { return 'inaccessible' }
        $exception = $exception.InnerException
    }
    'inaccessible'
}

function Get-DmFileSystemEntry {
    <#
    .SYNOPSIS
    Reads one filesystem entry's attributes without following its link target.
    .DESCRIPTION
    Returns an exists, missing, or inaccessible state and any link target.
    .PARAMETER Path
    Absolute filesystem entry path to examine.
    #>
    param([Parameter(Mandatory)][string]$Path)
    try { $attributes = [System.IO.File]::GetAttributes($Path) }
    catch { return [pscustomobject]@{ state = (Get-DmExceptionKind -ErrorRecord $_); isDirectory = $false; linkTarget = $null } }
    $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
    $linkTarget = $null
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        try {
            $info = if ($isDirectory) { [System.IO.DirectoryInfo]::new($Path) } else { [System.IO.FileInfo]::new($Path) }
            # A reparse point that is not a symbolic link or junction (for example a cloud placeholder) has no link target.
            $linkTarget = $info.LinkTarget
        }
        catch { return [pscustomobject]@{ state = 'inaccessible'; isDirectory = $isDirectory; linkTarget = $null } }
    }
    [pscustomobject]@{ state = 'exists'; isDirectory = $isDirectory; linkTarget = $linkTarget }
}

function ConvertFrom-DmLinkTarget {
    <#
    .SYNOPSIS
    Classifies a link target as absolute, relative, or unresolvable.
    .PARAMETER Target
    Raw link target; supported Windows namespace prefixes are normalized.
    #>
    param([string]$Target)
    $t = ConvertTo-DmNativeSeparator -Path $Target
    if ($IsWindows) {
        if ($t.StartsWith('\??\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) { $t = '\\' + $t.Substring(8) }
        elseif ($t.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) { $t = '\\' + $t.Substring(8) }
        elseif ($t.StartsWith('\??\') -or $t.StartsWith('\\?\')) { $t = $t.Substring(4) }
        if ($t.StartsWith('\\.\') -or $t.StartsWith('\??\') -or $t.StartsWith('\\?\')) { return [pscustomobject]@{ kind = 'unresolvable'; path = $null } }
    }
    if ([string]::IsNullOrWhiteSpace($t)) { return [pscustomobject]@{ kind = 'unresolvable'; path = $null } }
    if ([System.IO.Path]::IsPathFullyQualified($t)) { return [pscustomobject]@{ kind = 'absolute'; path = $t } }
    if ([System.IO.Path]::IsPathRooted($t)) { return [pscustomobject]@{ kind = 'unresolvable'; path = $null } }
    [pscustomobject]@{ kind = 'relative'; path = $t }
}

function Test-DmPathWithinRoot {
    <#
    .SYNOPSIS
    Tests textual containment on path-component boundaries.
    .DESCRIPTION
    Component-aware containment: $true when Path equals Root or lies beneath
    it on a component boundary. Comparison defaults to OrdinalIgnoreCase on
    Windows and macOS and Ordinal on Linux. Both paths must already be
    absolute and free of '.' and '..' components; this is purely textual.
    .PARAMETER Root
    Canonical absolute root path.
    .PARAMETER Path
    Absolute candidate path to compare with the root.
    .PARAMETER Comparison
    String comparison to use; defaults to the platform's path comparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [System.StringComparison]$Comparison = (Get-DmPathComparison)
    )
    $r = ConvertTo-DmNativeSeparator -Path $Root
    $p = ConvertTo-DmNativeSeparator -Path $Path
    $rootOfRoot = [System.IO.Path]::GetPathRoot($r)
    if ($r.Length -gt $rootOfRoot.Length) { $r = $r.TrimEnd($script:DmSeparator) }
    $pathRoot = [System.IO.Path]::GetPathRoot($p)
    if ($p.Length -gt $pathRoot.Length) { $p = $p.TrimEnd($script:DmSeparator) }
    if ([string]::Equals($r, $p, $Comparison)) { return $true }
    $prefix = if ($r.EndsWith($script:DmSeparator)) { $r } else { $r + $script:DmSeparator }
    $p.StartsWith($prefix, $Comparison)
}

function Resolve-DmCanonicalDirectory {
    <#
    .SYNOPSIS
    Resolves an absolute directory component by component.
    .DESCRIPTION
    Follows symbolic links and junctions. Returns @{ status; path } where
    status is ok, invalid, missing, notDirectory, inaccessible, or cycle.
    .PARAMETER Path
    Explicit absolute directory path to resolve.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $fail = { param([string]$Status) [pscustomobject]@{ status = $Status; path = $null } }
    $normalized = ConvertTo-DmNativeSeparator -Path $Path
    if (-not [System.IO.Path]::IsPathFullyQualified($normalized)) { return (& $fail 'invalid') }
    $root = [System.IO.Path]::GetPathRoot($normalized)
    $components = Split-DmPathComponent -Path $normalized.Substring($root.Length)
    if (@($components | Where-Object { $_ -ceq '.' -or $_ -ceq '..' }).Count -gt 0) { return (& $fail 'invalid') }

    $queue = [System.Collections.Generic.List[string]]::new()
    $queue.AddRange([string[]]$components)
    $current = $root
    $hops = 0
    while ($queue.Count -gt 0) {
        $component = $queue[0]
        $queue.RemoveAt(0)
        if ($component -ceq '.') { continue }
        if ($component -ceq '..') {
            $parent = [System.IO.Path]::GetDirectoryName($current)
            if (-not [string]::IsNullOrEmpty($parent)) { $current = $parent }
            continue
        }
        $candidate = [System.IO.Path]::Join($current, $component)
        $entry = Get-DmFileSystemEntry -Path $candidate
        if ($entry.state -cne 'exists') { return (& $fail $entry.state) }
        if ($null -ne $entry.linkTarget) {
            $hops++
            if ($hops -gt $script:DmMaxLinkHops) { return (& $fail 'cycle') }
            $target = ConvertFrom-DmLinkTarget -Target $entry.linkTarget
            switch ($target.kind) {
                'absolute' {
                    $targetRoot = [System.IO.Path]::GetPathRoot($target.path)
                    $queue.InsertRange(0, [string[]](Split-DmPathComponent -Path $target.path.Substring($targetRoot.Length)))
                    $current = $targetRoot
                }
                'relative' { $queue.InsertRange(0, [string[]](Split-DmPathComponent -Path $target.path)) }
                default { return (& $fail 'cycle') }
            }
            continue
        }
        if (-not $entry.isDirectory) { return (& $fail 'notDirectory') }
        $current = $candidate
    }
    $final = Get-DmFileSystemEntry -Path $current
    if ($final.state -cne 'exists') { return (& $fail $final.state) }
    if (-not $final.isDirectory) { return (& $fail 'notDirectory') }
    if ($current.Length -gt $root.Length) { $current = $current.TrimEnd($script:DmSeparator) }
    [pscustomobject]@{ status = 'ok'; path = $current }
}

function Resolve-DmVaultRoot {
    <#
    .SYNOPSIS
    Resolves an authorized explicit vault root to a canonical boundary.
    .DESCRIPTION
    Resolves the explicit vault root to its canonical directory. Runs only
    after the exact-vault authorization gate: -Gate must be the passed
    'vault-authorization' gate outcome for the same request, otherwise this
    throws. Returns [pscustomobject]@{ gate = 'vault-root'; passed; result;
    evidence; boundary } where boundary is @{ selectedRoot; canonicalRoot;
    comparison } when passed, else $null and result is a VAULT_TARGET_INVALID
    contract result. The root path is never echoed in results.
    .PARAMETER Gate
    Passed exact-vault authorization gate outcome for the request.
    .PARAMETER VaultRoot
    Explicit absolute vault-root directory to resolve.
    .PARAMETER Operation
    Operation identifier included if root resolution fails.
    .PARAMETER Targets
    Requested vault-relative targets reported as not attempted on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Gate,
        [Parameter(Mandatory)][AllowEmptyString()][string]$VaultRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [AllowEmptyCollection()][string[]]$Targets = @()
    )
    $gateName = 'vault-root'
    if ($null -eq $Gate -or -not $Gate.PSObject.Properties['gate'] -or $Gate.gate -cne 'vault-authorization' -or -not $Gate.passed) {
        throw [System.InvalidOperationException]::new('The vault root is resolved only after the exact-vault authorization gate passes.')
    }
    $resolution = Resolve-DmCanonicalDirectory -Path $VaultRoot
    $evidence = @(New-DmEvidence -Gate $gateName -Subject 'vaultRoot' -State $(if ($resolution.status -ceq 'ok') { 'resolved' } else { $resolution.status }))
    if ($resolution.status -cne 'ok') {
        $message = switch ($resolution.status) {
            'missing' { 'The selected vault root does not exist.' }
            'notDirectory' { 'The selected vault root is not a directory.' }
            'inaccessible' { 'The selected vault root or one of its parent folders is inaccessible.' }
            'cycle' { 'The selected vault root has a cyclic or unresolvable link chain.' }
            default { 'The selected vault root is not a valid explicit absolute directory path.' }
        }
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode 'VAULT_TARGET_INVALID' -Targets $Targets -Message $message `
            -RemainingWork @('Select an existing, accessible vault folder explicitly, then retry.') -Detail ([ordered]@{ reason = $resolution.status })
        return [pscustomobject][ordered]@{ gate = $gateName; passed = $false; result = $result; evidence = $evidence; boundary = $null }
    }
    $boundary = [pscustomobject][ordered]@{
        selectedRoot  = $VaultRoot
        canonicalRoot = $resolution.path
        comparison    = (Get-DmPathComparison)
    }
    [pscustomobject][ordered]@{ gate = $gateName; passed = $true; result = $null; evidence = $evidence; boundary = $boundary }
}

function New-DmTargetResolution {
    <#
    .SYNOPSIS
    Constructs a target-resolution record and maps its status to a result code.
    .PARAMETER Path
    Original vault-relative target path.
    .PARAMETER Status
    Resolution state, including resolved, missing, invalid, outside, or inaccessible.
    .PARAMETER ItemType
    Resolved item type: file, directory, or missing.
    .PARAMETER ResolvedPath
    Internal absolute resolved path; do not expose it in contract results.
    .PARAMETER ResolvedRelativePath
    Resolved path relative to the vault boundary.
    .PARAMETER ViaLink
    Whether resolution followed a symbolic link or junction.
    .PARAMETER Reason
    Safe explanation of the resolution outcome.
    #>
    param([string]$Path, [string]$Status, [string]$ItemType = 'missing', [string]$ResolvedPath = $null, [string]$ResolvedRelativePath = $null, [bool]$ViaLink = $false, [string]$Reason = '')
    $code = switch ($Status) {
        'invalid' { 'PATH_INVALID' }
        'outside' { 'PATH_OUTSIDE_VAULT' }
        'inaccessible' { 'READ_FAILED' }
        default { $null }
    }
    [pscustomobject][ordered]@{
        path                 = $Path
        status               = $Status
        code                 = $code
        exists               = ($Status -ceq 'resolved')
        itemType             = $ItemType
        resolvedPath         = $(if ([string]::IsNullOrEmpty($ResolvedPath)) { $null } else { $ResolvedPath })
        resolvedRelativePath = $(if ([string]::IsNullOrEmpty($ResolvedRelativePath)) { $null } else { $ResolvedRelativePath })
        viaLink              = $ViaLink
        reason               = $Reason
    }
}

function Resolve-DmVaultTarget {
    <#
    .SYNOPSIS
    Resolves a vault-relative target while enforcing canonical containment.
    .DESCRIPTION
    Resolves one vault-relative target inside the boundary from
    Resolve-DmVaultRoot. Each component is examined without following links;
    a link hop is followed only while the walk stays inside the canonical
    root, so nothing outside the vault is touched. Returns
    [pscustomobject]@{ path; status; code; exists; itemType; resolvedPath;
    resolvedRelativePath; viaLink; reason } with status resolved (exists),
    missing (code $null), invalid (PATH_INVALID), outside (PATH_OUTSIDE_VAULT:
    escape, cycle, or unprovable containment), or inaccessible (READ_FAILED).
    itemType is file, directory, or missing. resolvedPath is an internal
    absolute path that must never be placed in a contract result.
    .PARAMETER Boundary
    Canonical vault boundary obtained after successful authorization.
    .PARAMETER Path
    Literal slash-separated vault-relative target path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )
    $lexical = Test-DmVaultRelativePath -Path $Path
    if (-not $lexical.isValid) { return (New-DmTargetResolution -Path $Path -Status 'invalid' -Reason $lexical.reason) }
    $root = [string]$Boundary.canonicalRoot
    $comparison = [System.StringComparison]$Boundary.comparison

    $queue = [System.Collections.Generic.List[string]]::new()
    $queue.AddRange([string[]]$lexical.components)
    $stack = [System.Collections.Generic.List[string]]::new()
    $current = $root
    $hops = 0
    $viaLink = $false
    $isDirectory = $true
    $outside = { param([string]$Reason) New-DmTargetResolution -Path $Path -Status 'outside' -ViaLink $viaLink -Reason $Reason }

    while ($queue.Count -gt 0) {
        $component = $queue[0]
        $queue.RemoveAt(0)
        if ($component -ceq '.') { continue }
        if ($component -ceq '..') {
            if ($stack.Count -eq 0) { return (& $outside 'A link resolves above the vault root.') }
            $stack.RemoveAt($stack.Count - 1)
            $current = [System.IO.Path]::GetDirectoryName($current)
            $isDirectory = $true
            continue
        }
        $candidate = [System.IO.Path]::Join($current, $component)
        $entry = Get-DmFileSystemEntry -Path $candidate
        if ($entry.state -ceq 'inaccessible') {
            return (New-DmTargetResolution -Path $Path -Status 'inaccessible' -ViaLink $viaLink -Reason 'A path component is inaccessible.')
        }
        $last = $queue.Count -eq 0
        if ($entry.state -ceq 'missing' -or (-not $entry.isDirectory -and $null -eq $entry.linkTarget -and -not $last)) {
            if (@($queue | Where-Object { $_ -ceq '..' -or $_ -ceq '.' }).Count -gt 0) {
                return (& $outside 'Containment of the remaining link path cannot be proven.')
            }
            $relative = @($stack) + @($component) + @($queue)
            $resolved = [System.IO.Path]::Join($root, ($relative -join $script:DmSeparator))
            return (New-DmTargetResolution -Path $Path -Status 'missing' -ResolvedPath $resolved -ResolvedRelativePath ($relative -join '/') -ViaLink $viaLink -Reason 'The target does not exist.')
        }
        if ($null -ne $entry.linkTarget) {
            $viaLink = $true
            $hops++
            if ($hops -gt $script:DmMaxLinkHops) { return (& $outside 'The link chain is cyclic or too long to prove containment.') }
            $target = ConvertFrom-DmLinkTarget -Target $entry.linkTarget
            switch ($target.kind) {
                'absolute' {
                    if (-not (Test-DmPathWithinRoot -Root $root -Path $target.path -Comparison $comparison)) {
                        return (& $outside 'A link resolves outside the vault.')
                    }
                    $rootLength = $root.TrimEnd($script:DmSeparator).Length
                    $rest = if ($target.path.Length -gt $rootLength) { $target.path.Substring($rootLength) } else { '' }
                    $parts = Split-DmPathComponent -Path $rest
                    if (@($parts | Where-Object { $_ -ceq '.' -or $_ -ceq '..' }).Count -gt 0) {
                        return (& $outside 'Containment of an absolute link target cannot be proven.')
                    }
                    $stack.Clear()
                    $current = $root
                    $queue.InsertRange(0, [string[]]$parts)
                }
                'relative' { $queue.InsertRange(0, [string[]](Split-DmPathComponent -Path $target.path)) }
                default { return (& $outside 'A link target cannot be resolved.') }
            }
            continue
        }
        $stack.Add($component)
        $current = $candidate
        $isDirectory = $entry.isDirectory
    }
    if ($stack.Count -eq 0) {
        return (& $outside 'The target resolves to the vault root itself.')
    }
    New-DmTargetResolution -Path $Path -Status 'resolved' -ItemType $(if ($isDirectory) { 'directory' } else { 'file' }) `
        -ResolvedPath $current -ResolvedRelativePath (@($stack) -join '/') -ViaLink $viaLink -Reason ''
}

function Confirm-DmVaultTarget {
    <#
    .SYNOPSIS
    Rechecks a vault boundary and target immediately before access.
    .DESCRIPTION
    Rechecks the boundary immediately before an access: re-resolves the root
    and the target and compares them with the earlier resolution. Returns
    [pscustomobject]@{ confirmed; code; reason; resolution } where code is
    $null when confirmed, PATH_OUTSIDE_VAULT when the root moved or the
    target now escapes, READ_FAILED when a component became inaccessible,
    and TARGET_CONFLICT when the target now resolves elsewhere or changed
    existence or type.
    .PARAMETER Boundary
    Previously established canonical vault boundary.
    .PARAMETER Resolution
    Earlier target-resolution record to compare with the current target.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Resolution
    )
    $comparison = [System.StringComparison]$Boundary.comparison
    $deny = { param([string]$Code, [string]$Reason, $Fresh) [pscustomobject][ordered]@{ confirmed = $false; code = $Code; reason = $Reason; resolution = $Fresh } }
    $root = Resolve-DmCanonicalDirectory -Path ([string]$Boundary.selectedRoot)
    if ($root.status -cne 'ok' -or -not [string]::Equals($root.path, [string]$Boundary.canonicalRoot, $comparison)) {
        return (& $deny 'PATH_OUTSIDE_VAULT' 'The vault root no longer resolves to the same canonical folder.' $null)
    }
    $fresh = Resolve-DmVaultTarget -Boundary $Boundary -Path ([string]$Resolution.path)
    if ($null -ne $fresh.code) { return (& $deny $fresh.code $fresh.reason $fresh) }
    $sameStatus = $fresh.status -ceq $Resolution.status -and $fresh.itemType -ceq $Resolution.itemType
    $samePath = [string]::Equals([string]$fresh.resolvedPath, [string]$Resolution.resolvedPath, $comparison)
    if (-not ($sameStatus -and $samePath)) {
        return (& $deny 'TARGET_CONFLICT' 'The target changed after it was resolved.' $fresh)
    }
    [pscustomobject][ordered]@{ confirmed = $true; code = $null; reason = ''; resolution = $fresh }
}

function Read-DmVaultTargetBytes {
    <#
    .SYNOPSIS
    Rechecks containment and reads a resolved file's exact bytes.
    .DESCRIPTION
    Confirms the boundary (Confirm-DmVaultTarget) and then reads a resolved
    file's bytes. Returns [pscustomobject]@{ ok; code; reason; bytes;
    version } where version is 'sha256:<hex>' of the bytes read. code is the
    recheck code or READ_FAILED for an operational read failure.
    .PARAMETER Boundary
    Canonical vault boundary used for the immediate recheck.
    .PARAMETER Resolution
    Previously resolved file target to confirm and read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Resolution
    )
    $fail = { param([string]$Code, [string]$Reason) [pscustomobject][ordered]@{ ok = $false; code = $Code; reason = $Reason; bytes = $null; version = $null } }
    $check = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $Resolution
    if (-not $check.confirmed) { return (& $fail $check.code $check.reason) }
    if ($check.resolution.itemType -cne 'file') { return (& $fail 'READ_FAILED' 'The target is not a file.') }
    try { $bytes = [System.IO.File]::ReadAllBytes($check.resolution.resolvedPath) }
    catch { return (& $fail 'READ_FAILED' 'The target could not be read.') }
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    [pscustomobject][ordered]@{ ok = $true; code = $null; reason = ''; bytes = $bytes; version = ('sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()) }
}

Export-ModuleMember -Function Resolve-DmVaultRoot, Resolve-DmVaultTarget, Confirm-DmVaultTarget, Read-DmVaultTargetBytes, Test-DmPathWithinRoot
