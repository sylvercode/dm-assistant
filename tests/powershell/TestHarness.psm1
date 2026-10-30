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

function New-TestVaultFixture {
    <#
    Creates a synthetic, disposable vault under -ParentPath (defaults to a new
    folder in the system temp directory). Returns
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
    if ([string]::IsNullOrEmpty($ParentPath)) {
        $ParentPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('dmassist-test-' + [guid]::NewGuid().ToString('N'))
    }
    $root = Join-Path -Path $ParentPath -ChildPath $Name
    $outside = Join-Path -Path $ParentPath -ChildPath 'outside'
    [void][System.IO.Directory]::CreateDirectory($root)
    [void][System.IO.Directory]::CreateDirectory($outside)
    [System.IO.File]::WriteAllText((Join-Path -Path $outside -ChildPath 'secret.md'), "# Outside`nSynthetic outside-boundary file.`n")

    if ($null -eq $Notes) {
        $Notes = [ordered]@{
            'Adventures/Synthetic Arc.md' = "# Synthetic Arc`nInvented adventure text.`n"
            'Lore/Invented Town.md'       = "# Invented Town`nSee [[Synthetic Arc]].`n"
        }
    }
    $notePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $Notes.Keys) {
        $full = Join-Path -Path $root -ChildPath ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full))
        [System.IO.File]::WriteAllBytes($full, [System.Text.UTF8Encoding]::new($false).GetBytes([string]$Notes[$relative]))
        $notePaths.Add($full)
    }
    $profilePath = Join-Path -Path $root -ChildPath '.dmassist.yaml'
    if ($PSBoundParameters.ContainsKey('ProfileText') -and $null -ne $ProfileText) {
        [System.IO.File]::WriteAllBytes($profilePath, [System.Text.UTF8Encoding]::new($false).GetBytes($ProfileText))
    }
    [pscustomobject]@{
        Root        = $root
        ParentPath  = $ParentPath
        OutsidePath = $outside
        ProfilePath = $profilePath
        NotePaths   = [string[]]$notePaths.ToArray()
    }
}

function Remove-TestVaultFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture)
    if ($null -ne $Fixture -and (Test-Path -LiteralPath $Fixture.ParentPath)) {
        Remove-Item -LiteralPath $Fixture.ParentPath -Recurse -Force
    }
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
