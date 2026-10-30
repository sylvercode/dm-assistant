BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract

    $script:RepositoryRoot = Get-TestRepositoryRoot
    $script:RepoSchemaPath = [System.IO.Path]::Join($script:RepositoryRoot, 'skills', 'vault-orientation', 'assets', 'dmassist.schema.json')
    $script:RepoSchemaVersion = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($script:RepoSchemaPath))).ToLowerInvariant()

    function New-TestInstalledCopy {
        # Simulates an installed plugin: only the shipped content (plugin.json and skills/) is copied.
        param([Parameter(Mandatory)][string]$Name)
        $install = [System.IO.Path]::Join($TestDrive, $Name, 'installed-plugin')
        $null = [System.IO.Directory]::CreateDirectory($install)
        [System.IO.File]::Copy([System.IO.Path]::Join($script:RepositoryRoot, 'plugin.json'), [System.IO.Path]::Join($install, 'plugin.json'))
        Copy-Item -LiteralPath ([System.IO.Path]::Join($script:RepositoryRoot, 'skills')) -Destination $install -Recurse
        $install
    }

    function Remove-TestInstalledModules {
        Get-Module -All | Where-Object { $_.Path -and $_.Path.StartsWith($TestDrive, [System.StringComparison]::OrdinalIgnoreCase) } | Remove-Module -Force
    }

    function Import-TestInstalledResourceModule {
        param([Parameter(Mandatory)][string]$InstallRoot)
        Remove-TestInstalledModules
        Get-Module -Name PluginResources -All | Remove-Module -Force
        $scripts = [System.IO.Path]::Join($InstallRoot, 'skills', 'vault-orientation', 'scripts')
        Import-Module -Name ([System.IO.Path]::Join($scripts, 'PluginResources.psm1')) -Force -Global
        (Get-Module -Name PluginResources).Path
    }

    function Get-TestInstalledSchemaPath {
        param([Parameter(Mandatory)][string]$InstallRoot)
        [System.IO.Path]::Join($InstallRoot, 'skills', 'vault-orientation', 'assets', 'dmassist.schema.json')
    }

    function Set-TestSchemaJson {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][scriptblock]$Change)
        $schema = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable -Depth 64
        & $Change $schema
        [System.IO.File]::WriteAllText($Path, ($schema | ConvertTo-Json -Depth 64), [System.Text.UTF8Encoding]::new($false))
    }

    function Assert-ResourceBlocked {
        param($Outcome, [string]$Code, [string]$InstallRoot)
        $Outcome.passed | Should -BeFalse
        $Outcome.resource | Should -BeNullOrEmpty
        $r = $Outcome.result
        $r.completionStatus | Should -BeExactly 'not completed'
        $r.completionCode | Should -BeExactly $Code
        $r.changedTargets.Count | Should -Be 0
        (Test-DmResult -Result $r -RequestedTargets @('Campaign/dmassist.yaml')).isValid | Should -BeTrue
        $json = $r | ConvertTo-Json -Depth 8
        $json | Should -Not -Match ([regex]::Escape(($InstallRoot | ConvertTo-Json).Trim('"')))
        $json | Should -Not -Match ([regex]::Escape(($TestDrive | ConvertTo-Json).Trim('"')))
    }
}

AfterAll {
    Remove-TestInstalledModules
    Import-TestProductionModule -Name RuntimeContract, PluginResources
}

Describe 'Installed plugin schema resource' {
    Describe 'Installed copy from several working directories' {
        BeforeAll {
            $script:Install = New-TestInstalledCopy -Name 'intact'
            $script:LoadedFrom = Import-TestInstalledResourceModule -InstallRoot $script:Install
            $script:WorkDirs = @(
                [System.IO.Path]::Join($TestDrive, 'work-one'),
                [System.IO.Path]::Join($TestDrive, 'work-two', 'nested')
            )
            foreach ($dir in $script:WorkDirs) { $null = [System.IO.Directory]::CreateDirectory($dir) }
        }

        It 'imports the resource module from the installed copy, not the checkout' {
            $script:LoadedFrom | Should -BeLike ([System.IO.Path]::Join($script:Install, '*'))
        }

        It 'loads the same packaged schema artifact from every working directory' {
            $dirs = @($script:WorkDirs) + @($script:RepositoryRoot, [System.IO.Path]::GetTempPath())
            $runs = foreach ($dir in $dirs) {
                Push-Location -LiteralPath $dir
                try { Get-DmProfileSchemaResource -Operation 'profile.load' -Targets @('Campaign/dmassist.yaml') }
                finally { Pop-Location }
            }
            foreach ($run in $runs) {
                $run.passed | Should -BeTrue
                $run.gate | Should -BeExactly 'plugin-resource'
                $run.resource.identity | Should -BeExactly 'plugin:skills/vault-orientation/assets/dmassist.schema.json'
                $run.resource.resourcePath | Should -BeExactly 'skills/vault-orientation/assets/dmassist.schema.json'
                $run.resource.dialect | Should -BeExactly 'https://json-schema.org/draft/2020-12/schema'
                $run.resource.fullPath | Should -BeExactly (Get-TestInstalledSchemaPath -InstallRoot $script:Install)
            }
            @($runs.resource.version | Select-Object -Unique) | Should -Be @($script:RepoSchemaVersion)
            @($runs.resource.fullPath | Select-Object -Unique).Count | Should -Be 1
        }

        It 'accepts the pinned LF and CRLF schema bytes while reporting each raw-byte digest' {
            $install = New-TestInstalledCopy -Name 'line-endings'
            $schemaPath = Get-TestInstalledSchemaPath -InstallRoot $install
            $schemaText = [System.IO.File]::ReadAllText($schemaPath)
            foreach ($lineEnding in @("`n", "`r`n")) {
                $representedText = [regex]::Replace($schemaText, '\r?\n', $lineEnding)
                $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($representedText)
                [System.IO.File]::WriteAllBytes($schemaPath, $bytes)
                $null = Import-TestInstalledResourceModule -InstallRoot $install

                $outcome = Get-DmProfileSchemaResource -Operation 'profile.load'
                $expectedVersion = 'sha256:' + [System.Convert]::ToHexString(
                    [System.Security.Cryptography.SHA256]::HashData($bytes)
                ).ToLowerInvariant()
                $outcome.passed | Should -BeTrue
                $outcome.resource.version | Should -BeExactly $expectedVersion
            }
        }

        It 'validates a version 1 profile and rejects another version with the installed Draft 2020-12 artifact' {
            Push-Location -LiteralPath $script:WorkDirs[1]
            try { $resource = (Get-DmProfileSchemaResource).resource }
            finally { Pop-Location }
            Test-Json -Json '{"version":1}' -Schema $resource.schemaText -ErrorAction SilentlyContinue | Should -BeTrue
            Test-Json -Json '{"version":2}' -Schema $resource.schemaText -ErrorAction SilentlyContinue | Should -BeFalse
            Test-Json -Json '{"version":1,"unexpected":true}' -Schema $resource.schemaText -ErrorAction SilentlyContinue | Should -BeFalse
        }

        It 'loads the same artifact in a fresh process started in another working directory' {
            $modulePath = [System.IO.Path]::Join($script:Install, 'skills', 'vault-orientation', 'scripts', 'PluginResources.psm1')
            $command = "Import-Module -Name '$($modulePath.Replace("'", "''"))' -Force; `$r = Get-DmProfileSchemaResource; [string]`$r.passed + '|' + `$r.resource.version"
            $start = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', $command)) { $start.ArgumentList.Add($argument) }
            $start.WorkingDirectory = $script:WorkDirs[0]
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $start.UseShellExecute = $false
            $process = [System.Diagnostics.Process]::Start($start)
            $output = $process.StandardOutput.ReadToEnd()
            $null = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $process.ExitCode | Should -Be 0
            $output.Trim() | Should -BeExactly "True|$script:RepoSchemaVersion"
        }
    }

    Describe 'Missing or incompatible installed resource' {
        It 'returns RESOURCE_MISSING before profile use when the packaged schema is absent' {
            $install = New-TestInstalledCopy -Name 'missing'
            [System.IO.File]::Delete((Get-TestInstalledSchemaPath -InstallRoot $install))
            $null = Import-TestInstalledResourceModule -InstallRoot $install
            $work = [System.IO.Path]::Join($TestDrive, 'missing-work')
            $null = [System.IO.Directory]::CreateDirectory($work)
            Push-Location -LiteralPath $work
            try { $outcome = Get-DmProfileSchemaResource -Operation 'profile.load' -Targets @('Campaign/dmassist.yaml') }
            finally { Pop-Location }
            Assert-ResourceBlocked -Outcome $outcome -Code 'RESOURCE_MISSING' -InstallRoot $install
            $outcome.evidence[0].state | Should -BeExactly 'missing'
        }

        It 'does not fall back to the checkout or working-directory copy when the installed schema is absent' {
            $install = New-TestInstalledCopy -Name 'no-fallback'
            [System.IO.File]::Delete((Get-TestInstalledSchemaPath -InstallRoot $install))
            $null = Import-TestInstalledResourceModule -InstallRoot $install
            $decoyAssets = [System.IO.Path]::Join($TestDrive, 'decoy', 'assets')
            $null = [System.IO.Directory]::CreateDirectory($decoyAssets)
            [System.IO.File]::Copy($script:RepoSchemaPath, [System.IO.Path]::Join($decoyAssets, 'dmassist.schema.json'))
            [System.IO.File]::Copy($script:RepoSchemaPath, [System.IO.Path]::Join($TestDrive, 'decoy', 'dmassist.schema.json'))
            foreach ($dir in @([System.IO.Path]::Join($TestDrive, 'decoy'), $decoyAssets, $script:RepositoryRoot)) {
                Push-Location -LiteralPath $dir
                try { $outcome = Get-DmProfileSchemaResource -Operation 'profile.load' -Targets @('Campaign/dmassist.yaml') }
                finally { Pop-Location }
                Assert-ResourceBlocked -Outcome $outcome -Code 'RESOURCE_MISSING' -InstallRoot $install
            }
        }

        It 'returns RESOURCE_INCOMPATIBLE before profile use for <Case>' -ForEach @(
            @{ Case = 'malformed JSON'; Alter = { param($p) [System.IO.File]::WriteAllText($p, '{ "title": ') } }
            @{ Case = 'invalid UTF-8'; Alter = { param($p) [System.IO.File]::WriteAllBytes($p, [byte[]](0x7B, 0xFF, 0xFE, 0x7D)) } }
            @{ Case = 'a Draft-07 dialect'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['$schema'] = 'http://json-schema.org/draft-07/schema#' } } }
            @{ Case = 'a different schema identifier'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['$id'] = 'https://example.invalid/other.schema.json' } } }
            @{ Case = 'a different title'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['title'] = 'Synthetic Other Schema' } } }
            @{ Case = 'an open profile object'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['additionalProperties'] = $true } } }
            @{ Case = 'an unpinned profile version'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['properties']['version']['const'] = 2 } } }
            @{ Case = 'an unrequired profile version'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['required'] = @($s['required'] | Where-Object { $_ -cne 'version' }) } } }
            @{ Case = 'an unsupported preparation mode'; Alter = { param($p) Set-TestSchemaJson -Path $p -Change { param($s) $s['properties']['preparation']['properties']['mode']['enum'] = @('session_section', 'unsafe_mode') } } }
        ) {
            $install = New-TestInstalledCopy -Name ('incompatible-' + ($Case -replace '[^a-zA-Z0-9]+', '-'))
            & $Alter (Get-TestInstalledSchemaPath -InstallRoot $install)
            $null = Import-TestInstalledResourceModule -InstallRoot $install
            $work = [System.IO.Path]::Join($install, '..', 'work')
            $null = [System.IO.Directory]::CreateDirectory($work)
            Push-Location -LiteralPath $work
            try { $outcome = Get-DmProfileSchemaResource -Operation 'profile.load' -Targets @('Campaign/dmassist.yaml') }
            finally { Pop-Location }
            Assert-ResourceBlocked -Outcome $outcome -Code 'RESOURCE_INCOMPATIBLE' -InstallRoot $install
        }
    }

    Describe 'Static lookup rules' {
        It 'locates the schema only relative to the owner skill' {
            $source = [System.IO.File]::ReadAllText([System.IO.Path]::Join((Get-TestScriptsRoot), 'PluginResources.psm1'))
            $source | Should -Match ([regex]::Escape('[System.IO.Path]::GetDirectoryName($PSScriptRoot)'))
            $source | Should -Not -Match '(?i)Get-Location|\$PWD|CurrentDirectory|\$env:|GetEnvironmentVariable|vaultRoot|schemas[\\/]'
        }

        It 'ships exactly one packaged schema copy, inside the owner skill' {
            $copies = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File -Filter 'dmassist.schema.json' |
                    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
            $copies.Count | Should -Be 1
            $copies[0].FullName | Should -BeExactly $script:RepoSchemaPath
            [System.IO.Directory]::Exists([System.IO.Path]::Join($script:RepositoryRoot, 'schemas')) | Should -BeFalse
        }
    }
}
