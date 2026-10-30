Set-StrictMode -Version Latest

# Test-only helpers for the Feature 003 acceptance suite. Nothing here ships as
# a production capability: production modules never import or reference this
# file, and the authorization provider below is reachable only by calling
# Enable-TestAuthorizationProvider from inside a running Pester test.

$script:TestAuthorizedRoot = $null
$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\..'))

function Get-TestRepositoryRoot {
    [CmdletBinding()]
    param()
    $script:RepositoryRoot
}

function Get-TestScriptsRoot {
    [CmdletBinding()]
    param()
    Join-Path -Path $script:RepositoryRoot -ChildPath 'skills\vault-orientation\scripts'
}

function Import-TestProductionModule {
    # Imports production modules from the skill folder with -Force so each test file starts clean.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Name)
    foreach ($moduleName in $Name) {
        Import-Module -Name (Join-Path -Path (Get-TestScriptsRoot) -ChildPath "$moduleName.psm1") -Force -Global
    }
}

function Test-TestPathWithinDirectory {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $fullPath.StartsWith($prefix, $comparison)
}

function New-TestVaultFixture {
    <#
    Creates a synthetic, disposable vault under -ParentPath (defaults to the
    system temp directory). A fresh, uniquely named owned directory is created
    beneath that parent. Returns
    [pscustomobject]@{ Root; ParentPath; OutsidePath; ProfilePath; NotePaths }.
    All content is invented. -ProfileText writes a root .dmassist.yaml.
    #>
    [CmdletBinding()]
    param(
        [string]$ParentPath,
        [string]$Name = 'vault',
        [AllowNull()][string]$ProfileText,
        [System.Collections.IDictionary]$Notes
    )
    if ([string]::IsNullOrEmpty($ParentPath)) { $ParentPath = [System.IO.Path]::GetTempPath() }
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.', '..') -or
        $Name -match '[/\\:]' -or @($Name.ToCharArray() | Where-Object { [System.IO.Path]::GetInvalidFileNameChars() -contains $_ }).Count -gt 0) {
        throw [System.ArgumentException]::new('Fixture Name must be one directory name.')
    }
    $ownershipParentPath = [System.IO.Path]::GetFullPath($ParentPath)
    $ownedDirectory = Join-Path -Path $ownershipParentPath -ChildPath ('dmassist-test-' + [guid]::NewGuid().ToString('N'))
    $root = [System.IO.Path]::GetFullPath((Join-Path -Path $ownedDirectory -ChildPath $Name))
    if (-not (Test-TestPathWithinDirectory -Root $ownedDirectory -Path $root)) {
        throw [System.ArgumentException]::new('Fixture root must remain inside its uniquely owned directory.')
    }
    $outside = Join-Path -Path $ownedDirectory -ChildPath 'outside'
    if ($null -eq $Notes) {
        $Notes = [ordered]@{
            'Adventures/Synthetic Arc.md' = "# Synthetic Arc`nInvented adventure text.`n"
            'Lore/Invented Town.md'       = "# Invented Town`nSee [[Synthetic Arc]].`n"
        }
    }
    $validatedNotes = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in $Notes.Keys) {
        if ($relative -isnot [string] -or [string]::IsNullOrEmpty($relative) -or
            $relative.StartsWith('/') -or $relative.Contains('\') -or $relative.Contains(':') -or
            @($relative.Split('/') | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -in @('.', '..') }).Count -gt 0) {
            throw [System.ArgumentException]::new('Fixture note keys must be safe vault-relative paths.')
        }
        foreach ($component in $relative.Split('/')) {
            if (@($component.ToCharArray() | Where-Object { [System.IO.Path]::GetInvalidFileNameChars() -contains $_ }).Count -gt 0) {
                throw [System.ArgumentException]::new('Fixture note keys must be safe vault-relative paths.')
            }
        }
        $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
        if (-not (Test-TestPathWithinDirectory -Root $root -Path $full)) {
            throw [System.ArgumentException]::new('Fixture note paths must remain inside the fixture vault.')
        }
        $validatedNotes.Add([pscustomobject]@{ relative = $relative; full = $full; content = [string]$Notes[$relative] })
    }

    [void][System.IO.Directory]::CreateDirectory($root)
    [void][System.IO.Directory]::CreateDirectory($outside)
    [System.IO.File]::WriteAllText((Join-Path -Path $outside -ChildPath 'secret.md'), "# Outside`nSynthetic outside-boundary file.`n")

    $notePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($note in $validatedNotes) {
        $full = [string]$note.full
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full))
        [System.IO.File]::WriteAllBytes($full, [System.Text.UTF8Encoding]::new($false).GetBytes([string]$note.content))
        $notePaths.Add($full)
    }
    $profilePath = Join-Path -Path $root -ChildPath '.dmassist.yaml'
    if ($PSBoundParameters.ContainsKey('ProfileText') -and $null -ne $ProfileText) {
        [System.IO.File]::WriteAllBytes($profilePath, [System.Text.UTF8Encoding]::new($false).GetBytes($ProfileText))
    }
    [pscustomobject]@{
        Root        = $root
        ParentPath  = $ownedDirectory
        OwnershipParentPath = $ownershipParentPath
        OwnedDirectory = $ownedDirectory
        OutsidePath = $outside
        ProfilePath = $profilePath
        NotePaths   = [string[]]$notePaths.ToArray()
    }
}

function Remove-TestVaultFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture)
    if ($null -eq $Fixture -or $null -eq $Fixture.OwnedDirectory -or $null -eq $Fixture.OwnershipParentPath) { return }
    $parent = [System.IO.Path]::GetFullPath([string]$Fixture.OwnershipParentPath)
    $owned = [System.IO.Path]::GetFullPath([string]$Fixture.OwnedDirectory)
    $actualParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetDirectoryName($owned))
    $root = [System.IO.Path]::GetPathRoot($parent)
    if ($parent.Length -gt $root.Length) { $parent = $parent.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) }
    $actualRoot = [System.IO.Path]::GetPathRoot($actualParent)
    if ($actualParent.Length -gt $actualRoot.Length) { $actualParent = $actualParent.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) }
    $ownedName = [System.IO.Path]::GetFileName($owned)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($actualParent, $parent) -or $ownedName -notmatch '^dmassist-test-[0-9a-f]{32}$') {
        throw [System.ArgumentException]::new('The fixture cleanup target is not a uniquely owned fixture directory.')
    }
    if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Recurse -Force }
}

function Get-TestVaultSnapshot {
    <#
    Returns an ordinal-sorted inventory of every file and directory under the
    fixture parent (vault and outside directory) with SHA-256 hashes and last
    write times, for before/after comparison.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($item in [System.IO.Directory]::EnumerateFileSystemEntries($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
        $relative = [System.IO.Path]::GetRelativePath($Path, $item)
        if ([System.IO.Directory]::Exists($item)) {
            $entries.Add("D|$relative")
        }
        else {
            $hash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($item)))
            $ticks = [System.IO.File]::GetLastWriteTimeUtc($item).Ticks
            $entries.Add("F|$relative|$hash|$ticks")
        }
    }
    $array = $entries.ToArray()
    [System.Array]::Sort($array, [System.StringComparer]::Ordinal)
    $array
}

function New-TestOperationRequest {
    <#
    Builds a synthetic contract-section-2 request as an ordered hashtable.
    Use -Extra to add or override fields.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VaultRoot,
        [string]$Operation = 'notes.inspect',
        [string]$Mode = 'inspect',
        [string[]]$Targets = @('Adventures/Synthetic Arc.md'),
        [System.Collections.IDictionary]$Arguments = @{},
        [System.Collections.IDictionary]$Extra
    )
    $request = [ordered]@{
        contractVersion = '1'
        requestId       = 'test-' + [guid]::NewGuid().ToString('N')
        operation       = $Operation
        vaultRoot       = $VaultRoot
        campaignGroup   = [ordered]@{ campaign = 'Synthetic Campaign'; group = 'Synthetic Group' }
        mode            = $Mode
        arguments       = $Arguments
        targets         = [string[]]$Targets
    }
    if ($null -ne $Extra) {
        foreach ($key in $Extra.Keys) { $request[$key] = $Extra[$key] }
    }
    $request
}

function Get-TestCanonicalRoot {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $trimmed = $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ($trimmed.Length -eq 0 -or $trimmed.EndsWith(':')) { return $full }
    $trimmed
}

function Test-TestAuthorizedRoot {
    # Called only from the mock installed by Enable-TestAuthorizationProvider.
    [CmdletBinding()]
    param([AllowNull()][string]$VaultRoot)
    if ([string]::IsNullOrEmpty($script:TestAuthorizedRoot) -or [string]::IsNullOrEmpty($VaultRoot)) { return $false }
    if (-not [System.IO.Path]::IsPathFullyQualified($VaultRoot)) { return $false }
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    [string]::Equals((Get-TestCanonicalRoot -Path $VaultRoot), $script:TestAuthorizedRoot, $comparison)
}

function Enable-TestAuthorizationProvider {
    <#
    TEST-ONLY authorization provider. Must be called inside a Pester It,
    BeforeEach, or BeforeAll block. Mocks DependencyPreflight's internal
    Get-DmVaultAuthorization so that only the exact canonical -VaultRoot is
    reported 'authorized'; every other root stays 'unknown'. The mock is
    removed automatically when the enclosing Pester block ends. This never
    proves that production can verify Feature 001's authorization signal.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VaultRoot)
    if (-not [System.IO.Path]::IsPathFullyQualified($VaultRoot)) {
        throw [System.ArgumentException]::new('The test authorization provider requires an absolute vault root.')
    }
    $script:TestAuthorizedRoot = Get-TestCanonicalRoot -Path $VaultRoot
    Mock -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -MockWith {
        $authorized = TestHarness\Test-TestAuthorizedRoot -VaultRoot $VaultRoot
        [pscustomobject][ordered]@{
            dependencyId             = $Dependency.dependencyId
            vaultAuthorizationState  = $(if ($authorized) { 'authorized' } else { 'unknown' })
            evidence                 = $(if ($authorized) { 'test-only harness provider' } else { 'test-only harness provider: root not authorized' })
        }
    }
}

function Set-TestDependencyReadiness {
    <#
    TEST-ONLY readiness override (not an authorization provider). Mocks
    DependencyPreflight's internal Get-DmDependencyReadiness so every declared
    dependency reports -State. Must be called inside a Pester block.
    #>
    [CmdletBinding()]
    param([ValidateSet('ready', 'missing', 'incompatible', 'unknown')][string]$State = 'ready')
    $script:TestReadinessState = $State
    Mock -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -MockWith {
        [pscustomobject][ordered]@{
            dependencyId   = $Dependency.dependencyId
            readinessState = TestHarness\Get-TestReadinessState
            evidence       = 'test-only readiness override'
        }
    }
}

function Get-TestReadinessState {
    [CmdletBinding()]
    param()
    $script:TestReadinessState
}

$script:TestReadinessState = 'ready'

Export-ModuleMember -Function Get-TestRepositoryRoot, Get-TestScriptsRoot, Import-TestProductionModule, New-TestVaultFixture, Remove-TestVaultFixture, Get-TestVaultSnapshot, New-TestOperationRequest, Test-TestAuthorizedRoot, Enable-TestAuthorizationProvider, Set-TestDependencyReadiness, Get-TestReadinessState
