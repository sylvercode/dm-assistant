Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimePreflight.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PluginResources.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultConfiguration.psm1')

function New-DmInventoryOutcome {
    <#
    .SYNOPSIS
    Creates the common inventory result wrapper.
    .PARAMETER Result
    Shared operation result returned by the inventory call.
    .PARAMETER InventoryReport
    Inventory report, or null when the operation is blocked.
    #>
    param($Result, $InventoryReport = $null)
    [pscustomobject][ordered]@{
        result          = $Result
        inventoryReport = $InventoryReport
    }
}

function New-DmInventoryBlock {
    <#
    .SYNOPSIS
    Creates a blocked inventory operation result.
    .PARAMETER Operation
    Name of the blocked operation.
    .PARAMETER Code
    Stable completion code for the block.
    .PARAMETER Message
    User-facing explanation of the block.
    .PARAMETER RemainingWork
    Work still required to proceed.
    .PARAMETER Details
    Structured diagnostic details for the result.
    #>
    param(
        [string]$Operation,
        [string]$Code,
        [string]$Message,
        [string[]]$RemainingWork,
        [System.Collections.IDictionary]$Details
    )
    New-DmBlockedResult -Operation $Operation -CompletionCode $Code -Targets @() `
        -Message $Message -RemainingWork $RemainingWork -Detail $Details
}

function Test-DmInventoryMarkdownPath {
    <#
    .SYNOPSIS
    Checks whether a path has the Markdown extension.
    .PARAMETER Path
    Path to check.
    #>
    param([Parameter(Mandatory)][string]$Path)
    [System.IO.Path]::GetExtension($Path) -ieq '.md'
}

function Get-DmInventorySelectionIndexes {
    <#
    .SYNOPSIS
    Maps normalized selected paths back to their request indexes.
    .PARAMETER OriginalPaths
    Original selected paths from the request.
    .PARAMETER NormalizedPaths
    Validated normalized paths to map.
    .PARAMETER Comparer
    Path comparer used for normalized identities.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OriginalPaths,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NormalizedPaths,
        [Parameter(Mandatory)][System.StringComparer]$Comparer
    )
    $indexes = [System.Collections.Generic.Dictionary[string, int]]::new($Comparer)
    for ($index = 0; $index -lt $OriginalPaths.Count; $index++) {
        $check = Test-DmVaultRelativePath -Path $OriginalPaths[$index]
        if (-not $check.isValid) { continue }
        $normalized = [string]::Join('/', [string[]]$check.components)
        if (-not $indexes.ContainsKey($normalized)) { $indexes.Add($normalized, $index) }
    }
    $result = [System.Collections.Generic.List[int]]::new()
    foreach ($path in $NormalizedPaths) {
        if ($indexes.ContainsKey($path)) { $result.Add($indexes[$path]) }
        else { $result.Add($result.Count) }
    }
    [int[]]$result.ToArray()
}

function Test-DmInventoryGuidanceUsable {
    <#
    .SYNOPSIS
    Checks whether guidance contains usable prose beyond metadata and headings.
    .PARAMETER Text
    Guidance text to inspect.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $lines = [string[]]($Text -split '\r\n|\n|\r')
    $inFrontmatter = $false
    if ($lines.Count -gt 0 -and $lines[0].Trim() -ceq '---') {
        $inFrontmatter = $true
    }
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($index -eq 0 -and $inFrontmatter) { continue }
        if ($inFrontmatter) {
            if ($line.Trim() -ceq '---') { $inFrontmatter = $false }
            continue
        }
        if ($line -match '^\s{0,3}#{1,6}(?:\s|$)') { continue }
        if (-not [string]::IsNullOrWhiteSpace($line)) { return $true }
    }
    $false
}

function Get-DmInventoryGuidanceText {
    <#
    .SYNOPSIS
    Reads and validates one contained Markdown guidance source.
    .PARAMETER Boundary
    Authorized vault boundary used for safe resolution and reads.
    .PARAMETER Path
    Vault-relative guidance path.
    .PARAMETER RequireUsableContent
    Requires prose beyond frontmatter and headings.
    #>
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireUsableContent
    )
    $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path $Path
    if ($null -ne $resolution.code) {
        return [pscustomobject][ordered]@{
            passed = $false
            code = [string]$resolution.code
            reason = $null
            state = 'blocked'
            version = $null
            text = $null
        }
    }
    if (-not $resolution.exists) {
        return [pscustomobject][ordered]@{
            passed = $false
            code = 'REFERENCE_UNAVAILABLE'
            reason = 'missing'
            state = 'missing'
            version = $null
            text = $null
        }
    }
    if ($resolution.itemType -cne 'file' -or
        -not (Test-DmInventoryMarkdownPath -Path $Path) -or
        [string]::IsNullOrWhiteSpace([string]$resolution.resolvedRelativePath) -or
        -not (Test-DmInventoryMarkdownPath -Path ([string]$resolution.resolvedRelativePath))) {
        return [pscustomobject][ordered]@{
            passed = $false
            code = 'REFERENCE_UNAVAILABLE'
            reason = 'non-markdown'
            state = 'non-markdown'
            version = $null
            text = $null
        }
    }
    $read = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $resolution
    if (-not $read.ok) {
        return [pscustomobject][ordered]@{
            passed = $false
            code = [string]$read.code
            reason = 'unreadable'
            state = 'unreadable'
            version = $null
            text = $null
        }
    }
    try { $text = [System.Text.UTF8Encoding]::new($false, $true).GetString([byte[]]$read.bytes) }
    catch {
        return [pscustomobject][ordered]@{
            passed = $false
            code = 'REFERENCE_UNAVAILABLE'
            reason = 'unreadable'
            state = 'unreadable'
            version = $null
            text = $null
        }
    }
    if ($RequireUsableContent -and -not (Test-DmInventoryGuidanceUsable -Text $text)) {
        return [pscustomobject][ordered]@{
            passed = $false
            code = 'REFERENCE_UNAVAILABLE'
            reason = 'unusable'
            state = 'unusable'
            version = $null
            text = $null
        }
    }
    [pscustomobject][ordered]@{
        passed = $true
        code = $null
        reason = $null
        state = 'loaded'
        version = [string]$read.version
        text = $text
    }
}

function Test-DmInventoryDependencies {
    <#
    .SYNOPSIS
    Rechecks relevant profile and guidance versions before returning a report.
    .PARAMETER Boundary
    Authorized vault boundary used for version checks.
    .PARAMETER Profile
    Validated profile or null when no profile is configured.
    .PARAMETER ReviewedVersions
    Dependency versions captured during preflight.
    .PARAMETER GuidancePaths
    Configured and default guidance paths.
    .PARAMETER SelectedGuidancePaths
    Additional paths selected for this request.
    #>
    param(
        [Parameter(Mandatory)]$Boundary,
        [AllowNull()][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][object[]]$ReviewedVersions,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GuidancePaths,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SelectedGuidancePaths
    )
    try {
        $current = Get-DmProfileDependencyVersions -Boundary $Boundary -Profile $Profile `
            -ReferencePaths $GuidancePaths -AdditionalGuidancePaths $SelectedGuidancePaths
    }
    catch {
        return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changedIdentities = @() }
    }
    $versions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $current) { $versions[[string]$entry.identity] = [string]$entry.version }
    $relevantIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void]$relevantIdentities.Add('.dmassist.yaml')
    foreach ($path in $GuidancePaths) { [void]$relevantIdentities.Add($path) }
    foreach ($entry in $ReviewedVersions) {
        if ([string]$entry.identity -clike 'plugin:*') { [void]$relevantIdentities.Add([string]$entry.identity) }
    }
    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $ReviewedVersions) {
        $identity = [string]$entry.identity
        if (-not $relevantIdentities.Contains($identity)) { continue }
        if (-not $versions.ContainsKey($identity) -or $versions[$identity] -cne [string]$entry.version) {
            $changed.Add($identity)
        }
    }
    [pscustomobject][ordered]@{
        passed = ($changed.Count -eq 0)
        code = $(if ($changed.Count -eq 0) { $null } else { 'TARGET_CONFLICT' })
        changedIdentities = [string[]]$changed.ToArray()
    }
}

function Test-DmInventoryLoadedGuidanceSnapshot {
    <#
    .SYNOPSIS
    Checks that loaded guidance matches the captured source versions.
    .PARAMETER LoadedVersions
    Map of loaded guidance paths to their captured versions.
    .PARAMETER ReviewedVersions
    Current dependency versions.
    .PARAMETER Comparer
    Path comparer used for source identities.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$LoadedVersions,
        [Parameter(Mandatory)][object[]]$ReviewedVersions,
        [Parameter(Mandatory)][System.StringComparer]$Comparer
    )
    foreach ($path in $LoadedVersions.Keys) {
        $matches = @($ReviewedVersions | Where-Object { $Comparer.Equals([string]$_.identity, [string]$path) })
        if ($matches.Count -ne 1 -or [string]$matches[0].version -cne [string]$LoadedVersions[$path]) {
            return [pscustomobject][ordered]@{
                passed = $false
                changedIdentity = [string]$path
            }
        }
    }
    [pscustomobject][ordered]@{ passed = $true; changedIdentity = $null }
}

function Test-DmInventoryHasDotComponent {
    <#
    .SYNOPSIS
    Checks whether a path contains a dot-prefixed component.
    .PARAMETER Path
    Vault-relative path to inspect.
    #>
    param([Parameter(Mandatory)][string]$Path)
    foreach ($component in $Path.Split('/')) {
        if ($component.StartsWith('.', [System.StringComparison]::Ordinal)) { return $true }
    }
    $false
}

function Get-DmInventoryPathSortKey {
    <#
    .SYNOPSIS
    Creates the sortable key record for an inventory path.
    .PARAMETER Path
    Inventory path used as the sort key.
    #>
    param([Parameter(Mandatory)][string]$Path)
    [pscustomobject]@{ path = $Path }
}

function Sort-DmInventoryRecords {
    <#
    .SYNOPSIS
    Sorts inventory records deterministically by path or role.
    .PARAMETER Records
    Records to sort.
    .PARAMETER Key
    Record property used as the primary sort key.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records, [Parameter(Mandatory)][ValidateSet('path', 'role')][string]$Key)
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) { $items.Add($record) }
    $sort = [System.Comparison[object]]{
        param($left, $right)
        $leftValue = [string]$left.$Key
        $rightValue = [string]$right.$Key
        $comparison = [System.StringComparer]::OrdinalIgnoreCase.Compare($leftValue, $rightValue)
        if ($comparison -ne 0) { return $comparison }
        [System.StringComparer]::Ordinal.Compare($leftValue, $rightValue)
    }.GetNewClosure()
    $items.Sort($sort)
    $items.ToArray()
}

function Add-DmInventoryDirectoryEntries {
    <#
    .SYNOPSIS
    Recursively enumerates eligible entries within the authorized vault.
    .PARAMETER Boundary
    Authorized vault boundary used for safe traversal.
    .PARAMETER RelativeDirectory
    Vault-relative directory path, or empty for the vault root.
    .PARAMETER AbsoluteDirectory
    Resolved directory path to enumerate.
    .PARAMETER Entries
    Mutable list that receives discovered entries.
    #>
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RelativeDirectory,
        [Parameter(Mandatory)][string]$AbsoluteDirectory,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Entries
    )
    $directoryResolution = $null
    if (-not [string]::IsNullOrEmpty($RelativeDirectory)) {
        $directoryResolution = Resolve-DmVaultTarget -Boundary $Boundary -Path $RelativeDirectory
        if ($null -ne $directoryResolution.code) {
            return [pscustomobject]@{ passed = $false; code = [string]$directoryResolution.code }
        }
        if (-not $directoryResolution.exists -or $directoryResolution.itemType -cne 'directory') {
            return [pscustomobject]@{ passed = $false; code = 'TARGET_CONFLICT' }
        }
        $confirmed = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $directoryResolution
        if (-not $confirmed.confirmed) {
            return [pscustomobject]@{ passed = $false; code = [string]$confirmed.code }
        }
    }

    try { $children = [string[]][System.IO.Directory]::EnumerateFileSystemEntries($AbsoluteDirectory) }
    catch { return [pscustomobject]@{ passed = $false; code = 'READ_FAILED' } }
    foreach ($child in $children) {
        $name = [System.IO.Path]::GetFileName($child)
        if ([string]::IsNullOrEmpty($name) -or $name.StartsWith('.', [System.StringComparison]::Ordinal)) { continue }
        try { $attributes = [System.IO.File]::GetAttributes($child) }
        catch { return [pscustomobject]@{ passed = $false; code = 'READ_FAILED' } }
        $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
        $isLink = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        $relativePath = if ([string]::IsNullOrEmpty($RelativeDirectory)) { $name } else { "$RelativeDirectory/$name" }
        if ($isDirectory) {
            $Entries.Add([pscustomobject][ordered]@{ path = $relativePath; kind = 'directory'; resolution = $null })
            if ($isLink) { continue }
            $nested = Add-DmInventoryDirectoryEntries -Boundary $Boundary -RelativeDirectory $relativePath `
                -AbsoluteDirectory $child -Entries $Entries
            if (-not $nested.passed) { return $nested }
            continue
        }
        if (-not (Test-DmInventoryMarkdownPath -Path $name)) { continue }

        $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path $relativePath
        if ($null -ne $resolution.code) {
            return [pscustomobject]@{ passed = $false; code = [string]$resolution.code }
        }
        if (-not $resolution.exists) {
            return [pscustomobject]@{ passed = $false; code = $(if ($resolution.viaLink) { 'READ_FAILED' } else { 'TARGET_CONFLICT' }) }
        }
        if ($resolution.itemType -cne 'file' -or
            -not (Test-DmInventoryMarkdownPath -Path ([string]$resolution.resolvedRelativePath)) -or
            (Test-DmInventoryHasDotComponent -Path ([string]$resolution.resolvedRelativePath))) {
            continue
        }
        $confirmed = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $resolution
        if (-not $confirmed.confirmed) {
            return [pscustomobject]@{ passed = $false; code = [string]$confirmed.code }
        }
        $Entries.Add([pscustomobject][ordered]@{ path = $relativePath; kind = 'markdown'; resolution = $resolution })
    }

    if ($null -ne $directoryResolution) {
        $confirmed = Confirm-DmVaultTarget -Boundary $Boundary -Resolution $directoryResolution
        if (-not $confirmed.confirmed) {
            return [pscustomobject]@{ passed = $false; code = [string]$confirmed.code }
        }
    }
    [pscustomobject]@{ passed = $true; code = $null }
}

function Get-DmInventoryBasisOrder {
    <#
    .SYNOPSIS
    Returns the stable evidence-basis ordering for inventory mappings.
    #>
    @(
        'profile-configured', 'configured-guidance', 'default-guidance',
        'dm-selected-guidance', 'default-convention', 'entry-name',
        'folder-name', 'frontmatter', 'markdown-content'
    )
}

function ConvertTo-DmInventoryRole {
    <#
    .SYNOPSIS
    Normalizes a recognized campaign role label.
    .PARAMETER Label
    Role label to normalize.
    #>
    param([Parameter(Mandatory)][string]$Label)
    $normalized = $Label.Trim()
    switch -Regex ($normalized) {
        '^(?i:adventure|adventures)$' { return 'Adventures' }
        '^(?i:arc|arcs)$' { return 'Adventure' }
        '^(?i:lore)$' { return 'Lore' }
        '^(?i:monsters\s+stats)$' { return 'Monsters Stats' }
        '^(?i:rules)$' { return 'Rules' }
        '^(?i:sessions)$' { return 'Sessions' }
        '^(?i:handouts)$' { return 'Handouts' }
        '^(?i:player)$' { return 'Lore/Player' }
        '^(?i:locations?)$' { return 'Lore/Locations' }
        '^(?i:cosmology|persona)$' { return 'Lore/' + (Get-Culture).TextInfo.ToTitleCase($normalized.ToLowerInvariant()) }
        default { return $null }
    }
}

function Add-DmInventoryMapping {
    <#
    .SYNOPSIS
    Adds or merges one evidence-backed role mapping.
    .PARAMETER Mappings
    Mutable map of mappings keyed by role and path.
    .PARAMETER Role
    Normalized campaign role.
    .PARAMETER Path
    Vault-relative location for the role.
    .PARAMETER Kind
    Inventory entry kind, or unknown when the location was not enumerated.
    .PARAMETER Classification
    Whether the mapping is observed or inferred.
    .PARAMETER Basis
    Evidence category supporting the mapping.
    .PARAMETER Source
    Source path or configuration identity.
    .PARAMETER Summary
    Privacy-safe summary of the supporting evidence.
    .PARAMETER Uncertainty
    Explanation of provisional evidence, if any.
    .PARAMETER SourceVersion
    Captured version of the supporting source, if applicable.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Mappings,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('directory', 'markdown', 'unknown')][string]$Kind = 'unknown',
        [Parameter(Mandatory)][ValidateSet('observed', 'inferred')][string]$Classification,
        [Parameter(Mandatory)][string]$Basis,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Summary,
        [AllowNull()][string]$Uncertainty,
        [AllowNull()][string]$SourceVersion = $null
    )
    if ([string]::IsNullOrWhiteSpace($Role) -or [string]::IsNullOrWhiteSpace($Path) -or
        (Test-DmInventoryHasDotComponent -Path $Path) -or
        ($Kind -cne 'directory' -and [System.IO.Path]::GetExtension($Path).Length -gt 0 -and
            -not (Test-DmInventoryMarkdownPath -Path $Path))) { return }
    $key = "$Role`0$Path"
    if (-not $Mappings.ContainsKey($key)) {
        $Mappings[$key] = [ordered]@{
            role = $Role
            path = $Path
            classification = $Classification
            basisValues = [System.Collections.Generic.List[string]]::new()
            evidenceValues = [System.Collections.Generic.List[object]]::new()
            uncertainty = $null
            evidenceVersions = [System.Collections.Generic.List[string]]::new()
        }
    }
    $mapping = $Mappings[$key]
    if ($Classification -ceq 'observed') {
        $mapping.classification = 'observed'
        $mapping.uncertainty = $null
    }
    elseif ($mapping.classification -cne 'observed' -and [string]::IsNullOrWhiteSpace([string]$mapping.uncertainty)) {
        $mapping.uncertainty = $Uncertainty
    }
    if (-not $mapping.basisValues.Contains($Basis)) { $mapping.basisValues.Add($Basis) }
    $exists = $false
    foreach ($item in $mapping.evidenceValues) {
        if ([string]$item.basis -ceq $Basis -and [string]$item.source -ceq $Source -and [string]$item.summary -ceq $Summary) {
            $exists = $true
            break
        }
    }
    if (-not $exists) {
        $mapping.evidenceValues.Add([pscustomobject][ordered]@{ basis = $Basis; source = $Source; summary = $Summary })
    }
    if (-not [string]::IsNullOrEmpty($SourceVersion)) {
        $versionIdentity = "$Source`0$SourceVersion"
        if (-not $mapping.evidenceVersions.Contains($versionIdentity)) { $mapping.evidenceVersions.Add($versionIdentity) }
    }
}

function Get-DmInventoryGuidanceAssignments {
    <#
    .SYNOPSIS
    Extracts explicit role-to-location assignments from loaded guidance.
    .PARAMETER LoadedSources
    Guidance sources that passed preflight.
    .PARAMETER GuidanceTexts
    Loaded guidance text keyed by source path.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$LoadedSources,
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, string]]$GuidanceTexts
    )
    $assignments = [System.Collections.Generic.List[object]]::new()
    foreach ($loaded in $LoadedSources) {
        $source = [string]$loaded.path
        if (-not $GuidanceTexts.ContainsKey($source)) { continue }
        $basis = switch ([string]$loaded.selectionKind) {
            'configured' { 'configured-guidance' }
            'default-designated' { 'default-guidance' }
            default { 'dm-selected-guidance' }
        }
        foreach ($line in [string[]]([string]$GuidanceTexts[$source] -split '\r\n|\n|\r')) {
            if ($line -match '^\s*([A-Za-z0-9][A-Za-z0-9 ._-]{0,79}?)\s+(?:contains|holds|stores)\s+(?:the\s+)?(adventures?|arcs?|lore|monsters\s+stats|rules|sessions|handouts|locations?|cosmology|persona|player)\b') {
                $role = ConvertTo-DmInventoryRole -Label ([string]$Matches[2])
                if ($null -ne $role) {
                    $assignments.Add([pscustomobject]@{
                        path = ([string]$Matches[1]).Trim().TrimEnd('/')
                        role = $role
                        basis = $basis
                        source = $source
                        summary = 'Loaded guidance explicitly assigns this location to the stated role.'
                    })
                }
            }
        }
    }
    $assignments.ToArray()
}

function Get-DmInventoryNoteRoleLabels {
    <#
    .SYNOPSIS
    Extracts explicit role labels from permitted Markdown content.
    .PARAMETER Text
    Markdown text whose inspection was authorized by the content gate.
    #>
    param([Parameter(Mandatory)][string]$Text)
    $labels = [System.Collections.Generic.List[object]]::new()
    $lines = [string[]]($Text -split '\r\n|\n|\r')
    $bodyStart = 0
    if ($lines.Count -gt 0 -and $lines[0].Trim() -ceq '---') {
        for ($index = 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index].Trim() -ceq '---') { $bodyStart = $index + 1; break }
            if ($lines[$index] -match '^\s*(?:role|type|section|category)\s*:\s*["'']?([^"'']+?)["'']?\s*$') {
                $role = ConvertTo-DmInventoryRole -Label ([string]$Matches[1])
                if ($null -ne $role) { $labels.Add([pscustomobject]@{ role = $role; basis = 'frontmatter' }) }
            }
        }
    }
    for ($index = $bodyStart; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '(?i)\bthis\s+(?:note|document|file)\s+is\s+(?:an?\s+)?(adventure|arc|lore|location|cosmology|persona|player|rules|session|handout|monsters\s+stats)\b') {
            $role = ConvertTo-DmInventoryRole -Label ([string]$Matches[1])
            if ($null -ne $role) { $labels.Add([pscustomobject]@{ role = $role; basis = 'markdown-content' }) }
        }
    }
    $labels.ToArray()
}

function Get-DmInventorySectionRole {
    <#
    .SYNOPSIS
    Identifies a recognized conventional section name.
    .PARAMETER Component
    Current path component.
    .PARAMETER ParentComponents
    Parent path components used to qualify nested Lore sections.
    #>
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ParentComponents
    )
    $role = ConvertTo-DmInventoryRole -Label $Component
    if ($null -ne $role -and $Component -notmatch '^(?i:player|locations?|cosmology|persona)$') { return $role }
    if ($ParentComponents.Count -gt 0 -and $ParentComponents[$ParentComponents.Count - 1] -ieq 'Lore' -and
        $Component -match '^(?i:player|locations|cosmology|persona)$') {
        $name = (Get-Culture).TextInfo.ToTitleCase($Component.ToLowerInvariant())
        return "Lore/$name"
    }
    $null
}

function Get-DmInventoryTokenMappings {
    <#
    .SYNOPSIS
    Adds inferred mappings supported by whole-word Adventure or Arc tokens.
    .PARAMETER Entries
    Eligible inventory entries to inspect.
    .PARAMETER Mappings
    Mutable map that receives evidence-backed mappings.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Mappings
    )
    foreach ($entry in $Entries) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$entry.path)
        if ($baseName -notmatch '(?i)(?<![\p{L}\p{N}])(?<token>Adventure|Adventures|Arc|Arcs)(?![\p{L}\p{N}])') { continue }
        $token = [string]$Matches.token
        $parentComponents = [string[]]@([string]$entry.path -split '/' | Select-Object -SkipLast 1)
        $role = if ($token -match '^(?i:arc|arcs)$') {
            'Adventure'
        }
        elseif (@($parentComponents | Where-Object { $_ -ieq 'Adventures' }).Count -gt 0) {
            'Adventure'
        }
        else {
            'Adventures'
        }
        $basis = if ([string]$entry.kind -ceq 'directory') { 'folder-name' } else { 'entry-name' }
        Add-DmInventoryMapping -Mappings $Mappings -Role $role -Path ([string]$entry.path) -Kind ([string]$entry.kind) `
            -Classification inferred -Basis $basis -Source ([string]$entry.path) `
            -Summary 'The eligible entry name contains a recognized whole-word role token.' `
            -Uncertainty 'Name evidence is provisional and may not establish the intended campaign role.'
    }
}

function Get-DmInventoryProfileAssignments {
    <#
    .SYNOPSIS
    Extracts role assignments from a validated profile.
    .PARAMETER Profile
    Validated profile or null when none is configured.
    #>
    param([AllowNull()][System.Collections.IDictionary]$Profile)
    if ($null -eq $Profile -or -not $Profile.Contains('sections') -or $Profile.sections -isnot [System.Collections.IDictionary]) {
        return @()
    }
    $roleNames = [ordered]@{
        adventures = 'Adventures'
        lore = 'Lore'
        monsters_stats = 'Monsters Stats'
        rules = 'Rules'
        sessions = 'Sessions'
        handouts = 'Handouts'
    }
    $assignments = [System.Collections.Generic.List[object]]::new()
    foreach ($section in $Profile.sections.Keys) {
        $role = if ($roleNames.Contains([string]$section)) { [string]$roleNames[[string]$section] } else { ConvertTo-DmInventoryRole -Label ([string]$section) }
        $value = $Profile.sections[$section]
        if ($value -is [string]) {
            if ($null -eq $role) { continue }
            $assignments.Add([pscustomobject]@{
                path = [string]$value
                role = $role
                basis = 'profile-configured'
                source = '.dmassist.yaml'
                summary = 'The validated profile directly configures this location for the stated role.'
            })
        }
        elseif ($section -ceq 'custom' -and $value -is [System.Collections.IDictionary]) {
            foreach ($customName in $value.Keys) {
                if ($value[$customName] -isnot [string]) { continue }
                $customRole = ConvertTo-DmInventoryRole -Label ([string]$customName)
                if ($null -eq $customRole) { continue }
                $assignments.Add([pscustomobject]@{
                    path = [string]$value[$customName]
                    role = $customRole
                    basis = 'profile-configured'
                    source = '.dmassist.yaml'
                    summary = 'The validated profile directly configures this location for the stated role.'
                })
            }
        }
    }
    $assignments.ToArray()
}

function Add-DmInventoryConventionalMappings {
    <#
    .SYNOPSIS
    Adds inferred mappings supported by exact conventional section names.
    .PARAMETER Entries
    Eligible inventory entries to inspect.
    .PARAMETER Mappings
    Mutable map that receives evidence-backed mappings.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Mappings
    )
    foreach ($entry in $Entries) {
        if ([string]$entry.kind -cne 'directory') { continue }
        $components = [string[]]([string]$entry.path -split '/')
        $prefix = [System.Collections.Generic.List[string]]::new()
        $parents = [System.Collections.Generic.List[string]]::new()
        foreach ($component in $components) {
            $prefix.Add($component)
            $role = Get-DmInventorySectionRole -Component $component -ParentComponents ([string[]]$parents.ToArray())
            if ($null -ne $role) {
                Add-DmInventoryMapping -Mappings $Mappings -Role $role -Path ([string]::Join('/', [string[]]$prefix.ToArray())) -Kind directory `
                    -Classification inferred -Basis 'default-convention' -Source ([string]$entry.path) `
                    -Summary 'The location uses an exact recognized conventional section name.' `
                    -Uncertainty 'Conventional naming is provisional and may not establish the intended campaign role.'
            }
            $parents.Add($component)
        }
    }
}

function ConvertTo-DmInventoryPublicMappings {
    <#
    .SYNOPSIS
    Converts internal mappings to ordered, deterministic report records.
    .PARAMETER Mappings
    Evidence-backed mappings to expose in the report.
    #>
    param([Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Mappings)
    $basisOrder = Get-DmInventoryBasisOrder
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($mapping in $Mappings.Values) {
        $basis = [System.Collections.Generic.List[string]]::new()
        foreach ($allowed in $basisOrder) {
            if ($mapping.basisValues.Contains($allowed)) { $basis.Add($allowed) }
        }
        $evidence = @($mapping.evidenceValues | Sort-Object -Property `
            @{ Expression = { [array]::IndexOf($basisOrder, [string]$_.basis) } }, `
            @{ Expression = { [string]$_.source } }, `
            @{ Expression = { [string]$_.summary } } -CaseSensitive)
        $records.Add([pscustomobject][ordered]@{
            role = [string]$mapping.role
            path = [string]$mapping.path
            classification = [string]$mapping.classification
            basis = [string[]]$basis.ToArray()
            evidence = [object[]]$evidence
            uncertainty = [string]$mapping.uncertainty
        })
    }
    $array = [object[]]$records.ToArray()
    $sort = [System.Comparison[object]]{
        param($left, $right)
        foreach ($field in @('role', 'path', 'classification')) {
            $comparison = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$left.$field, [string]$right.$field)
            if ($comparison -ne 0) { return $comparison }
            $comparison = [System.StringComparer]::Ordinal.Compare([string]$left.$field, [string]$right.$field)
            if ($comparison -ne 0) { return $comparison }
        }
        [System.StringComparer]::Ordinal.Compare(
            (Get-DmInventoryMappingEvidenceSortKey -Mapping $left),
            (Get-DmInventoryMappingEvidenceSortKey -Mapping $right)
        )
    }
    $records.Sort($sort)
    $records.ToArray()
}

function Get-DmInventoryMappingEvidenceSortKey {
    <#
    .SYNOPSIS
    Creates a deterministic sort key for mapping evidence.
    .PARAMETER Mapping
    Mapping whose evidence supplies the sort key.
    #>
    param([Parameter(Mandatory)]$Mapping)
    [string]::Join([char]0, [string[]]@($Mapping.evidence | ForEach-Object {
        '{0}{1}{2}{3}{4}{5}' -f $_.basis, [char]1, $_.source, [char]1, $_.summary, [char]2
    }))
}

function Get-DmInventoryAmbiguities {
    <#
    .SYNOPSIS
    Identifies competing mappings and binds decision IDs to their evidence.
    .PARAMETER Mappings
    Candidate mappings to compare.
    .PARAMETER CanonicalRoot
    Canonical identity of the authorized vault.
    .PARAMETER ProposalRequested
    Whether the request intends to create a proposal.
    .PARAMETER Decisions
    User decisions supplied for current ambiguity alternatives.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Mappings,
        [Parameter(Mandatory)][string]$CanonicalRoot,
        [Parameter(Mandatory)][bool]$ProposalRequested,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Decisions
    )
    $groups = [System.Collections.Generic.List[object]]::new()
    $records = @($Mappings.Values)
    $byPath = @{}
    foreach ($mapping in $records) {
        if (-not $byPath.ContainsKey([string]$mapping.path)) { $byPath[[string]$mapping.path] = [System.Collections.Generic.List[object]]::new() }
        $byPath[[string]$mapping.path].Add($mapping)
    }
    foreach ($path in $byPath.Keys) {
        $items = @($byPath[$path] | Sort-Object -Property role -CaseSensitive)
        $roles = @($items | ForEach-Object { [string]$_.role } | Select-Object -Unique)
        if ($roles.Count -gt 1) {
            $groups.Add([pscustomobject]@{ subject = [string]$path; reason = 'More than one supported role interpretation applies to this location.'; alternatives = $items })
        }
    }
    $byRole = @{}
    foreach ($mapping in $records) {
        if (-not $byRole.ContainsKey([string]$mapping.role)) { $byRole[[string]$mapping.role] = [System.Collections.Generic.List[object]]::new() }
        $byRole[[string]$mapping.role].Add($mapping)
    }
    foreach ($role in $byRole.Keys) {
        $items = @($byRole[$role] | Where-Object { $_.classification -ceq 'observed' -or
            @($_.basisValues | Where-Object { $_ -in @('default-convention', 'folder-name') }).Count -gt 0 })
        $paths = @($items | ForEach-Object { [string]$_.path } | Select-Object -Unique)
        if ($paths.Count -gt 1 -and
            (@($items | Where-Object { $_.classification -ceq 'observed' }).Count -gt 0 -or $ProposalRequested)) {
            $reason = if (@($items | Where-Object { $_.classification -ceq 'observed' }).Count -gt 0) {
                'A directly stated location differs from another supported location for this role.'
            }
            else {
                'More than one supported location could supply this role in a proposed profile.'
            }
            $groups.Add([pscustomobject]@{ subject = [string]$role; reason = $reason; alternatives = $items })
        }
    }

    $result = [System.Collections.Generic.List[object]]::new()
    $seenGroups = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($group in $groups) {
        $alternatives = [System.Collections.Generic.List[object]]::new()
        foreach ($mapping in $group.alternatives) {
            $evidence = @($mapping.evidenceValues | Sort-Object -Property basis, source, summary -CaseSensitive)
            $versions = [string]::Join([char]1, [string[]]@($mapping.evidenceVersions | Sort-Object -CaseSensitive))
            $descriptor = '{0}|{1}|{2}|{3}' -f $mapping.role, $mapping.path, (Get-DmInventoryMappingEvidenceSortKey -Mapping @{ evidence = $evidence }), $versions
            $alternatives.Add([pscustomobject]@{
                descriptor = $descriptor
                interpretation = [string]$mapping.role
                path = [string]$mapping.path
                evidence = $evidence
            })
        }
        $alternatives = [System.Collections.Generic.List[object]]@($alternatives |
            Sort-Object -Property @{ Expression = { [string]$_.interpretation }; Ascending = $true }, @{ Expression = { [string]$_.path }; Ascending = $true }, @{ Expression = { [string]$_.descriptor }; Ascending = $true })
        if ($alternatives.Count -lt 2) { continue }
        $groupKey = [string]$group.subject + '|' + [string]::Join('|', [string[]]@($alternatives | ForEach-Object { $_.descriptor }))
        if (-not $seenGroups.Add($groupKey)) { continue }
        $canonical = [string]::Join([char]0, @(
            'dm-assistant-inventory-ambiguity-v1',
            $CanonicalRoot,
            [string]$group.subject,
            [string]::Join([char]1, [string[]]@($alternatives | ForEach-Object { $_.descriptor }))
        ))
        $ambiguityHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant().Substring(0, 24)
        $ambiguityId = "amb-$ambiguityHash"
        $publicAlternatives = [System.Collections.Generic.List[object]]::new()
        foreach ($alternative in $alternatives) {
            $alternativeCanonical = [string]::Join([char]0, @('dm-assistant-inventory-alternative-v1', $ambiguityId, [string]$alternative.descriptor))
            $alternativeHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($alternativeCanonical))).ToLowerInvariant().Substring(0, 24)
            $publicAlternatives.Add([pscustomobject][ordered]@{
                alternativeId = "alt-$alternativeHash"
                interpretation = [string]$alternative.interpretation
                path = [string]$alternative.path
                evidence = [object[]]$alternative.evidence
            })
        }
        $selectedAlternative = $null
        foreach ($decision in $Decisions) {
            if ([string]$decision.ambiguityId -cne $ambiguityId) { continue }
            $match = @($publicAlternatives | Where-Object { [string]$_.alternativeId -ceq [string]$decision.alternativeId })
            if ($match.Count -eq 1) { $selectedAlternative = [string]$match[0].alternativeId }
        }
        $result.Add([pscustomobject][ordered]@{
            ambiguityId = $ambiguityId
            subject = [string]$group.subject
            alternatives = [object[]]$publicAlternatives.ToArray()
            reason = [string]$group.reason
            requiresDmDecision = ($ProposalRequested -and $null -eq $selectedAlternative)
            selectedAlternativeId = $selectedAlternative
        })
    }
    $result.ToArray()
}

function New-DmInventoryProfileProposal {
    <#
    .SYNOPSIS
    Builds and validates a read-only proposal while preserving existing profile text.
    .PARAMETER Boundary
    Authorized vault boundary used to re-read the existing profile.
    .PARAMETER BaseProfile
    Effective validated profile values used to compare section defaults.
    .PARAMETER ProfileVersion
    Captured profile version, or absent when no profile exists.
    .PARAMETER Mappings
    Public evidence-backed candidate mappings.
    .PARAMETER Entries
    Eligible inventory entries used to confirm mapped directories.
    .PARAMETER Ambiguities
    Current ambiguity records and any validated selections.
    #>
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][System.Collections.IDictionary]$BaseProfile,
        [Parameter(Mandatory)][string]$ProfileVersion,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Mappings,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Ambiguities
    )

    $roleKeys = [ordered]@{
        Adventures = 'adventures'
        Lore = 'lore'
        'Monsters Stats' = 'monsters_stats'
        Rules = 'rules'
        Sessions = 'sessions'
        Handouts = 'handouts'
    }
    $selectedPaths = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $selectedRoles = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($ambiguity in $Ambiguities) {
        if ([string]::IsNullOrEmpty([string]$ambiguity.selectedAlternativeId)) { continue }
        $alternative = @($ambiguity.alternatives | Where-Object {
                [string]$_.alternativeId -ceq [string]$ambiguity.selectedAlternativeId
            })
        if ($alternative.Count -ne 1) { continue }
        $subject = [string]$ambiguity.subject
        if ($roleKeys.Contains($subject)) {
            $selectedPaths[$subject] = [string]$alternative[0].path
        }
        elseif ($roleKeys.Contains([string]$alternative[0].interpretation)) {
            $selectedRoles[$subject] = [string]$alternative[0].interpretation
        }
    }

    $entryDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $Entries) {
        if ([string]$entry.kind -ceq 'directory') { [void]$entryDirectories.Add([string]$entry.path) }
    }
    $mappingGroups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::Ordinal)
    foreach ($mapping in $Mappings) {
        $role = [string]$mapping.role
        if (-not $roleKeys.Contains($role) -or -not $entryDirectories.Contains([string]$mapping.path)) { continue }
        if ($selectedPaths.ContainsKey($role) -and $selectedPaths[$role] -cne [string]$mapping.path) { continue }
        if ($selectedRoles.ContainsKey([string]$mapping.path) -and $selectedRoles[[string]$mapping.path] -cne $role) { continue }
        if (-not $mappingGroups.ContainsKey($role)) {
            $mappingGroups[$role] = [System.Collections.Generic.List[object]]::new()
        }
        $mappingGroups[$role].Add($mapping)
    }

    $updates = [ordered]@{}
    foreach ($role in $roleKeys.Keys) {
        if (-not $mappingGroups.ContainsKey([string]$role)) { continue }
        $paths = [string[]]@($mappingGroups[[string]$role] | ForEach-Object { [string]$_.path } | Select-Object -Unique)
        if ($paths.Count -ne 1) {
            return [pscustomobject][ordered]@{
                passed = $false
                code = 'OPERATION_FAILED'
                content = $null
                differences = $null
                message = 'More than one supported section location remains after current decisions.'
            }
        }
        $key = [string]$roleKeys[[string]$role]
        $currentPath = [string]$BaseProfile.sections[$key]
        if ($paths[0] -cne $currentPath) { $updates[$key] = $paths[0] }
    }

    $exists = $ProfileVersion -cne 'absent'
    $originalText = $null
    $bom = ''
    if ($exists) {
        $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path '.dmassist.yaml'
        if ($null -ne $resolution.code -or -not $resolution.exists -or $resolution.itemType -cne 'file') {
            return [pscustomobject][ordered]@{
                passed = $false; code = 'TARGET_CONFLICT'; content = $null; differences = $null
                message = 'The profile changed or could not be safely resolved while preparing the proposal.'
            }
        }
        $read = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $resolution
        if (-not $read.ok -or [string]$read.version -cne $ProfileVersion) {
            return [pscustomobject][ordered]@{
                passed = $false; code = 'TARGET_CONFLICT'; content = $null; differences = $null
                message = 'The profile changed while preparing the proposal.'
            }
        }
        try { $originalText = [System.Text.UTF8Encoding]::new($false, $true).GetString([byte[]]$read.bytes) }
        catch {
            return [pscustomobject][ordered]@{
                passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                message = 'The existing profile text cannot be preserved as readable UTF-8.'
            }
        }
        if ($originalText.StartsWith([string][char]0xFEFF, [System.StringComparison]::Ordinal)) {
            $bom = [string][char]0xFEFF
            $originalText = $originalText.Substring(1)
        }
        $unsafeFilename = $false
        foreach ($match in [regex]::Matches($originalText, '(?<![\w./@-])(?<name>(?:[\w.-]+[\\/])*[\w-]+\.(?<ext>[A-Za-z]{2,8}))')) {
            $candidateName = [string]$match.Groups['name'].Value
            $extension = [string]$match.Groups['ext'].Value
            if ($candidateName -cne 'dmassist.yaml' -and $extension -inotmatch '^md$') {
                $unsafeFilename = $true
                break
            }
        }
        if ($originalText -match '(?i)(?:[A-Z]:[\\/]|\\\\[^\\\s]+\\|(?<![\w:/])\/(?:[^\/\s]+\/)*[^\/\s]+)' -or $unsafeFilename) {
            return [pscustomobject][ordered]@{
                passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                message = 'The existing profile contains a path or filename that cannot be disclosed safely in a proposal.'
            }
        }
    }
    else {
        $originalText = $null
    }

    $changes = [System.Collections.Generic.List[object]]::new()
    if (-not $exists) {
        $builder = [System.Text.StringBuilder]::new()
        [void]$builder.Append("version: 1`n")
        if ($updates.Count -gt 0) {
            [void]$builder.Append("sections:`n")
            foreach ($key in $roleKeys.Values) {
                if (-not $updates.Contains([string]$key)) { continue }
                $line = "  $key`: '" + ([string]$updates[[string]$key]).Replace("'", "''") + "'"
                [void]$builder.Append($line + "`n")
            }
        }
        $content = [string]$builder.ToString()
        $differenceLines = [System.Collections.Generic.List[string]]::new()
        $differenceLines.Add('Proposed content for new .dmassist.yaml:')
        $differenceLines.Add($content.TrimEnd("`r", "`n"))
        $differences = [string]::Join("`n", [string[]]$differenceLines.ToArray())
    }
    else {
        $distinctLineEndings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($lineEndingMatch in [regex]::Matches($originalText, '\r\n|\n|\r')) {
            [void]$distinctLineEndings.Add([string]$lineEndingMatch.Value)
        }
        if ($updates.Count -gt 0 -and $distinctLineEndings.Count -gt 1) {
            return [pscustomobject][ordered]@{
                passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                message = 'The existing profile uses mixed line endings that cannot be preserved safely.'
            }
        }
        $newlineMatch = [regex]::Match($originalText, '\r\n|\n|\r')
        $lineEnding = if ($newlineMatch.Success) { $newlineMatch.Value } else { [Environment]::NewLine }
        $hasTrailingNewline = [regex]::IsMatch($originalText, '(?:\r\n|\n|\r)$')
        $lines = [System.Collections.Generic.List[string]]::new([string[]][regex]::Split($originalText, '\r\n|\n|\r'))
        if ($hasTrailingNewline -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -ceq '') {
            $lines.RemoveAt($lines.Count - 1)
        }
        $sectionStart = -1
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^sections\s*:\s*(?:#.*)?$') { $sectionStart = $index; break }
            if ($lines[$index] -match '^sections\s*:') {
                return [pscustomobject][ordered]@{
                    passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                    message = 'The existing profile uses a sections layout that cannot be edited without reformatting it.'
                }
            }
        }
        if ($sectionStart -lt 0 -and $updates.Count -gt 0) {
            if ($lines.Count -gt 0 -and -not $hasTrailingNewline) { $lines.Add('') }
            $sectionStart = $lines.Count
            $lines.Add('sections:')
            foreach ($key in $roleKeys.Values) {
                if (-not $updates.Contains([string]$key)) { continue }
                $line = "  $key`: '" + ([string]$updates[[string]$key]).Replace("'", "''") + "'"
                $lines.Add($line)
                $changes.Add([pscustomobject]@{ line = $lines.Count; before = $null; after = $line })
            }
            $changes.Insert(0, [pscustomobject]@{ line = $sectionStart + 1; before = $null; after = 'sections:' })
        }
        elseif ($sectionStart -ge 0 -and $updates.Count -gt 0) {
            $sectionEnd = $lines.Count
            for ($index = $sectionStart + 1; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match '^[^\s#].*$') { $sectionEnd = $index; break }
            }
            foreach ($key in $roleKeys.Values) {
                if (-not $updates.Contains([string]$key)) { continue }
                $propertyLine = -1
                for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
                    if ($lines[$index] -match ("^  " + [regex]::Escape([string]$key) + "\s*:")) {
                        $propertyLine = $index
                        break
                    }
                    if ($lines[$index] -match '^\S') {
                        return [pscustomobject][ordered]@{
                            passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                            message = 'The existing profile indentation cannot be preserved safely.'
                        }
                    }
                }
                $value = "'" + ([string]$updates[[string]$key]).Replace("'", "''") + "'"
                if ($propertyLine -ge 0) {
                    $oldLine = [string]$lines[$propertyLine]
                    if ($oldLine -notmatch ("^(  " + [regex]::Escape([string]$key) + "\s*:\s*)(.+)$")) {
                        return [pscustomobject][ordered]@{
                            passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                            message = 'The existing profile value cannot be updated without changing its structure.'
                        }
                    }
                    $prefix = [string]$Matches[1]
                    $remainder = [string]$Matches[2]
                    if ($remainder -match '^(?:[>|][+-]?\s*|[\[{].*)$') {
                        return [pscustomobject][ordered]@{
                            passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                            message = 'The existing profile value uses a complex scalar form that cannot be preserved safely.'
                        }
                    }
                    $commentStart = -1
                    $quote = [char]0
                    for ($characterIndex = 0; $characterIndex -lt $remainder.Length; $characterIndex++) {
                        $character = $remainder[$characterIndex]
                        if ($quote -ceq [char]39) {
                            if ($character -ceq [char]39 -and $characterIndex + 1 -lt $remainder.Length -and $remainder[$characterIndex + 1] -ceq [char]39) {
                                $characterIndex++
                            }
                            elseif ($character -ceq [char]39) { $quote = [char]0 }
                            continue
                        }
                        if ($quote -ceq [char]34) {
                            if ($character -ceq [char]92) { $characterIndex++; continue }
                            if ($character -ceq [char]34) { $quote = [char]0 }
                            continue
                        }
                        if ($character -ceq [char]39 -or $character -ceq [char]34) { $quote = $character; continue }
                        if ($character -ceq '#' -and ($characterIndex -eq 0 -or [char]::IsWhiteSpace($remainder[$characterIndex - 1]))) {
                            $commentStart = $characterIndex
                            break
                        }
                    }
                    $suffix = ''
                    if ($commentStart -ge 0) {
                        $suffixStart = $commentStart
                        while ($suffixStart -gt 0 -and [char]::IsWhiteSpace($remainder[$suffixStart - 1])) { $suffixStart-- }
                        $suffix = $remainder.Substring($suffixStart)
                    }
                    else {
                        $suffix = [regex]::Match($remainder, '\s*$').Value
                    }
                    $newLine = $prefix + $value + $suffix
                    if ($newLine -cne $oldLine) {
                        $lines[$propertyLine] = $newLine
                        $changes.Add([pscustomobject]@{ line = $propertyLine + 1; before = $oldLine; after = $newLine })
                    }
                }
                else {
                    $newLine = "  $key`: $value"
                    $lines.Insert($sectionEnd, $newLine)
                    $sectionEnd++
                    $changes.Add([pscustomobject]@{ line = $sectionEnd; before = $null; after = $newLine })
                }
            }
        }
        $contentBody = [string]::Join($lineEnding, [string[]]$lines.ToArray())
        if ($hasTrailingNewline -and $contentBody.Length -gt 0) { $contentBody += $lineEnding }
        $content = $bom + $contentBody
        if ($content -ceq ($bom + $originalText)) {
            $differences = 'No changes. Existing .dmassist.yaml is unchanged.'
        }
        else {
            $diff = [System.Collections.Generic.List[string]]::new()
            $diff.Add('--- .dmassist.yaml')
            $diff.Add('+++ .dmassist.yaml')
            foreach ($change in $changes) {
                $diff.Add("@@ line $($change.line) @@")
                if ($null -ne $change.before) { $diff.Add('-' + [string]$change.before) }
                if ($null -ne $change.after) { $diff.Add('+' + [string]$change.after) }
            }
            if ($changes.Count -eq 0) {
                return [pscustomobject][ordered]@{
                    passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
                    message = 'The complete profile difference could not be represented safely.'
                }
            }
            $differences = [string]::Join("`n", [string[]]$diff.ToArray())
        }
    }

    $parsed = ConvertFrom-DmVaultProfileYaml -Yaml $content
    if (-not $parsed.passed) {
        return [pscustomobject][ordered]@{
            passed = $false; code = 'OPERATION_FAILED'; content = $null; differences = $null
            message = 'The generated profile proposal could not be parsed safely.'
        }
    }
    $schema = Test-DmProfileSchema -Profile $parsed.profile
    if (-not $schema.passed) {
        return [pscustomobject][ordered]@{
            passed = $false; code = [string]$schema.code; content = $null; differences = $null
            message = 'The generated profile proposal did not pass the installed version-one schema.'
        }
    }
    [pscustomobject][ordered]@{
        passed = $true
        code = $null
        content = $content
        differences = $differences
        message = ''
    }
}

function Invoke-DmInventory {
    <#
    .SYNOPSIS
    Validates and orients an explicit read-only vault inventory request.
    .DESCRIPTION
    The operation is available only through explicit import and invocation.
    Registry metadata validates the request but does not dispatch it.
    .PARAMETER Request
    Feature 003 operation request for the authorized vault inventory.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Request)

    $preflight = Invoke-DmPreflight -Request $Request
    if (-not $preflight.passed) { return (New-DmInventoryOutcome -Result $preflight.result) }
    $normalizedRequest = $preflight.request
    $operation = [string]$normalizedRequest.operation
    if ($operation -cne 'vault.orientation.inventory' -or $normalizedRequest.mode -cne 'inspect') {
        $result = New-DmInventoryBlock -Operation 'vault.orientation.inventory' -Code 'INVALID_REQUEST' `
            -Message 'Inventory requires the registered operation in inspect mode.' `
            -RemainingWork @('Send a valid inspect-mode inventory request, then retry.') -Details $null
        return (New-DmInventoryOutcome -Result $result)
    }

    try { $context = Get-DmPreNoteContext -Preflight $preflight }
    catch {
        $result = New-DmInventoryBlock -Operation $operation -Code 'TARGET_CONFLICT' `
            -Message 'A required profile or guidance dependency could not be verified; no inventory report was returned.' `
            -RemainingWork @('Revalidate the profile and local guidance, then retry.') -Details $null
        return (New-DmInventoryOutcome -Result $result)
    }
    if (-not $context.passed) { return (New-DmInventoryOutcome -Result $context.result) }

    $arguments = $normalizedRequest.arguments
    $selectedGuidance = [string[]]$arguments.selectedGuidance
    $optionalGuidance = [string[]]$arguments.optionalGuidance
    $pathComparer = if ([System.StringComparison]$preflight.boundary.comparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $selectedGuidanceSet = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($selectedPath in $selectedGuidance) { [void]$selectedGuidanceSet.Add($selectedPath) }
    $optionalSet = [System.Collections.Generic.HashSet[string]]::new(
        $(if ([System.StringComparison]$preflight.boundary.comparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
                [System.StringComparer]::OrdinalIgnoreCase
            }
            else { [System.StringComparer]::Ordinal })
    )
    foreach ($path in $optionalGuidance) { [void]$optionalSet.Add($path) }
    $originalSelected = @()
    $originalArguments = if ($Request -is [System.Collections.IDictionary]) { $Request['arguments'] } else { $Request.arguments }
    if ($originalArguments -is [System.Collections.IDictionary] -and $originalArguments.Contains('selectedGuidance')) {
        $originalSelected = @($originalArguments['selectedGuidance'])
    }
    elseif ($null -ne $originalArguments -and $originalArguments.PSObject.Properties['selectedGuidance']) {
        $originalSelected = @($originalArguments.selectedGuidance)
    }
    $selectionIndexes = Get-DmInventorySelectionIndexes -OriginalPaths ([string[]]$originalSelected) `
        -NormalizedPaths $selectedGuidance -Comparer $pathComparer

    $guidancePath = $null
    $selectionKind = $null
    if ($null -ne $context.profile -and $context.profile.Contains('guidance')) {
        $guidancePath = [string]$context.profile.guidance.path
        $selectionKind = 'configured'
    }
    else {
        $defaultResolution = Resolve-DmVaultTarget -Boundary $preflight.boundary -Path '.dmassist-guidance.md'
        if ($null -ne $defaultResolution.code) {
            $result = New-DmInventoryBlock -Operation $operation -Code ([string]$defaultResolution.code) `
                -Message 'The designated local guidance could not be safely resolved.' `
                -RemainingWork @('Correct or restore the local guidance, then retry.') -Details $null
            return (New-DmInventoryOutcome -Result $result)
        }
        if ($defaultResolution.exists) {
            $guidancePath = '.dmassist-guidance.md'
            $selectionKind = 'default-designated'
        }
    }

    $loadedSources = [System.Collections.Generic.List[object]]::new()
    $guidanceTexts = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $guidancePaths = [System.Collections.Generic.List[string]]::new()
    $selectedLoaded = [System.Collections.Generic.List[string]]::new()
    $loadedGuidanceVersions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $skipped = [System.Collections.Generic.List[object]]::new()
    $configuredOrDefaultLoaded = $false
    $designatedState = 'not-applicable'
    if ($null -ne $guidancePath) {
        $guidancePaths.Add($guidancePath)
        $designatedState = 'pending'
        $designated = Get-DmInventoryGuidanceText -Boundary $preflight.boundary -Path $guidancePath
        if (-not $designated.passed) {
            $designatedState = [string]$designated.state
            $code = if ($designated.code -cin @('PATH_INVALID', 'PATH_OUTSIDE_VAULT', 'READ_FAILED')) { [string]$designated.code } else { 'REFERENCE_UNAVAILABLE' }
            $result = New-DmInventoryBlock -Operation $operation -Code $code `
                -Message 'The designated local guidance is unavailable or not eligible Markdown.' `
                -RemainingWork @('Restore or correct the designated local guidance, then retry.') -Details $null
            return (New-DmInventoryOutcome -Result $result)
        }
        $designatedState = [string]$designated.state
        $loadedSources.Add([pscustomobject][ordered]@{ path = $guidancePath; selectionKind = $selectionKind })
        $guidanceTexts[$guidancePath] = [string]$designated.text
        $loadedGuidanceVersions[$guidancePath] = [string]$designated.version
        $configuredOrDefaultLoaded = $true
    }
    else {
        $guidancePaths.Add('.dmassist-guidance.md')
    }

    for ($index = 0; $index -lt $selectedGuidance.Count; $index++) {
        $path = $selectedGuidance[$index]
        if ($null -ne $guidancePath -and $pathComparer.Equals($path, $guidancePath)) {
            $loadedSources.Add([pscustomobject][ordered]@{ path = $path; selectionKind = 'request-selected' })
            $selectedLoaded.Add($path)
            $alreadyIncluded = $false
            foreach ($loadedPath in $guidancePaths) {
                if ($pathComparer.Equals($loadedPath, $path)) { $alreadyIncluded = $true; break }
            }
            if (-not $alreadyIncluded) { $guidancePaths.Add($path) }
            continue
        }
        $optional = $optionalSet.Contains($path)
        $selectedState = 'pending'
        $selected = Get-DmInventoryGuidanceText -Boundary $preflight.boundary -Path $path -RequireUsableContent
        $selectedState = [string]$selected.state
        if (-not $selected.passed) {
            if ($optional -and $selected.reason -cin @('missing', 'unreadable', 'non-markdown', 'unusable')) {
                $skipped.Add([pscustomobject][ordered]@{ selectionIndex = $selectionIndexes[$index]; reason = $selected.reason })
                continue
            }
            $code = if ($selected.code -cin @('PATH_INVALID', 'PATH_OUTSIDE_VAULT', 'READ_FAILED')) { [string]$selected.code } else { 'REFERENCE_UNAVAILABLE' }
            $result = New-DmInventoryBlock -Operation $operation -Code $code `
                -Message 'A required selected guidance source is unavailable or not eligible Markdown.' `
                -RemainingWork @('Restore or correct the selected guidance, then retry.') -Details $null
            return (New-DmInventoryOutcome -Result $result)
        }
        $loadedSources.Add([pscustomobject][ordered]@{ path = $path; selectionKind = 'request-selected' })
        $guidanceTexts[$path] = [string]$selected.text
        $guidancePaths.Add($path)
        $selectedLoaded.Add($path)
        $loadedGuidanceVersions[$path] = [string]$selected.version
    }

    $loadedSnapshotCheck = Test-DmInventoryLoadedGuidanceSnapshot -LoadedVersions $loadedGuidanceVersions `
        -ReviewedVersions ([object[]]$context.dependencyVersions) -Comparer $pathComparer
    if (-not $loadedSnapshotCheck.passed) {
        $result = New-DmInventoryBlock -Operation $operation -Code 'TARGET_CONFLICT' `
            -Message 'Loaded guidance changed after the pre-note snapshot; no inventory report was returned.' `
            -RemainingWork @('Revalidate the profile and local guidance, then retry.') `
            -Details ([ordered]@{ changedDependencies = @([string]$loadedSnapshotCheck.changedIdentity) })
        return (New-DmInventoryOutcome -Result $result)
    }

    $internalEntries = [System.Collections.Generic.List[object]]::new()
    $traversal = Add-DmInventoryDirectoryEntries -Boundary $preflight.boundary -RelativeDirectory '' `
        -AbsoluteDirectory ([string]$preflight.boundary.canonicalRoot) -Entries $internalEntries
    if (-not $traversal.passed) {
        $code = if ([string]$traversal.code -cin @('PATH_INVALID', 'PATH_OUTSIDE_VAULT', 'READ_FAILED', 'TARGET_CONFLICT')) {
            [string]$traversal.code
        }
        else { 'READ_FAILED' }
        $result = New-DmInventoryBlock -Operation $operation -Code $code `
            -Message 'The vault inventory could not be enumerated safely; no report was returned.' `
            -RemainingWork @('Restore stable, readable vault access, then retry.') -Details $null
        return (New-DmInventoryOutcome -Result $result)
    }

    $preflightSourcePaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($selectedPath in $selectedGuidance) { [void]$preflightSourcePaths.Add($selectedPath) }
    if ($null -ne $guidancePath) { [void]$preflightSourcePaths.Add($guidancePath) }
    $retainedEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $internalEntries) {
        if (-not $preflightSourcePaths.Contains([string]$entry.path)) { $retainedEntries.Add($entry) }
    }
    $internalEntries = $retainedEntries

    $internalEntries = [System.Collections.Generic.List[object]]::new(
        [object[]](Sort-DmInventoryRecords -Records ([object[]]$internalEntries.ToArray()) -Key path)
    )
    $noteVersions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $noteRoles = [System.Collections.Generic.List[object]]::new()
    $contentInspected = $false
    if ($loadedSources.Count -gt 0) {
        foreach ($entry in $internalEntries) {
            if ([string]$entry.kind -cne 'markdown' -or
                $loadedGuidanceVersions.ContainsKey([string]$entry.path) -or
                $selectedGuidanceSet.Contains([string]$entry.path)) { continue }
            $contentInspected = $true
            $read = Read-DmVaultTargetBytes -Boundary $preflight.boundary -Resolution $entry.resolution
            if (-not $read.ok) {
                $code = if ([string]$read.code -cin @('PATH_INVALID', 'PATH_OUTSIDE_VAULT', 'READ_FAILED', 'TARGET_CONFLICT')) {
                    [string]$read.code
                }
                else { 'READ_FAILED' }
                $result = New-DmInventoryBlock -Operation $operation -Code $code `
                    -Message 'An eligible Markdown note could not be inspected safely; no report was returned.' `
                    -RemainingWork @('Restore stable, readable vault access, then retry.') -Details $null
                return (New-DmInventoryOutcome -Result $result)
            }
            try { $noteText = [System.Text.UTF8Encoding]::new($false, $true).GetString([byte[]]$read.bytes) }
            catch {
                $result = New-DmInventoryBlock -Operation $operation -Code 'READ_FAILED' `
                    -Message 'An eligible Markdown note was not valid readable UTF-8; no report was returned.' `
                    -RemainingWork @('Restore readable Markdown content, then retry.') -Details $null
                return (New-DmInventoryOutcome -Result $result)
            }
            $noteVersions[[string]$entry.path] = [string]$read.version
            foreach ($label in Get-DmInventoryNoteRoleLabels -Text $noteText) {
                $noteRoles.Add([pscustomobject]@{
                    path = [string]$entry.path
                    role = [string]$label.role
                    basis = [string]$label.basis
                    source = [string]$entry.path
                    sourceVersion = [string]$read.version
                })
            }
        }
    }

    $selectedLoadedPaths = [string[]]$selectedLoaded.ToArray()
    $dependencyCheck = Test-DmInventoryDependencies -Boundary $preflight.boundary -Profile $context.profile `
        -ReviewedVersions ([object[]]$context.dependencyVersions) -GuidancePaths ([string[]]$guidancePaths.ToArray()) `
        -SelectedGuidancePaths $selectedLoadedPaths
    if (-not $dependencyCheck.passed) {
        $result = New-DmInventoryBlock -Operation $operation -Code 'TARGET_CONFLICT' `
            -Message 'The profile or loaded guidance changed after validation; no inventory report was returned.' `
            -RemainingWork @('Revalidate the profile and local guidance, then retry.') `
            -Details ([ordered]@{ changedDependencies = [string[]]$dependencyCheck.changedIdentities })
        return (New-DmInventoryOutcome -Result $result)
    }

    foreach ($entry in $internalEntries) {
        if (-not $noteVersions.ContainsKey([string]$entry.path)) { continue }
        $recheck = Read-DmVaultTargetBytes -Boundary $preflight.boundary -Resolution $entry.resolution
        if (-not $recheck.ok -or [string]$recheck.version -cne $noteVersions[[string]$entry.path]) {
            $result = New-DmInventoryBlock -Operation $operation -Code 'TARGET_CONFLICT' `
                -Message 'A note inspected for inventory evidence changed before report completion; no report was returned.' `
                -RemainingWork @('Revalidate the notes and local guidance, then retry.') -Details $null
            return (New-DmInventoryOutcome -Result $result)
        }
    }

    $mappings = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $entryKinds = [System.Collections.Generic.Dictionary[string, string]]::new($pathComparer)
    foreach ($entry in $internalEntries) { $entryKinds[[string]$entry.path] = [string]$entry.kind }
    $profileVersion = if ($null -ne $context.context -and $context.context.PSObject.Properties['profileVersion']) {
        [string]$context.context.profileVersion
    }
    else { 'absent' }
    foreach ($assignment in Get-DmInventoryProfileAssignments -Profile $context.sourceProfile) {
        $pathCheck = Test-DmVaultRelativePath -Path ([string]$assignment.path)
        if (-not $pathCheck.isValid -or (Test-DmInventoryHasDotComponent -Path ([string]$assignment.path))) { continue }
        $kind = if ($entryKinds.ContainsKey([string]$assignment.path)) { $entryKinds[[string]$assignment.path] } else { 'unknown' }
        Add-DmInventoryMapping -Mappings $mappings -Role ([string]$assignment.role) -Path ([string]$assignment.path) -Kind $kind `
            -Classification observed -Basis ([string]$assignment.basis) -Source ([string]$assignment.source) `
            -Summary ([string]$assignment.summary) -Uncertainty $null -SourceVersion $profileVersion
    }
    foreach ($assignment in Get-DmInventoryGuidanceAssignments -LoadedSources ([object[]]$loadedSources.ToArray()) -GuidanceTexts $guidanceTexts) {
        $pathCheck = Test-DmVaultRelativePath -Path ([string]$assignment.path)
        if (-not $pathCheck.isValid -or (Test-DmInventoryHasDotComponent -Path ([string]$assignment.path))) { continue }
        $kind = if ($entryKinds.ContainsKey([string]$assignment.path)) { $entryKinds[[string]$assignment.path] } else { 'unknown' }
        Add-DmInventoryMapping -Mappings $mappings -Role ([string]$assignment.role) -Path ([string]$assignment.path) -Kind $kind `
            -Classification observed -Basis ([string]$assignment.basis) -Source ([string]$assignment.source) `
            -Summary ([string]$assignment.summary) -Uncertainty $null `
            -SourceVersion ([string]$loadedGuidanceVersions[[string]$assignment.source])
    }
    Add-DmInventoryConventionalMappings -Entries ([object[]]$internalEntries.ToArray()) -Mappings $mappings
    Get-DmInventoryTokenMappings -Entries ([object[]]$internalEntries.ToArray()) -Mappings $mappings
    foreach ($label in $noteRoles) {
        Add-DmInventoryMapping -Mappings $mappings -Role ([string]$label.role) -Path ([string]$label.path) -Kind markdown `
            -Classification inferred -Basis ([string]$label.basis) -Source ([string]$label.source) `
            -Summary 'Permitted Markdown content explicitly labels or self-identifies this role.' `
            -Uncertainty 'Note-content evidence is provisional and may not establish the intended campaign role.' `
            -SourceVersion ([string]$label.sourceVersion)
    }
    $publicMappings = [object[]](ConvertTo-DmInventoryPublicMappings -Mappings $mappings)
    $decisionArray = @()
    if ($arguments.Contains('mappingDecisions')) { $decisionArray = @($arguments.mappingDecisions) }
    $ambiguities = [object[]](Get-DmInventoryAmbiguities -Mappings $mappings -CanonicalRoot ([string]$preflight.boundary.canonicalRoot) `
        -ProposalRequested ([bool]$arguments.proposeProfile) -Decisions ([object[]]$decisionArray))
    $ambiguitySort = [System.Comparison[object]]{
        param($left, $right)
        $comparison = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$left.subject, [string]$right.subject)
        if ($comparison -ne 0) { return $comparison }
        $comparison = [System.StringComparer]::Ordinal.Compare([string]$left.subject, [string]$right.subject)
        if ($comparison -ne 0) { return $comparison }
        [System.StringComparer]::Ordinal.Compare([string]$left.ambiguityId, [string]$right.ambiguityId)
    }
    $ambiguityList = [System.Collections.Generic.List[object]]::new()
    foreach ($ambiguity in $ambiguities) { $ambiguityList.Add($ambiguity) }
    $ambiguityList.Sort($ambiguitySort)
    $decisionIssues = [System.Collections.Generic.List[object]]::new()
    for ($decisionIndex = 0; $decisionIndex -lt $decisionArray.Count; $decisionIndex++) {
        $decision = $decisionArray[$decisionIndex]
        $currentAmbiguity = @($ambiguityList | Where-Object {
                [string]$_.ambiguityId -ceq [string]$decision.ambiguityId
            })
        $currentAlternative = if ($currentAmbiguity.Count -eq 1) {
            @($currentAmbiguity[0].alternatives | Where-Object {
                    [string]$_.alternativeId -ceq [string]$decision.alternativeId
                })
        }
        else { @() }
        if (@($currentAmbiguity).Count -ne 1 -or @($currentAlternative).Count -ne 1) {
            $decisionIssues.Add([pscustomobject][ordered]@{
                decisionIndex = $decisionIndex
                reason = 'stale-or-unknown'
            })
        }
    }
    $publicEntries = [object[]]@($internalEntries | ForEach-Object {
        [pscustomobject][ordered]@{ path = [string]$_.path; kind = [string]$_.kind }
    })

    $report = [pscustomobject][ordered]@{
        schemaVersion = 1
        operation = 'vault.orientation.inventory'
        scan = [pscustomobject][ordered]@{
            contentInspected = $contentInspected
            dotPrefixedEntriesExcluded = $true
            nonMarkdownEntriesExcluded = $true
            nonDotMarkdownIncludedRegardlessOfOsAttributes = $true
            nonMarkdownContentsRead = $false
            attachmentContentsRead = $false
        }
        guidance = [pscustomobject][ordered]@{
            loadedSources = [object[]]$loadedSources.ToArray()
            skippedOptionalSources = [object[]]$skipped.ToArray()
            configuredOrDefaultLoaded = $configuredOrDefaultLoaded
            requestSelectedLoaded = $selectedLoadedPaths
            contentInspectionBasis = if ($loadedSources.Count -gt 0) { 'guidance_loaded' } else { 'names_only' }
        }
        entries = $publicEntries
        candidateMappings = $publicMappings
        ambiguities = [object[]]$ambiguityList.ToArray()
        profileProposal = $null
    }
    $result = New-DmEntryPointResult -Operation $operation -State Complete -CompletionCode 'OK' -Targets @()
    if ([bool]$arguments.proposeProfile) {
        $unresolvedProposalChoice = @($report.ambiguities | Where-Object { $_.requiresDmDecision }).Count -gt 0
        $staleProposalChoice = $decisionIssues.Count -gt 0
        $proposalBase = if ($null -ne $context.profile) {
            $context.profile
        }
        else {
            Resolve-DmProfileDefaults -Profile ([ordered]@{})
        }
        $proposalMappings = if ($unresolvedProposalChoice -or $staleProposalChoice) {
            [object[]]@()
        }
        else {
            $publicMappings
        }
        $proposal = New-DmInventoryProfileProposal -Boundary $preflight.boundary -BaseProfile $proposalBase `
            -ProfileVersion $profileVersion -Mappings $proposalMappings -Entries $publicEntries `
            -Ambiguities ([object[]]$ambiguityList.ToArray())
        if (-not $proposal.passed) {
            $code = if ([string]$proposal.code -cin @('TARGET_CONFLICT', 'PREREQUISITE_MISSING', 'PROFILE_PARSE_INVALID', 'PROFILE_NORMALIZATION_INVALID', 'PROFILE_SCHEMA_INVALID')) {
                [string]$proposal.code
            }
            else { 'OPERATION_FAILED' }
            $result = New-DmInventoryBlock -Operation $operation -Code $code `
                -Message ([string]$proposal.message) `
                -RemainingWork @('Resolve the profile preservation or validation limitation, then retry.') -Details $null
            return (New-DmInventoryOutcome -Result $result)
        }
        $report.profileProposal = [pscustomobject][ordered]@{
            status = 'drafted-unapproved'
            content = if ($unresolvedProposalChoice -or $staleProposalChoice) { $null } else { [string]$proposal.content }
            evidence = [object[]]$publicMappings
            differences = if ($unresolvedProposalChoice -or $staleProposalChoice) { $null } else { [string]$proposal.differences }
            decisionIssues = [object[]]$decisionIssues.ToArray()
        }
        $postProposalDependencyCheck = Test-DmInventoryDependencies -Boundary $preflight.boundary -Profile $context.profile `
            -ReviewedVersions ([object[]]$context.dependencyVersions) -GuidancePaths ([string[]]$guidancePaths.ToArray()) `
            -SelectedGuidancePaths $selectedLoadedPaths
        if (-not $postProposalDependencyCheck.passed) {
            $result = New-DmInventoryBlock -Operation $operation -Code 'TARGET_CONFLICT' `
                -Message 'The profile or loaded guidance changed while preparing the proposal; no report was returned.' `
                -RemainingWork @('Revalidate the profile and local guidance, then retry.') -Details $null
            return (New-DmInventoryOutcome -Result $result)
        }
        foreach ($entry in $internalEntries) {
            $entryPath = [string]$entry.path
            if (-not $noteVersions.ContainsKey($entryPath)) { continue }
            $recheck = Read-DmVaultTargetBytes -Boundary $preflight.boundary -Resolution $entry.resolution
            if (-not $recheck.ok -or [string]$recheck.version -cne $noteVersions[$entryPath]) {
                $result = New-DmInventoryBlock -Operation $operation -Code 'TARGET_CONFLICT' `
                    -Message 'A note inspected for proposal evidence changed before report completion; no report was returned.' `
                    -RemainingWork @('Revalidate the notes and local guidance, then retry.') -Details $null
                return (New-DmInventoryOutcome -Result $result)
            }
        }
        if ($unresolvedProposalChoice -or $staleProposalChoice) {
            $result = New-DmInventoryBlock -Operation $operation -Code 'AMBIGUOUS_CONTEXT' `
                -Message 'A profile proposal depends on unresolved, stale, or unknown mapping choices; no proposal content was generated.' `
                -RemainingWork @('Review the current alternatives and provide fresh DM direction, then retry.') -Details $null
        }
    }
    New-DmInventoryOutcome -Result $result -InventoryReport $report
}

Export-ModuleMember -Function Invoke-DmInventory
