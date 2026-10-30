BeforeAll {
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force

# These are the proposed public preview/apply entry points. Keep the tests at
# that boundary so encoding policy is exercised through the complete workflow.
Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, VaultInspection, PluginResources, VaultConfiguration, ChangePreview, SafeNoteWriter, ApplyNoteChanges

function New-TestEncodedBytes {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][ValidateSet('utf8-bom', 'utf16-le', 'utf16-be', 'utf8')][string]$EncodingKind
    )
    $encoding = switch ($EncodingKind) {
        'utf8-bom' { [System.Text.UTF8Encoding]::new($true, $true) }
        'utf16-le' { [System.Text.UnicodeEncoding]::new($false, $true, $true) }
        'utf16-be' { [System.Text.UnicodeEncoding]::new($true, $true, $true) }
        'utf8' { [System.Text.UTF8Encoding]::new($false, $true) }
    }
    $body = $encoding.GetBytes($Text)
    if ($EncodingKind -eq 'utf8') { return ,$body }
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.AddRange([byte[]]$encoding.GetPreamble())
    $bytes.AddRange([byte[]]$body)
    ,$bytes.ToArray()
}

function Get-TestTargetBytes {
    param([Parameter(Mandatory)][string]$RelativePath)
    [System.IO.File]::ReadAllBytes((Join-Path -Path $script:fixture.Root -ChildPath ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
}

function New-TestEditRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('preview', 'apply')][string]$Mode,
        [Parameter(Mandatory)][string[]]$Targets,
        [Parameter(Mandatory)][string]$RequestId,
        [System.Collections.IDictionary]$Extra
    )
    $requestExtra = [ordered]@{ requestId = $RequestId }
    if ($null -ne $Extra) {
        foreach ($key in $Extra.Keys) { $requestExtra[$key] = $Extra[$key] }
    }
    New-TestOperationRequest -VaultRoot $script:fixture.Root -Operation 'note.replace-text' -Mode $Mode -Targets $Targets `
        -Arguments ([ordered]@{ oldText = 'Before'; newText = 'After' }) -Extra $requestExtra
}

}

Describe 'Encoding safety for note writes' {
    BeforeEach {
        $profile = @"
version: 1
guidance:
  path: .dmassist-guidance.md
"@
        $fixture = New-TestVaultFixture -ProfileText $profile -Notes ([ordered]@{
            'Notes/Target.md' = "Before`r`nKeep`n"
            'Notes/Second.md' = "Before`r`nKeep`n"
        })
        [System.IO.File]::WriteAllText(
            (Join-Path -Path $fixture.Root -ChildPath '.dmassist-guidance.md'),
            'Synthetic local guidance.',
            [System.Text.UTF8Encoding]::new($false)
        )
        $script:fixture = $fixture
        Set-TestDependencyReadiness -State ready
        Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
        $script:targetOne = 'Notes/Target.md'
        $script:targetTwo = 'Notes/Second.md'
    }

    AfterEach {
        Remove-TestVaultFixture -Fixture $fixture
    }

    It 'strictly round-trips BOM-marked UTF-8 and UTF-16, and BOM-less UTF-8 with original line endings' {
        $sourceText = "Before`r`nKeep`nLast`r"
        foreach ($encodingKind in @('utf8-bom', 'utf16-le', 'utf16-be', 'utf8')) {
            $inputBytes = New-TestEncodedBytes -Text $sourceText -EncodingKind $encodingKind
            [System.IO.File]::WriteAllBytes((Join-Path -Path $fixture.Root -ChildPath 'Notes\Target.md'), $inputBytes)
            $request = New-TestEditRequest -Mode apply -Targets @($script:targetOne) -RequestId "preserve-$encodingKind"

            $outcome = Invoke-DmApply -Request $request
            $outcome.result.completionStatus | Should -BeExactly 'complete'
            $outcome.result.completionCode | Should -BeIn @('OK', 'NO_CHANGES')
            $expectedBytes = New-TestEncodedBytes -Text ($sourceText.Replace('Before', 'After')) -EncodingKind $encodingKind
            $actualBytes = Get-TestTargetBytes -RelativePath $script:targetOne
            [System.Convert]::ToHexString($actualBytes) | Should -BeExactly ([System.Convert]::ToHexString($expectedBytes))
        }
    }

    It 'returns ENCODING_UNSAFE for undecodable bytes and preserves them byte-for-byte' {
        [byte[]]$undecodable = @(0xFF, 0xFE, 0x00, 0xD8, 0xFF)
        [System.IO.File]::WriteAllBytes((Join-Path -Path $fixture.Root -ChildPath 'Notes\Target.md'), $undecodable)
        $request = New-TestEditRequest -Mode apply -Targets @($script:targetOne) -RequestId 'undecodable'

        $outcome = Invoke-DmApply -Request $request
        $outcome.result.completionStatus | Should -BeExactly 'not completed'
        $outcome.result.completionCode | Should -BeExactly 'ENCODING_UNSAFE'
        [System.Convert]::ToHexString((Get-TestTargetBytes -RelativePath $script:targetOne)) |
            Should -BeExactly ([System.Convert]::ToHexString($undecodable))
    }

    It 'rejects a multi-target preview before any write when a later target is undecodable' {
        $firstOriginal = New-TestEncodedBytes -Text "Before`r`nKeep`n" -EncodingKind utf8
        [byte[]]$secondOriginal = @(0xFF, 0xFE, 0x00, 0xD8, 0xFF)
        [System.IO.File]::WriteAllBytes((Join-Path -Path $fixture.Root -ChildPath 'Notes\Target.md'), $firstOriginal)
        [System.IO.File]::WriteAllBytes((Join-Path -Path $fixture.Root -ChildPath 'Notes\Second.md'), $secondOriginal)
        $targets = [string[]]@($script:targetOne, $script:targetTwo)
        $preview = Invoke-DmPreview -Request (New-TestEditRequest -Mode preview -Targets $targets -RequestId 'multi-unsafe-preview')
        $preview.result.completionCode | Should -BeExactly 'ENCODING_UNSAFE'
        $preview.preview | Should -BeNullOrEmpty
        [System.Convert]::ToHexString((Get-TestTargetBytes -RelativePath $script:targetOne)) |
            Should -BeExactly ([System.Convert]::ToHexString($firstOriginal))
        [System.Convert]::ToHexString((Get-TestTargetBytes -RelativePath $script:targetTwo)) |
            Should -BeExactly ([System.Convert]::ToHexString($secondOriginal))
    }
}
