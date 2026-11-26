[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('prepare', 'preview', 'apply')][string]$Action,
    [string]$RequestJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$readStandardInput = -not $PSBoundParameters.ContainsKey('RequestJson') -and [Console]::IsInputRedirected
$runtime = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'vault-orientation\scripts'
foreach ($module in 'RuntimeContract', 'VaultPathValidation', 'VaultBoundary', 'RuntimePreflight',
    'PluginResources', 'VaultConfiguration', 'ChangePreview', 'ApplyNoteChanges') {
    Import-Module (Join-Path $runtime "$module.psm1")
}

function New-ArticleBlock([string]$Code, [string]$Message) {
    $remainingWork = if ($Code -ceq 'TARGET_CONFLICT') {
        'Stop and ask the DM how to proceed; do not automatically retry. After direction, revalidate from prepare.'
    } else {
        'Address the blocker, then restart at prepare.'
    }
    @{
        result = New-DmBlockedResult -Operation $operation -CompletionCode $Code -Targets $targets `
            -Message $Message -RemainingWork @($remainingWork)
    }
}

function Get-ArticleHash([byte[]]$Bytes) {
    'sha256:' + [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertFrom-ArticleUtf8([byte[]]$Bytes) {
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { return $text.Substring(1) }
    $text
}

function ConvertTo-ArticleDestination($Path, $VaultRoot) {
    if ($Path -isnot [string]) { return $null }
    if ((Test-DmVaultRelativePath -Path $Path).isValid) { return $Path }
    if ($VaultRoot -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($VaultRoot) -or
        -not [IO.Path]::IsPathFullyQualified($Path)) { return $null }

    try { $root = [IO.Path]::GetFullPath($VaultRoot) }
    catch [ArgumentException], [NotSupportedException], [System.IO.PathTooLongException] { return $null }
    $candidate = $Path
    if ($IsWindows) {
        $root = $root.Replace('/', '\')
        $candidate = $candidate.Replace('/', '\')
    }
    $separator = [IO.Path]::DirectorySeparatorChar
    if (-not $root.EndsWith([string]$separator)) { $root += $separator }
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $candidate.StartsWith($root, $comparison)) { return $null }
    $relative = $candidate.Substring($root.Length)
    if ($IsWindows) { $relative = $relative.Replace('\', '/') }
    if (-not (Test-DmVaultRelativePath -Path $relative).isValid) { return $null }
    $relative
}

function Invoke-ArticleStage {
    $operation = ''
    $targets = @()
    if ($readStandardInput) {
        try {
            [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false, $true)
            $RequestJson = [Console]::In.ReadToEnd()
        }
        catch [System.Text.DecoderFallbackException] {
            return (New-ArticleBlock 'INVALID_REQUEST' 'Standard input must contain valid UTF-8 JSON.')
        }
    }
    if ([string]::IsNullOrWhiteSpace($RequestJson)) {
        return (New-ArticleBlock 'INVALID_REQUEST' 'Supply one JSON request object on standard input.')
    }
    try { $inputData = ConvertFrom-Json -InputObject $RequestJson -AsHashtable -NoEnumerate }
    catch { return (New-ArticleBlock 'INVALID_REQUEST' 'Supply a valid JSON request object.') }
    $common = @('vaultRoot', 'callerPreflight', 'campaignGroup', 'articleType', 'destination', 'operation')
    $required = $common
    if ($Action -ne 'prepare') { $required += @('preparationId', 'content') }
    if ($Action -eq 'apply') { $required += 'previewId' }
    $optional = if ($Action -eq 'apply') { @('contextInputs', 'approvedPreviewId') }
        elseif ($Action -eq 'preview') { @('contextInputs') } else { @() }
    if ($inputData -isnot [System.Collections.IDictionary] -or
        @($required.Where({ $_ -cnotin $inputData.Keys })).Count -or
        @($inputData.Keys.Where({ $_ -cnotin ($required + $optional) })).Count) {
        return (New-ArticleBlock 'INVALID_REQUEST' 'The JSON fields do not match this article stage.')
    }
    if ($inputData.operation -isnot [string] -or
        $inputData.operation -cnotin @('note.create-article', 'note.create-article-fact-change') -or
        $inputData.articleType -isnot [string] -or $inputData.articleType -cnotmatch '\A[a-z][a-z0-9_]*\z') {
        return (New-ArticleBlock 'INVALID_REQUEST' 'Supply a registered create operation and article type.')
    }
    $operation = $inputData.operation
    $destination = ConvertTo-ArticleDestination -Path $inputData.destination -VaultRoot $inputData.vaultRoot
    if ($null -eq $destination) {
        return (New-ArticleBlock 'INVALID_REQUEST' 'Supply one explicit destination inside the vault, as a vault-relative or in-vault absolute path.')
    }
    $targets = @($destination)
    if ($Action -ne 'prepare' -and ($inputData.content -isnot [string] -or
        [string]::IsNullOrWhiteSpace($inputData.content) -or $inputData.content -match '<!--\s*fill-in:\s*required\b')) {
        return (New-ArticleBlock 'INVALID_REQUEST' 'Supply a nonempty draft with all required markers filled.')
    }

    $inputs = @(@{ identity = 'destination'; path = $destination; version = 'absent' })
    $separator = $destination.LastIndexOf('/')
    if ($separator -ge 0) {
        $inputs += @{ identity = 'destination-parent'; path = $destination.Substring(0, $separator); version = 'directory' }
    }
    $request = [ordered]@{
        contractVersion = Get-DmContractVersion
        requestId = [guid]::NewGuid().ToString()
        operation = $operation
        vaultRoot = $inputData.vaultRoot
        callerPreflight = $inputData.callerPreflight
        campaignGroup = $inputData.campaignGroup
        mode = 'preview'
        targets = $targets
        arguments = @{ content = $(if ($Action -eq 'prepare') { 'Preparation only' } else { $inputData.content }) }
        authoringInputs = $inputs
    }
    $preflight = Invoke-DmPreflight -Request $request
    if (-not $preflight.passed) { return @{ result = $preflight.result } }
    if (@('note.create-article', 'note.create-article-fact-change') -contains $operation) {
        $canonicalInputCheck = Get-DmArticleAuthoringInputTargets -Preflight $preflight
        if (-not $canonicalInputCheck.ok) {
            return (New-ArticleBlock ([string]$canonicalInputCheck.code) ([string]$canonicalInputCheck.message))
        }
        $canonicalInputs = [System.Collections.Generic.List[object]]::new()
        foreach ($canonicalInput in @($canonicalInputCheck.inputs)) {
            $originalInput = @($inputs | Where-Object { [string]$_.identity -ceq [string]$canonicalInput.identity }) | Select-Object -First 1
            $canonicalInputs.Add([pscustomobject][ordered]@{
                identity = [string]$canonicalInput.identity
                path = [string]$originalInput.path
                version = [string]$canonicalInput.observedVersion
                canonicalPath = [string]$canonicalInput.resolution.resolvedPath
            })
        }
        $inputs = [object[]]$canonicalInputs.ToArray()
        $request.authoringInputs = $inputs
    }
    $shared = Get-DmSharedReferenceResource -Operation $operation -Targets $targets
    if (-not $shared.passed) { return @{ result = $shared.result } }
    $context = Get-DmPreNoteContext -Preflight $preflight
    if (-not $context.passed) { return @{ result = $context.result } }
    $targetCheck = Get-DmArticleAuthoringInputTargets -Preflight $preflight
    if (-not $targetCheck.ok) { return (New-ArticleBlock $targetCheck.code $targetCheck.message) }

    $guidancePath = '.dmassist-guidance.md'
    if ($null -ne $context.profile -and $context.profile.Contains('guidance')) { $guidancePath = $context.profile.guidance.path }
    $guidance = Read-DmVaultTargetBytes -Boundary $preflight.boundary `
        -Resolution (Resolve-DmVaultTarget -Boundary $preflight.boundary -Path $guidancePath)
    $guidanceVersion = ($context.dependencyVersions | Where-Object { $_.identity -ceq $guidancePath }).version
    if (-not $guidance.ok) { return (New-ArticleBlock $guidance.code 'The designated guidance could not be read safely.') }
    if ($guidance.version -cne $guidanceVersion) {
        return (New-ArticleBlock 'TARGET_CONFLICT' 'The designated guidance changed during preparation.')
    }
    try { $guidanceText = ConvertFrom-ArticleUtf8 $guidance.bytes }
    catch [System.Text.DecoderFallbackException] { return (New-ArticleBlock 'RESOURCE_INCOMPATIBLE' 'The designated guidance is not valid UTF-8.') }
    $inputs += @{ identity = 'designated-guidance'; path = $guidancePath; version = $guidance.version }
    if ($context.context.profileState -ceq 'valid') {
        $inputs += @{ identity = 'profile'; path = '.dmassist.yaml'; version = $context.context.profileVersion }
    }

    $type = $inputData.articleType
    $configured = if ($null -ne $context.profile) { Resolve-DmProfileTemplate -Profile $context.profile -ArticleType $type }
    if ($null -ne $configured -and $configured.available) {
        $source = @{ kind = 'configured'; path = $configured.path }
        $resolution = Resolve-DmVaultTarget -Boundary $preflight.boundary -Path $configured.path
        if ($resolution.code) {
            return (New-ArticleBlock $resolution.code 'The configured template could not be safely resolved; no fallback was used.')
        }
        if (-not $resolution.exists -or $resolution.itemType -cne 'file') {
            $code = if ($Action -eq 'prepare') { 'REFERENCE_UNAVAILABLE' } else { 'TARGET_CONFLICT' }
            return (New-ArticleBlock $code 'The configured template is missing or is not a file; no fallback was used.')
        }
        $snapshot = Read-DmVaultTargetBytes -Boundary $preflight.boundary -Resolution $resolution
        if (-not $snapshot.ok) { return (New-ArticleBlock $snapshot.code 'The configured template could not be read safely; no fallback was used.') }
        $bytes = $snapshot.bytes
        $source.version = $snapshot.version
        $inputs += @{ identity = 'selected-template'; path = $configured.path; version = $snapshot.version }
    }
    elseif ($type -cin @('adventure', 'character', 'handout', 'location', 'monster', 'party', 'persona', 'rule', 'session')) {
        $source = @{ kind = 'bundled'; path = "templates/$type.md" }
        try { $bytes = [IO.File]::ReadAllBytes((Join-Path (Split-Path $PSScriptRoot) "templates\$type.md")) }
        catch [System.IO.IOException], [UnauthorizedAccessException] {
            return (New-ArticleBlock 'RESOURCE_MISSING' 'The bundled template could not be read; repair the plugin installation.')
        }
        $source.version = Get-ArticleHash $bytes
    }
    else { return (New-ArticleBlock 'REFERENCE_UNAVAILABLE' 'No template is configured for this custom article type.') }
    try { $template = ConvertFrom-ArticleUtf8 $bytes }
    catch [System.Text.DecoderFallbackException] { return (New-ArticleBlock 'RESOURCE_INCOMPATIBLE' 'The selected template is not valid UTF-8.') }
    if ([string]::IsNullOrWhiteSpace($template)) { return (New-ArticleBlock 'RESOURCE_INCOMPATIBLE' 'The selected template is empty.') }

    # Bind the draft to the resource bytes prepared for it, including bundled resources outside the vault.
    $prepared = [ordered]@{
        operation = $operation; root = $preflight.boundary.canonicalRoot; campaignGroup = $preflight.request.campaignGroup
        articleType = $type; inputs = $inputs; source = $source; shared = $shared.resource.version
    }
    $preparationId = Get-ArticleHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-DmJcsJson -Value $prepared)))
    if ($Action -eq 'prepare') {
        return @{
            preparationId = $preparationId
            sharedReference = $shared.resource.text
            guidance = @{ path = $guidancePath; text = $guidanceText }
            template = @{ source = $source; text = $template }
        }
    }
    if ($inputData.preparationId -isnot [string] -or $inputData.preparationId -cne $preparationId) {
        return (New-ArticleBlock 'TARGET_CONFLICT' 'Preparation no longer matches the current article inputs.')
    }
    if ($inputData.Contains('contextInputs')) {
        if ($inputData.contextInputs -isnot [array] -or @($inputData.contextInputs.Where({
            $_ -isnot [System.Collections.IDictionary] -or -not $_.Contains('identity') -or
            $_.identity -isnot [string] -or $_.identity -cnotmatch '\Arelevant-context(?:-[0-9]+)?\z'
        })).Count) { return (New-ArticleBlock 'INVALID_REQUEST' 'Supply only relevant-context snapshots in contextInputs.') }
        $inputs += $inputData.contextInputs
    }
    $request.authoringInputs = $inputs
    $preview = Invoke-DmPreview -Request $request
    if ($Action -eq 'preview' -or $null -eq $preview.preview) { return $preview }
    if ($inputData.previewId -isnot [string] -or $inputData.previewId -cne $preview.preview.previewId) {
        return (New-ArticleBlock 'TARGET_CONFLICT' 'The current draft and inputs do not match the previous preview.')
    }
    if ($preview.preview.requiresApproval -and
        (-not $inputData.Contains('approvedPreviewId') -or $inputData.approvedPreviewId -cne $preview.preview.previewId)) {
        return (New-ArticleBlock 'CONFIRMATION_REQUIRED' 'This change requires explicit DM approval of the exact preview.')
    }
    $request.mode = 'apply'
    $request.approvedPreviewId = $preview.preview.previewId
    $request.reviewedVersions = $preview.preview.reviewedVersions
    $request.reviewedDependencyVersions = $preview.preview.reviewedDependencyVersions
    Invoke-DmApply -Request $request
}

Invoke-ArticleStage | ConvertTo-Json -Depth 20 -Compress
