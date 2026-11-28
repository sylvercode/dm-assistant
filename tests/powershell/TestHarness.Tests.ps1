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

Describe 'No-follow test vault snapshots' {
    It 'captures outside directory-link metadata without following the link' {
        $fixture = New-TestVaultFixture -ParentPath $TestDrive
        try {
            $outsideDirectoryLink = Join-Path $fixture.Root 'outside-directory'

            try {
                [void][System.IO.Directory]::CreateSymbolicLink($outsideDirectoryLink, $fixture.OutsidePath)
            }
            catch {
                try {
                    $null = New-Item -ItemType Junction -Path $outsideDirectoryLink -Target $fixture.OutsidePath -ErrorAction Stop
                }
                catch {
                    Set-ItResult -Skipped -Because 'directory symbolic links and junctions cannot be created here'
                    return
                }
            }

            $snapshot = @(Get-TestOwnedVaultSnapshot -Fixture $fixture)
            $vaultPrefix = [System.IO.Path]::GetFileName($fixture.Root) + [System.IO.Path]::DirectorySeparatorChar
            $outsideDirectoryAlias = $vaultPrefix + 'outside-directory'
            $arcRelative = $vaultPrefix + 'Adventures'
            $noteRelative = $vaultPrefix + 'Adventures' + [System.IO.Path]::DirectorySeparatorChar + 'Synthetic Arc.md'

            ($snapshot | Where-Object RelativePath -EQ $arcRelative).Kind | Should -BeExactly 'directory'
            $note = $snapshot | Where-Object RelativePath -EQ $noteRelative
            $note.Kind | Should -BeExactly 'file'
            $note.Sha256 | Should -BeExactly ([System.Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($fixture.NotePaths[0]))
            ))
            $note.LastWriteTimeUtcTicks | Should -Be ([System.IO.File]::GetLastWriteTimeUtc($fixture.NotePaths[0]).Ticks)
            (($note.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) | Should -BeFalse

            $directoryLink = $snapshot | Where-Object RelativePath -EQ $outsideDirectoryAlias
            $directoryLink.Kind | Should -BeExactly 'link'
            $directoryLink.LinkTarget | Should -BeExactly $fixture.OutsidePath
            @($snapshot | Where-Object RelativePath -Like "$outsideDirectoryAlias*").Count | Should -Be 1
            @($snapshot | Where-Object RelativePath -Like "$vaultPrefix*").Count | Should -Be 5
        }
        finally {
            Remove-TestVaultFixture -Fixture $fixture
        }
    }

    It 'captures outside and dangling file-link metadata without hashing targets' {
        $fixture = New-TestVaultFixture -ParentPath $TestDrive
        try {
            $outsideFile = Join-Path $fixture.OutsidePath 'secret.md'
            $outsideFileLink = Join-Path $fixture.Root 'outside-link.md'
            $danglingLink = Join-Path $fixture.Root 'dangling.md'
            try {
                [void][System.IO.File]::CreateSymbolicLink($outsideFileLink, $outsideFile)
                [void][System.IO.File]::CreateSymbolicLink($danglingLink, (Join-Path $fixture.OutsidePath 'missing.md'))
            }
            catch {
                Set-ItResult -Skipped -Because 'file symbolic links cannot be created here'
                return
            }

            $snapshot = @(Get-TestOwnedVaultSnapshot -Fixture $fixture)
            $vaultPrefix = [System.IO.Path]::GetFileName($fixture.Root) + [System.IO.Path]::DirectorySeparatorChar
            $fileLink = $snapshot | Where-Object RelativePath -EQ ($vaultPrefix + 'outside-link.md')
            $fileLink.Kind | Should -BeExactly 'link'
            $fileLink.LinkTarget | Should -BeExactly $outsideFile
            $fileLink.PSObject.Properties.Name | Should -Not -Contain 'Sha256'

            $dangling = $snapshot | Where-Object RelativePath -EQ ($vaultPrefix + 'dangling.md')
            $dangling.Kind | Should -BeExactly 'link'
            $dangling.LinkTarget | Should -BeExactly (Join-Path $fixture.OutsidePath 'missing.md')
            $dangling.PSObject.Properties.Name | Should -Not -Contain 'Sha256'
        }
        finally {
            Remove-TestVaultFixture -Fixture $fixture
        }
    }

    It 'refuses to snapshot a caller-owned directory that is not a generated fixture' {
        $callerDirectory = Join-Path $TestDrive 'caller-owned'
        [void][System.IO.Directory]::CreateDirectory($callerDirectory)
        $sentinel = Join-Path $callerDirectory 'preserve.txt'
        [System.IO.File]::WriteAllText($sentinel, 'preserve')
        $fixture = [pscustomobject]@{
            OwnershipParentPath = $TestDrive
            OwnedDirectory = $callerDirectory
            Root = $callerDirectory
        }

        { Get-TestOwnedVaultSnapshot -Fixture $fixture } | Should -Throw
        [System.IO.File]::ReadAllText($sentinel) | Should -BeExactly 'preserve'
    }
}
