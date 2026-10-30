BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract

    function New-RawResult {
        param([System.Collections.IDictionary]$Fields)
        [pscustomobject]$Fields
    }
    function New-Record { param($Path, $Outcome) [pscustomobject][ordered]@{ path = $Path; outcome = $Outcome } }
}

Describe 'RuntimeContract code taxonomy' {
    It 'defines exactly the three statuses' {
        Get-DmCompletionStatus | Should -Be @('complete', 'not completed', 'partially completed')
    }

    It 'defines exactly the 25 stable codes in contract order' {
        $codes = Get-DmCompletionCode
        @($codes.Keys) | Should -Be @(
            'OK', 'NO_CHANGES', 'PREREQUISITE_MISSING', 'VAULT_AUTHORIZATION_UNPROVEN', 'VAULT_TARGET_INVALID',
            'INVALID_REQUEST', 'PATH_INVALID', 'PATH_OUTSIDE_VAULT', 'RESOURCE_MISSING', 'RESOURCE_INCOMPATIBLE',
            'PROFILE_PARSE_INVALID', 'PROFILE_NORMALIZATION_INVALID', 'PROFILE_SCHEMA_INVALID', 'PROFILE_FILESYSTEM_INVALID',
            'REFERENCE_UNAVAILABLE', 'AMBIGUOUS_CONTEXT', 'CONFIRMATION_REQUIRED', 'USER_CANCELLED',
            'ENCODING_UNSAFE', 'TARGET_CONFLICT', 'READ_FAILED', 'WRITE_FAILED',
            'INTERRUPTED', 'OPERATION_FAILED')
    }

    It 'maps <Code> to exactly <Allowed>' -ForEach @(
        @{ Code = 'OK'; Allowed = @('complete') }
        @{ Code = 'NO_CHANGES'; Allowed = @('complete') }
        @{ Code = 'PREREQUISITE_MISSING'; Allowed = @('not completed') }
        @{ Code = 'VAULT_AUTHORIZATION_UNPROVEN'; Allowed = @('not completed') }
        @{ Code = 'VAULT_TARGET_INVALID'; Allowed = @('not completed') }
        @{ Code = 'INVALID_REQUEST'; Allowed = @('not completed') }
        @{ Code = 'PATH_INVALID'; Allowed = @('not completed') }
        @{ Code = 'PATH_OUTSIDE_VAULT'; Allowed = @('not completed', 'partially completed') }
        @{ Code = 'RESOURCE_MISSING'; Allowed = @('not completed') }
        @{ Code = 'RESOURCE_INCOMPATIBLE'; Allowed = @('not completed') }
        @{ Code = 'PROFILE_PARSE_INVALID'; Allowed = @('not completed') }
        @{ Code = 'PROFILE_NORMALIZATION_INVALID'; Allowed = @('not completed') }
        @{ Code = 'PROFILE_SCHEMA_INVALID'; Allowed = @('not completed') }
        @{ Code = 'PROFILE_FILESYSTEM_INVALID'; Allowed = @('not completed') }
        @{ Code = 'REFERENCE_UNAVAILABLE'; Allowed = @('not completed') }
        @{ Code = 'AMBIGUOUS_CONTEXT'; Allowed = @('not completed') }
        @{ Code = 'CONFIRMATION_REQUIRED'; Allowed = @('not completed') }
        @{ Code = 'USER_CANCELLED'; Allowed = @('not completed') }
        @{ Code = 'ENCODING_UNSAFE'; Allowed = @('not completed') }
        @{ Code = 'TARGET_CONFLICT'; Allowed = @('not completed', 'partially completed') }
        @{ Code = 'READ_FAILED'; Allowed = @('not completed', 'partially completed') }
        @{ Code = 'WRITE_FAILED'; Allowed = @('not completed', 'partially completed') }
        @{ Code = 'INTERRUPTED'; Allowed = @('not completed', 'partially completed') }
        @{ Code = 'OPERATION_FAILED'; Allowed = @('not completed', 'partially completed') }
    ) {
        (Get-DmCompletionCode)[$Code] | Should -Be $Allowed
        foreach ($status in Get-DmCompletionStatus) {
            $fields = [ordered]@{
                operation        = 'test.op'
                completionStatus = $status
                completionCode   = $Code
                changedTargets   = @()
                unchangedTargets = @()
                remainingWork    = @()
            }
            if ($status -eq 'partially completed') {
                $fields.changedTargets = @(New-Record 'a.md' 'written')
                $fields.unchangedTargets = @(New-Record 'b.md' 'not attempted')
                $fields.remainingWork = @('b.md')
            }
            if ($status -ne 'complete') { $fields['errorDetails'] = [pscustomobject][ordered]@{ code = $Code; message = 'Safe message.' } }
            (Test-DmResult -Result (New-RawResult $fields)).isValid | Should -Be ($Allowed -contains $status) -Because "$Code with $status"
        }
    }

    It 'rejects unknown and wrongly cased codes and statuses' {
        foreach ($pair in @(@('ok', 'complete'), @('UNKNOWN', 'not completed'), @('OK', 'Complete'), @('OK', 'done'))) {
            $fields = [ordered]@{ operation = 'x'; completionStatus = $pair[1]; completionCode = $pair[0]; changedTargets = @(); unchangedTargets = @(); remainingWork = @() }
            (Test-DmResult -Result (New-RawResult $fields)).isValid | Should -BeFalse
        }
    }
}

Describe 'RuntimeContract result field order' {
    It 'produces fields in the exact contract order without errorDetails on success' {
        $r = New-DmResult -Operation 'notes.inspect' -CompletionStatus 'complete' -CompletionCode 'OK' -UnchangedTargets @('a.md')
        @($r.PSObject.Properties.Name) | Should -Be @('operation', 'completionStatus', 'completionCode', 'changedTargets', 'unchangedTargets', 'remainingWork')
    }

    It 'appends errorDetails last with code, message, and optional details' {
        $r = New-DmResult -Operation 'x' -CompletionStatus 'not completed' -CompletionCode 'PATH_INVALID' -UnchangedTargets @((New-DmTargetRecord -Path 'a.md' -Outcome 'not attempted')) -RemainingWork @('fix path') -ErrorMessage 'Path is invalid.' -ErrorDetail ([ordered]@{ target = 'a.md' })
        @($r.PSObject.Properties.Name)[-1] | Should -Be 'errorDetails'
        @($r.errorDetails.PSObject.Properties.Name) | Should -Be @('code', 'message', 'details')
        $r.errorDetails.code | Should -BeExactly 'PATH_INVALID'
        $r.errorDetails.details.target | Should -Be 'a.md'
    }

    It 'rejects reordered, missing, or extra fields' {
        $reordered = [ordered]@{ completionStatus = 'complete'; operation = 'x'; completionCode = 'OK'; changedTargets = @(); unchangedTargets = @(); remainingWork = @() }
        $missing = [ordered]@{ operation = 'x'; completionStatus = 'complete'; completionCode = 'OK'; changedTargets = @(); unchangedTargets = @() }
        $extra = [ordered]@{ operation = 'x'; completionStatus = 'complete'; completionCode = 'OK'; changedTargets = @(); unchangedTargets = @(); remainingWork = @(); note = 'x' }
        foreach ($f in $reordered, $missing, $extra) { (Test-DmResult -Result (New-RawResult $f)).isValid | Should -BeFalse }
    }

    It 'rejects non-array target and remaining-work fields' {
        $f = [ordered]@{ operation = 'x'; completionStatus = 'complete'; completionCode = 'OK'; changedTargets = 'a.md'; unchangedTargets = @(); remainingWork = @() }
        (Test-DmResult -Result (New-RawResult $f)).isValid | Should -BeFalse
    }
}

Describe 'RuntimeContract target records and partition' {
    It 'accepts each documented outcome' -ForEach @(
        @{ Outcome = 'written' }, @{ Outcome = 'deleted' }, @{ Outcome = 'unchanged' },
        @{ Outcome = 'conflict' }, @{ Outcome = 'failed' }, @{ Outcome = 'not attempted' }
    ) {
        $rec = New-DmTargetRecord -Path 'Notes/a.md' -Outcome $Outcome
        @($rec.PSObject.Properties.Name) | Should -Be @('path', 'outcome')
        $rec.outcome | Should -BeExactly $Outcome
    }

    It 'rejects unknown outcomes and non-vault-relative paths' {
        { New-DmTargetRecord -Path 'a.md' -Outcome 'skipped' } | Should -Throw
        { New-DmTargetRecord -Path '/abs/a.md' -Outcome 'written' } | Should -Throw
        { New-DmTargetRecord -Path 'C:\a.md' -Outcome 'written' } | Should -Throw
        { New-DmTargetRecord -Path 'dir\a.md' -Outcome 'written' } | Should -Throw
    }

    It 'rejects changed outcomes in unchangedTargets and unchanged outcomes in changedTargets' {
        $a = [ordered]@{ operation = 'x'; completionStatus = 'complete'; completionCode = 'OK'; changedTargets = @(New-Record 'a.md' 'unchanged'); unchangedTargets = @(); remainingWork = @() }
        $b = [ordered]@{ operation = 'x'; completionStatus = 'complete'; completionCode = 'OK'; changedTargets = @(); unchangedTargets = @(New-Record 'a.md' 'written'); remainingWork = @() }
        (Test-DmResult -Result (New-RawResult $a)).isValid | Should -BeFalse
        (Test-DmResult -Result (New-RawResult $b)).isValid | Should -BeFalse
    }

    It 'accepts an exact partition of requested targets' {
        $r = New-DmResult -Operation 'x' -CompletionStatus 'partially completed' -CompletionCode 'WRITE_FAILED' `
            -ChangedTargets @('a.md') `
            -UnchangedTargets @((New-DmTargetRecord -Path 'b.md' -Outcome 'failed'), (New-DmTargetRecord -Path 'c.md' -Outcome 'not attempted')) `
            -RemainingWork @('b.md', 'c.md') -ErrorMessage 'Write failed.' -RequestedTargets @('a.md', 'b.md', 'c.md')
        $r.changedTargets[0].outcome | Should -BeExactly 'written'
        (Test-DmResult -Result $r -RequestedTargets @('a.md', 'b.md', 'c.md')).isValid | Should -BeTrue
    }

    It 'rejects a missing, extra, or duplicated target' {
        $r = New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'NO_CHANGES' -UnchangedTargets @('a.md', 'b.md')
        (Test-DmResult -Result $r -RequestedTargets @('a.md', 'b.md', 'c.md')).isValid | Should -BeFalse
        (Test-DmResult -Result $r -RequestedTargets @('a.md')).isValid | Should -BeFalse
        $dup = [ordered]@{ operation = 'x'; completionStatus = 'partially completed'; completionCode = 'WRITE_FAILED'; changedTargets = @(New-Record 'a.md' 'written'); unchangedTargets = @(New-Record 'a.md' 'failed'); remainingWork = @('a'); errorDetails = [pscustomobject][ordered]@{ code = 'WRITE_FAILED'; message = 'm' } }
        (Test-DmResult -Result (New-RawResult $dup)).isValid | Should -BeFalse
        { New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'OK' -UnchangedTargets @('a.md') -RequestedTargets @('a.md', 'b.md') } | Should -Throw
    }

    It 'uses empty arrays for a no-target operation' {
        $r = New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'NO_CHANGES' -RequestedTargets @()
        $r.changedTargets.Count | Should -Be 0
        $r.unchangedTargets.Count | Should -Be 0
        $r.remainingWork.Count | Should -Be 0
        , $r.changedTargets | Should -BeOfType [object[]]
    }
}

Describe 'RuntimeContract completion rules' {
    It 'rejects complete with remaining work, errorDetails, or unfinished targets' {
        { New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'OK' -RemainingWork @('more') } | Should -Throw
        { New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'OK' -ErrorMessage 'oops' } | Should -Throw
        foreach ($o in 'conflict', 'failed', 'not attempted') {
            { New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'OK' -UnchangedTargets @((New-DmTargetRecord -Path 'a.md' -Outcome $o)) } | Should -Throw
        }
    }

    It 'rejects NO_CHANGES with changed targets' {
        { New-DmResult -Operation 'x' -CompletionStatus 'complete' -CompletionCode 'NO_CHANGES' -ChangedTargets @('a.md') } | Should -Throw
    }

    It 'rejects not completed with changed targets or without errorDetails' {
        { New-DmResult -Operation 'x' -CompletionStatus 'not completed' -CompletionCode 'WRITE_FAILED' -ChangedTargets @('a.md') -ErrorMessage 'm' } | Should -Throw
        { New-DmResult -Operation 'x' -CompletionStatus 'not completed' -CompletionCode 'WRITE_FAILED' } | Should -Throw
    }

    It 'requires a changed target and remaining work for partially completed' {
        { New-DmResult -Operation 'x' -CompletionStatus 'partially completed' -CompletionCode 'WRITE_FAILED' -UnchangedTargets @((New-DmTargetRecord -Path 'b.md' -Outcome 'failed')) -RemainingWork @('b') -ErrorMessage 'm' } | Should -Throw
        { New-DmResult -Operation 'x' -CompletionStatus 'partially completed' -CompletionCode 'WRITE_FAILED' -ChangedTargets @('a.md') -ErrorMessage 'm' } | Should -Throw
    }
}

Describe 'RuntimeContract safe error details' {
    It 'requires errorDetails.code to equal completionCode' {
        $f = [ordered]@{ operation = 'x'; completionStatus = 'not completed'; completionCode = 'PATH_INVALID'; changedTargets = @(); unchangedTargets = @(); remainingWork = @(); errorDetails = [pscustomobject][ordered]@{ code = 'READ_FAILED'; message = 'm' } }
        (Test-DmResult -Result (New-RawResult $f)).isValid | Should -BeFalse
    }

    It 'requires a non-empty message and no unknown error fields' {
        $empty = [ordered]@{ operation = 'x'; completionStatus = 'not completed'; completionCode = 'PATH_INVALID'; changedTargets = @(); unchangedTargets = @(); remainingWork = @(); errorDetails = [pscustomobject][ordered]@{ code = 'PATH_INVALID'; message = ' ' } }
        $extra = [ordered]@{ operation = 'x'; completionStatus = 'not completed'; completionCode = 'PATH_INVALID'; changedTargets = @(); unchangedTargets = @(); remainingWork = @(); errorDetails = [pscustomobject][ordered]@{ code = 'PATH_INVALID'; message = 'm'; stack = 'trace' } }
        (Test-DmResult -Result (New-RawResult $empty)).isValid | Should -BeFalse
        (Test-DmResult -Result (New-RawResult $extra)).isValid | Should -BeFalse
    }

    It 'rejects absolute paths in error messages or details: <Text>' -ForEach @(
        @{ Text = 'Failed at C:\Users\dm\vault\a.md' }
        @{ Text = 'Failed at /home/dm/vault/a.md' }
        @{ Text = 'Failed at \\server\share\a.md' }
        @{ Text = 'Failed at file:///tmp/a.md' }
    ) {
        { New-DmResult -Operation 'x' -CompletionStatus 'not completed' -CompletionCode 'READ_FAILED' -ErrorMessage $Text } | Should -Throw
        { New-DmResult -Operation 'x' -CompletionStatus 'not completed' -CompletionCode 'READ_FAILED' -ErrorMessage 'Read failed.' -ErrorDetail @{ where = $Text } } | Should -Throw
    }

    It 'allows vault-relative paths in details' {
        $r = New-DmResult -Operation 'x' -CompletionStatus 'not completed' -CompletionCode 'READ_FAILED' -ErrorMessage 'Read failed for a vault note.' -ErrorDetail @{ target = 'Lore/Invented Town.md' }
        (Test-DmResult -Result $r).isValid | Should -BeTrue
    }

    It 'builds blocked results with every target not attempted' {
        $r = New-DmBlockedResult -Operation 'notes.inspect' -CompletionCode 'VAULT_AUTHORIZATION_UNPROVEN' -Message 'Exact-vault authorization is unproven.' -Targets @('a.md', 'b.md')
        $r.completionStatus | Should -BeExactly 'not completed'
        $r.changedTargets.Count | Should -Be 0
        @($r.unchangedTargets.outcome) | Should -Be @('not attempted', 'not attempted')
        $r.remainingWork.Count | Should -BeGreaterThan 0
        (Test-DmResult -Result $r -RequestedTargets @('a.md', 'b.md')).isValid | Should -BeTrue
    }

    It 'rejects a non-object result' {
        (Test-DmResult -Result $null).isValid | Should -BeFalse
        (Test-DmResult -Result @{ operation = 'x' }).isValid | Should -BeFalse
    }
}
