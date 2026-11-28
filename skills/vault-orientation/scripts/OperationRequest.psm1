Set-StrictMode -Version Latest

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VaultPathValidation.psm1')

# Operation registry and contract section 2 request validation. Validation
# checks request shape only: it infers nothing from the working directory,
# plugin directory, notes, profile, or environment, and it never resolves the
# vault root (that happens after the authorization gate).

$script:DmRequestFields = @('contractVersion', 'requestId', 'operation', 'vaultRoot', 'campaignGroup', 'mode', 'arguments', 'targets', 'callerPreflight', 'authoringInputs',
    'approvedPreviewId', 'reviewedVersions', 'reviewedDependencyVersions', 'declinedReviewId')
$script:DmRequiredRequestFields = @('contractVersion', 'requestId', 'operation', 'vaultRoot', 'campaignGroup', 'mode', 'arguments', 'targets')
$script:DmModes = @('inspect', 'preview', 'apply')
$script:DmArgumentTypes = @('string', 'boolean', 'integer', 'stringArray', 'mappingDecisions')
$script:DmChangeKinds = @('read', 'edit', 'create', 'delete', 'reorganize', 'unclassified')
$script:DmConversionDecisions = @('preserve')
$script:DmDigestPattern = '^sha256:[0-9a-f]{64}$'
$script:DmOperationNamePattern = '^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$'
$script:DmOperations = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

function Get-DmExactField {
    <#
    .SYNOPSIS
    Performs a case-sensitive lookup in a dictionary or custom object.
    .DESCRIPTION
    Returns a map with present and value fields, including for a null value.
    .PARAMETER Object
    Object containing the field.
    .PARAMETER Name
    Exact, case-sensitive field name.
    #>
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ($key -is [string] -and $key -ceq $Name) { return @{ present = $true; value = $Object[$key] } }
        }
    }
    elseif ($Object -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Object.PSObject.Properties) {
            if ($property.Name -ceq $Name) { return @{ present = $true; value = $property.Value } }
        }
    }
    @{ present = $false; value = $null }
}

function Get-DmFieldName {
    <#
    .SYNOPSIS
    Enumerates field names from a dictionary or custom object.
    .PARAMETER Object
    Candidate object whose keys or properties should be listed.
    #>
    param($Object)
    if ($Object -is [System.Collections.IDictionary]) { return @($Object.Keys) }
    if ($Object -is [System.Management.Automation.PSCustomObject]) { return @($Object.PSObject.Properties.Name) }
    @()
}

function Test-DmObjectValue {
    <#
    .SYNOPSIS
    Checks whether a value has the supported request-object shape.
    .PARAMETER Value
    Candidate dictionary or custom object.
    #>
    param($Value)
    $Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]
}

function Test-DmListValue {
    <#
    .SYNOPSIS
    Checks whether a value is a non-string, non-dictionary list.
    .PARAMETER Value
    Candidate list value.
    #>
    param($Value)
    $null -ne $Value -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary] -and $Value -is [System.Collections.IList]
}

function Test-DmPlainText {
    <#
    .SYNOPSIS
    Validates nonempty, single-line text without control characters.
    .PARAMETER Value
    Candidate string to validate.
    .PARAMETER MaxLength
    Maximum permitted character count; defaults to 256.
    #>
    param($Value, [int]$MaxLength = 256)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt $MaxLength) { return $false }
    foreach ($ch in $Value.ToCharArray()) {
        if ([int]$ch -lt 0x20 -or ([int]$ch -ge 0x7F -and [int]$ch -le 0x9F)) { return $false }
    }
    $true
}

function Test-DmArgumentValue {
    <#
    .SYNOPSIS
    Checks an operation argument against its registered type and empty-value rule.
    .PARAMETER Value
    Argument value to validate.
    .PARAMETER Spec
    Normalized argument specification with type and allowEmpty fields.
    #>
    param($Value, $Spec)
    switch ($Spec.type) {
        'string' {
            if ($Value -isnot [string]) { return $false }
            if (-not $Spec.allowEmpty -and $Value.Length -eq 0) { return $false }
            return $true
        }
        'boolean' { return $Value -is [bool] }
        'integer' { return $Value -is [int] -or $Value -is [long] }
        { $_ -in @('stringArray', 'mappingDecisions') } { return Test-DmListValue -Value $Value }
    }
    $false
}

function ConvertTo-DmArgumentSpec {
    <#
    .SYNOPSIS
    Normalizes registered argument definitions into an ordered specification.
    .PARAMETER AllowedArguments
    Argument names or a dictionary of type, required, and allowEmpty rules.
    #>
    param($AllowedArguments)
    $specs = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    if ($null -eq $AllowedArguments) { return , $specs }
    if ($AllowedArguments -is [System.Collections.IDictionary]) {
        foreach ($name in $AllowedArguments.Keys) {
            $raw = $AllowedArguments[$name]
            $type = 'string'; $required = $false; $allowEmpty = $true
            if ($raw -is [string]) { $type = $raw }
            elseif (Test-DmObjectValue -Value $raw) {
                $t = Get-DmExactField -Object $raw -Name 'type'; if ($t.present) { $type = [string]$t.value }
                $r = Get-DmExactField -Object $raw -Name 'required'; if ($r.present) { $required = [bool]$r.value }
                $e = Get-DmExactField -Object $raw -Name 'allowEmpty'; if ($e.present) { $allowEmpty = [bool]$e.value }
            }
            else { throw [System.ArgumentException]::new("Argument '$name' has an invalid specification.") }
            if ($type -cnotin $script:DmArgumentTypes) { throw [System.ArgumentException]::new("Argument '$name' has unsupported type '$type'.") }
            if ([string]$name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$') { throw [System.ArgumentException]::new('Argument names must be alphanumeric identifiers.') }
            $specs.Add([string]$name, [pscustomobject][ordered]@{ type = $type; required = $required; allowEmpty = $allowEmpty })
        }
        return , $specs
    }
    foreach ($name in @($AllowedArguments)) {
        if ([string]$name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$') { throw [System.ArgumentException]::new('Argument names must be alphanumeric identifiers.') }
        $specs.Add([string]$name, [pscustomobject][ordered]@{ type = 'string'; required = $false; allowEmpty = $true })
    }
    , $specs
}

function Register-DmOperation {
    <#
    .SYNOPSIS
    Registers an operation and its request-validation and change rules.
    .DESCRIPTION
    Returns the registration. Built-in operations cannot be replaced.
    .PARAMETER Name
    Lowercase operation identifier using dotted or hyphenated components.
    .PARAMETER Modes
    Nonempty subset of inspect, preview, and apply.
    .PARAMETER FactChanging
    Whether the operation can change established campaign facts.
    .PARAMETER AllowedArguments
    Argument names, or a dictionary mapping each name to type, required, and
    allowEmpty rules. Supported types are string, boolean, and integer.
    .PARAMETER Builder
    Trusted script block accepting CurrentText, Arguments, and TargetPath and
    returning the complete replacement text; required for preview or apply.
    .PARAMETER ChangeKind
    Read, edit, delete, reorganize, or unclassified; defaults to read for
    inspect-only operations and unclassified otherwise.
    .PARAMETER MinTargets
    Minimum accepted number of targets; defaults to one.
    .PARAMETER MaxTargets
    Maximum accepted number of targets; defaults to the largest integer.
    .PARAMETER Description
    Human-readable description of the registered operation.
    .PARAMETER RequiresMappings
    Marks an operation as dependent on folder or note-role mappings, requiring
    designated local guidance rather than a mapping-independent lookup.
    .PARAMETER RequiresCampaignGroup
    Requires explicit campaign/group context before campaign-note access.
    .PARAMETER PageLocalSafe
    Allows only a non-fact-changing single-target create to use the page-local approval exception.
    .PARAMETER Force
    Replaces an existing non-built-in registration; built-ins remain protected.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Modes,
        [Parameter(Mandatory)][bool]$FactChanging,
        [AllowNull()]$AllowedArguments,
        [scriptblock]$Builder,
        [string]$ChangeKind,
        [ValidateRange(0, [int]::MaxValue)][int]$MinTargets = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$MaxTargets = [int]::MaxValue,
        [string]$Description = '',
        [switch]$RequiresMappings,
        [switch]$RequiresCampaignGroup,
        [switch]$PageLocalSafe,
        [switch]$Force
    )
    if ($Name -cnotmatch $script:DmOperationNamePattern) { throw [System.ArgumentException]::new('Operation names must be lowercase dotted identifiers.') }
    if ($Modes.Count -eq 0 -or @($Modes | Where-Object { $_ -cnotin $script:DmModes }).Count -gt 0) {
        throw [System.ArgumentException]::new('Modes must be a non-empty subset of inspect, preview, apply.')
    }
    $writes = @($Modes | Where-Object { $_ -cne 'inspect' }).Count -gt 0
    if ($writes -and $null -eq $Builder) { throw [System.ArgumentException]::new('An operation with preview or apply mode requires a builder.') }
    if ([string]::IsNullOrEmpty($ChangeKind)) { $ChangeKind = $(if ($writes) { 'unclassified' } else { 'read' }) }
    if ($ChangeKind -cnotin $script:DmChangeKinds) { throw [System.ArgumentException]::new("Unknown change kind '$ChangeKind'.") }
    if ($PageLocalSafe -and ($ChangeKind -cne 'create' -or $FactChanging)) {
        throw [System.ArgumentException]::new('PageLocalSafe is valid only for create operations that do not change established campaign facts.')
    }
    if ($MaxTargets -lt $MinTargets) { throw [System.ArgumentException]::new('MaxTargets must be at least MinTargets.') }
    if ($script:DmOperations.Contains($Name)) {
        if ($script:DmOperations[$Name].builtIn) { throw [System.InvalidOperationException]::new("Built-in operation '$Name' cannot be replaced.") }
        if (-not $Force) { throw [System.InvalidOperationException]::new("Operation '$Name' is already registered.") }
        $script:DmOperations.Remove($Name)
    }
    $registration = [pscustomobject][ordered]@{
        name         = $Name
        description  = $Description
        modes        = [string[]]@($script:DmModes | Where-Object { $_ -cin $Modes })
        arguments    = (ConvertTo-DmArgumentSpec -AllowedArguments $AllowedArguments)
        factChanging = $FactChanging
        changeKind   = $ChangeKind
        minTargets   = $MinTargets
        maxTargets   = $MaxTargets
        builder               = $Builder
        requiresMappings      = [bool]$RequiresMappings
        requiresCampaignGroup = [bool]$RequiresCampaignGroup
        pageLocalSafe         = [bool]$PageLocalSafe
        builtIn               = $false
    }
    $script:DmOperations.Add($Name, $registration)
    $registration
}

function Unregister-DmOperation {
    <#
    .SYNOPSIS
    Removes a non-built-in operation registration.
    .DESCRIPTION
    Returns true when removed, false when absent, and throws for a built-in.
    .PARAMETER Name
    Exact name of the registration to remove.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:DmOperations.Contains($Name)) { return $false }
    if ($script:DmOperations[$Name].builtIn) { throw [System.InvalidOperationException]::new("Built-in operation '$Name' cannot be removed.") }
    $script:DmOperations.Remove($Name)
    $true
}

function Get-DmOperation {
    <#
    .SYNOPSIS
    Gets one registered operation or all operations in registration order.
    .PARAMETER Name
    Optional exact name; an absent registration returns null.
    #>
    [CmdletBinding()]
    param([string]$Name)
    if ($PSBoundParameters.ContainsKey('Name')) {
        if ($script:DmOperations.Contains($Name)) { return $script:DmOperations[$Name] }
        return $null
    }
    foreach ($key in $script:DmOperations.Keys) { $script:DmOperations[$key] }
}

function Test-DmVersionValue {
    <#
    .SYNOPSIS
    Checks for an absent marker or a SHA-256 version identifier.
    .PARAMETER Value
    Candidate version string.
    #>
    param($Value)
    $Value -is [string] -and ($Value -ceq 'absent' -or $Value -cmatch $script:DmDigestPattern)
}

function Test-DmVaultRootShape {
    <#
    .SYNOPSIS
    Checks the lexical shape of an explicit absolute vault root.
    .DESCRIPTION
    This does not resolve the path or prove authorization or containment.
    .PARAMETER Value
    Candidate vault-root string.
    #>
    param($Value)
    if (-not (Test-DmPlainText -Value $Value -MaxLength 4096)) { return $false }
    if ($Value.StartsWith('\\?\') -or $Value.StartsWith('\\.\') -or $Value.StartsWith('//?/') -or $Value.StartsWith('//./')) { return $false }
    if ($Value.IndexOfAny([char[]]@('*', '?', '<', '>', '|', '"')) -ge 0) { return $false }
    [System.IO.Path]::IsPathFullyQualified($Value)
}

function Test-DmOperationRequest {
    <#
    .SYNOPSIS
    Validates and normalizes an explicit operation request without vault access.
    .DESCRIPTION
    Validates one contract section 2 request (hashtable or pscustomobject).
    Returns [pscustomobject]@{ isValid; code; problems; request } where code is
    $null, 'INVALID_REQUEST' (shape problems), or 'PATH_INVALID' (a target
    violates the lexical path rules), problems are safe messages that never
    echo request values, and request is the normalized request when valid:
    contractVersion, requestId, operation, vaultRoot, campaignGroup
    {campaign; group}, mode, arguments (ordered, schema order), targets
    (string[]), approvedPreviewId, reviewedVersions
    ({path; observedVersion; replacementVersion; conversionDecision}[]),
    reviewedDependencyVersions ({identity; version}[]), declinedReviewId,
    callerPreflight ({vaultRoot; dependenciesReady; vaultAuthorized}).
    Absent optional values are $null.
    .PARAMETER Request
    Untrusted request dictionary or custom object to validate against the
    registered operation and request contract.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Request)

    $problems = [System.Collections.Generic.List[string]]::new()
    $pathProblems = [System.Collections.Generic.List[string]]::new()
    $finish = {
        param($Normalized)
        $code = $null
        if ($problems.Count -gt 0) { $code = 'INVALID_REQUEST' } elseif ($pathProblems.Count -gt 0) { $code = 'PATH_INVALID' }
        [pscustomobject][ordered]@{
            isValid  = ($null -eq $code)
            code     = $code
            problems = [string[]]@($problems) + [string[]]@($pathProblems)
            request  = $(if ($null -eq $code) { $Normalized } else { $null })
        }
    }

    if (-not (Test-DmObjectValue -Value $Request)) {
        $problems.Add('The request must be an object.')
        return (& $finish $null)
    }
    foreach ($name in (Get-DmFieldName -Object $Request)) {
        if ($name -isnot [string] -or $name -cnotin $script:DmRequestFields) { $problems.Add('The request contains an unknown field.'); break }
    }
    $f = @{}
    foreach ($name in $script:DmRequestFields) { $f[$name] = Get-DmExactField -Object $Request -Name $name }
    foreach ($name in $script:DmRequiredRequestFields) {
        if (-not $f[$name].present) { $problems.Add("$name is required.") }
    }

    $contractVersion = $f['contractVersion'].value
    if ($f['contractVersion'].present -and ($contractVersion -isnot [string] -or $contractVersion -cne (Get-DmContractVersion))) {
        $problems.Add("contractVersion must be the string '$(Get-DmContractVersion)'.")
    }
    $requestId = $f['requestId'].value
    if ($f['requestId'].present -and -not (Test-DmPlainText -Value $requestId)) { $problems.Add('requestId must be a non-empty single-line string of at most 256 characters.') }

    $operationName = $f['operation'].value
    $registration = $null
    if ($f['operation'].present) {
        if ($operationName -isnot [string] -or $operationName -cnotmatch $script:DmOperationNamePattern) {
            $problems.Add('operation must be a registered operation identifier.')
        }
        elseif (-not $script:DmOperations.Contains($operationName)) {
            $problems.Add('operation is not a registered operation.')
        }
        else { $registration = $script:DmOperations[$operationName] }
    }

    $vaultRoot = $f['vaultRoot'].value
    if ($f['vaultRoot'].present -and -not (Test-DmVaultRootShape -Value $vaultRoot)) {
        $problems.Add('vaultRoot must be an explicit absolute path; it is never expanded or inferred.')
    }

    $callerPreflight = $null
    if ($f['callerPreflight'].present -and $null -ne $f['callerPreflight'].value) {
        $raw = $f['callerPreflight'].value
        $root = Get-DmExactField -Object $raw -Name 'vaultRoot'
        $ready = Get-DmExactField -Object $raw -Name 'dependenciesReady'
        $authorized = Get-DmExactField -Object $raw -Name 'vaultAuthorized'
        $names = @(Get-DmFieldName -Object $raw)
        $rootValue = $root.value
        if ($IsWindows -and $rootValue -is [string]) {
            if ($rootValue.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) { $rootValue = '\\' + $rootValue.Substring(8) }
            elseif ($rootValue.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) { $rootValue = $rootValue.Substring(4) }
        }
        if (-not (Test-DmObjectValue -Value $raw) -or $names.Count -ne 3 -or
            -not (Test-DmVaultRootShape -Value $rootValue) -or
            $ready.value -isnot [bool] -or $authorized.value -isnot [bool]) {
            $problems.Add('callerPreflight must contain exactly an absolute vaultRoot and Boolean dependenciesReady and vaultAuthorized confirmations.')
        }
        else {
            $callerPreflight = [pscustomobject][ordered]@{
                vaultRoot = [string]$rootValue
                dependenciesReady = $ready.value
                vaultAuthorized = $authorized.value
            }
        }
    }

    $campaignGroup = $null
    if ($f['campaignGroup'].present) {
        $cg = $f['campaignGroup'].value
        if (-not (Test-DmObjectValue -Value $cg)) {
            $problems.Add('campaignGroup must be an object with explicit campaign and group values.')
        }
        else {
            $cgNames = @(Get-DmFieldName -Object $cg)
            if (@($cgNames | Where-Object { $_ -cnotin @('campaign', 'group') }).Count -gt 0) { $problems.Add('campaignGroup contains an unknown field.') }
            $normalizedCg = [ordered]@{}
            foreach ($key in @('campaign', 'group')) {
                $entry = Get-DmExactField -Object $cg -Name $key
                if (-not $entry.present) { $problems.Add("campaignGroup.$key is required; use an explicit null when the operation does not use it.") }
                elseif ($null -ne $entry.value -and -not (Test-DmPlainText -Value $entry.value)) { $problems.Add("campaignGroup.$key must be a non-empty string or null.") }
                $normalizedCg[$key] = $entry.value
            }
            $campaignGroup = [pscustomobject]$normalizedCg
        }
    }

    $mode = $f['mode'].value
    if ($f['mode'].present) {
        if ($mode -isnot [string] -or $mode -cnotin $script:DmModes) { $problems.Add('mode must be inspect, preview, or apply.') }
        elseif ($null -ne $registration -and $mode -cnotin $registration.modes) { $problems.Add('The operation does not support the requested mode.') }
    }

    $arguments = [ordered]@{}
    if ($f['arguments'].present) {
        $rawArguments = $f['arguments'].value
        if (-not (Test-DmObjectValue -Value $rawArguments)) {
            $problems.Add('arguments must be an object.')
        }
        elseif ($null -ne $registration) {
            foreach ($name in (Get-DmFieldName -Object $rawArguments)) {
                if ($name -isnot [string] -or -not $registration.arguments.Contains($name)) { $problems.Add('arguments contains an argument the operation does not accept.'); break }
            }
            foreach ($name in $registration.arguments.Keys) {
                $spec = $registration.arguments[$name]
                $entry = Get-DmExactField -Object $rawArguments -Name $name
                if (-not $entry.present) {
                    if ($spec.required) { $problems.Add("Argument $name is required.") }
                    if ($registration.name -ceq 'vault.orientation.inventory') {
                        switch -CaseSensitive ($name) {
                            'selectedGuidance' { $arguments[$name] = [string[]]@() }
                            'optionalGuidance' { $arguments[$name] = [string[]]@() }
                            'proposeProfile' { $arguments[$name] = $false }
                            'mappingDecisions' { $arguments[$name] = [object[]]@() }
                        }
                    }
                    continue
                }
                if (-not (Test-DmArgumentValue -Value $entry.value -Spec $spec)) { $problems.Add("Argument $name must be a $($spec.type) value.") }
                $arguments[$name] = $entry.value
            }
        }
    }

    if ($null -ne $registration -and $registration.name -ceq 'vault.orientation.inventory' -and
        $f['arguments'].present -and (Test-DmObjectValue -Value $f['arguments'].value)) {
        $rawArguments = $f['arguments'].value
        $pathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq [char]'\') {
            [System.StringComparer]::OrdinalIgnoreCase
        }
        else {
            [System.StringComparer]::Ordinal
        }
        $normalizedPaths = @{}
        $invalidGuidancePath = $false
        foreach ($field in @('selectedGuidance', 'optionalGuidance')) {
            $entry = Get-DmExactField -Object $rawArguments -Name $field
            $rawPaths = @()
            if ($entry.present) { $rawPaths = $entry.value }
            if (-not (Test-DmListValue -Value $rawPaths)) { continue }
            $paths = [System.Collections.Generic.List[string]]::new()
            $seenPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparison)
            $index = 0
            foreach ($path in $rawPaths) {
                if ($path -isnot [string]) {
                    $problems.Add("Argument $field[$index] must be a string.")
                }
                else {
                    $check = Test-DmVaultRelativePath -Path $path
                    if (-not $check.isValid) {
                        $pathProblems.Add("Argument $field[$index]: $($check.reason)")
                        $invalidGuidancePath = $true
                    }
                    else {
                        $normalizedPath = [string]::Join('/', [string[]]$check.components)
                        if ($seenPaths.Add($normalizedPath)) { $paths.Add($normalizedPath) }
                    }
                }
                $index++
            }
            $normalizedPaths[$field] = [string[]]$paths.ToArray()
            $arguments[$field] = [string[]]$paths.ToArray()
        }

        $proposeEntry = Get-DmExactField -Object $rawArguments -Name 'proposeProfile'
        $proposeProfile = $false
        if ($proposeEntry.present -and $proposeEntry.value -is [bool]) { $proposeProfile = $proposeEntry.value }
        $decisionsEntry = Get-DmExactField -Object $rawArguments -Name 'mappingDecisions'
        $rawDecisions = @()
        if ($decisionsEntry.present) { $rawDecisions = $decisionsEntry.value }
        if ($decisionsEntry.present -and -not $proposeProfile) {
            $problems.Add('mappingDecisions is valid only when proposeProfile is true.')
        }
        if (Test-DmListValue -Value $rawDecisions) {
            $decisions = [System.Collections.Generic.List[object]]::new()
            $seenAmbiguities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $seenDecisions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $index = 0
            foreach ($decision in $rawDecisions) {
                $validDecision = Test-DmObjectValue -Value $decision
                if ($validDecision) {
                    $names = @(Get-DmFieldName -Object $decision)
                    $ambiguity = Get-DmExactField -Object $decision -Name 'ambiguityId'
                    $alternative = Get-DmExactField -Object $decision -Name 'alternativeId'
                    $validDecision = $names.Count -eq 2 -and $ambiguity.present -and $alternative.present -and
                        (Test-DmPlainText -Value $ambiguity.value -MaxLength 2147483647) -and
                        (Test-DmPlainText -Value $alternative.value -MaxLength 2147483647) -and
                        ([string]$ambiguity.value).IndexOfAny([char[]]@([char]0x2028, [char]0x2029)) -lt 0 -and
                        ([string]$alternative.value).IndexOfAny([char[]]@([char]0x2028, [char]0x2029)) -lt 0
                    if ($validDecision) {
                        $ambiguityId = [string]$ambiguity.value
                        $alternativeId = [string]$alternative.value
                        $decisionKey = "$($ambiguityId.Length):$ambiguityId$alternativeId"
                        if (-not $seenDecisions.Add($decisionKey) -or -not $seenAmbiguities.Add($ambiguityId)) {
                            $validDecision = $false
                        }
                        $decisions.Add([pscustomobject][ordered]@{
                            ambiguityId  = $ambiguityId
                            alternativeId = $alternativeId
                        })
                    }
                }
                if (-not $validDecision) { $problems.Add("Argument mappingDecisions[$index] must carry exactly non-empty single-line ambiguityId and alternativeId strings, with at most one decision per ambiguity.") }
                $index++
            }
            $arguments['mappingDecisions'] = [object[]]$decisions.ToArray()
        }

        if (-not $invalidGuidancePath -and $normalizedPaths.ContainsKey('selectedGuidance') -and $normalizedPaths.ContainsKey('optionalGuidance')) {
            $selectedSet = [System.Collections.Generic.HashSet[string]]::new($pathComparison)
            foreach ($path in $normalizedPaths['selectedGuidance']) { $null = $selectedSet.Add($path) }
            foreach ($path in $normalizedPaths['optionalGuidance']) {
                if (-not $selectedSet.Contains($path)) {
                    $problems.Add('optionalGuidance must be a subset of selectedGuidance.')
                    break
                }
            }
        }
    }

    $targets = [string[]]@()
    if ($f['targets'].present) {
        $rawTargets = $f['targets'].value
        if (-not (Test-DmListValue -Value $rawTargets)) {
            $problems.Add('targets must be an array of vault-relative paths.')
        }
        else {
            $list = [System.Collections.Generic.List[string]]::new()
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $index = 0
            foreach ($target in $rawTargets) {
                if ($target -isnot [string]) { $problems.Add("targets[$index] must be a string.") }
                else {
                    $check = Test-DmVaultRelativePath -Path $target
                    if (-not $check.isValid) { $pathProblems.Add("targets[$index]: $($check.reason)") }
                    if (-not $seen.Add($target)) { $problems.Add("targets[$index] repeats an earlier target.") }
                    $list.Add($target)
                }
                $index++
            }
            $targets = [string[]]$list.ToArray()
            if ($null -ne $registration) {
                if ($index -lt $registration.minTargets -or $index -gt $registration.maxTargets) {
                    $problems.Add('The number of targets is not valid for the operation.')
                }
            }
        }
    }

    $authoringInputs = $null
    $authoringInputsField = $f['authoringInputs']
    $isArticleCreate = $null -ne $registration -and $registration.name -cin @('note.create-article', 'note.create-article-fact-change')
    if ($isArticleCreate) {
        if (-not $authoringInputsField.present -or -not (Test-DmListValue -Value $authoringInputsField.value) -or
            @($authoringInputsField.value).Count -lt 1) {
            $problems.Add('Article creation requires authoringInputs for the destination and its existing parent when it is not the vault root.')
        }
        else {
            $entries = [System.Collections.Generic.List[object]]::new()
            $identities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $index = 0
            foreach ($entry in $authoringInputsField.value) {
                $ok = Test-DmObjectValue -Value $entry
                if ($ok) {
                    $names = @(Get-DmFieldName -Object $entry)
                    $identity = Get-DmExactField -Object $entry -Name 'identity'
                    $path = Get-DmExactField -Object $entry -Name 'path'
                    $version = Get-DmExactField -Object $entry -Name 'version'
                    $canonicalPath = Get-DmExactField -Object $entry -Name 'canonicalPath'
                    $pathCheck = if ($path.value -is [string]) { Test-DmVaultRelativePath -Path $path.value } else { $null }
                    $allowedVersion = $version.value -is [string] -and (
                        $version.value -ceq 'directory' -or (Test-DmVersionValue -Value $version.value)
                    )
                    $unknownNames = @($names | Where-Object { $_ -cnotin @('identity', 'path', 'version', 'canonicalPath') })
                    $canonicalValid = -not $canonicalPath.present -or (
                        $canonicalPath.value -is [string] -and [System.IO.Path]::IsPathFullyQualified([string]$canonicalPath.value)
                    )
                    $ok = $unknownNames.Count -eq 0 -and @($names).Count -ge 3 -and @($names).Count -le 4 -and
                        $canonicalValid -and $identity.present -and (Test-DmPlainText -Value $identity.value -MaxLength 128) -and
                        $path.present -and $null -ne $pathCheck -and $pathCheck.isValid -and $version.present -and $allowedVersion
                    if ($ok -and -not $identities.Add([string]$identity.value)) { $ok = $false }
                    if ($ok) {
                        $entryValue = [ordered]@{
                            identity = [string]$identity.value
                            path = [string]$path.value
                            version = [string]$version.value
                        }
                        if ($canonicalPath.present) { $entryValue['canonicalPath'] = [string]$canonicalPath.value }
                        $entries.Add([pscustomobject]$entryValue)
                    }
                }
                if (-not $ok) { $problems.Add("authoringInputs[$index] must carry one unique identity, a valid vault-relative path, and a valid version.") }
                $index++
            }

            $destinationEntries = @($entries | Where-Object { $_.identity -ceq 'destination' })
            $parentEntries = @($entries | Where-Object { $_.identity -ceq 'destination-parent' })
            if ($destinationEntries.Count -ne 1) {
                $problems.Add('authoringInputs must identify exactly one destination.')
            }
            elseif ($targets.Count -eq 1) {
                $targetPath = [string]$targets[0]
                $separator = $targetPath.LastIndexOf('/')
                $parentPath = if ($separator -lt 0) { '' } else { $targetPath.Substring(0, $separator) }
                $parentValid = if ([string]::IsNullOrEmpty($parentPath)) {
                    $parentEntries.Count -eq 0
                }
                else {
                    $parentEntries.Count -eq 1 -and $parentEntries[0].path -ceq $parentPath -and $parentEntries[0].version -ceq 'directory'
                }
                if ($destinationEntries[0].path -cne $targetPath -or $destinationEntries[0].version -cne 'absent' -or -not $parentValid) {
                    $problems.Add('authoringInputs must bind the absent target and its existing parent, when not the vault root, to the sole requested destination.')
                }
            }
            $authoringInputs = [object[]]$entries.ToArray()
        }
    }
    elseif ($authoringInputsField.present) {
        $problems.Add('authoringInputs is valid only for article-creation operations.')
    }

    $approved = $f['approvedPreviewId']
    $reviewed = $f['reviewedVersions']
    $reviewedDeps = $f['reviewedDependencyVersions']
    $declined = $f['declinedReviewId']
    $approvedPreviewId = $null
    $reviewedVersions = $null
    $reviewedDependencyVersions = $null
    $declinedReviewId = $null

    if ($approved.present) {
        if ($approved.value -isnot [string] -or $approved.value -cnotmatch $script:DmDigestPattern) { $problems.Add('approvedPreviewId must be a sha256 preview identifier.') }
        if ($mode -cne 'apply') { $problems.Add('approvedPreviewId is valid only with mode apply.') }
        $approvedPreviewId = $approved.value
        if (-not $reviewed.present) { $problems.Add('reviewedVersions is required with approvedPreviewId.') }
        if (-not $reviewedDeps.present) { $problems.Add('reviewedDependencyVersions is required with approvedPreviewId.') }
    }
    else {
        if ($reviewed.present) { $problems.Add('reviewedVersions is valid only with approvedPreviewId.') }
        if ($reviewedDeps.present) { $problems.Add('reviewedDependencyVersions is valid only with approvedPreviewId.') }
    }

    if ($reviewed.present) {
        if (-not (Test-DmListValue -Value $reviewed.value)) { $problems.Add('reviewedVersions must be an array.') }
        else {
            $entries = [System.Collections.Generic.List[object]]::new()
            $index = 0
            foreach ($entry in $reviewed.value) {
                $ok = Test-DmObjectValue -Value $entry
                if ($ok) {
                    $names = @(Get-DmFieldName -Object $entry)
                    $ok = @($names | Where-Object { $_ -cnotin @('path', 'observedVersion', 'replacementVersion', 'conversionDecision') }).Count -eq 0
                    $p = Get-DmExactField -Object $entry -Name 'path'
                    $o = Get-DmExactField -Object $entry -Name 'observedVersion'
                    $r = Get-DmExactField -Object $entry -Name 'replacementVersion'
                    $c = Get-DmExactField -Object $entry -Name 'conversionDecision'
                    $ok = $ok -and (Test-DmVersionValue -Value $o.value) -and (Test-DmVersionValue -Value $r.value) -and
                        $c.value -is [string] -and $c.value -cin $script:DmConversionDecisions
                    $expectedPath = if ($index -lt $targets.Count) { $targets[$index] } else { $null }
                    if ($ok -and $p.present -and ($p.value -isnot [string] -or $p.value -cne $expectedPath)) { $ok = $false }
                    if ($ok) {
                        $entries.Add([pscustomobject][ordered]@{ path = $expectedPath; observedVersion = $o.value; replacementVersion = $r.value; conversionDecision = $c.value })
                    }
                }
                if (-not $ok) { $problems.Add("reviewedVersions[$index] must carry observedVersion, replacementVersion, and conversionDecision for the target at the same position.") }
                $index++
            }
            if ($index -ne $targets.Count) { $problems.Add('reviewedVersions must contain one entry per target, in targets order.') }
            $reviewedVersions = [object[]]$entries.ToArray()
        }
    }

    if ($reviewedDeps.present) {
        if (-not (Test-DmListValue -Value $reviewedDeps.value)) { $problems.Add('reviewedDependencyVersions must be an array.') }
        else {
            $entries = [System.Collections.Generic.List[object]]::new()
            $index = 0
            foreach ($entry in $reviewedDeps.value) {
                $ok = Test-DmObjectValue -Value $entry
                if ($ok) {
                    $names = @(Get-DmFieldName -Object $entry)
                    $i = Get-DmExactField -Object $entry -Name 'identity'
                    $v = Get-DmExactField -Object $entry -Name 'version'
                    $ok = $names.Count -eq 2 -and $i.present -and $v.present -and (Test-DmPlainText -Value $i.value -MaxLength 1024) -and (Test-DmVersionValue -Value $v.value)
                    if ($ok) { $entries.Add([pscustomobject][ordered]@{ identity = $i.value; version = $v.value }) }
                }
                if (-not $ok) { $problems.Add("reviewedDependencyVersions[$index] must carry exactly identity and version.") }
                $index++
            }
            $reviewedDependencyVersions = [object[]]$entries.ToArray()
        }
    }

    if ($declined.present) {
        if (-not (Test-DmPlainText -Value $declined.value)) { $problems.Add('declinedReviewId must be a non-empty string.') }
        if ($mode -cne 'apply') { $problems.Add('declinedReviewId is valid only with mode apply.') }
        if ($approved.present) { $problems.Add('declinedReviewId cannot be combined with approvedPreviewId.') }
        $declinedReviewId = $declined.value
    }

    $normalizedFields = [ordered]@{
        contractVersion            = $contractVersion
        requestId                  = $requestId
        operation                  = $operationName
        vaultRoot                  = $vaultRoot
        campaignGroup              = $campaignGroup
        mode                       = $mode
        arguments                  = $arguments
        targets                    = $targets
        approvedPreviewId          = $approvedPreviewId
        reviewedVersions           = $reviewedVersions
        reviewedDependencyVersions = $reviewedDependencyVersions
        declinedReviewId           = $declinedReviewId
        callerPreflight            = $callerPreflight
    }
    if ($authoringInputsField.present) {
        $normalizedFields.Insert(8, 'authoringInputs', $authoringInputs)
    }
    $normalized = [pscustomobject]$normalizedFields
    & $finish $normalized
}

function Register-DmBuiltInOperation {
    <#
    .SYNOPSIS
    Registers an operation and marks it as protected built-in functionality.
    .PARAMETER Parameters
    Hashtable of arguments accepted by Register-DmOperation.
    #>
    param([hashtable]$Parameters)
    $registration = Register-DmOperation @Parameters
    $registration.builtIn = $true
}

$articleContentBuilder = {
    param($CurrentText, $Arguments, $TargetPath)
    $null = $CurrentText
    $null = $TargetPath
    [string]$Arguments['content']
}

Register-DmBuiltInOperation -Parameters @{
    Name             = 'notes.inspect'
    Description      = 'Reports existence, type, and byte fingerprint of explicit vault-relative targets without reading content into the result.'
    Modes            = @('inspect')
    FactChanging     = $false
    AllowedArguments = @{}
    ChangeKind       = 'read'
    MinTargets       = 1
}

Register-DmBuiltInOperation -Parameters @{
    Name             = 'vault.orientation.inventory'
    Description      = 'Validates an explicit read-only orientation and inventory request without dispatching it.'
    Modes            = @('inspect')
    FactChanging     = $false
    AllowedArguments = [ordered]@{
        selectedGuidance = 'stringArray'
        optionalGuidance = 'stringArray'
        proposeProfile = 'boolean'
        mappingDecisions = 'mappingDecisions'
    }
    ChangeKind       = 'read'
    MinTargets       = 0
    MaxTargets       = 0
    RequiresMappings = $false
    RequiresCampaignGroup = $false
}

Register-DmBuiltInOperation -Parameters @{
    Name             = 'note.replace-text'
    Description      = 'Replaces every ordinal occurrence of oldText with newText in each target note.'
    Modes            = @('preview', 'apply')
    FactChanging     = $false
    AllowedArguments = [ordered]@{
        oldText = @{ type = 'string'; required = $true; allowEmpty = $false }
        newText = @{ type = 'string'; required = $true; allowEmpty = $true }
    }
    ChangeKind       = 'edit'
    MinTargets       = 1
    Builder          = {
        param($CurrentText, $Arguments, $TargetPath)
        $null = $TargetPath
        ([string]$CurrentText).Replace([string]$Arguments['oldText'], [string]$Arguments['newText'])
    }
}

Register-DmBuiltInOperation -Parameters @{
    Name             = 'note.create-article'
    Description      = 'Creates one new article at its explicitly supplied vault-relative destination.'
    Modes            = @('preview', 'apply')
    FactChanging     = $false
    AllowedArguments = [ordered]@{
        content = @{ type = 'string'; required = $true; allowEmpty = $false }
    }
    ChangeKind       = 'create'
    MinTargets       = 1
    MaxTargets       = 1
    RequiresMappings = $true
    RequiresCampaignGroup = $true
    PageLocalSafe    = $true
    Builder          = $articleContentBuilder
}

Register-DmBuiltInOperation -Parameters @{
    Name             = 'note.create-article-fact-change'
    Description      = 'Creates one new article whose content changes established campaign facts; requires exact preview approval.'
    Modes            = @('preview', 'apply')
    FactChanging     = $true
    AllowedArguments = [ordered]@{
        content = @{ type = 'string'; required = $true; allowEmpty = $false }
    }
    ChangeKind       = 'create'
    MinTargets       = 1
    MaxTargets       = 1
    RequiresMappings = $true
    RequiresCampaignGroup = $true
    Builder          = $articleContentBuilder
}

Export-ModuleMember -Function Register-DmOperation, Unregister-DmOperation, Get-DmOperation, Test-DmOperationRequest
