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
}
