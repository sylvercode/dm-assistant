Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')

# Installed owner-skill resource lookup (contract section 4). The profile
# schema is located only relative to this installed skill's own scripts
# folder; there is no repository-checkout, vault, or current-directory
# fallback and no second copy.

$script:DmSchemaResource = [pscustomobject][ordered]@{
    identity     = 'plugin:skills/vault-orientation/assets/dmassist.schema.json'
    resourcePath = 'skills/vault-orientation/assets/dmassist.schema.json'
    fileName     = 'dmassist.schema.json'
    dialect      = 'https://json-schema.org/draft/2020-12/schema'
    schemaId     = 'https://github.com/sylvercode/dm-assistant/skills/vault-orientation/assets/dmassist.schema.json'
    title        = 'DM Assistant Vault Configuration Profile, Version 1'
}

function Get-DmProfileSchemaPath {
    <#
    .SYNOPSIS
    Resolves the packaged profile schema relative to the owning skill.
    #>
    $skillRoot = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
    [System.IO.Path]::Join($skillRoot, 'assets', $script:DmSchemaResource.fileName)
}

function Test-DmProfileSchemaShape {
    <#
    .SYNOPSIS
    Checks the packaged schema's identity, dialect, and version-one shape.
    .DESCRIPTION
    Returns a safe reason string on mismatch, or an empty string on success.
    .PARAMETER Schema
    Parsed JSON schema dictionary to inspect.
    #>
    param($Schema)
    if ($Schema -isnot [System.Collections.IDictionary]) { return 'The schema is not a JSON object.' }
    if ($Schema['$schema'] -isnot [string] -or $Schema['$schema'] -cne $script:DmSchemaResource.dialect) { return 'The schema does not declare JSON Schema Draft 2020-12.' }
    if ($Schema['$id'] -isnot [string] -or $Schema['$id'] -cne $script:DmSchemaResource.schemaId) { return 'The schema identifier does not match the packaged profile schema.' }
    if ($Schema['title'] -isnot [string] -or $Schema['title'] -cne $script:DmSchemaResource.title) { return 'The schema title does not match profile version 1.' }
    if ($Schema['type'] -cne 'object' -or $Schema['additionalProperties'] -isnot [bool] -or $Schema['additionalProperties']) {
        return 'The schema does not describe a closed profile object.'
    }
    $required = @($Schema['required'])
    if ('version' -cnotin $required) { return 'The schema does not require the profile version.' }
    $properties = $Schema['properties']
    if ($properties -isnot [System.Collections.IDictionary] -or $properties['version'] -isnot [System.Collections.IDictionary]) { return 'The schema does not define the profile version.' }
    $version = $properties['version']
    $const = $version['const']
    $constIsOne = ($const -is [long] -or $const -is [int]) -and $const -eq 1
    if ($version['type'] -cne 'integer' -or -not $constIsOne) {
        return 'The schema does not pin profile version 1.'
    }
    ''
}

function Get-DmProfileSchemaResource {
    <#
    .SYNOPSIS
    Loads and validates the schema packaged with the owning skill.
    .DESCRIPTION
    Loads the packaged profile schema from the installed owner skill,
    independent of the current directory. Returns
    [pscustomobject]@{ gate = 'plugin-resource'; passed; result; evidence;
    resource } where resource is, when passed, [pscustomobject]@{ identity;
    resourcePath (plugin-relative); version ('sha256:<hex>' of the file
    bytes); schemaId; dialect; title; schemaText; fullPath (internal; never
    place it in a contract result) }. A missing or unreadable artifact blocks
    with RESOURCE_MISSING; malformed JSON, a dialect other than Draft 2020-12,
    or a schema that does not match the version 1 profile contract blocks
    with RESOURCE_INCOMPATIBLE; an unavailable Draft 2020-12 validator blocks
    with PREREQUISITE_MISSING.
    .PARAMETER Operation
    Operation identifier included if resource loading is blocked.
    .PARAMETER Targets
    Requested vault-relative targets to report as not attempted on failure.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Operation = '',
        [AllowEmptyCollection()][string[]]$Targets = @()
    )
    $gate = 'plugin-resource'
    $identity = $script:DmSchemaResource.identity
    $block = {
        param([string]$Code, [string]$State, [string]$Message, [string]$Work)
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode $Code -Targets $Targets -Message $Message -RemainingWork @($Work) `
            -Detail ([ordered]@{ resource = $script:DmSchemaResource.resourcePath; reason = $State })
        [pscustomobject][ordered]@{ gate = $gate; passed = $false; result = $result; evidence = @(New-DmEvidence -Gate $gate -Subject $identity -State $State); resource = $null }
    }
    $reinstall = 'Reinstall the plugin so its packaged profile schema is present and unmodified, then retry.'

    $path = Get-DmProfileSchemaPath
    try { $bytes = [System.IO.File]::ReadAllBytes($path) }
    catch { return (& $block 'RESOURCE_MISSING' 'missing' 'The packaged profile schema is missing or unreadable; no profile setting was used.' $reinstall) }
    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        $schema = $text | ConvertFrom-Json -AsHashtable -Depth 64 -ErrorAction Stop
    }
    catch { return (& $block 'RESOURCE_INCOMPATIBLE' 'malformed' 'The packaged profile schema is malformed; no profile setting was used.' $reinstall) }
    $reason = Test-DmProfileSchemaShape -Schema $schema
    if ($reason) { return (& $block 'RESOURCE_INCOMPATIBLE' 'incompatible' "The packaged profile schema is incompatible: $reason No profile setting was used." $reinstall) }

    $testJson = Get-Command -Name 'Test-Json' -CommandType Cmdlet -ErrorAction SilentlyContinue
    if ($null -eq $testJson -or -not $testJson.Parameters.ContainsKey('Schema')) {
        return (& $block 'PREREQUISITE_MISSING' 'validator-missing' 'The JSON Schema Draft 2020-12 validator is unavailable; no profile setting was used.' 'Use the supported PowerShell runtime documented in docs/powershell-runtime-support.md, then retry.')
    }
    try {
        $accepts = Test-Json -Json '{"version":1}' -Schema $text -ErrorAction SilentlyContinue
        $rejects = -not (Test-Json -Json '{"version":2}' -Schema $text -ErrorAction SilentlyContinue)
    }
    catch { $accepts = $false; $rejects = $false }
    if (-not ($accepts -and $rejects)) {
        return (& $block 'RESOURCE_INCOMPATIBLE' 'incompatible' 'The packaged profile schema cannot validate profile version 1 with the Draft 2020-12 validator; no profile setting was used.' $reinstall)
    }

    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $resource = [pscustomobject][ordered]@{
        identity     = $identity
        resourcePath = $script:DmSchemaResource.resourcePath
        version      = 'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
        schemaId     = $script:DmSchemaResource.schemaId
        dialect      = $script:DmSchemaResource.dialect
        title        = $script:DmSchemaResource.title
        schemaText   = $text
        fullPath     = $path
    }
    [pscustomobject][ordered]@{ gate = $gate; passed = $true; result = $null; evidence = @(New-DmEvidence -Gate $gate -Subject $identity -State 'loaded' -Detail $resource.version); resource = $resource }
}

$script:DmSharedReferenceResource = [pscustomobject][ordered]@{
    identity     = 'plugin:skills/vault-orientation/VAULT-REFERENCE.md'
    resourcePath = 'skills/vault-orientation/VAULT-REFERENCE.md'
    fileName     = 'VAULT-REFERENCE.md'
}

function Get-DmSharedReferencePath {
    <#
    .SYNOPSIS
    Resolves the shared reference relative to the owning skill.
    #>
    $skillRoot = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
    [System.IO.Path]::Join($skillRoot, $script:DmSharedReferenceResource.fileName)
}

function Get-DmSharedReferenceResource {
    <#
    .SYNOPSIS
    Loads and fingerprints the skill's packaged shared vault reference.
    .DESCRIPTION
    Loads the plugin-owned shared vault reference (contract section 3 step 3)
    from the installed owner skill, independent of the current directory and
    never from the vault. Returns [pscustomobject]@{ gate =
    'shared-reference'; passed; result; evidence; resource } where resource
    is, when passed, [pscustomobject]@{ identity; resourcePath; version
    ('sha256:<hex>' of the file bytes); text; fullPath (internal; never place
    it in a contract result) }. A missing or unreadable file blocks with
    RESOURCE_MISSING; text that is not strict UTF-8 blocks with
    RESOURCE_INCOMPATIBLE.
    .PARAMETER Operation
    Operation identifier included if the resource cannot be loaded.
    .PARAMETER Targets
    Requested vault-relative targets to report as not attempted on failure.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Operation = '',
        [AllowEmptyCollection()][string[]]$Targets = @()
    )
    $gate = 'shared-reference'
    $identity = $script:DmSharedReferenceResource.identity
    $block = {
        param([string]$Code, [string]$State, [string]$Message)
        $result = New-DmBlockedResult -Operation $Operation -CompletionCode $Code -Targets $Targets -Message $Message `
            -RemainingWork @('Reinstall the plugin so its shared vault reference is present and unmodified, then retry.') `
            -Detail ([ordered]@{ resource = $script:DmSharedReferenceResource.resourcePath; reason = $State })
        [pscustomobject][ordered]@{ gate = $gate; passed = $false; result = $result; evidence = @(New-DmEvidence -Gate $gate -Subject $identity -State $State); resource = $null }
    }
    $path = Get-DmSharedReferencePath
    try { $bytes = [System.IO.File]::ReadAllBytes($path) }
    catch { return (& $block 'RESOURCE_MISSING' 'missing' 'The plugin shared vault reference is missing or unreadable; no profile or campaign note was read.') }
    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    }
    catch { return (& $block 'RESOURCE_INCOMPATIBLE' 'malformed' 'The plugin shared vault reference is not valid UTF-8 text; no profile or campaign note was read.') }
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $resource = [pscustomobject][ordered]@{
        identity     = $identity
        resourcePath = $script:DmSharedReferenceResource.resourcePath
        version      = 'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
        text         = $text
        fullPath     = $path
    }
    [pscustomobject][ordered]@{ gate = $gate; passed = $true; result = $null; evidence = @(New-DmEvidence -Gate $gate -Subject $identity -State 'loaded' -Detail $resource.version); resource = $resource }
}

Export-ModuleMember -Function Get-DmProfileSchemaResource, Get-DmSharedReferenceResource
