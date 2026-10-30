BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract

    $script:DiagnosticsModulePath = Join-Path -Path (Get-TestScriptsRoot) -ChildPath 'OperationDiagnostics.psm1'
    $script:DiagnosticsModuleAvailable = Test-Path -LiteralPath $script:DiagnosticsModulePath
    if ($script:DiagnosticsModuleAvailable) {
        Import-Module -Name $script:DiagnosticsModulePath -Force -Global
    }

    $script:SyntheticVaultRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'dmassist-diagnostics-test-vault'
    $script:SyntheticNotePath = Join-Path -Path $script:SyntheticVaultRoot -ChildPath 'Lore\Invented Note.md'
    $script:SyntheticNoteContent = @'
# Synthetic note
UNIQUE-DIAGNOSTIC-NOTE-CONTENT-DO-NOT-REPORT
Invented campaign details that must not appear in diagnostics.
'@
    $script:SyntheticRelativeTarget = 'Lore/Invented Note.md'
}

Describe 'OperationDiagnostics safe error details' {
    It 'provides the safe diagnostic helper' {
        $script:DiagnosticsModuleAvailable | Should -BeTrue -Because 'T037 supplies OperationDiagnostics.psm1'
        Get-Command -Name New-DmSafeDiagnostic -Module OperationDiagnostics -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty -Because 'New-DmSafeDiagnostic constructs sanitized contract errorDetails'
    }

    It 'omits synthetic note contents and absolute paths while preserving the vault-relative target' {
        if (-not $script:DiagnosticsModuleAvailable -or
            -not (Get-Command -Name New-DmSafeDiagnostic -Module OperationDiagnostics -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Waiting for the New-DmSafeDiagnostic API in T037'
            return
        }

        $unsafeDetails = [ordered]@{
            target      = $script:SyntheticRelativeTarget
            sourcePath  = $script:SyntheticNotePath
            noteContent = $script:SyntheticNoteContent
            reason      = 'Synthetic read failure.'
        }
        $errorDetails = New-DmSafeDiagnostic -Code 'READ_FAILED' `
            -Message "Could not read $($script:SyntheticNotePath): $($script:SyntheticNoteContent)" `
            -Details $unsafeDetails

        @($errorDetails.PSObject.Properties.Name) | Should -Be @('code', 'message', 'details')
        $errorDetails.code | Should -BeExactly 'READ_FAILED'
        $serialized = $errorDetails | ConvertTo-Json -Depth 10 -Compress
        $serialized | Should -Not -Match ([regex]::Escape($script:SyntheticNoteContent))
        $serialized | Should -Not -Match ([regex]::Escape($script:SyntheticVaultRoot))
        $serialized | Should -Not -Match ([regex]::Escape($script:SyntheticNotePath))
        $errorDetails.details.target | Should -BeExactly $script:SyntheticRelativeTarget
        @($errorDetails.details.PSObject.Properties.Name) | Should -Be @('target')

        $result = New-DmResult -Operation 'notes.inspect' -CompletionStatus 'not completed' `
            -CompletionCode $errorDetails.code `
            -UnchangedTargets @((New-DmTargetRecord -Path $script:SyntheticRelativeTarget -Outcome 'failed')) `
            -RemainingWork @('Retry inspection after resolving the read failure.') `
            -ErrorMessage $errorDetails.message -ErrorDetail ([ordered]@{ target = $errorDetails.details.target }) `
            -RequestedTargets @($script:SyntheticRelativeTarget)
        (Test-DmResult -Result $result -RequestedTargets @($script:SyntheticRelativeTarget)).isValid |
            Should -BeTrue
    }

    It 'validates diagnostic targets as paths and preserves legal punctuation' {
        $safe = New-DmSafeDiagnostic -Code 'READ_FAILED' -Details ([ordered]@{ target = 'Lore/Thing (draft).md' })
        $safe.details.target | Should -BeExactly 'Lore/Thing (draft).md'

        foreach ($invalidPath in @('C:/private/note.md', '../outside/note.md', 'Lore/*.md', 'Lore//note.md')) {
            $unsafe = New-DmSafeDiagnostic -Code 'READ_FAILED' -Details ([ordered]@{ target = $invalidPath })
            $unsafe.PSObject.Properties.Name | Should -Not -Contain 'details'
        }
    }

    It 'accepts legal path punctuation in the complete result envelope' {
        $target = 'Scenes(/Locked.md'
        $result = New-DmEntryPointResult -Operation 'notes.inspect' -State Failure -CompletionCode 'READ_FAILED' `
            -Targets @($target) -UnchangedTargets @((New-DmTargetRecord -Path $target -Outcome 'failed')) `
            -RemainingWork @("Inspect $target after restoring access.") -Message 'The target could not be read.' `
            -Details ([ordered]@{ target = $target })

        (Test-DmResult -Result $result -RequestedTargets @($target)).isValid | Should -BeTrue
        $result.errorDetails.details.target | Should -BeExactly $target
    }
}

Describe 'OperationDiagnostics local-only behavior' {
    It 'does not implement network requests or off-device telemetry sinks' {
        $script:DiagnosticsModuleAvailable | Should -BeTrue -Because 'T037 supplies OperationDiagnostics.psm1'
        if (-not $script:DiagnosticsModuleAvailable) { return }

        $source = [System.IO.File]::ReadAllText($script:DiagnosticsModulePath)
        $networkOrTelemetrySinks = '(?i)\b(?:Invoke-WebRequest|Invoke-RestMethod|Invoke-WebMethod|Start-BitsTransfer|HttpClient|WebClient|HttpWebRequest|WebRequest|Send-DmTelemetry|Send-DmUsageTelemetry|Upload-DmDiagnostics)\b|System\.Net\.'
        $source | Should -Not -Match $networkOrTelemetrySinks
    }
}
