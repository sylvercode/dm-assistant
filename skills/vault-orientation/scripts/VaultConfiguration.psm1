Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultBoundary.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PluginResources.psm1')

function ConvertTo-DmProfileNormalizedValue {
    <#
    .SYNOPSIS
    Recursively normalizes profile mapping values under version-one rules.
    .DESCRIPTION
    Scalar values use invariant representations; nulls and collections in
    scalar positions are rejected, and the root version value is preserved.
    .PARAMETER Value
    Parsed YAML mapping or scalar to normalize.
    .PARAMETER PropertyName
    Name of the current property, used to identify the profile version.
    .PARAMETER ParentPath
    Current profile property path used for normalization error context.
    #>
    param(
        [AllowNull()]$Value,
        [string]$PropertyName = '',
        [string]$ParentPath = '$'
    )

    if ($Value -is [System.Collections.IDictionary]) {
        $normalized = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $child = [string]$key
            $normalized[$child] = ConvertTo-DmProfileNormalizedValue -Value $Value[$key] -PropertyName $child -ParentPath "$ParentPath.$child"
        }
        return $normalized
    }

    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        throw "Collections are not valid profile scalar values at $ParentPath."
    }

    if ($null -eq $Value) {
        throw "Null is not a valid profile scalar value at $ParentPath."
    }

    if ($PropertyName -ceq 'version' -and $ParentPath -ceq '$.version') {
        return $Value
    }

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) {
        return $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { throw "Empty profile text is not valid at $ParentPath." }
        return $Value
    }
    if ($Value -is [IFormattable]) {
        return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    throw "Unsupported profile scalar at $ParentPath."
}

function ConvertFrom-DmVaultProfileYaml {
    <#
    .SYNOPSIS
    Parses exactly one YAML profile mapping and normalizes its values.
    .DESCRIPTION
    Malformed, duplicate-key, multi-document, or unsupported YAML is rejected;
    normalization failures return a separate stable code.
    .PARAMETER Yaml
    Complete YAML profile text to parse as data.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Yaml)

    try {
        Import-Module powershell-yaml -RequiredVersion 0.4.12 -ErrorAction Stop
        $documents = @(ConvertFrom-Yaml -Yaml $Yaml -AllDocuments -Ordered -ErrorAction Stop)
        if ($documents.Count -ne 1) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_PARSE_INVALID'; profile = $null; message = 'The profile must contain exactly one YAML document.' }
        }
        $parsed = $documents[0]
        if ($null -eq $parsed -or $parsed -isnot [System.Collections.IDictionary]) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_PARSE_INVALID'; profile = $null; message = 'The profile must be one YAML mapping.' }
        }
    }
    catch {
        return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_PARSE_INVALID'; profile = $null; message = 'The profile contains malformed YAML, duplicate keys, or unsupported syntax.' }
    }

    try {
        $normalized = ConvertTo-DmProfileNormalizedValue -Value $parsed
    }
    catch {
        return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_NORMALIZATION_INVALID'; profile = $null; message = 'A profile value cannot be normalized under the version 1 rules.' }
    }

    [pscustomobject][ordered]@{ passed = $true; code = $null; profile = $normalized; message = '' }
}

function Test-DmProfileSchema {
    <#
    .SYNOPSIS
    Validates a normalized profile against the Draft 2020-12 schema.
    .PARAMETER Profile
    Normalized profile dictionary to validate without applying defaults.
    .PARAMETER SchemaText
    Optional schema text; omitted or empty loads the installed skill resource.
    .PARAMETER PowerShellVersion
    Runtime version to check for validator availability; defaults to the current version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [string]$SchemaText,
        [version]$PowerShellVersion = [version]$PSVersionTable.PSVersion
    )

    if ($PowerShellVersion -lt [version]'7.4') {
        return [pscustomobject][ordered]@{ passed = $false; code = 'PREREQUISITE_MISSING'; message = 'PowerShell 7.4 or later is required for Draft 2020-12 schema validation.' }
    }

    if ([string]::IsNullOrWhiteSpace($SchemaText)) {
        $resource = Get-DmProfileSchemaResource -Operation 'profile.validate'
        if (-not $resource.passed) {
            return [pscustomobject][ordered]@{ passed = $false; code = [string]$resource.result.completionCode; message = 'The installed profile schema is unavailable or incompatible.' }
        }
        $SchemaText = [string]$resource.resource.schemaText
    }

    try {
        $json = ConvertTo-Json -InputObject $Profile -Depth 100 -Compress -ErrorAction Stop
        $valid = Test-Json -Json $json -Schema $SchemaText -ErrorAction Stop
        if (-not $valid) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_SCHEMA_INVALID'; message = 'The normalized profile does not match the supported profile schema.' }
        }
    }
    catch {
        if ($_.Exception.Message -match 'not valid with the schema') {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_SCHEMA_INVALID'; message = 'The normalized profile does not match the supported profile schema.' }
        }
        return [pscustomobject][ordered]@{ passed = $false; code = 'PREREQUISITE_MISSING'; message = 'Draft 2020-12 profile validation is unavailable in this PowerShell runtime.' }
    }
    [pscustomobject][ordered]@{ passed = $true; code = $null; message = '' }
}

function Resolve-DmProfileDefaults {
    <#
    .SYNOPSIS
    Produces an effective profile with the version-one contract defaults.
    .DESCRIPTION
    Apply only after successful schema validation; the source mapping is not
    intentionally mutated.
    .PARAMETER Profile
    Validated normalized profile dictionary.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Profile)

    $result = [ordered]@{}
    foreach ($key in $Profile.Keys) {
        $value = $Profile[$key]
        if ($value -is [System.Collections.IDictionary]) {
            $nested = [ordered]@{}
            foreach ($nestedKey in $value.Keys) {
                $nestedValue = $value[$nestedKey]
                if ($nestedValue -is [System.Collections.IDictionary]) {
                    $nestedNested = [ordered]@{}
                    foreach ($leafKey in $nestedValue.Keys) { $nestedNested[[string]$leafKey] = $nestedValue[$leafKey] }
                    $nested[[string]$nestedKey] = $nestedNested
                }
                else { $nested[[string]$nestedKey] = $nestedValue }
            }
            $result[[string]$key] = $nested
        }
        else { $result[[string]$key] = $value }
    }

    if (-not $result.Contains('sections')) { $result.sections = [ordered]@{} }
    $sectionDefaults = [ordered]@{
        adventures = 'Adventures'
        lore = 'Lore'
        monsters_stats = 'Monsters Stats'
        rules = 'Rules'
        sessions = 'Sessions'
        handouts = 'Handouts'
    }
    foreach ($key in $sectionDefaults.Keys) {
        if (-not $result.sections.Contains($key)) { $result.sections[$key] = $sectionDefaults[$key] }
    }
    if (-not $result.sections.Contains('custom')) { $result.sections.custom = [ordered]@{} }

    if (-not $result.Contains('preparation')) {
        $result.preparation = [ordered]@{ mode = 'session_section'; heading = 'Preparation' }
    }
    elseif ($result.preparation.mode -ceq 'session_section' -and -not $result.preparation.Contains('heading')) {
        $result.preparation.heading = 'Preparation'
    }

    if (-not $result.Contains('templates')) { $result.templates = [ordered]@{} }
    if (-not $result.templates.Contains('custom')) { $result.templates.custom = [ordered]@{} }
    $result
}

function Read-DmVaultProfile {
    <#
    .SYNOPSIS
    Reads, parses, validates, and defaults the vault-root profile if present.
    .DESCRIPTION
    Returns an absent, valid, or invalid state and the source byte version;
    invalid profiles do not fall back to discovery.
    .PARAMETER Boundary
    Canonical authorized vault boundary for profile resolution and access.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Boundary)

    $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path '.dmassist.yaml'
    if ($resolution.status -ceq 'missing') {
        return [pscustomobject][ordered]@{ state = 'absent'; code = $null; profile = $null; sourceProfile = $null; sourceVersion = 'absent'; message = '' }
    }
    if ($resolution.status -cne 'resolved' -or $resolution.itemType -cne 'file') {
        return [pscustomobject][ordered]@{ state = 'invalid'; code = 'PROFILE_FILESYSTEM_INVALID'; profile = $null; sourceProfile = $null; sourceVersion = $null; message = 'The root profile path is not a readable file.' }
    }
    $read = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $resolution
    if (-not $read.ok) {
        return [pscustomobject][ordered]@{ state = 'invalid'; code = 'READ_FAILED'; profile = $null; sourceProfile = $null; sourceVersion = $null; message = 'The root profile could not be read.' }
    }
    try { $yaml = [System.Text.UTF8Encoding]::new($false, $true).GetString([byte[]]$read.bytes) }
    catch { return [pscustomobject][ordered]@{ state = 'invalid'; code = 'PROFILE_PARSE_INVALID'; profile = $null; sourceProfile = $null; sourceVersion = $read.version; message = 'The profile is not valid UTF-8 YAML.' } }
    $parsed = ConvertFrom-DmVaultProfileYaml -Yaml $yaml
    if (-not $parsed.passed) {
        return [pscustomobject][ordered]@{ state = 'invalid'; code = $parsed.code; profile = $null; sourceProfile = $null; sourceVersion = $read.version; message = $parsed.message }
    }
    $schema = Test-DmProfileSchema -Profile $parsed.profile
    if (-not $schema.passed) {
        return [pscustomobject][ordered]@{ state = 'invalid'; code = $schema.code; profile = $null; sourceProfile = $parsed.profile; sourceVersion = $read.version; message = $schema.message }
    }
    $effective = Resolve-DmProfileDefaults -Profile $parsed.profile
    [pscustomobject][ordered]@{ state = 'valid'; code = $null; profile = $effective; sourceProfile = $parsed.profile; sourceVersion = $read.version; message = '' }
}

function Get-DmConfiguredDirectoryPaths {
    <#
    .SYNOPSIS
    Lists explicitly configured section and separate-preparation directories.
    .PARAMETER Profile
    Profile dictionary containing the configured paths to collect.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Profile)
    $paths = [System.Collections.Generic.List[string]]::new()
    if ($Profile.Contains('sections')) {
        $sections = $Profile.sections
        foreach ($name in @('adventures', 'lore', 'monsters_stats', 'rules', 'sessions', 'handouts')) {
            if ($sections.Contains($name)) { $paths.Add([string]$sections[$name]) }
        }
        if ($sections.Contains('custom')) {
            foreach ($item in $sections.custom.Values) { $paths.Add([string]$item.path) }
        }
    }
    if ($Profile.Contains('preparation') -and $Profile.preparation.mode -ceq 'separate_folder') {
        $paths.Add([string]$Profile.preparation.path)
    }
    , [string[]]$paths.ToArray()
}

function Get-DmConfiguredReferencePaths {
    <#
    .SYNOPSIS
    Lists configured guidance, party, and template reference paths.
    .PARAMETER Profile
    Profile dictionary containing the references to collect.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Profile)
    $paths = [System.Collections.Generic.List[string]]::new()
    if ($Profile.Contains('guidance')) { $paths.Add([string]$Profile.guidance.path) }
    if ($Profile.Contains('party')) { $paths.Add([string]$Profile.party.note) }
    if ($Profile.Contains('templates')) {
        foreach ($key in $Profile.templates.Keys) {
            if ($key -ceq 'custom') {
                foreach ($path in $Profile.templates.custom.Values) { $paths.Add([string]$path) }
            }
            else { $paths.Add([string]$Profile.templates[$key]) }
        }
    }
    , [string[]]$paths.ToArray()
}

function Test-DmProfileFilesystem {
    <#
    .SYNOPSIS
    Validates configured directory containment and reference path syntax.
    .DESCRIPTION
    Explicit section directories must already exist inside the vault. Reference
    existence and readability are checked separately when needed.
    .PARAMETER Boundary
    Canonical authorized vault boundary.
    .PARAMETER Profile
    Validated source profile with its explicitly configured paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile
    )
    foreach ($path in (Get-DmConfiguredDirectoryPaths -Profile $Profile)) {
        $lexical = Test-DmVaultRelativePath -Path $path
        if (-not $lexical.isValid) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PATH_INVALID'; message = 'A configured profile path is not a valid vault-relative path.'; path = $path }
        }
        $resolved = Resolve-DmVaultTarget -Boundary $Boundary -Path $path
        if ($resolved.code -ceq 'PATH_OUTSIDE_VAULT' -or $resolved.status -ceq 'missing' -or $resolved.status -ceq 'resolved' -and $resolved.itemType -cne 'directory') {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_FILESYSTEM_INVALID'; message = 'A configured section folder is missing, invalid, or outside the vault.'; path = $path }
        }
        if ($resolved.code) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PROFILE_FILESYSTEM_INVALID'; message = 'A configured section folder could not be safely checked.'; path = $path }
        }
    }
    foreach ($path in (Get-DmConfiguredReferencePaths -Profile $Profile)) {
        $lexical = Test-DmVaultRelativePath -Path $path
        if (-not $lexical.isValid) {
            return [pscustomobject][ordered]@{ passed = $false; code = 'PATH_INVALID'; message = 'A configured profile reference is not a valid vault-relative path.'; path = $path }
        }
    }
    [pscustomobject][ordered]@{ passed = $true; code = $null; message = ''; path = $null }
}

function Resolve-DmProfileTemplate {
    <#
    .SYNOPSIS
    Finds the configured template path for an article type without fallback.
    .PARAMETER Profile
    Validated profile containing optional template mappings.
    .PARAMETER ArticleType
    Built-in or custom template identifier to look up.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][string]$ArticleType
    )
    $path = $null
    if ($Profile.Contains('templates')) {
        if ($Profile.templates.Contains($ArticleType)) { $path = [string]$Profile.templates[$ArticleType] }
        elseif ($Profile.templates.Contains('custom') -and $Profile.templates.custom.Contains($ArticleType)) { $path = [string]$Profile.templates.custom[$ArticleType] }
    }
    [pscustomobject][ordered]@{
        available = -not [string]::IsNullOrEmpty($path)
        path = $path
        message = $(if ([string]::IsNullOrEmpty($path)) { 'No template is configured; ask the DM which template to use.' } else { '' })
    }
}

function Resolve-DmSectionDestination {
    <#
    .SYNOPSIS
    Finds the unique configured section containing a note path.
    .DESCRIPTION
    No matches or multiple shared/nested matches return AMBIGUOUS_CONTEXT.
    .PARAMETER Profile
    Validated profile containing section mappings.
    .PARAMETER NotePath
    Vault-relative note path to classify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][string]$NotePath
    )
    $matches = [System.Collections.Generic.List[string]]::new()
    if ($Profile.Contains('sections')) {
        foreach ($name in @('adventures', 'lore', 'monsters_stats', 'rules', 'sessions', 'handouts')) {
            if ($Profile.sections.Contains($name)) {
                $prefix = ([string]$Profile.sections[$name]).TrimEnd('/')
                if ($NotePath -ceq $prefix -or $NotePath.StartsWith($prefix + '/', [System.StringComparison]::Ordinal)) { $matches.Add($name) }
            }
        }
        if ($Profile.sections.Contains('custom')) {
            foreach ($name in $Profile.sections.custom.Keys) {
                $prefix = ([string]$Profile.sections.custom[$name].path).TrimEnd('/')
                if ($NotePath -ceq $prefix -or $NotePath.StartsWith($prefix + '/', [System.StringComparison]::Ordinal)) { $matches.Add([string]$name) }
            }
        }
    }
    if ($matches.Count -ne 1) {
        return [pscustomobject][ordered]@{ resolved = $false; code = 'AMBIGUOUS_CONTEXT'; sections = [string[]]$matches.ToArray() }
    }
    [pscustomobject][ordered]@{ resolved = $true; code = $null; sections = [string[]]$matches.ToArray() }
}

function Test-DmProfileReference {
    <#
    .SYNOPSIS
    Checks that a configured reference resolves to a readable in-vault file.
    .PARAMETER Boundary
    Canonical authorized vault boundary.
    .PARAMETER Path
    Vault-relative path of the required configured reference.
    .PARAMETER Kind
    Reference category: guidance, template, party, or preparation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('guidance', 'template', 'party', 'preparation')][string]$Kind
    )
    $lexical = Test-DmVaultRelativePath -Path $Path
    if (-not $lexical.isValid) { return [pscustomobject][ordered]@{ passed = $false; code = 'PATH_INVALID'; message = 'The configured reference path is invalid.' } }
    $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path $Path
    if ($resolution.code) {
        return [pscustomobject][ordered]@{ passed = $false; code = [string]$resolution.code; message = 'The configured reference could not be safely resolved.' }
    }
    if (-not $resolution.exists -or $resolution.itemType -cne 'file') {
        return [pscustomobject][ordered]@{ passed = $false; code = 'REFERENCE_UNAVAILABLE'; message = 'The configured reference is missing or is not a file.' }
    }
    $read = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $resolution
    if (-not $read.ok) {
        return [pscustomobject][ordered]@{ passed = $false; code = [string]$read.code; message = 'The configured reference could not be read.' }
    }
    [pscustomobject][ordered]@{ passed = $true; code = $null; message = ''; version = $read.version; path = $Path }
}

function Get-DmProfileDependencyVersions {
    <#
    .SYNOPSIS
    Collects ordered profile, schema, and configured-reference versions.
    .PARAMETER Boundary
    Canonical authorized vault boundary for profile and reference access.
    .PARAMETER Profile
    Validated profile whose referenced paths are fingerprinted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile
    )
    $versions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $profileResolution = Resolve-DmVaultTarget -Boundary $Boundary -Path '.dmassist.yaml'
    if ($profileResolution.exists) {
        $profileRead = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $profileResolution
        if (-not $profileRead.ok) { throw 'The profile changed or could not be read while computing dependency versions.' }
        $versions.Add('.dmassist.yaml', $profileRead.version)
        $schema = Get-DmProfileSchemaResource -Operation 'profile.validate'
        if (-not $schema.passed) { throw 'The installed profile schema is unavailable or incompatible.' }
        $versions.Add([string]$schema.resource.identity, [string]$schema.resource.version)
    }
    $referencePaths = [System.Collections.Generic.List[string]]::new()
    if ($Profile.Contains('guidance')) { $referencePaths.Add([string]$Profile.guidance.path) }
    if ($Profile.Contains('party')) { $referencePaths.Add([string]$Profile.party.note) }
    if ($Profile.Contains('templates')) {
        foreach ($key in $Profile.templates.Keys) {
            if ($key -ceq 'custom') { foreach ($value in $Profile.templates.custom.Values) { $referencePaths.Add([string]$value) } }
            else { $referencePaths.Add([string]$Profile.templates[$key]) }
        }
    }
    foreach ($path in $referencePaths) {
        $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path $path
        if (-not $resolution.exists -or $resolution.itemType -cne 'file') { $version = 'absent' }
        else {
            $read = Read-DmVaultTargetBytes -Boundary $Boundary -Resolution $resolution
            if (-not $read.ok) { throw "The reference '$path' changed or could not be read while computing dependency versions." }
            $version = $read.version
        }
        $versions[$path] = $version
    }
    $identities = [string[]]@($versions.Keys)
    [System.Array]::Sort($identities, [System.StringComparer]::Ordinal)
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($identity in $identities) {
        $entries.Add([pscustomobject][ordered]@{ identity = $identity; version = $versions[$identity] })
    }
    , [object[]]$entries.ToArray()
}

function Test-DmProfileDependencyVersions {
    <#
    .SYNOPSIS
    Detects changes to the previously reviewed profile dependency snapshot.
    .PARAMETER Boundary
    Canonical authorized vault boundary for the current version checks.
    .PARAMETER Profile
    Validated profile whose dependencies should be rechecked.
    .PARAMETER ReviewedVersions
    Ordered previously observed dependency identity and version records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Boundary,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][object[]]$ReviewedVersions
    )
    try { $current = Get-DmProfileDependencyVersions -Boundary $Boundary -Profile $Profile }
    catch {
        return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changedIdentities = @(); message = 'A profile dependency changed or became unavailable; revalidate before continuing.' }
    }
    if ($current.Count -ne $ReviewedVersions.Count) {
        return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changedIdentities = @('dependency-set'); message = 'The profile dependency set changed; revalidate before continuing.' }
    }
    $changed = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $current.Count; $i++) {
        if ($current[$i].identity -cne $ReviewedVersions[$i].identity -or $current[$i].version -cne $ReviewedVersions[$i].version) {
            $changed.Add([string]$current[$i].identity)
        }
    }
    if ($changed.Count -gt 0) {
        return [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT'; changedIdentities = [string[]]$changed.ToArray(); message = 'A profile or reference changed; revalidate before continuing.' }
    }
    [pscustomobject][ordered]@{ passed = $true; code = $null; changedIdentities = @(); message = '' }
}

function Get-DmVaultDiscovery {
    <#
    .SYNOPSIS
    Reports conventional directory candidates without changing the vault.
    .PARAMETER Boundary
    Canonical authorized vault boundary in which to inspect candidate directories.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Boundary)
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('Adventures', 'Lore', 'Monsters Stats', 'Rules', 'Sessions', 'Handouts')) {
        $resolution = Resolve-DmVaultTarget -Boundary $Boundary -Path $name
        if ($resolution.exists -and $resolution.itemType -ceq 'directory') {
            $candidates.Add([pscustomobject][ordered]@{ section = $name; path = $name; state = 'inferred'; reason = 'Conventional directory exists.' })
        }
        else {
            $candidates.Add([pscustomobject][ordered]@{ section = $name; path = $null; state = 'missing'; reason = 'No conventional directory was found.' })
        }
    }
    [pscustomobject][ordered]@{ changed = $false; candidates = $candidates.ToArray() }
}

function Get-DmPreNoteContext {
    <#
    .SYNOPSIS
    Establishes shared guidance, profile, and context after successful preflight.
    .DESCRIPTION
    Missing designated local guidance or an ambiguous mapping blocks dependent
    work; absent guidance permits only a specific mapping-independent inspection.
    .PARAMETER Preflight
    Successful preflight outcome containing the request and vault boundary.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Preflight)

    if (-not $Preflight.passed) {
        return [pscustomobject][ordered]@{ passed = $false; result = $Preflight.result; profile = $null; discovery = $null; dependencyVersions = @(); context = $null }
    }

    $ownerRoot = Split-Path -Parent $PSScriptRoot
    $sharedReferencePath = Join-Path -Path $ownerRoot -ChildPath 'VAULT-REFERENCE.md'
    try { $sharedText = [System.IO.File]::ReadAllText($sharedReferencePath, [System.Text.Encoding]::UTF8) }
    catch {
        $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode 'RESOURCE_MISSING' -Targets $Preflight.targets -Message 'The installed shared reference is unavailable.' -RemainingWork @('Repair the plugin installation, then retry.')
        return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $null; discovery = $null; dependencyVersions = @(); context = $null }
    }
    if ([string]::IsNullOrWhiteSpace($sharedText)) {
        $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode 'RESOURCE_INCOMPATIBLE' -Targets $Preflight.targets -Message 'The installed shared reference is empty.' -RemainingWork @('Repair the plugin installation, then retry.')
        return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $null; discovery = $null; dependencyVersions = @(); context = $null }
    }

    $loaded = Read-DmVaultProfile -Boundary $Preflight.boundary
    if ($loaded.state -ceq 'invalid') {
        $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode $loaded.code -Targets $Preflight.targets -Message $loaded.message -RemainingWork @('Correct or restore the profile, then retry.')
        return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $null; discovery = $null; dependencyVersions = @(); context = $null }
    }
    if ($loaded.state -ceq 'absent') {
        $discovery = Get-DmVaultDiscovery -Boundary $Preflight.boundary
        $request = $Preflight.request
        $registration = Get-DmOperation -Name ([string]$request.operation)
        if ($request.mode -cne 'inspect' -or ($null -ne $registration -and $registration.requiresMappings)) {
            $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode 'AMBIGUOUS_CONTEXT' -Targets $Preflight.targets -Message 'No local guidance is designated; only a specific read-only inspect lookup may proceed.' -RemainingWork @('Designate local guidance or request a specific mapping-independent lookup.')
            return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $null; discovery = $discovery; dependencyVersions = @([pscustomobject][ordered]@{ identity = '.dmassist.yaml'; version = 'absent' }); context = $null }
        }
        return [pscustomobject][ordered]@{
            passed = $true; result = $null; profile = $null; discovery = $discovery
            dependencyVersions = @([pscustomobject][ordered]@{ identity = '.dmassist.yaml'; version = 'absent' })
            sequence = @('vault-root-selected', 'dependency-readiness', 'vault-authorization', 'shared-reference', 'profile-absence', 'guidance-absence', 'campaign-group')
            context = [pscustomobject]@{ sharedReferenceLoaded = $true; profileState = 'absent'; guidanceLoaded = $false; campaignGroup = $request.campaignGroup }
        }
    }

    $filesystem = Test-DmProfileFilesystem -Boundary $Preflight.boundary -Profile $loaded.sourceProfile
    if (-not $filesystem.passed) {
        $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode $filesystem.code -Targets $Preflight.targets -Message $filesystem.message -RemainingWork @('Correct the configured paths, then retry.') -Detail ([ordered]@{ target = $filesystem.path })
        return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $null; discovery = $null; dependencyVersions = @(); context = $null }
    }
    $guidanceLoaded = $false
    if ($loaded.profile.Contains('guidance')) {
        $guidance = Test-DmProfileReference -Boundary $Preflight.boundary -Path ([string]$loaded.profile.guidance.path) -Kind guidance
        if (-not $guidance.passed) {
            $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode $guidance.code -Targets $Preflight.targets -Message $guidance.message -RemainingWork @('Restore the configured guidance, then retry.')
            return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $null; discovery = $null; dependencyVersions = @(); context = $null }
        }
        $guidanceLoaded = $true
    }
    $dependencies = Get-DmProfileDependencyVersions -Boundary $Preflight.boundary -Profile $loaded.profile
    $request = $Preflight.request
    $registration = Get-DmOperation -Name ([string]$request.operation)
    $needsMapping = $request.mode -cne 'inspect' -or ($null -ne $registration -and $registration.requiresMappings)
    if (-not $guidanceLoaded -and $needsMapping) {
        $blocked = New-DmBlockedResult -Operation $Preflight.operation -CompletionCode 'AMBIGUOUS_CONTEXT' -Targets $Preflight.targets -Message 'No local guidance is designated; this request depends on unresolved note or folder mappings.' -RemainingWork @('Designate local guidance or request a specific mapping-independent lookup.')
        return [pscustomobject][ordered]@{ passed = $false; result = $blocked; profile = $loaded.profile; discovery = $null; dependencyVersions = $dependencies; context = $null }
    }
    [pscustomobject][ordered]@{
        passed = $true
        result = $null
        profile = $loaded.profile
        discovery = $null
        dependencyVersions = $dependencies
        sequence = @('vault-root-selected', 'dependency-readiness', 'vault-authorization', 'shared-reference', 'profile-validated', $(if ($guidanceLoaded) { 'guidance-loaded' } else { 'guidance-absence' }), 'campaign-group')
        context = [pscustomobject][ordered]@{
            sharedReferenceLoaded = $true
            profileState = 'valid'
            profileVersion = $loaded.sourceVersion
            guidanceLoaded = $guidanceLoaded
            campaignGroup = $request.campaignGroup
        }
    }
}

Export-ModuleMember -Function ConvertFrom-DmVaultProfileYaml, Test-DmProfileSchema, Resolve-DmProfileDefaults, Read-DmVaultProfile, Test-DmProfileFilesystem, Test-DmProfileReference, Resolve-DmProfileTemplate, Resolve-DmSectionDestination, Get-DmProfileDependencyVersions, Test-DmProfileDependencyVersions, Get-DmVaultDiscovery, Get-DmPreNoteContext
