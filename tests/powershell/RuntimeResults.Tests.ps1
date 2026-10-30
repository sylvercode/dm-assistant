BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, VaultInspection, PluginResources, VaultConfiguration, SafeNoteWriter, ChangePreview, ApplyNoteChanges

    function New-RawResult {
        param([System.Collections.IDictionary]$Fields)
        [pscustomobject]$Fields
    }

    function New-ResultRecord {
        param([string]$Path, [string]$Outcome)
        [pscustomobject][ordered]@{ path = $Path; outcome = $Outcome }
    }

    function New-StatusCase {
        param([string]$Operation, [string]$Code, [string]$Status)

        $fields = [ordered]@{
            operation        = $Operation
            completionStatus = $Status
            completionCode   = $Code
            changedTargets   = @()
            unchangedTargets = @()
            remainingWork    = @()
        }

        switch ($Status) {
            'complete' {
                if ($Code -ceq 'NO_CHANGES') {
                    $fields.unchangedTargets = @(
                        (New-ResultRecord 'alpha.md' 'unchanged'),
                        (New-ResultRecord 'beta.md' 'unchanged')
                    )
                }
                else {
                    $fields.changedTargets = @(New-ResultRecord 'alpha.md' 'written')
                    $fields.unchangedTargets = @(New-ResultRecord 'beta.md' 'unchanged')
                }
            }
            'not completed' {
                $fields.unchangedTargets = @(
                    (New-ResultRecord 'alpha.md' 'not attempted'),
                    (New-ResultRecord 'beta.md' 'not attempted')
                )
                $fields.remainingWork = @('alpha.md', 'beta.md')
                $fields['errorDetails'] = [pscustomobject][ordered]@{
                    code    = $Code
                    message = 'The requested operation could not complete.'
                    details = [pscustomobject][ordered]@{ target = 'alpha.md' }
                }
            }
            'partially completed' {
                $fields.changedTargets = @(New-ResultRecord 'alpha.md' 'written')
                $fields.unchangedTargets = @(New-ResultRecord 'beta.md' 'failed')
                $fields.remainingWork = @('beta.md')
                $fields['errorDetails'] = [pscustomobject][ordered]@{
                    code    = $Code
                    message = 'The operation stopped after an earlier target changed.'
                    details = [pscustomobject][ordered]@{ target = 'beta.md' }
                }
            }
        }

        New-RawResult $fields
    }
}

Describe 'Runtime result code and status contract' {
    It 'accepts every allowed status and rejects every disallowed status for <Code>' -ForEach @(
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
        $taxonomy = Get-DmCompletionCode
        $taxonomy[$Code] | Should -Be $Allowed

        foreach ($status in Get-DmCompletionStatus) {
            $candidate = New-StatusCase -Operation 'notes.synthetic' -Code $Code -Status $status
            (Test-DmResult -Result $candidate -RequestedTargets @('alpha.md', 'beta.md')).isValid |
                Should -Be ($Allowed -ccontains $status) -Because "$Code with $status"
        }
    }

    It 'allows partial status only with a changed target and remaining work' {
        foreach ($code in 'PATH_OUTSIDE_VAULT', 'TARGET_CONFLICT', 'READ_FAILED', 'WRITE_FAILED', 'INTERRUPTED', 'OPERATION_FAILED') {
            { New-DmResult -Operation 'notes.synthetic' -CompletionStatus 'partially completed' -CompletionCode $code `
                    -UnchangedTargets @((New-DmTargetRecord -Path 'beta.md' -Outcome 'failed')) `
                    -RemainingWork @('beta.md') -ErrorMessage 'Operation stopped safely.' } | Should -Throw

            $partial = New-DmResult -Operation 'notes.synthetic' -CompletionStatus 'partially completed' -CompletionCode $code `
                -ChangedTargets @('alpha.md') `
                -UnchangedTargets @((New-DmTargetRecord -Path 'beta.md' -Outcome 'not attempted')) `
                -RemainingWork @('beta.md') -ErrorMessage 'Operation stopped safely.' `
                -RequestedTargets @('alpha.md', 'beta.md')
            $partial.completionStatus | Should -BeExactly 'partially completed'
            (Test-DmResult -Result $partial -RequestedTargets @('alpha.md', 'beta.md')).isValid | Should -BeTrue
        }
    }
}

Describe 'Runtime result envelope ordering and target lists' {
    It 'keeps the result and diagnostic fields in contract order' {
        $success = New-DmResult -Operation 'notes.inspect' -CompletionStatus 'complete' -CompletionCode 'OK' `
            -ChangedTargets @('alpha.md') -UnchangedTargets @('beta.md')
        @($success.PSObject.Properties.Name) | Should -Be @(
            'operation', 'completionStatus', 'completionCode', 'changedTargets', 'unchangedTargets', 'remainingWork'
        )

        $blocked = New-DmBlockedResult -Operation 'notes.inspect' -CompletionCode 'INVALID_REQUEST' `
            -Message 'The request is invalid.' -Targets @('second.md', 'first.md') `
            -RemainingWork @('second.md', 'first.md')
        @($blocked.PSObject.Properties.Name) | Should -Be @(
            'operation', 'completionStatus', 'completionCode', 'changedTargets', 'unchangedTargets', 'remainingWork', 'errorDetails'
        )
        @($blocked.errorDetails.PSObject.Properties.Name) | Should -Be @('code', 'message')
        $blocked.errorDetails.code | Should -BeExactly $blocked.completionCode
    }

    It 'preserves deterministic target and remaining-work order' {
        $result = New-DmResult -Operation 'notes.apply' -CompletionStatus 'partially completed' -CompletionCode 'WRITE_FAILED' `
            -ChangedTargets @('third.md', 'first.md') `
            -UnchangedTargets @(
                (New-DmTargetRecord -Path 'fourth.md' -Outcome 'failed'),
                (New-DmTargetRecord -Path 'second.md' -Outcome 'not attempted')
            ) `
            -RemainingWork @('fourth.md', 'second.md') `
            -ErrorMessage 'The operation stopped after a write failure.' `
            -RequestedTargets @('third.md', 'first.md', 'fourth.md', 'second.md')

        @($result.changedTargets.path) | Should -Be @('third.md', 'first.md')
        @($result.changedTargets.outcome) | Should -Be @('written', 'written')
        @($result.unchangedTargets.path) | Should -Be @('fourth.md', 'second.md')
        @($result.unchangedTargets.outcome) | Should -Be @('failed', 'not attempted')
        @($result.remainingWork) | Should -Be @('fourth.md', 'second.md')
        (Test-DmResult -Result $result -RequestedTargets @('third.md', 'first.md', 'fourth.md', 'second.md')).isValid |
            Should -BeTrue
    }
}

Describe 'Runtime result target partition and incomplete results' {
    It 'requires changed and unchanged targets to partition the request exactly' {
        $partition = New-DmResult -Operation 'notes.apply' -CompletionStatus 'complete' -CompletionCode 'OK' `
            -ChangedTargets @('alpha.md') -UnchangedTargets @('beta.md') `
            -RequestedTargets @('alpha.md', 'beta.md')
        (Test-DmResult -Result $partition -RequestedTargets @('alpha.md', 'beta.md')).isValid | Should -BeTrue

        (Test-DmResult -Result $partition -RequestedTargets @('alpha.md', 'beta.md', 'missing.md')).isValid |
            Should -BeFalse
        (Test-DmResult -Result $partition -RequestedTargets @('alpha.md')).isValid | Should -BeFalse

        $duplicate = [ordered]@{
            operation        = 'notes.apply'
            completionStatus = 'partially completed'
            completionCode   = 'WRITE_FAILED'
            changedTargets   = @(New-ResultRecord 'alpha.md' 'written')
            unchangedTargets = @(New-ResultRecord 'alpha.md' 'failed')
            remainingWork    = @('alpha.md')
            errorDetails     = [pscustomobject][ordered]@{ code = 'WRITE_FAILED'; message = 'Write failed safely.' }
        }
        (Test-DmResult -Result (New-RawResult $duplicate) -RequestedTargets @('alpha.md')).isValid | Should -BeFalse
    }

    It 'rejects incomplete results labeled complete at each shared entry point' {
        foreach ($operation in 'runtime.preflight', 'notes.inspect', 'notes.preview', 'notes.apply') {
            $withRemainingWork = [ordered]@{
                operation        = $operation
                completionStatus = 'complete'
                completionCode   = 'OK'
                changedTargets   = @()
                unchangedTargets = @(New-ResultRecord 'alpha.md' 'unchanged')
                remainingWork    = @('alpha.md')
            }
            (Test-DmResult -Result (New-RawResult $withRemainingWork) -RequestedTargets @('alpha.md')).isValid |
                Should -BeFalse -Because "$operation must not report incomplete work as complete"

            $withError = [ordered]@{
                operation        = $operation
                completionStatus = 'complete'
                completionCode   = 'OK'
                changedTargets   = @()
                unchangedTargets = @(New-ResultRecord 'alpha.md' 'unchanged')
                remainingWork    = @()
                errorDetails     = [pscustomobject][ordered]@{ code = 'OK'; message = 'An error occurred.' }
            }
            (Test-DmResult -Result (New-RawResult $withError) -RequestedTargets @('alpha.md')).isValid |
                Should -BeFalse -Because "$operation must not attach an error to a complete result"

            { New-DmResult -Operation $operation -CompletionStatus 'complete' -CompletionCode 'OK' `
                    -UnchangedTargets @('alpha.md') -RemainingWork @('alpha.md') } | Should -Throw
            { New-DmResult -Operation $operation -CompletionStatus 'complete' -CompletionCode 'WRITE_FAILED' `
                    -UnchangedTargets @('alpha.md') } | Should -Throw
        }
    }

    It 'uses empty arrays for an operation with no targets' {
        $result = New-DmResult -Operation 'notes.inspect' -CompletionStatus 'complete' -CompletionCode 'NO_CHANGES' `
            -RequestedTargets @()
        $result.changedTargets.Count | Should -Be 0
        $result.unchangedTargets.Count | Should -Be 0
        $result.remainingWork.Count | Should -Be 0
        (Test-DmResult -Result $result -RequestedTargets @()).isValid | Should -BeTrue
    }

    It 'keeps every public entry point from reporting malformed requests as complete' {
        $request = [ordered]@{}
        $outcomes = [ordered]@{
            preflight = Invoke-DmPreflight -Request $request
            inspect   = Invoke-DmInspect -Request $request
            preview   = Invoke-DmPreview -Request $request
            apply     = Invoke-DmApply -Request $request
        }
        foreach ($name in $outcomes.Keys) {
            $result = $outcomes[$name].result
            $result.completionStatus | Should -BeExactly 'not completed' -Because $name
            $result.completionCode | Should -BeExactly 'INVALID_REQUEST' -Because $name
            (Test-DmResult -Result $result).isValid | Should -BeTrue -Because $name
        }
    }

    It 'rejects incomplete complete results from the shared adapter' {
        foreach ($operation in 'runtime.preflight', 'notes.inspect', 'notes.preview', 'notes.apply') {
            {
                New-DmEntryPointResult -Operation $operation -State Complete -Targets @('alpha.md') `
                    -RemainingWork @('alpha.md')
            } | Should -Throw -Because $operation
        }
    }
}

Describe 'Runtime result safe diagnostics' {
    It 'accepts safe vault-relative error details and preserves the cause code' {
        $result = New-DmResult -Operation 'notes.inspect' -CompletionStatus 'not completed' -CompletionCode 'READ_FAILED' `
            -UnchangedTargets @((New-DmTargetRecord -Path 'Lore/Invented Town.md' -Outcome 'not attempted')) `
            -RemainingWork @('Lore/Invented Town.md') -ErrorMessage 'The requested note could not be read.' `
            -ErrorDetail ([ordered]@{ target = 'Lore/Invented Town.md'; state = 'unavailable' }) `
            -RequestedTargets @('Lore/Invented Town.md')

        $result.errorDetails.code | Should -BeExactly 'READ_FAILED'
        (Test-DmResult -Result $result -RequestedTargets @('Lore/Invented Town.md')).isValid | Should -BeTrue
    }

    It 'rejects absolute paths in messages and nested diagnostic details' -ForEach @(
        @{ Text = 'Read failed at C:\Users\dm\vault\a.md' }
        @{ Text = 'Read failed at /home/dm/vault/a.md' }
        @{ Text = 'Read failed at \\server\share\a.md' }
        @{ Text = 'Read failed at file:///vault/a.md' }
    ) {
        { New-DmResult -Operation 'notes.inspect' -CompletionStatus 'not completed' -CompletionCode 'READ_FAILED' `
                -ErrorMessage $Text } | Should -Throw
        { New-DmResult -Operation 'notes.inspect' -CompletionStatus 'not completed' -CompletionCode 'READ_FAILED' `
                -ErrorMessage 'The requested note could not be read.' -ErrorDetail ([ordered]@{ context = @{ location = $Text } }) } |
            Should -Throw
    }

    It 'rejects a mismatched diagnostic code and an empty diagnostic message' {
        $mismatched = [ordered]@{
            operation        = 'notes.inspect'
            completionStatus = 'not completed'
            completionCode   = 'READ_FAILED'
            changedTargets   = @()
            unchangedTargets = @()
            remainingWork    = @('retry')
            errorDetails     = [pscustomobject][ordered]@{ code = 'OPERATION_FAILED'; message = 'Read failed safely.' }
        }
        $emptyMessage = [ordered]@{
            operation        = 'notes.inspect'
            completionStatus = 'not completed'
            completionCode   = 'READ_FAILED'
            changedTargets   = @()
            unchangedTargets = @()
            remainingWork    = @('retry')
            errorDetails     = [pscustomobject][ordered]@{ code = 'READ_FAILED'; message = ' ' }
        }
        (Test-DmResult -Result (New-RawResult $mismatched)).isValid | Should -BeFalse
        (Test-DmResult -Result (New-RawResult $emptyMessage)).isValid | Should -BeFalse
    }
}
