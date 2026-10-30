BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
}

Describe 'Test vault fixture ownership' {
    It 'removes only its generated fixture directory and preserves the caller parent' {
        $parent = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($parent)
        $sentinel = Join-Path $parent 'caller-owned.txt'
        [System.IO.File]::WriteAllText($sentinel, 'preserve')
        $fixture = New-TestVaultFixture -ParentPath $parent
        $owned = [string]$fixture.OwnedDirectory

        Remove-TestVaultFixture -Fixture $fixture

        Test-Path -LiteralPath $owned | Should -BeFalse
        Test-Path -LiteralPath $parent | Should -BeTrue
        [System.IO.File]::ReadAllText($sentinel) | Should -BeExactly 'preserve'
    }

    It 'refuses cleanup when the fixture does not name a direct unique child' {
        $parent = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($parent)
        $fixture = [pscustomobject]@{
            OwnershipParentPath = [System.IO.Path]::GetDirectoryName($parent)
            OwnedDirectory = $parent
        }

        { Remove-TestVaultFixture -Fixture $fixture } | Should -Throw
        Test-Path -LiteralPath $parent | Should -BeTrue
    }

    It 'rejects fixture names that escape their uniquely owned directory' {
        $parent = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($parent)
        $sentinel = Join-Path $parent 'caller-owned.txt'
        [System.IO.File]::WriteAllText($sentinel, 'preserve')

        { New-TestVaultFixture -ParentPath $parent -Name '..\..\real-vault' } | Should -Throw

        [System.IO.File]::ReadAllText($sentinel) | Should -BeExactly 'preserve'
        @(Get-ChildItem -LiteralPath $parent -Force).Count | Should -Be 1
    }

    It 'rejects fixture note paths that escape the vault before writing' {
        $parent = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($parent)
        $sentinel = Join-Path $parent 'caller-owned.txt'
        [System.IO.File]::WriteAllText($sentinel, 'preserve')

        { New-TestVaultFixture -ParentPath $parent -Notes ([ordered]@{ '../../caller-owned.txt' = 'overwrite' }) } | Should -Throw

        [System.IO.File]::ReadAllText($sentinel) | Should -BeExactly 'preserve'
        @(Get-ChildItem -LiteralPath $parent -Force).Count | Should -Be 1
    }

    It 'returns the prerequisite exit code when Pester is unavailable under Stop error preference' {
        $moduleDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($moduleDirectory)
        $previousModulePath = $env:PSModulePath
        $previousTestModulePath = $env:DM_TEST_PESTER_MODULE_PATH
        $runner = Join-Path $PSScriptRoot 'Invoke-Tests.ps1'
        $isolatedRunner = Join-Path $moduleDirectory 'Invoke-Tests-isolated.ps1'
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        try {
            $env:DM_TEST_PESTER_MODULE_PATH = $moduleDirectory
            $source = [System.IO.File]::ReadAllText($runner)
            $source = $source.Replace(
                'Set-StrictMode -Version Latest',
                '$env:PSModulePath = $env:DM_TEST_PESTER_MODULE_PATH' + [Environment]::NewLine + 'Set-StrictMode -Version Latest'
            )
            [System.IO.File]::WriteAllText($isolatedRunner, $source)
            & $pwsh -NoLogo -NoProfile -File $isolatedRunner 2>$null
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:PSModulePath = $previousModulePath
            if ($null -eq $previousTestModulePath) { Remove-Item Env:DM_TEST_PESTER_MODULE_PATH -ErrorAction SilentlyContinue }
            else { $env:DM_TEST_PESTER_MODULE_PATH = $previousTestModulePath }
        }

        $exitCode | Should -Be 2
    }
}
