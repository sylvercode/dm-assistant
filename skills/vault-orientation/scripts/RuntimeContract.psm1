Set-StrictMode -Version Latest

# Module conventions shared by every script in this folder (audited by the
# static audit): use -LiteralPath for every filesystem cmdlet; never use
# Invoke-Expression, [scriptblock]::Create, or -Command/argument strings built
# from data; never install or upgrade modules; never reference the repository
# test folder; diagnostics never contain note content or absolute paths.

$script:DmContractVersion = '1'

$script:DmCompletionStatuses = @('complete', 'not completed', 'partially completed')

$script:DmCompletionCodes = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
foreach ($entry in @(
        @('OK', @('complete')),
        @('NO_CHANGES', @('complete')),
        @('PREREQUISITE_MISSING', @('not completed')),
        @('VAULT_AUTHORIZATION_UNPROVEN', @('not completed')),
        @('VAULT_TARGET_INVALID', @('not completed')),
        @('INVALID_REQUEST', @('not completed')),
        @('PATH_INVALID', @('not completed')),
        @('PATH_OUTSIDE_VAULT', @('not completed', 'partially completed')),
        @('RESOURCE_MISSING', @('not completed')),
        @('RESOURCE_INCOMPATIBLE', @('not completed')),
        @('PROFILE_PARSE_INVALID', @('not completed')),
        @('PROFILE_NORMALIZATION_INVALID', @('not completed')),
        @('PROFILE_SCHEMA_INVALID', @('not completed')),
        @('PROFILE_FILESYSTEM_INVALID', @('not completed')),
        @('REFERENCE_UNAVAILABLE', @('not completed')),
        @('AMBIGUOUS_CONTEXT', @('not completed')),
        @('CONFIRMATION_REQUIRED', @('not completed')),
        @('USER_CANCELLED', @('not completed')),
        @('ENCODING_UNSAFE', @('not completed')),
        @('TARGET_CONFLICT', @('not completed', 'partially completed')),
        @('READ_FAILED', @('not completed', 'partially completed')),
        @('WRITE_FAILED', @('not completed', 'partially completed')),
        @('INTERRUPTED', @('not completed', 'partially completed')),
        @('OPERATION_FAILED', @('not completed', 'partially completed'))
    )) {
    $script:DmCompletionCodes.Add($entry[0], [string[]]$entry[1])
}

$script:DmChangedOutcomes = @('written', 'deleted')
$script:DmUnchangedOutcomes = @('unchanged', 'conflict', 'failed', 'not attempted')
$script:DmResultFieldOrder = @('operation', 'completionStatus', 'completionCode', 'changedTargets', 'unchangedTargets', 'remainingWork', 'errorDetails')

function Get-DmContractVersion {
    <#
    .SYNOPSIS
    Returns the version of the shared operation-result contract.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $script:DmContractVersion
}

function Get-DmCompletionStatus {
    <#
    .SYNOPSIS
    Returns the allowed operation completion statuses in contract order.
    #>
    [CmdletBinding()]
    param()
    [string[]]$script:DmCompletionStatuses
}

function Get-DmCompletionCode {
    <#
    .SYNOPSIS
    Returns an ordered map of stable completion codes to their allowed statuses.
    #>
    [CmdletBinding()]
    param()
    $copy = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($key in $script:DmCompletionCodes.Keys) {
        $copy.Add($key, [string[]]$script:DmCompletionCodes[$key])
    }
    , $copy
}

function Get-DmTargetOutcome {
    <#
    .SYNOPSIS
    Returns the supported target outcomes, optionally filtered by change state.
    .PARAMETER Kind
    Selects All, Changed, or Unchanged outcomes; defaults to All.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'Changed', 'Unchanged')][string]$Kind = 'All'
    )
    switch ($Kind) {
        'Changed' { [string[]]$script:DmChangedOutcomes }
        'Unchanged' { [string[]]$script:DmUnchangedOutcomes }
        default { [string[]]($script:DmChangedOutcomes + $script:DmUnchangedOutcomes) }
    }
}

function Test-DmSafeText {
    <#
    .SYNOPSIS
    Checks diagnostic text for absolute path forms.
    .PARAMETER Text
    Text to check for drive, UNC, rooted, and file-URI paths; null is allowed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $true }
    if ($Text -match '(?i)(^|[\s"''(=:])[a-z]:[\\/]') { return $false }
    if ($Text -match '(^|[\s"''(=])\\\\[^\\\s]') { return $false }
    if ($Text -match '(^|[\s"''(=])/[^\s/]') { return $false }
    if ($Text -match '(?i)\bfile:/') { return $false }
    return $true
}

function Test-DmVaultRelativeText {
    <#
    .SYNOPSIS
    Checks whether a path is safe to retain as a vault-relative diagnostic.
    .DESCRIPTION
    Rejects absolute, traversal, wildcard, control-character, and malformed
    paths without interpreting punctuation that is legal in a path component.
    .PARAMETER Path
    Candidate path text; null, empty, rooted, drive, and URI forms are rejected.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path.StartsWith('/') -or $Path.Contains('\') -or $Path -match '^[A-Za-z]:' -or $Path -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or
        $Path -match '[\x00-\x1f\x7f*?\[\]]') { return $false }
    foreach ($component in $Path.Split('/')) {
        if ([string]::IsNullOrEmpty($component) -or $component -ceq '.' -or $component -ceq '..') { return $false }
    }
    return $true
}

function New-DmTargetRecord {
    <#
    .SYNOPSIS
    Creates a validated target record for a result envelope.
    .PARAMETER Path
    Vault-relative path identifying the target.
    .PARAMETER Outcome
    Contract target outcome, such as written, unchanged, failed, or not attempted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Outcome
    )
    if (-not (Test-DmVaultRelativeText -Path $Path)) {
        throw [System.ArgumentException]::new('A target record requires a vault-relative path.')
    }
    if ($Outcome -cnotin ($script:DmChangedOutcomes + $script:DmUnchangedOutcomes)) {
        throw [System.ArgumentException]::new("Unknown target outcome '$Outcome'.")
    }
    [pscustomobject][ordered]@{ path = $Path; outcome = $Outcome }
}

function ConvertTo-DmTargetRecordArray {
    <#
    .SYNOPSIS
    Converts paths and existing target records into validated target records.
    .PARAMETER Items
    Ordered collection of vault-relative strings or objects with path and outcome.
    .PARAMETER DefaultOutcome
    Outcome assigned to string entries; existing records keep their own outcome.
    #>
    param([AllowNull()][AllowEmptyCollection()][object[]]$Items, [string]$DefaultOutcome)
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            $list.Add((New-DmTargetRecord -Path $item -Outcome $DefaultOutcome))
        }
        else {
            $list.Add((New-DmTargetRecord -Path ([string]$item.path) -Outcome ([string]$item.outcome)))
        }
    }
    , [object[]]$list.ToArray()
}

function New-DmResult {
    <#
    .SYNOPSIS
    Builds and validates an ordered operation-result envelope.
    .DESCRIPTION
    Targets may be target records or plain vault-relative strings (strings in
    -ChangedTargets become 'written'; strings in -UnchangedTargets become
    'unchanged'). Supplying -ErrorMessage adds errorDetails with the same code.
    Throws when the envelope would violate the contract.
    .PARAMETER Operation
    Stable operation identifier for the result.
    .PARAMETER CompletionStatus
    Contract status: complete, not completed, or partially completed.
    .PARAMETER CompletionCode
    Stable completion code compatible with the supplied status.
    .PARAMETER ChangedTargets
    Ordered written or deleted target records, or paths defaulting to written.
    .PARAMETER UnchangedTargets
    Ordered unchanged, failed, conflict, or unattempted records, or unchanged paths.
    .PARAMETER RemainingWork
    Ordered work items still required to finish the operation.
    .PARAMETER ErrorMessage
    Safe diagnostic message included for an incomplete result.
    .PARAMETER ErrorDetail
    Optional safe diagnostic details; do not include note content or absolute paths.
    .PARAMETER RequestedTargets
    Optional complete target set used to validate the changed/unchanged partition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [Parameter(Mandatory)][string]$CompletionStatus,
        [Parameter(Mandatory)][string]$CompletionCode,
        [AllowNull()][AllowEmptyCollection()][object[]]$ChangedTargets = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$UnchangedTargets = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$RemainingWork = @(),
        [string]$ErrorMessage,
        [System.Collections.IDictionary]$ErrorDetail,
        [AllowEmptyCollection()][string[]]$RequestedTargets
    )
    $result = [ordered]@{
        operation        = $Operation
        completionStatus = $CompletionStatus
        completionCode   = $CompletionCode
        changedTargets   = (ConvertTo-DmTargetRecordArray -Items $ChangedTargets -DefaultOutcome 'written')
        unchangedTargets = (ConvertTo-DmTargetRecordArray -Items $UnchangedTargets -DefaultOutcome 'unchanged')
        remainingWork    = [object[]]@(@($RemainingWork) | Where-Object { $null -ne $_ })
    }
    if ($PSBoundParameters.ContainsKey('ErrorMessage') -or $PSBoundParameters.ContainsKey('ErrorDetail')) {
        $errorDetails = [ordered]@{ code = $CompletionCode; message = $ErrorMessage }
        if ($PSBoundParameters.ContainsKey('ErrorDetail') -and $null -ne $ErrorDetail) {
            $errorDetails['details'] = [pscustomobject]$ErrorDetail
        }
        $result['errorDetails'] = [pscustomobject]$errorDetails
    }
    $object = [pscustomobject]$result
    $validationArgs = @{ Result = $object }
    if ($PSBoundParameters.ContainsKey('RequestedTargets')) { $validationArgs['RequestedTargets'] = $RequestedTargets }
    $validation = Test-DmResult @validationArgs
    if (-not $validation.isValid) {
        throw [System.InvalidOperationException]::new('Invalid result envelope: ' + ($validation.errors -join '; '))
    }
    $object
}

function New-DmEntryPointResult {
    <#
    .SYNOPSIS
    Builds an entry-point result through the shared result contract.
    .DESCRIPTION
    This adapter derives completion
    status from whether any requested target changed and delegates the sole
    envelope construction to New-DmResult.
    .PARAMETER Operation
    Stable operation identifier; an empty identifier is reported as unknown.
    .PARAMETER State
    Entry-point state: Complete, Blocked, or Failure.
    .PARAMETER CompletionCode
    Optional stable code; defaults depend on state and whether targets changed.
    .PARAMETER Message
    Safe message for a blocked or failed operation.
    .PARAMETER Targets
    Ordered requested vault-relative targets used to validate the result.
    .PARAMETER ChangedTargets
    Ordered changed target records or paths.
    .PARAMETER UnchangedTargets
    Optional explicit unchanged records; otherwise derived from Targets and State.
    .PARAMETER RemainingWork
    Work items still required after an incomplete operation.
    .PARAMETER Details
    Optional safe diagnostic detail fields for an incomplete result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [Parameter(Mandatory)][ValidateSet('Complete', 'Blocked', 'Failure')][string]$State,
        [string]$CompletionCode,
        [string]$Message,
        [AllowEmptyCollection()][string[]]$Targets = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$ChangedTargets = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$UnchangedTargets,
        [AllowNull()][AllowEmptyCollection()][object[]]$RemainingWork = @(),
        [System.Collections.IDictionary]$Details
    )
    $changed = ConvertTo-DmTargetRecordArray -Items $ChangedTargets -DefaultOutcome 'written'
    $unchanged = [System.Collections.Generic.List[object]]::new()
    if ($PSBoundParameters.ContainsKey('UnchangedTargets')) {
        foreach ($target in (ConvertTo-DmTargetRecordArray -Items $UnchangedTargets -DefaultOutcome 'unchanged')) {
            $unchanged.Add($target)
        }
    }
    else {
        $changedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($target in $changed) { [void]$changedPaths.Add([string]$target.path) }
        foreach ($path in $Targets) {
            if (-not $changedPaths.Contains($path)) {
                $outcome = if ($State -ceq 'Blocked') { 'not attempted' } else { 'unchanged' }
                $unchanged.Add((New-DmTargetRecord -Path $path -Outcome $outcome))
            }
        }
    }
    $code = if ([string]::IsNullOrWhiteSpace($CompletionCode)) {
        if ($State -ceq 'Complete' -and $changed.Count -eq 0) { 'NO_CHANGES' }
        elseif ($State -ceq 'Complete') { 'OK' }
        else { 'OPERATION_FAILED' }
    }
    else { $CompletionCode }
    $status = if ($State -ceq 'Complete') { 'complete' } elseif ($changed.Count -gt 0) { 'partially completed' } else { 'not completed' }
    $allowed = $script:DmCompletionCodes[$code]
    if ($null -eq $allowed) { $code = 'OPERATION_FAILED'; $allowed = $script:DmCompletionCodes[$code] }
    if ($status -cnotin $allowed) {
        $code = 'OPERATION_FAILED'
        $status = if ($changed.Count -gt 0) { 'partially completed' } else { 'not completed' }
    }
    $args = @{
        Operation = $(if ([string]::IsNullOrWhiteSpace($Operation)) { 'unknown' } else { $Operation })
        CompletionStatus = $status
        CompletionCode = $code
        ChangedTargets = $changed
        UnchangedTargets = $unchanged.ToArray()
        RemainingWork = $RemainingWork
        RequestedTargets = $Targets
    }
    if ($status -cne 'complete') {
        $args.ErrorMessage = if ([string]::IsNullOrWhiteSpace($Message)) { "The operation did not complete ($code)." } else { $Message }
        if ($PSBoundParameters.ContainsKey('Details') -and $null -ne $Details) { $args.ErrorDetail = $Details }
    }
    New-DmResult @args
}

function New-DmBlockedResult {
    <#
    .SYNOPSIS
    Builds a result for a gate that stopped before any target was attempted.
    .DESCRIPTION
    The result is 'not completed'; every requested target is listed as
    'not attempted'.
    .PARAMETER Operation
    Stable operation identifier for the blocked request.
    .PARAMETER CompletionCode
    Contract code explaining why the gate blocked.
    .PARAMETER Message
    Safe diagnostic message describing the blocker.
    .PARAMETER Targets
    Requested vault-relative targets, reported as not attempted.
    .PARAMETER RemainingWork
    Optional next steps; defaults to resolving the reported completion code.
    .PARAMETER Detail
    Optional safe diagnostic detail fields.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Operation,
        [Parameter(Mandatory)][string]$CompletionCode,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][AllowEmptyCollection()][string[]]$Targets = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$RemainingWork,
        [System.Collections.IDictionary]$Detail
    )
    $unchanged = [System.Collections.Generic.List[object]]::new()
    foreach ($t in @($Targets)) {
        if ([string]::IsNullOrEmpty($t)) { continue }
        $unchanged.Add((New-DmTargetRecord -Path $t -Outcome 'not attempted'))
    }
    if ($null -eq $RemainingWork -or @($RemainingWork).Count -eq 0) {
        $RemainingWork = @("Resolve $CompletionCode, then retry the requested operation.")
    }
    $params = @{
        Operation = $Operation
        State = 'Blocked'
        CompletionCode = $CompletionCode
        Message = $Message
        Targets = $Targets
        UnchangedTargets = $unchanged.ToArray()
        RemainingWork = $RemainingWork
    }
    if ($PSBoundParameters.ContainsKey('Detail') -and $null -ne $Detail) { $params['Details'] = $Detail }
    New-DmEntryPointResult @params
}

function New-DmGateOutcome {
    <#
    .SYNOPSIS
    Creates a preflight gate outcome with optional non-content evidence.
    .DESCRIPTION
    Passed gates carry no result; blocked gates
    carry the contract result to return. Evidence entries are non-content
    records ([pscustomobject]@{ gate; subject; state; detail }).
    .PARAMETER Gate
    Identifier of the gate being reported.
    .PARAMETER Passed
    Whether the gate succeeded; false requires a blocked result.
    .PARAMETER Result
    Contract result for a blocked gate; must be null for a passed gate.
    .PARAMETER Evidence
    Ordered non-content evidence records collected by the gate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Gate,
        [Parameter(Mandatory)][bool]$Passed,
        [AllowNull()]$Result,
        [AllowNull()][AllowEmptyCollection()][object[]]$Evidence = @()
    )
    if ($Passed -and $null -ne $Result) { throw [System.ArgumentException]::new('A passed gate cannot carry a result.') }
    if (-not $Passed -and $null -eq $Result) { throw [System.ArgumentException]::new('A blocked gate requires a result.') }
    [pscustomobject][ordered]@{
        gate     = $Gate
        passed   = $Passed
        result   = $Result
        evidence = [object[]]@(@($Evidence) | Where-Object { $null -ne $_ })
    }
}

function New-DmEvidence {
    <#
    .SYNOPSIS
    Creates a non-content-bearing evidence record for a preflight gate.
    .PARAMETER Gate
    Identifier of the gate that produced the evidence.
    .PARAMETER Subject
    Dependency, requirement, or other item checked.
    .PARAMETER State
    Observed state of the subject.
    .PARAMETER Detail
    Optional non-content description of the observation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Gate,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$State,
        [string]$Detail = ''
    )
    [pscustomobject][ordered]@{ gate = $Gate; subject = $Subject; state = $State; detail = $Detail }
}

function Test-DmSafeDiagnosticValue {
    <#
    .SYNOPSIS
    Validates structured diagnostic data without treating paths as prose.
    .PARAMETER Value
    Optional scalar, collection, or object contained in error details.
    .PARAMETER FieldName
    Name of the containing structured field; targets and changed dependency
    identities use path validation.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Value, [string]$FieldName = '')
    if ($FieldName -ceq 'target') {
        return ($Value -is [string] -and (Test-DmVaultRelativeText -Path $Value))
    }
    if ($FieldName -ceq 'changedDependencies') {
        if ($Value -isnot [System.Collections.IList] -or $Value -is [string] -or $Value.Count -gt 64) { return $false }
        $identities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($identity in $Value) {
            if ($identity -isnot [string] -or $identity.Length -gt 512) { return $false }
            $isPluginResource = $identity.StartsWith('plugin:', [System.StringComparison]::Ordinal) -and
                (Test-DmVaultRelativeText -Path $identity.Substring(7))
            if (-not ($isPluginResource -or (Test-DmVaultRelativeText -Path $identity) -or $identity -ceq 'dependency-set') -or
                -not $identities.Add($identity)) { return $false }
        }
        return $true
    }
    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) { return (Test-DmSafeText -Text $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if (-not (Test-DmSafeDiagnosticValue -Value $Value[$key] -FieldName ([string]$key))) { return $false }
        }
        return $true
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if (-not (Test-DmSafeDiagnosticValue -Value $property.Value -FieldName $property.Name)) { return $false }
        }
        return $true
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if (-not (Test-DmSafeDiagnosticValue -Value $item -FieldName $FieldName)) { return $false }
        }
    }
    return $true
}

function Test-DmResult {
    <#
    .SYNOPSIS
    Validates an operation result against the shared contract.
    .DESCRIPTION
    Returns
    [pscustomobject]@{ isValid = [bool]; errors = [string[]] }.
    When -RequestedTargets is supplied, changedTargets and unchangedTargets must
    partition exactly that set.
    .PARAMETER Result
    Result object to validate, including field order, status, code, and details.
    .PARAMETER RequestedTargets
    Optional vault-relative target set that the result must partition exactly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Result,
        [AllowEmptyCollection()][string[]]$RequestedTargets
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $finish = { [pscustomobject][ordered]@{ isValid = ($errors.Count -eq 0); errors = [string[]]$errors.ToArray() } }

    if ($null -eq $Result -or $Result -isnot [System.Management.Automation.PSCustomObject]) {
        $errors.Add('Result must be an object.')
        return (& $finish)
    }
    $names = @($Result.PSObject.Properties.Name)
    $expected = @($script:DmResultFieldOrder[0..5])
    $hasError = $names -ccontains 'errorDetails'
    if ($hasError) { $expected += 'errorDetails' }
    if (($names -join '|') -cne ($expected -join '|')) {
        $errors.Add("Result fields must be exactly '$($expected -join ', ')' in order; found '$($names -join ', ')'.")
        return (& $finish)
    }

    $status = $Result.completionStatus
    $code = $Result.completionCode
    if ($status -isnot [string] -or $status -cnotin $script:DmCompletionStatuses) { $errors.Add("Unknown completionStatus '$status'.") }
    if ($code -isnot [string] -or -not $script:DmCompletionCodes.Contains($code)) {
        $errors.Add("Unknown completionCode '$code'.")
    }
    elseif ($status -cnotin $script:DmCompletionCodes[$code]) {
        $errors.Add("Code '$code' does not allow status '$status'.")
    }
    if ($Result.operation -isnot [string] -or [string]::IsNullOrWhiteSpace($Result.operation)) { $errors.Add('operation must be a non-empty string.') }

    foreach ($field in 'changedTargets', 'unchangedTargets', 'remainingWork') {
        $value = $Result.$field
        if ($null -eq $value -or $value -isnot [array]) { $errors.Add("$field must be an array.") }
    }
    if ($errors.Count -gt 0) { return (& $finish) }

    $changed = @($Result.changedTargets)
    $unchanged = @($Result.unchangedTargets)
    $remaining = @($Result.remainingWork)
    $paths = [System.Collections.Generic.List[string]]::new()
    $nonUnchangedOutcome = $false
    foreach ($pair in @(
            @{ list = $changed; allowed = $script:DmChangedOutcomes; name = 'changedTargets' },
            @{ list = $unchanged; allowed = $script:DmUnchangedOutcomes; name = 'unchangedTargets' })) {
        foreach ($record in $pair.list) {
            if ($null -eq $record -or $record -isnot [System.Management.Automation.PSCustomObject] -or (@($record.PSObject.Properties.Name) -join '|') -cne 'path|outcome') {
                $errors.Add("$($pair.name) entries must be target records with 'path' and 'outcome'.")
                continue
            }
            if (-not (Test-DmVaultRelativeText -Path $record.path)) { $errors.Add("$($pair.name) contains a path that is not vault-relative.") }
            if ($record.outcome -cnotin $pair.allowed) { $errors.Add("$($pair.name) contains outcome '$($record.outcome)', which is not allowed there.") }
            if ($pair.name -eq 'unchangedTargets' -and $record.outcome -cne 'unchanged') { $nonUnchangedOutcome = $true }
            $paths.Add([string]$record.path)
        }
    }
    $distinct = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($p in $paths) {
        if (-not $distinct.Add($p)) { $errors.Add("Target '$p' appears more than once across changedTargets and unchangedTargets.") }
    }
    if ($PSBoundParameters.ContainsKey('RequestedTargets')) {
        $requested = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($r in @($RequestedTargets)) { if ($null -ne $r) { [void]$requested.Add($r) } }
        if (-not $requested.SetEquals($distinct)) {
            $errors.Add('changedTargets and unchangedTargets must partition the requested targets.')
        }
    }

    switch ($status) {
        'complete' {
            if ($hasError) { $errors.Add('A complete result must not include errorDetails.') }
            if ($remaining.Count -gt 0) { $errors.Add('A complete result must not report remaining work.') }
            if ($nonUnchangedOutcome) { $errors.Add('A complete result cannot contain conflicted, failed, or unattempted targets.') }
            if ($code -ceq 'NO_CHANGES' -and $changed.Count -gt 0) { $errors.Add('NO_CHANGES cannot report changed targets.') }
        }
        'not completed' {
            if ($changed.Count -gt 0) { $errors.Add('A not completed result cannot report changed targets.') }
            if (-not $hasError) { $errors.Add('A not completed result requires errorDetails.') }
        }
        'partially completed' {
            if ($changed.Count -eq 0) { $errors.Add('A partially completed result requires at least one changed target.') }
            if (-not $hasError) { $errors.Add('A partially completed result requires errorDetails.') }
            if ($remaining.Count -eq 0) { $errors.Add('A partially completed result must report remaining work.') }
        }
    }

    if ($hasError) {
        $detail = $Result.errorDetails
        if ($null -eq $detail -or $detail -isnot [System.Management.Automation.PSCustomObject]) {
            $errors.Add('errorDetails must be an object.')
        }
        else {
            $detailNames = @($detail.PSObject.Properties.Name)
            $shapeOk = $detailNames.Count -ge 2 -and $detailNames[0] -ceq 'code' -and $detailNames[1] -ceq 'message' -and
                ($detailNames.Count -eq 2 -or ($detailNames.Count -eq 3 -and $detailNames[2] -ceq 'details'))
            if (-not $shapeOk) {
                $errors.Add('errorDetails must contain code, message, and optional details, in that order.')
            }
            else {
                if ($detail.code -cne $code) { $errors.Add('errorDetails.code must equal completionCode.') }
                if ($detail.message -isnot [string] -or [string]::IsNullOrWhiteSpace($detail.message)) {
                    $errors.Add('errorDetails.message must be a non-empty string.')
                }
            }
            if (-not (Test-DmSafeDiagnosticValue -Value $detail)) {
                $errors.Add('errorDetails must not contain absolute paths or invalid target paths.')
            }
        }
    }
    & $finish
}

Export-ModuleMember -Function Get-DmContractVersion, Get-DmCompletionStatus, Get-DmCompletionCode, Test-DmVaultRelativeText, Test-DmSafeText, Test-DmSafeDiagnosticValue, New-DmTargetRecord, New-DmResult, New-DmEntryPointResult, New-DmBlockedResult, Test-DmResult, New-DmGateOutcome, New-DmEvidence
