Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DependencyPreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultConfiguration.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PluginResources.psm1')

function Get-DmFileAccessFingerprint {
    <#
    .SYNOPSIS
    Fingerprints a file's discretionary access control list.
    .PARAMETER Path
    Existing file whose access rules are read.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $security = [System.IO.FileSystemAclExtensions]::GetAccessControl(
        [System.IO.FileInfo]::new($Path),
        [System.Security.AccessControl.AccessControlSections]::Access
    )
    $hash = [System.Security.Cryptography.SHA256]::HashData($security.GetSecurityDescriptorBinaryForm())
    [pscustomobject][ordered]@{
        security = $security
        version  = 'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
    }
}

function Get-DmByteFingerprint {
    <#
    .SYNOPSIS
    Returns the SHA-256 version identifier for exact note or resource bytes.
    .PARAMETER Bytes
    Byte sequence to fingerprint; an empty sequence is valid.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-DmCurrentChangeDependencyVersions {
    <#
    .SYNOPSIS
    Collects ordered versions of profile, reference, and plugin-resource inputs.
    .PARAMETER Boundary
    Canonical authorized vault boundary for profile and reference access.
    .PARAMETER Profile
    Validated profile, or null to fingerprint the absent or current profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [AllowNull()]$Profile
    )

    $versions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in (Get-DmProfileDependencyVersions -Boundary $Boundary -Profile $Profile)) {
        $versions.Add([string]$entry.identity, [string]$entry.version)
    }

    $inventory = Get-DmDependencyInventoryVersion
    $versions[[string]$inventory.identity] = [string]$inventory.version

    $shared = Get-DmSharedReferenceResource -Operation 'note.change'
    if (-not $shared.passed) { throw 'The packaged shared reference is unavailable.' }
    $versions[[string]$shared.resource.identity] = [string]$shared.resource.version

    $identities = [string[]]@($versions.Keys)
    [System.Array]::Sort($identities, [System.StringComparer]::Ordinal)
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($identity in $identities) {
        $entries.Add([pscustomobject][ordered]@{ identity = $identity; version = $versions[$identity] })
    }
    , [object[]]$entries.ToArray()
}

function Test-DmChangeDependencyVersions {
    <#
    .SYNOPSIS
    Compares ordered current and expected dependency-version snapshots.
    .PARAMETER Current
    Current ordered dependency identity and version records.
    .PARAMETER Expected
    Previously observed or approved ordered dependency records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Current,
        [Parameter(Mandatory)][object[]]$Expected
    )

    if ($Current.Count -ne $Expected.Count) {
        return [pscustomobject][ordered]@{ matches = $false; changedIdentities = @('dependency-set') }
    }
    $changed = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Current.Count; $i++) {
        if ([string]$Current[$i].identity -cne [string]$Expected[$i].identity -or
            [string]$Current[$i].version -cne [string]$Expected[$i].version) {
            $changed.Add([string]$Current[$i].identity)
        }
    }
    [pscustomobject][ordered]@{ matches = ($changed.Count -eq 0); changedIdentities = [string[]]$changed.ToArray() }
}

function ConvertFrom-DmNoteBytes {
    <#
    .SYNOPSIS
    Strictly decodes supported note bytes and verifies an exact round trip.
    .DESCRIPTION
    Supports BOM-marked UTF-8/UTF-16 and BOM-less UTF-8; unsafe bytes return
    ENCODING_UNSAFE rather than being converted.
    .PARAMETER Bytes
    Complete original note bytes, including any byte-order mark.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $encodingName = 'utf-8'
    $preamble = [byte[]]@()
    $offset = 0
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        $encodingName = 'utf-8'
        $preamble = [byte[]]@(0xEF, 0xBB, 0xBF)
        $offset = 3
    }
    elseif ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x00) {
        return [pscustomobject][ordered]@{ ok = $false; code = 'ENCODING_UNSAFE'; text = $null; encodingName = $null; encoding = $null; preamble = @(); roundTrips = $false }
    }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        $encodingName = 'utf-16le'
        $encoding = [System.Text.UnicodeEncoding]::new($false, $false, $true)
        $preamble = [byte[]]@(0xFF, 0xFE)
        $offset = 2
    }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        $encodingName = 'utf-16be'
        $encoding = [System.Text.UnicodeEncoding]::new($true, $false, $true)
        $preamble = [byte[]]@(0xFE, 0xFF)
        $offset = 2
    }
    elseif ($Bytes -contains 0x00) {
        return [pscustomobject][ordered]@{ ok = $false; code = 'ENCODING_UNSAFE'; text = $null; encodingName = $null; encoding = $null; preamble = @(); roundTrips = $false }
    }

    try {
        $text = $encoding.GetString($Bytes, $offset, $Bytes.Length - $offset)
        $body = $encoding.GetBytes($text)
        $roundTrip = [byte[]]::new($preamble.Length + $body.Length)
        if ($preamble.Length -gt 0) { [System.Array]::Copy($preamble, 0, $roundTrip, 0, $preamble.Length) }
        if ($body.Length -gt 0) { [System.Array]::Copy($body, 0, $roundTrip, $preamble.Length, $body.Length) }
        $roundTrips = [System.Linq.Enumerable]::SequenceEqual([byte[]]$Bytes, [byte[]]$roundTrip)
        [pscustomobject][ordered]@{
            ok            = $roundTrips
            code          = if ($roundTrips) { $null } else { 'ENCODING_UNSAFE' }
            text          = $text
            encodingName  = $encodingName
            encoding      = $encoding
            preamble      = $preamble
            roundTrips    = $roundTrips
        }
    }
    catch {
        [pscustomobject][ordered]@{ ok = $false; code = 'ENCODING_UNSAFE'; text = $null; encodingName = $null; encoding = $null; preamble = @(); roundTrips = $false }
    }
}

function ConvertTo-DmPreparedNote {
    <#
    .SYNOPSIS
    Prepares replacement bytes in the original supported note encoding.
    .DESCRIPTION
    Prepares a full replacement without touching the live target. Strictly
    decodable UTF-8/UTF-16 is round-tripped before preservation is accepted.
    .PARAMETER OriginalBytes
    Complete original note bytes used to determine encoding and BOM.
    .PARAMETER ReplacementText
    Complete replacement text; line endings in this value are encoded as given.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$OriginalBytes,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ReplacementText
    )

    $decoded = ConvertFrom-DmNoteBytes -Bytes $OriginalBytes
    if (-not $decoded.ok) {
        return [pscustomobject][ordered]@{
            ok = $false; code = 'ENCODING_UNSAFE'; message = 'The target contains text that cannot be decoded strictly as supported Unicode.'
            conversionDecision = 'undecodable-no-write'; bytes = $null; text = $null
        }
    }

    if (-not $decoded.roundTrips) {
        return [pscustomobject][ordered]@{
            ok = $false; code = 'ENCODING_UNSAFE'; message = 'The target bytes do not round-trip exactly as supported Unicode.'
            conversionDecision = 'undecodable-no-write'; bytes = $null; text = $null
        }
    }

    try {
        $body = $decoded.encoding.GetBytes($ReplacementText)
        $output = [byte[]]::new($decoded.preamble.Length + $body.Length)
        if ($decoded.preamble.Length -gt 0) { [System.Array]::Copy($decoded.preamble, 0, $output, 0, $decoded.preamble.Length) }
        if ($body.Length -gt 0) { [System.Array]::Copy($body, 0, $output, $decoded.preamble.Length, $body.Length) }
        [pscustomobject][ordered]@{
            ok = $true; code = $null; message = ''; conversionDecision = 'preserve'; bytes = $output; text = $ReplacementText
        }
    }
    catch {
        [pscustomobject][ordered]@{
            ok = $false; code = 'ENCODING_UNSAFE'; message = 'The proposed text cannot be encoded strictly as supported Unicode.'
            conversionDecision = 'undecodable-no-write'; bytes = $null; text = $null
        }
    }
}

function Invoke-DmAtomicReplace {
    <#
    .SYNOPSIS
    Stages and atomically replaces one note after boundary and version rechecks.
    .DESCRIPTION
    Stages complete bytes beside the resolved target, validates target and
    dependency versions at the replacement boundary, then uses a replace-class
    operation. Atomicity is per note and depends on the platform file system.
    .PARAMETER Boundary
    Canonical authorized vault boundary used for immediate rechecks.
    .PARAMETER Resolution
    Previously resolved target to revalidate before replacement.
    .PARAMETER Bytes
    Complete prepared replacement bytes to stage on the target filesystem.
    .PARAMETER ExpectedVersion
    Target fingerprint observed during preparation or review.
    .PARAMETER ExpectedDependencies
    Ordered dependency-version snapshot to recheck immediately before replacement.
    .PARAMETER Profile
    Validated profile for dependency checks, or null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Resolution,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [Parameter(Mandatory)][object[]]$ExpectedDependencies,
        [AllowNull()]$Profile
    )

    $stagePath = $null
    $directoryLease = $null
    try {
        $initialBoundary = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $Resolution
        if (-not $initialBoundary.confirmed) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$initialBoundary.code; message = 'The target boundary changed before staging.' }
        }
        $directoryLease = Open-DmVaultDirectoryLease -Boundary $Boundary -Resolution $initialBoundary.resolution
        $boundaryCheck = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $initialBoundary.resolution
        if (-not $boundaryCheck.confirmed) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$boundaryCheck.code; message = 'The target boundary changed before staging.' }
        }
        $directory = [System.IO.Path]::GetDirectoryName([string]$boundaryCheck.resolution.resolvedPath)
        $current = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $boundaryCheck.resolution
        if (-not $current.ok) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$current.code; message = 'The target could not be revalidated before staging.' }
        }
        if ([string]$current.version -cne $ExpectedVersion) {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; message = 'The target changed before staging.' }
        }
        $targetSecurity = Get-DmFileAccessFingerprint -Path ([string]$boundaryCheck.resolution.resolvedPath)
        $stagePath = [System.IO.Path]::Combine($directory, ".dmassist-$([guid]::NewGuid().ToString('N')).tmp")
        $stageHandle = [DmAssistant.IO.DirectoryLease]::CreateProtectedStage($stagePath)
        $stream = [System.IO.FileStream]::new($stageHandle, [System.IO.FileAccess]::Write, 4096, $false)
        try {
            [System.IO.FileSystemAclExtensions]::SetAccessControl(
                [System.IO.FileInfo]::new($stagePath),
                $targetSecurity.security
            )
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }

        $boundaryCheck = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $Resolution
        if (-not $boundaryCheck.confirmed) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$boundaryCheck.code; message = 'The target boundary changed before replacement.' }
        }
        $current = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $boundaryCheck.resolution
        if (-not $current.ok) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$current.code; message = 'The target could not be revalidated before replacement.' }
        }
        if ([string]$current.version -cne $ExpectedVersion) {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; message = 'The target changed before replacement.' }
        }
        try { $freshDependencies = Get-DmCurrentChangeDependencyVersions -Boundary $Boundary -Profile $Profile }
        catch {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; message = 'A profile, reference, or installed resource could not be revalidated before replacement.' }
        }
        $dependencyCheck = Test-DmChangeDependencyVersions -Current $freshDependencies -Expected $ExpectedDependencies
        if (-not $dependencyCheck.matches) {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; message = 'A profile, reference, or installed resource changed before replacement.' }
        }

        $finalBoundary = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $boundaryCheck.resolution
        if (-not $finalBoundary.confirmed) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$finalBoundary.code; message = 'The target boundary changed immediately before replacement.' }
        }
        $finalCurrent = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $finalBoundary.resolution
        if (-not $finalCurrent.ok) {
            return [pscustomobject][ordered]@{ ok = $false; code = [string]$finalCurrent.code; message = 'The target could not be revalidated immediately before replacement.' }
        }
        if ([string]$finalCurrent.version -cne $ExpectedVersion) {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; message = 'The target changed immediately before replacement.' }
        }
        $finalSecurity = Get-DmFileAccessFingerprint -Path ([string]$finalBoundary.resolution.resolvedPath)
        if ([string]$finalSecurity.version -cne [string]$targetSecurity.version) {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; message = 'The target access rules changed before replacement.' }
        }

        $replaceMethod = [System.IO.File].GetMethod('Replace', [type[]]@([string], [string], [string]))
        $replaceArguments = [object[]]::new(3)
        $replaceArguments[0] = $stagePath
        $replaceArguments[1] = [string]$finalBoundary.resolution.resolvedPath
        $replaceArguments[2] = $null
        # Reflection preserves a real null backup path; PowerShell binds null as an empty string here.
        $null = $replaceMethod.Invoke($null, $replaceArguments)
        $stagePath = $null
        [pscustomobject][ordered]@{ ok = $true; code = $null; message = '' }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        [pscustomobject][ordered]@{ ok = $false; code = 'INTERRUPTED'; message = 'The operation was interrupted before the target was replaced.' }
    }
    catch [System.OperationCanceledException] {
        [pscustomobject][ordered]@{ ok = $false; code = 'INTERRUPTED'; message = 'The operation was interrupted before the target was replaced.' }
    }
    catch {
        [pscustomobject][ordered]@{ ok = $false; code = 'WRITE_FAILED'; message = 'The complete replacement could not be staged or atomically installed.' }
    }
    finally {
        if ($null -ne $stagePath) {
            try { [System.IO.File]::Delete($stagePath) } catch { $null = $_ }
        }
        if ($null -ne $directoryLease) { $directoryLease.Dispose() }
    }
}

function Invoke-DmSafeNoteWrite {
    <#
    .SYNOPSIS
    Writes one prepared target using the per-note atomic replacement path.
    .PARAMETER Boundary
    Canonical authorized vault boundary.
    .PARAMETER Target
    Prepared target containing resolution, observedVersion, and replacementBytes.
    .PARAMETER ExpectedDependencies
    Optional dependency snapshot; when omitted, the current versions are read.
    .PARAMETER Profile
    Validated profile for dependency revalidation, or null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)]$Target,
        [AllowNull()][object[]]$ExpectedDependencies,
        [AllowNull()]$Profile
    )

    $expectedVersion = [string]$Target.observedVersion
    $replacementBytes = [byte[]]$Target.replacementBytes
    if (-not $PSBoundParameters.ContainsKey('ExpectedDependencies') -or $null -eq $ExpectedDependencies) {
        try { $ExpectedDependencies = Get-DmCurrentChangeDependencyVersions -Boundary $Boundary -Profile $Profile }
        catch {
            return [pscustomobject][ordered]@{ ok = $false; code = 'TARGET_CONFLICT'; reason = 'A profile, reference, or installed resource could not be verified.' }
        }
    }

    $outcome = Invoke-DmAtomicReplace -Boundary $Boundary -Resolution $Target.resolution -Bytes $replacementBytes `
        -ExpectedVersion $expectedVersion -ExpectedDependencies ([object[]]$ExpectedDependencies) -Profile $Profile
    [pscustomobject][ordered]@{ ok = [bool]$outcome.ok; code = $outcome.code; reason = [string]$outcome.message }
}

Export-ModuleMember -Function Get-DmByteFingerprint, Get-DmCurrentChangeDependencyVersions, Test-DmChangeDependencyVersions, ConvertFrom-DmNoteBytes, ConvertTo-DmPreparedNote, Get-DmFileAccessFingerprint, Invoke-DmAtomicReplace, Invoke-DmSafeNoteWrite
