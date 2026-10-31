BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, RuntimePreflight

    $script:ProductionModules = @('RuntimeContract', 'DependencyPreflight', 'RuntimePreflight')
    $script:FileCmdlets = @('Get-Content', 'Set-Content', 'Add-Content', 'Out-File', 'Get-Item', 'Get-ChildItem', 'Test-Path',
        'Resolve-Path', 'New-Item', 'Remove-Item', 'Move-Item', 'Copy-Item', 'Rename-Item', 'Get-FileHash', 'Select-String', 'Import-Csv')
    $script:InstallCmdlets = @('Install-Module', 'Update-Module', 'Save-Module', 'Install-PSResource', 'Update-PSResource', 'Save-PSResource', 'Install-Package') |
        Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue }

    function Register-VaultAccessSpy {
        # Any production-module filesystem cmdlet call that names the fixture throws and is recorded.
        param([Parameter(Mandatory)][string]$FixtureParent)
        $global:DmTestSpyParent = $FixtureParent
        foreach ($module in $script:ProductionModules) {
            foreach ($cmd in $script:FileCmdlets) {
                Mock -ModuleName $module -CommandName $cmd -ParameterFilter {
                    $joined = (@($PSBoundParameters.Values) | ForEach-Object { "$_" }) -join '|'
                    $joined.IndexOf($global:DmTestSpyParent, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                } -MockWith { throw 'Vault access attempted by production preflight.' }
            }
            foreach ($cmd in $script:InstallCmdlets) {
                Mock -ModuleName $module -CommandName $cmd -MockWith { throw 'Installation attempted by production preflight.' }
            }
        }
    }

    function Assert-NoVaultAccessOrInstall {
        foreach ($module in $script:ProductionModules) {
            foreach ($cmd in $script:FileCmdlets) {
                Should -Invoke -ModuleName $module -CommandName $cmd -Times 0 -Exactly -Scope It -ParameterFilter {
                    $joined = (@($PSBoundParameters.Values) | ForEach-Object { "$_" }) -join '|'
                    $joined.IndexOf($global:DmTestSpyParent, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                }
            }
            foreach ($cmd in $script:InstallCmdlets) {
                Should -Invoke -ModuleName $module -CommandName $cmd -Times 0 -Exactly -Scope It
            }
        }
    }

    function Assert-BlockedResult {
        param($Outcome, [string]$Code, [string[]]$Targets)
        $Outcome.passed | Should -BeFalse
        $r = $Outcome.result
        $r.completionStatus | Should -BeExactly 'not completed'
        $r.completionCode | Should -BeExactly $Code
        $r.changedTargets.Count | Should -Be 0
        @($r.unchangedTargets | Where-Object { $_.outcome -ne 'not attempted' }).Count | Should -Be 0
        $r.errorDetails.code | Should -BeExactly $Code
        (Test-DmResult -Result $r -RequestedTargets $Targets).isValid | Should -BeTrue
    }

    function Invoke-WithLockedVault {
        # Holds exclusive handles on the profile and notes so any read attempt fails.
        param($Fixture, [scriptblock]$Action)
        $handles = [System.Collections.Generic.List[System.IO.FileStream]]::new()
        try {
            foreach ($path in @($Fixture.ProfilePath) + $Fixture.NotePaths) {
                if ([System.IO.File]::Exists($path)) {
                    $handles.Add([System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None))
                }
            }
            & $Action
        }
        finally {
            foreach ($h in $handles) { $h.Dispose() }
        }
    }
}

Describe 'RuntimePreflight production gate' {
    BeforeEach {
        $fixture = New-TestVaultFixture -ProfileText "version: 1`n"
        $before = Get-TestVaultSnapshot -Path $fixture.ParentPath
        $targets = @('Adventures/Synthetic Arc.md')
        $request = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets
        Register-VaultAccessSpy -FixtureParent $fixture.ParentPath
    }

    AfterEach {
        Get-TestVaultSnapshot -Path $fixture.ParentPath | Should -Be $before -Because 'blocked preflight must not write'
        Assert-NoVaultAccessOrInstall
        Remove-TestVaultFixture -Fixture $fixture
    }

    Describe 'Production gate: runtime prerequisites (no authorization provider)' {
        It 'accepts the documented supported runtime in this environment' {
            $gate = Test-DmRuntimePrerequisite -Operation 'notes.inspect'
            $gate.passed | Should -BeTrue -Because ($gate.evidence | Out-String)
            $gate.result | Should -BeNullOrEmpty
        }

        It 'returns a deep copy of runtime support metadata that cannot alter the gate' {
            $matrix = Get-DmRuntimeSupportMatrix
            $matrix.operatingSystems[0] = 'Linux'
            $matrix.modules[0].name = 'missing-module'
            $matrix.modules[0].version = '0.0'
            $matrix.modules = @()

            $fresh = Get-DmRuntimeSupportMatrix
            $fresh.operatingSystems | Should -Be @('Windows')
            $fresh.modules.Count | Should -Be 1
            $fresh.modules[0].name | Should -BeExactly 'powershell-yaml'
            $fresh.modules[0].version | Should -BeExactly '0.4.12'
            (Test-DmRuntimePrerequisite -Operation 'notes.inspect').passed | Should -BeTrue
        }

        It 'returns PREREQUISITE_MISSING for PowerShell <Version> (<Edition>)' -ForEach @(
            @{ Version = '7.3.12'; Edition = 'Core' }
            @{ Version = '7.4.0'; Edition = 'Core' }
            @{ Version = '7.7.0'; Edition = 'Core' }
            @{ Version = '5.1.26100'; Edition = 'Desktop' }
        ) {
            Mock -ModuleName RuntimePreflight -CommandName Get-DmRuntimeEnvironment -MockWith {
                [pscustomobject]@{ powerShellVersion = [version]$Version; edition = $Edition; operatingSystem = 'Windows' }
            }
            Set-TestDependencyReadiness -State ready
            $outcome = Invoke-DmPreflight -Request $request
            Assert-BlockedResult -Outcome $outcome -Code 'PREREQUISITE_MISSING' -Targets $targets
            Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -Times 0 -Exactly -Scope It
        }

        It 'rejects a prerelease with the supported PowerShell version number' {
            Mock -ModuleName RuntimePreflight -CommandName Get-DmRuntimeEnvironment -MockWith {
                [pscustomobject]@{ powerShellVersion = [version]'7.6.9'; edition = 'Core'; operatingSystem = 'Windows'; isPrerelease = $true }
            }
            Set-TestDependencyReadiness -State ready
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'PREREQUISITE_MISSING' -Targets $targets
            Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -Times 0 -Exactly -Scope It
        }

        It 'returns PREREQUISITE_MISSING on unsupported operating system <Os>' -ForEach @(
            @{ Os = 'macOS' }, @{ Os = 'Linux' }, @{ Os = 'Unknown' }
        ) {
            Mock -ModuleName RuntimePreflight -CommandName Get-DmRuntimeEnvironment -MockWith {
                [pscustomobject]@{ powerShellVersion = [version]'7.6.9'; edition = 'Core'; operatingSystem = $Os }
            }
            Set-TestDependencyReadiness -State ready
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'PREREQUISITE_MISSING' -Targets $targets
        }

        It 'returns PREREQUISITE_MISSING when powershell-yaml is <Case>' -ForEach @(
            @{ Case = 'missing'; Versions = @(); Importable = $false }
            @{ Case = 'a different version'; Versions = @('0.4.7'); Importable = $false }
            @{ Case = 'a newer version only'; Versions = @('0.4.13'); Importable = $false }
            @{ Case = 'present but broken'; Versions = @('0.4.12'); Importable = $false }
        ) {
            Mock -ModuleName RuntimePreflight -CommandName Get-DmInstalledModuleVersion -MockWith { $Versions }
            Mock -ModuleName RuntimePreflight -CommandName Test-DmRequiredModuleImport -MockWith { [bool]$Importable }
            Set-TestDependencyReadiness -State ready
            $outcome = Invoke-DmPreflight -Request $request
            Assert-BlockedResult -Outcome $outcome -Code 'PREREQUISITE_MISSING' -Targets $targets
            $outcome.result.errorDetails.details.module | Should -Be 'powershell-yaml'
        }

        It 'uses unknown and omits unregistered operation values in blocked results' {
            Set-TestDependencyReadiness -State ready
            $unsafeOperation = 'C:\private\synthetic note.md'
            $req = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets -Extra @{ operation = $unsafeOperation }
            $outcome = Invoke-DmPreflight -Request $req
            $outcome.operation | Should -BeExactly 'unknown'
            $outcome.result.operation | Should -BeExactly 'unknown'
            ($outcome | ConvertTo-Json -Depth 8) | Should -Not -Match ([regex]::Escape($unsafeOperation))
        }

        It 'returns PREREQUISITE_MISSING when a declared dependency is <State>' -ForEach @(
            @{ State = 'missing' }, @{ State = 'incompatible' }, @{ State = 'unknown' }
        ) {
            Set-TestDependencyReadiness -State $State
            Mock -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -MockWith {
                [pscustomobject]@{ dependencyId = $Dependency.dependencyId; vaultAuthorizationState = 'unknown'; evidence = 'spy' }
            }
            $outcome = Invoke-DmPreflight -Request $request
            Assert-BlockedResult -Outcome $outcome -Code 'PREREQUISITE_MISSING' -Targets $targets
            $outcome.result.errorDetails.details.dependencyId | Should -Be 'obsidian-link-resolver'
            $outcome.result.errorDetails.details.readinessState | Should -Be $State
            $outcome.result.errorDetails.details.minimumVersion | Should -BeExactly '2.1.0'
            @($outcome.result.errorDetails.details.requiredTools) | Should -Be @('resolve_obsidian_link', 'get_server_info')
            $outcome.result.errorDetails.message | Should -Match 'resolve_obsidian_link'
            $outcome.result.errorDetails.message | Should -Match 'get_server_info'
            $outcome.result.remainingWork[0] | Should -Match 'handoff'
            if ($State -eq 'unknown') { $outcome.result.remainingWork[0] | Should -Not -Match '^Install' }
            Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -Times 0 -Exactly -Scope It
        }

        It 'never reports the real readiness probe as ready, so real preflight blocks with PREREQUISITE_MISSING' {
            $inventory = @(Get-DmDependencyInventory)
            $probe = InModuleScope DependencyPreflight -Parameters @{ Dep = $inventory[0] } { param($Dep) Get-DmDependencyReadiness -Dependency $Dep }
            $probe.readinessState | Should -BeIn @('missing', 'unknown')
            $probe.evidence | Should -Not -BeNullOrEmpty
            Test-DmSafeText -Text $probe.evidence | Should -BeTrue
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'PREREQUISITE_MISSING' -Targets $targets
        }

        It 'returns RESOURCE_MISSING when the dependency inventory asset is unavailable' {
            Mock -ModuleName DependencyPreflight -CommandName Get-DmDependencyInventoryPath -MockWith { Join-Path -Path $TestDrive -ChildPath 'absent.json' }
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'RESOURCE_MISSING' -Targets $targets
        }

        It 'rejects an incompatible dependency inventory: <Case>' -ForEach @(
            @{ Case = 'empty'; Duplicate = $false }
            @{ Case = 'duplicate dependency'; Duplicate = $true }
        ) {
            $dependencies = @()
            if ($Duplicate) {
                $entry = [ordered]@{
                    dependencyId = 'obsidian-link-resolver'
                    type = 'mcp-server'
                    minimumVersion = '2.1.0'
                    requiredTools = @('resolve_obsidian_link', 'get_server_info')
                }
                $dependencies = @($entry, $entry)
            }
            $inventory = [ordered]@{ inventoryVersion = 2; dependencies = $dependencies }
            $global:DmTestInventoryPath = Join-Path -Path $TestDrive -ChildPath ('inventory-' + [guid]::NewGuid().ToString('N') + '.json')
            [System.IO.File]::WriteAllText($global:DmTestInventoryPath, ($inventory | ConvertTo-Json -Depth 8))
            Mock -ModuleName DependencyPreflight -CommandName Get-DmDependencyInventoryPath -MockWith { $global:DmTestInventoryPath }
            Set-TestDependencyReadiness -State ready
            try {
                Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'RESOURCE_INCOMPATIBLE' -Targets $targets
                Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -Times 0 -Exactly -Scope It
            }
            finally {
                Remove-Variable -Name DmTestInventoryPath -Scope Global
            }
        }

        It 'rejects an incompatible required-tools list: <Case>' -ForEach @(
            @{ Case = 'missing'; Tools = $null; Omit = $true }
            @{ Case = 'null'; Tools = $null; Omit = $false }
            @{ Case = 'scalar'; Tools = 'get_server_info'; Omit = $false }
            @{ Case = 'empty'; Tools = @(); Omit = $false }
            @{ Case = 'duplicate'; Tools = @('get_server_info', 'get_server_info'); Omit = $false }
            @{ Case = 'invalid name'; Tools = @('get_server_info', 'bad/name'); Omit = $false }
            @{ Case = 'non-string'; Tools = @('get_server_info', 42); Omit = $false }
        ) {
            $entry = [ordered]@{
                dependencyId = 'obsidian-link-resolver'
                type = 'mcp-server'
                minimumVersion = '2.1.0'
                requiredTools = $Tools
            }
            if ($Omit) { $entry.Remove('requiredTools') }
            $inventory = [ordered]@{ inventoryVersion = 2; dependencies = @($entry) }
            $global:DmTestInventoryPath = Join-Path -Path $TestDrive -ChildPath ('inventory-' + [guid]::NewGuid().ToString('N') + '.json')
            [System.IO.File]::WriteAllText($global:DmTestInventoryPath, ($inventory | ConvertTo-Json -Depth 8))
            Mock -ModuleName DependencyPreflight -CommandName Get-DmDependencyInventoryPath -MockWith { $global:DmTestInventoryPath }
            try {
                Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'RESOURCE_INCOMPATIBLE' -Targets $targets
            }
            finally {
                Remove-Variable -Name DmTestInventoryPath -Scope Global
            }
        }
    }

    Describe 'Production gate: exact-vault authorization (no authorization provider)' {
        It 'reports the production authorization handoff as unknown' {
            $inventory = @(Get-DmDependencyInventory)
            $auth = InModuleScope DependencyPreflight -Parameters @{ Dep = $inventory[0]; Root = $fixture.Root } {
                param($Dep, $Root) Get-DmVaultAuthorization -Dependency $Dep -VaultRoot $Root
            }
            $auth.vaultAuthorizationState | Should -Be 'unknown'
        }

        It 'returns VAULT_AUTHORIZATION_UNPROVEN when every dependency is ready' {
            Set-TestDependencyReadiness -State ready
            $outcome = Invoke-WithLockedVault -Fixture $fixture -Action { Invoke-DmPreflight -Request $request }
            Assert-BlockedResult -Outcome $outcome -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
            $outcome.result.errorDetails.message | Should -Not -Match ([regex]::Escape($fixture.Root))
            $outcome.result.errorDetails.message | Should -Match 'PowerShell runtime'
            $outcome.result.remainingWork[0] | Should -Match 'active session Resolver'
        }

        It 'is repeatable across runs and working directories' {
            Set-TestDependencyReadiness -State ready
            $codes = foreach ($dir in @($TestDrive, $fixture.OutsidePath, [System.IO.Path]::GetTempPath())) {
                Push-Location -LiteralPath $dir
                try { (Invoke-DmPreflight -Request $request).result.completionCode } finally { Pop-Location }
            }
            $codes | Should -Be @('VAULT_AUTHORIZATION_UNPROVEN', 'VAULT_AUTHORIZATION_UNPROVEN', 'VAULT_AUTHORIZATION_UNPROVEN')
        }

        It 'returns VAULT_AUTHORIZATION_UNPROVEN for an inconclusive authorization answer: <Case>' -ForEach @(
            @{ Case = 'not authorized'; State = 'not authorized'; Throw = $false }
            @{ Case = 'malformed'; State = 'yes'; Throw = $false }
            @{ Case = 'error'; State = $null; Throw = $true }
        ) {
            Set-TestDependencyReadiness -State ready
            Mock -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -MockWith {
                if ($Throw) { throw 'probe failure' }
                [pscustomobject]@{ dependencyId = $Dependency.dependencyId; vaultAuthorizationState = $State; evidence = 'x' }
            }
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
        }

        It 'ignores an authorization-like correlation id and vault path name' {
            Set-TestDependencyReadiness -State ready
            $authorizedFixture = New-TestVaultFixture -Name 'authorized-vault' -ProfileText "version: 1`n"
            try {
                $req = New-TestOperationRequest -VaultRoot $authorizedFixture.Root -Targets $targets -Extra @{ requestId = 'authorized:true' }
                Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $req) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
            }
            finally { Remove-TestVaultFixture -Fixture $authorizedFixture }
        }

        It 'is not unlocked by authorization-like request field <Field>' -ForEach @(
            @{ Field = 'authorized'; Value = $true }
            @{ Field = 'vaultAuthorization'; Value = 'authorized' }
            @{ Field = 'authorizationToken'; Value = 'synthetic-token' }
            @{ Field = 'arguments'; Value = @{ authorized = $true } }
            @{ Field = 'authorizationProvider'; Value = { 'authorized' } }
        ) {
            Set-TestDependencyReadiness -State ready
            $req = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets -Extra @{ $Field = $Value }
            $outcome = Invoke-DmPreflight -Request $req
            $outcome.passed | Should -BeFalse
            # Request-shape validation may reject unknown fields first; it must never authorize.
            $outcome.result.completionCode | Should -BeIn @('VAULT_AUTHORIZATION_UNPROVEN', 'INVALID_REQUEST')
            Assert-BlockedResult -Outcome $outcome -Code $outcome.result.completionCode -Targets $targets
        }

        It 'is not unlocked by authorization-like environment variables' {
            Set-TestDependencyReadiness -State ready
            $names = @('DMASSIST_VAULT_AUTHORIZED', 'DM_ASSISTANT_AUTHORIZED_VAULT', 'DMASSIST_AUTHORIZATION_PROVIDER', 'OBSIDIAN_LINK_RESOLVER_AUTHORIZED_ROOTS')
            try {
                foreach ($n in $names) { [System.Environment]::SetEnvironmentVariable($n, $fixture.Root) }
                Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
            }
            finally {
                foreach ($n in $names) { [System.Environment]::SetEnvironmentVariable($n, $null) }
            }
        }

        It 'is not unlocked by authorization-like profile or configuration content' {
            Set-TestDependencyReadiness -State ready
            $configured = New-TestVaultFixture -ProfileText "version: 1`nauthorized: true`nvaultAuthorization: granted`n"
            try {
                [System.IO.File]::WriteAllText((Join-Path -Path $configured.Root -ChildPath '.mcp.json'), '{"mcpServers":{"obsidian-link-resolver":{"authorizedRoots":["."]}}}')
                [System.IO.File]::WriteAllText((Join-Path -Path $configured.Root -ChildPath '.dmassist.authorization'), 'authorized')
                $req = New-TestOperationRequest -VaultRoot $configured.Root -Targets $targets
                $snap = Get-TestVaultSnapshot -Path $configured.ParentPath
                Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $req) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
                Get-TestVaultSnapshot -Path $configured.ParentPath | Should -Be $snap
            }
            finally { Remove-TestVaultFixture -Fixture $configured }
        }

        It 'checks runtime prerequisites before authorization' {
            Mock -ModuleName RuntimePreflight -CommandName Get-DmInstalledModuleVersion -MockWith { @() }
            Set-TestDependencyReadiness -State ready
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'PREREQUISITE_MISSING' -Targets $targets
        }

        It 'rejects a malformed request with INVALID_REQUEST before readiness: <Case>' -ForEach @(
            @{ Case = 'relative vault root'; Field = 'vaultRoot'; Value = 'relative/vault' }
            @{ Case = 'missing vault root'; Field = 'vaultRoot'; Value = $null }
            @{ Case = 'wrong contract version'; Field = 'contractVersion'; Value = '2' }
            @{ Case = 'unknown mode'; Field = 'mode'; Value = 'write' }
            @{ Case = 'empty request id'; Field = 'requestId'; Value = '' }
        ) {
            Set-TestDependencyReadiness -State ready
            $req = New-TestOperationRequest -VaultRoot $fixture.Root -Targets $targets
            if ($null -eq $Value) { $req.Remove($Field) } else { $req[$Field] = $Value }
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $req) -Code 'INVALID_REQUEST' -Targets $targets
            Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmDependencyReadiness -Times 0 -Exactly -Scope It
        }

        It 'rejects a non-object request with INVALID_REQUEST' {
            $outcome = Invoke-DmPreflight -Request 'not a request'
            $outcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
        }
    }

    Describe 'Test harness provider exactness (downstream tier sanity)' {
        It 'authorizes only the exact injected root' {
            Set-TestDependencyReadiness -State ready
            $other = New-TestVaultFixture
            try {
                Enable-TestAuthorizationProvider -VaultRoot $other.Root
                Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
                Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
                $outcome = Invoke-DmPreflight -Request $request
                $outcome.passed | Should -BeTrue
                $outcome.result | Should -BeNullOrEmpty
            }
            finally { Remove-TestVaultFixture -Fixture $other }
        }

        It 'leaves no provider active outside the block that enabled it' {
            Set-TestDependencyReadiness -State ready
            Assert-BlockedResult -Outcome (Invoke-DmPreflight -Request $request) -Code 'VAULT_AUTHORIZATION_UNPROVEN' -Targets $targets
        }
    }

    Describe 'Production modules expose no authorization seam' {
        It 'no exported function accepts a provider or authorization parameter' {
            foreach ($module in $script:ProductionModules) {
                foreach ($cmd in (Get-Module -Name $module).ExportedFunctions.Values) {
                    @($cmd.Parameters.Keys | Where-Object { $_ -match '(?i)provider|authori[sz]' }) | Should -BeNullOrEmpty -Because "$module\$($cmd.Name)"
                }
            }
        }

        It 'production sources never reference the test harness or install modules' {
            foreach ($file in [System.IO.Directory]::GetFiles((Get-TestScriptsRoot), '*.psm1')) {
                $text = [System.IO.File]::ReadAllText($file)
                $text | Should -Not -Match '(?i)tests[\\/]|TestHarness|Enable-TestAuthorizationProvider'
                $text | Should -Not -Match '(?i)\b(Install|Update|Save)-(Module|PSResource|Package)\b'
            }
        }

        It 'preflight modules read no environment variables' {
            foreach ($module in $script:ProductionModules) {
                $text = [System.IO.File]::ReadAllText((Join-Path -Path (Get-TestScriptsRoot) -ChildPath "$module.psm1"))
                $text | Should -Not -Match '(?i)\$env:|GetEnvironmentVariable'
            }
        }
    }

    Describe 'Dependency inventory mirrors Feature 001' {
        It 'matches the Expected Runtime Dependencies table in specs/001-shared-vault-guidance/spec.md' {
            $spec = [System.IO.File]::ReadAllText((Join-Path -Path (Get-TestRepositoryRoot) -ChildPath 'specs\001-shared-vault-guidance\spec.md'))
            $section = [regex]::Match($spec, '(?ms)^## Expected Runtime Dependencies.*?(?=^## )').Value
            $section | Should -Not -BeNullOrEmpty
            $rows = @($section -split "`r?`n" | Where-Object { $_ -match '^\|' } | Select-Object -Skip 2)
            $inventory = @(Get-DmDependencyInventory)
            $inventory.Count | Should -Be $rows.Count
            foreach ($row in $rows) {
                $minimum = [regex]::Match($row, 'minimum compatible release is `([^`]+)`').Groups[1].Value
                $link = [regex]::Match($row, '^\|\s*\[([^\]]+)\]\(([^)]+)\)')
                $link.Success | Should -BeTrue
                $id = ([uri]$link.Groups[2].Value).Segments[-1].TrimEnd('/')
                $purpose = $row.Split('|')[3]
                $tools = @([regex]::Matches($purpose, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
                $tools.Count | Should -BeGreaterThan 0
                $entry = $inventory | Where-Object { $_.dependencyId -ceq $id }
                $entry | Should -Not -BeNullOrEmpty -Because "inventory must declare '$id'"
                $entry.minimumVersion | Should -BeExactly $minimum
                @($entry.requiredTools) | Should -Be $tools
                $entry.displayName | Should -BeExactly $link.Groups[1].Value
                $entry.project | Should -BeExactly $link.Groups[2].Value
            }
        }
    }
}
