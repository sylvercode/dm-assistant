BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, OperationRequest, VaultBoundary, RuntimePreflight, PluginResources, VaultConfiguration, VaultInventory
    $script:InventoryEntryPoint = Join-Path (Get-TestScriptsRoot) 'Invoke-DmInventory.ps1'

    function Invoke-TestInventoryEntryPoint {
        param([Parameter(Mandatory)][string]$Json)
        $output = $Json | & (Get-Process -Id $PID).Path -NoProfile -File $script:InventoryEntryPoint
        $LASTEXITCODE | Should -Be 0
        $output | ConvertFrom-Json -AsHashtable
    }

    function New-TestInventoryRequest {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$VaultRoot,
            [System.Collections.IDictionary]$Arguments = [ordered]@{},
            [System.Collections.IDictionary]$Extra
        )
        $request = New-TestOperationRequest -VaultRoot $VaultRoot -Operation 'vault.orientation.inventory' -Mode 'inspect' -Targets @() -Arguments $Arguments
        $request['campaignGroup'] = [ordered]@{ campaign = $null; group = $null }
        if ($null -ne $Extra) {
            foreach ($key in $Extra.Keys) { $request[$key] = $Extra[$key] }
        }
        $request
    }

    function Assert-InventoryWrapper {
        param($Outcome)
        @($Outcome.PSObject.Properties.Name) | Should -Be @('result', 'inventoryReport')
        $Outcome.result | Should -Not -BeNullOrEmpty
        @($Outcome.result.changedTargets).Count | Should -Be 0
    }

    function Set-TestGuidanceFile {
        param([string]$VaultRoot, [string]$Path, [string]$Text)
        $absolutePath = Join-Path -Path $VaultRoot -ChildPath $Path
        $parent = [System.IO.Path]::GetDirectoryName($absolutePath)
        if (-not [System.IO.Directory]::Exists($parent)) { [void][System.IO.Directory]::CreateDirectory($parent) }
        [System.IO.File]::WriteAllText($absolutePath, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    function Reset-TestInventoryFixture {
        param([System.Collections.IDictionary]$Notes)
        Remove-TestVaultFixture -Fixture $fixture
        New-TestVaultFixture -ParentPath $TestDrive -Notes $Notes
    }

    function Set-TestGuidanceReadFailureMock {
        param([string]$Path)
        $targetPath = $Path
        $readMock = {
            param($Boundary, $Resolution)
            if ([string]$Resolution.path -ceq $targetPath) {
                return [pscustomobject][ordered]@{ ok = $false; code = 'READ_FAILED'; reason = 'synthetic read failure'; bytes = $null; version = $null }
            }
            $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
            [pscustomobject][ordered]@{
                ok = $true
                code = $null
                reason = ''
                bytes = $bytes
                version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
        }.GetNewClosure()
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultTargetBytes -MockWith $readMock
        Mock -ModuleName VaultInventory -CommandName Read-DmVaultTargetBytes -MockWith $readMock
    }

    function New-TestInventoryFileLink {
        param([string]$Path, [string]$Target)
        try {
            [void][System.IO.File]::CreateSymbolicLink($Path, $Target)
            $true
        }
        catch { $false }
    }

    $script:InventoryFileLinkSkipReason = 'Creating file symbolic links requires Windows Developer Mode or elevation in this environment.'
}

Describe 'Caller-confirmed inventory without an authorization test provider' {
    BeforeEach {
        $fixture = New-TestVaultFixture -ParentPath $TestDrive
        $request = New-TestInventoryRequest -VaultRoot $fixture.Root
        $request.callerPreflight = [ordered]@{
            vaultRoot = $fixture.Root
            dependenciesReady = $true
            vaultAuthorized = $true
        }
    }

    AfterEach { Remove-TestVaultFixture -Fixture $fixture }

    It 'accepts matching caller confirmation and produces an inventory' {
        $outcome = Invoke-DmInventory -Request $request
        $outcome.result.completionCode | Should -BeExactly 'OK'
        $outcome.inventoryReport.operation | Should -BeExactly 'vault.orientation.inventory'
    }

    It 'uses the shipped entry point for names-only inventory without modifying the vault' {
        $inputData = [ordered]@{
            vaultRoot = $fixture.Root
            callerPreflight = $request.callerPreflight
        }
        $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
        $outcome = Invoke-TestInventoryEntryPoint -Json (ConvertTo-Json -InputObject $inputData -Depth 10 -Compress)
        $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

        $outcome.result.completionCode | Should -BeExactly 'OK'
        $outcome.inventoryReport.scan.contentInspected | Should -BeFalse
        $outcome.inventoryReport.guidance.contentInspectionBasis | Should -BeExactly 'names_only'
        @($outcome.inventoryReport.entries | ForEach-Object { $_.path }) | Should -Contain 'Adventures'
        $after | Should -BeExactly $before
    }

    It 'returns a review-only proposal through the shipped entry point' {
        $inputData = [ordered]@{
            vaultRoot = $fixture.Root
            callerPreflight = $request.callerPreflight
            proposeProfile = $true
        }
        $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
        $outcome = Invoke-TestInventoryEntryPoint -Json (ConvertTo-Json -InputObject $inputData -Depth 10 -Compress)
        $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

        $outcome.result.completionCode | Should -BeExactly 'OK'
        $outcome.inventoryReport.profileProposal.status | Should -BeExactly 'drafted-unapproved'
        $outcome.inventoryReport.profileProposal.content | Should -Not -BeNullOrEmpty
        $after | Should -BeExactly $before
    }

    It 'rejects missing caller confirmation before accessing the vault' {
        $inputData = [ordered]@{ vaultRoot = $fixture.Root }
        $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
        $outcome = Invoke-TestInventoryEntryPoint -Json (ConvertTo-Json -InputObject $inputData -Depth 10 -Compress)
        $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

        $outcome.result.completionCode | Should -BeExactly 'PREREQUISITE_MISSING'
        $outcome.inventoryReport | Should -BeNull
        $after | Should -BeExactly $before
    }

    It 'rejects negative exact-root authorization before accessing the vault' {
        $inputData = [ordered]@{
            vaultRoot = $fixture.Root
            callerPreflight = [ordered]@{
                vaultRoot = $fixture.Root
                dependenciesReady = $true
                vaultAuthorized = $false
            }
        }
        $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
        $outcome = Invoke-TestInventoryEntryPoint -Json (ConvertTo-Json -InputObject $inputData -Depth 10 -Compress)
        $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

        $outcome.result.completionCode | Should -BeExactly 'VAULT_AUTHORIZATION_UNPROVEN'
        $outcome.inventoryReport | Should -BeNull
        $after | Should -BeExactly $before
    }

    It 'rejects unknown wrapper fields as an invalid request' {
        $inputData = [ordered]@{
            vaultRoot = $fixture.Root
            callerPreflight = $request.callerPreflight
            unexpected = 'ignored fields must not become behavior'
        }
        $outcome = Invoke-TestInventoryEntryPoint -Json (ConvertTo-Json -InputObject $inputData -Depth 10 -Compress)
        $outcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
        $outcome.inventoryReport | Should -BeNull
    }

    It 'rejects malformed JSON as an invalid request' {
        $outcome = Invoke-TestInventoryEntryPoint -Json '{"vaultRoot":'

        $outcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
        $outcome.inventoryReport | Should -BeNull
    }

    It 'inventories an article created through the shipped authoring workflow' {
        Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.dmassist-guidance.md' -Text 'Use synthetic conventions.'
        $article = [ordered]@{
            vaultRoot = $fixture.Root
            callerPreflight = $request.callerPreflight
            campaignGroup = @{ campaign = 'Test'; group = 'Test' }
            articleType = 'character'
            destination = 'New Character.md'
            operation = 'note.create-article'
        }
        $entryPoint = Join-Path (Get-TestRepositoryRoot) 'skills\article-authoring\scripts\Invoke-DmArticleAuthoring.ps1'
        function Invoke-IntegrationArticleStage($Action, $InputRequest) {
            $json = ConvertTo-Json -InputObject $InputRequest -Depth 10 -Compress
            $output = $json | & (Get-Process -Id $PID).Path -NoProfile -File $entryPoint -Action $Action
            $LASTEXITCODE | Should -Be 0
            $output | ConvertFrom-Json
        }
        $prepared = Invoke-IntegrationArticleStage prepare $article
        $prepared.guidance.text | Should -BeExactly 'Use synthetic conventions.'
        $article.preparationId = $prepared.preparationId
        $article.content = $prepared.template.text.Replace('<!-- fill-in: required Character name -->', 'Ash Fen')
        $preview = Invoke-IntegrationArticleStage preview $article
        $preview.result.completionCode | Should -BeExactly 'OK'
        $article.previewId = $preview.preview.previewId
        (Invoke-IntegrationArticleStage apply $article).result.completionCode | Should -BeExactly 'OK'

        $outcome = Invoke-DmInventory -Request $request
        $outcome.result.completionCode | Should -BeExactly 'OK'
        @($outcome.inventoryReport.entries | ForEach-Object { $_.path }) | Should -Contain 'New Character.md'
    }

    It 'blocks <scenario> before profile, guidance, or note reads' -TestCases @(
        @{ scenario = 'missing confirmation'; change = 'missing'; code = 'PREREQUISITE_MISSING' }
        @{ scenario = 'negative readiness'; change = 'readiness'; code = 'PREREQUISITE_MISSING' }
        @{ scenario = 'negative authorization'; change = 'authorization'; code = 'VAULT_AUTHORIZATION_UNPROVEN' }
        @{ scenario = 'wrong-root authorization'; change = 'root'; code = 'VAULT_AUTHORIZATION_UNPROVEN' }
    ) {
        param($change, $code)
        switch ($change) {
            'missing' { $request.Remove('callerPreflight') }
            'readiness' { $request.callerPreflight.dependenciesReady = $false }
            'authorization' { $request.callerPreflight.vaultAuthorized = $false }
            'root' { $request.callerPreflight.vaultRoot = $fixture.OutsidePath }
        }
        Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith {
            throw 'Profile read before caller preflight passed.'
        }
        Mock -ModuleName VaultInventory -CommandName Read-DmVaultTargetBytes -MockWith {
            throw 'Guidance or note read before caller preflight passed.'
        }

        $outcome = Invoke-DmInventory -Request $request
        $outcome.result.completionCode | Should -BeExactly $code
        $outcome.inventoryReport | Should -BeNull
        Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName VaultInventory -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
    }
}

Describe 'Read-only vault orientation and inventory' {
    BeforeEach {
        Set-TestDependencyReadiness -State ready
        $fixture = New-TestVaultFixture -ParentPath $TestDrive
        $request = New-TestInventoryRequest -VaultRoot $fixture.Root
    }

    AfterEach { Remove-TestVaultFixture -Fixture $fixture }

    Context 'US1 preflight and guidance gates' {
        It 'exports the inventory runtime API for internal use' {
            $modulePath = Join-Path -Path (Get-TestScriptsRoot) -ChildPath 'VaultInventory.psm1'
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            (Get-Command -Name Invoke-DmInventory -Module VaultInventory -ErrorAction Stop).Name | Should -BeExactly 'Invoke-DmInventory'

            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.operation | Should -BeExactly 'vault.orientation.inventory'
            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.schemaVersion | Should -Be 1
            $outcome.inventoryReport.operation | Should -BeExactly 'vault.orientation.inventory'
        }

        It 'returns the shared wrapper with a null report for invalid request shape before vault reads' {
            $invalid = New-TestInventoryRequest -VaultRoot $fixture.Root
            $invalid['mode'] = 'preview'
            Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith {
                throw 'Profile read before request-shape validation.'
            }

            $outcome = Invoke-DmInventory -Request $invalid

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
            $outcome.inventoryReport | Should -BeNull
            Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
        }

        It 'stops on missing dependencies before authorization, profile, or guidance access' {
            Set-TestDependencyReadiness -State missing
            Mock -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -MockWith {
                throw 'Authorization was checked before dependency readiness.'
            }
            Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith {
                throw 'Profile read before dependency readiness.'
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'PREREQUISITE_MISSING'
            $outcome.inventoryReport | Should -BeNull
            Should -Invoke -ModuleName DependencyPreflight -CommandName Get-DmVaultAuthorization -Times 0 -Exactly -Scope It
            Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
        }

        It 'does not read the profile or guidance when exact-vault authorization is unproven' {
            Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith {
                throw 'Profile read before exact-vault authorization.'
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'VAULT_AUTHORIZATION_UNPROVEN'
            $outcome.inventoryReport | Should -BeNull
            Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
        }

        It 'blocks a present invalid profile without conventional discovery or a partial report' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nunknown: value`n")
            Mock -ModuleName VaultConfiguration -CommandName Get-DmVaultDiscovery -MockWith {
                throw 'Discovery ran for an invalid present profile.'
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'PROFILE_SCHEMA_INVALID'
            $outcome.inventoryReport | Should -BeNull
            Should -Invoke -ModuleName VaultConfiguration -CommandName Get-DmVaultDiscovery -Times 0 -Exactly -Scope It
        }

        It 'validates selected guidance before discovery and reports only the shared failure shape' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Required.md')
                optionalGuidance = [string[]]@()
            }
            Mock -ModuleName VaultConfiguration -CommandName Get-DmVaultDiscovery -MockWith {
                throw 'Discovery ran before selected guidance validation.'
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'REFERENCE_UNAVAILABLE'
            $outcome.inventoryReport | Should -BeNull
            Should -Invoke -ModuleName VaultConfiguration -CommandName Get-DmVaultDiscovery -Times 0 -Exactly -Scope It
        }

        It 'allows absent or all-skipped optional guidance to produce a names-only report' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $selectedPath = 'Selected/Missing.md'
            $optionalPath = if ($IsWindows) { 'selected/missing.md' } else { $selectedPath }
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@($selectedPath)
                optionalGuidance = [string[]]@($optionalPath)
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.scan.contentInspected | Should -BeFalse
            $outcome.inventoryReport.guidance.contentInspectionBasis | Should -BeExactly 'names_only'
            @($outcome.inventoryReport.guidance.skippedOptionalSources).Count | Should -Be 1
            $outcome.inventoryReport.guidance.skippedOptionalSources[0].selectionIndex | Should -Be 0
            $outcome.inventoryReport.guidance.skippedOptionalSources[0].reason | Should -BeExactly 'missing'
        }

        It 'loads dot-prefixed Markdown only when explicitly selected' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.dm-extra-guidance.md' -Text "# Extra`nUse the selected source for synthetic orientation.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('.dm-extra-guidance.md') }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.guidance.requestSelectedLoaded | Should -Be @('.dm-extra-guidance.md')
            $outcome.inventoryReport.guidance.contentInspectionBasis | Should -BeExactly 'guidance_loaded'
        }

        It 'does not treat a profile or the shared reference alone as authority to inspect note content' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`n")

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.scan.contentInspected | Should -BeFalse
            $outcome.inventoryReport.guidance.contentInspectionBasis | Should -BeExactly 'names_only'
            @($outcome.inventoryReport.candidateMappings | Where-Object classification -EQ 'observed').Count | Should -Be 0
        }

        It 'rechecks loaded guidance and profile dependencies before returning a report' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Required.md' -Text "# Required`nSynthetic guidance body.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Required.md') }
            Mock -ModuleName VaultInventory -CommandName Test-DmInventoryDependencies -MockWith {
                [pscustomobject]@{ passed = $false; code = 'TARGET_CONFLICT'; changedIdentities = @('Selected/Required.md') }
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
            $outcome.inventoryReport | Should -BeNull
        }

        It 'deduplicates case-insensitive configured and selected guidance dependencies' {
            if (-not $IsWindows) {
                Set-ItResult -Skipped -Because 'case-insensitive vault paths are specific to Windows'
                return
            }
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.dmassist-guidance.md' -Text "# Guidance`nSynthetic guidance body.`n"
            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nguidance:`n  path: .dmassist-guidance.md`n")
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('.DMASSIST-GUIDANCE.md')
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.guidance.loadedSources.Count | Should -Be 2
            $outcome.inventoryReport.guidance.loadedSources[0].selectionKind | Should -BeExactly 'configured'
            $outcome.inventoryReport.guidance.loadedSources[1].selectionKind | Should -BeExactly 'request-selected'
            $outcome.inventoryReport.guidance.loadedSources[1].path | Should -BeExactly '.DMASSIST-GUIDANCE.md'
        }
    }

    Context 'US1 selected guidance usability' {
        It 'blocks essential guidance that is <Case>' -ForEach @(
            @{ Case = 'missing'; Path = 'Selected/Missing.md'; Text = $null }
            @{ Case = 'unreadable'; Path = 'Selected/Unreadable.md'; Text = "Synthetic guidance body.`n" }
            @{ Case = 'non-Markdown'; Path = 'Selected/NonMarkdown.txt'; Text = "Synthetic guidance body.`n" }
            @{ Case = 'empty'; Path = 'Selected/Empty.md'; Text = '' }
            @{ Case = 'whitespace-only'; Path = 'Selected/Whitespace.md'; Text = " `n`t`n" }
            @{ Case = 'frontmatter-only'; Path = 'Selected/Frontmatter.md'; Text = "---`ntitle: Synthetic`n---`n" }
            @{ Case = 'heading-only'; Path = 'Selected/Heading.md'; Text = "# Heading only`n## Another heading`n" }
        ) {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            if ($null -ne $Text) { Set-TestGuidanceFile -VaultRoot $fixture.Root -Path $Path -Text $Text }
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@($Path) }
            if ($Case -ceq 'unreadable') {
                Set-TestGuidanceReadFailureMock -Path $Path
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'REFERENCE_UNAVAILABLE'
            $outcome.inventoryReport | Should -BeNull
        }

        It 'skips optional missing, unreadable, non-Markdown, and unusable sources without exposing their paths' -ForEach @(
            @{ Reason = 'missing'; Path = 'Selected/Missing.md'; Text = $null }
            @{ Reason = 'unreadable'; Path = 'Selected/Unreadable.md'; Text = "Synthetic body.`n" }
            @{ Reason = 'non-markdown'; Path = 'Selected/NonMarkdown.txt'; Text = "Synthetic body.`n" }
            @{ Reason = 'unusable'; Path = 'Selected/Unusable.md'; Text = "# Only a heading`n" }
        ) {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Usable`nAn additional selected source allows names-only or content inspection.`n"
            if ($null -ne $Text) { Set-TestGuidanceFile -VaultRoot $fixture.Root -Path $Path -Text $Text }
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Usable.md', $Path)
                optionalGuidance = [string[]]@($Path)
            }
            if ($Reason -ceq 'unreadable') {
                Set-TestGuidanceReadFailureMock -Path $Path
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'OK'
            @($outcome.inventoryReport.guidance.skippedOptionalSources).Count | Should -Be 1
            $outcome.inventoryReport.guidance.skippedOptionalSources[0].selectionIndex | Should -Be 1
            $outcome.inventoryReport.guidance.skippedOptionalSources[0].reason | Should -BeExactly $Reason
            $serialized = $outcome.inventoryReport | ConvertTo-Json -Depth 20
            $serialized | Should -Not -Match ([regex]::Escape($Path))
        }

        It 'does not let optional selection weaken a configured required guidance source' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nguidance:`n  path: Selected/Required.md`n")
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Required.md')
                optionalGuidance = [string[]]@('Selected/Required.md')
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'REFERENCE_UNAVAILABLE'
            $outcome.inventoryReport | Should -BeNull
        }

        It 'never skips invalid lexical paths or uncontained selections' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('../outside.md')
                optionalGuidance = [string[]]@('../outside.md')
            }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'PATH_INVALID'
            $outcome.inventoryReport | Should -BeNull
        }

        It 'loads usable but silent guidance without requiring every location to be described' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Silent.md' -Text "# Guidance`nThis source does not assign any campaign folder.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Silent.md') }

            $outcome = Invoke-DmInventory -Request $request

            Assert-InventoryWrapper -Outcome $outcome
            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.guidance.requestSelectedLoaded | Should -Be @('Selected/Silent.md')
            $outcome.inventoryReport.guidance.contentInspectionBasis | Should -BeExactly 'guidance_loaded'
        }
    }

    Context 'US2 inventory traversal and evidence' {
        It 'matches the six layout oracles and leaves each fixture unchanged' {
            $layouts = @(
                @{
                    Name = 'root-level adventure'
                    Notes = [ordered]@{
                        'The Glass Comet Adventure.md' = "# The Glass Comet`nSynthetic adventure.`n"
                        'Unrelated Root Note.md' = "# Unrelated`nSynthetic unrelated note.`n"
                        'Arcade.md' = "# Arcade`nSynthetic title without a whole-word role token.`n"
                    }
                    Guidance = $null
                    Entries = @(
                        'Arcade.md|markdown'
                        'The Glass Comet Adventure.md|markdown'
                        'Unrelated Root Note.md|markdown'
                    )
                    Expected = @('Adventures|The Glass Comet Adventure.md|inferred|entry-name')
                    Unsupported = @('Unrelated Root Note.md', 'Arcade.md')
                }
                @{
                    Name = 'single-file conventional section'
                    Notes = [ordered]@{ 'Adventures/The Glass Comet.md' = "# The Glass Comet`nSynthetic adventure.`n" }
                    Guidance = $null
                    Entries = @('Adventures|directory', 'Adventures/The Glass Comet.md|markdown')
                    Expected = @('Adventures|Adventures|inferred|default-convention')
                    Unsupported = 'Adventures/The Glass Comet.md'
                }
                @{
                    Name = 'folder-based arc'
                    Notes = [ordered]@{ 'Adventures/Arc - The Glass Comet/Encounters.md' = "# Encounters`nSynthetic encounter.`n" }
                    Guidance = $null
                    Entries = @(
                        'Adventures|directory'
                        'Adventures/Arc - The Glass Comet|directory'
                        'Adventures/Arc - The Glass Comet/Encounters.md|markdown'
                    )
                    Expected = @(
                        'Adventures|Adventures|inferred|default-convention'
                        'Adventure|Adventures/Arc - The Glass Comet|inferred|folder-name'
                    )
                    Unsupported = 'Adventures/Arc - The Glass Comet/Encounters.md'
                }
                @{
                    Name = 'mixed files and arcs'
                    Notes = [ordered]@{
                        'Adventures/Adventure - The Glass Comet.md' = "# Glass Comet`nSynthetic adventure.`n"
                        'Adventures/Arc - Iron Crown/Session 1.md' = "# Session 1`nSynthetic session.`n"
                        'Unrelated Root Note.md' = "# Unrelated`nSynthetic unrelated note.`n"
                    }
                    Guidance = $null
                    Entries = @(
                        'Adventures|directory'
                        'Adventures/Adventure - The Glass Comet.md|markdown'
                        'Adventures/Arc - Iron Crown|directory'
                        'Adventures/Arc - Iron Crown/Session 1.md|markdown'
                        'Unrelated Root Note.md|markdown'
                    )
                    Expected = @(
                        'Adventures|Adventures|inferred|default-convention'
                        'Adventure|Adventures/Adventure - The Glass Comet.md|inferred|entry-name'
                        'Adventure|Adventures/Arc - Iron Crown|inferred|folder-name'
                    )
                    Unsupported = 'Unrelated Root Note.md'
                }
                @{
                    Name = 'renamed section'
                    Notes = [ordered]@{ 'Chronicles/The Glass Comet.md' = "# The Glass Comet`nSynthetic adventure.`n" }
                    Guidance = 'Chronicles contains adventures.'
                    Entries = @(
                        'Chronicles|directory'
                        'Chronicles/The Glass Comet.md|markdown'
                        'Selected|directory'
                    )
                    Expected = @('Adventures|Chronicles|observed|dm-selected-guidance')
                    Unsupported = 'Chronicles/The Glass Comet.md'
                }
                @{
                    Name = 'additional Lore sections'
                    Notes = [ordered]@{
                        'Lore/Locations/Harbor.md' = "# Harbor`nSynthetic location.`n"
                        'Lore/Cosmology/Planes.md' = "# Planes`nSynthetic cosmology.`n"
                    }
                    Guidance = $null
                    Entries = @(
                        'Lore|directory'
                        'Lore/Cosmology|directory'
                        'Lore/Cosmology/Planes.md|markdown'
                        'Lore/Locations|directory'
                        'Lore/Locations/Harbor.md|markdown'
                    )
                    Expected = @(
                        'Lore|Lore|inferred|default-convention'
                        'Lore/Locations|Lore/Locations|inferred|default-convention'
                        'Lore/Cosmology|Lore/Cosmology|inferred|default-convention'
                    )
                    Unsupported = 'Lore/Locations/Harbor.md'
                }
            )

            foreach ($layout in $layouts) {
                $fixture = Reset-TestInventoryFixture -Notes $layout.Notes
                $request = New-TestInventoryRequest -VaultRoot $fixture.Root
                Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
                if ($null -ne $layout.Guidance) {
                    Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text $layout.Guidance
                    $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Layout.md') }
                }
                $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

                $outcome = Invoke-DmInventory -Request $request

                $outcome.result.completionCode | Should -BeExactly 'OK' -Because $layout.Name
                $outcome.inventoryReport | Should -Not -BeNull
                $actual = @($outcome.inventoryReport.candidateMappings | ForEach-Object {
                    '{0}|{1}|{2}|{3}' -f $_.role, $_.path, $_.classification, $_.basis[0]
                })
                foreach ($expected in $layout.Expected) { $actual | Should -Contain $expected -Because $layout.Name }
                $actualEntries = [string[]]@($outcome.inventoryReport.entries | ForEach-Object { '{0}|{1}' -f $_.path, $_.kind })
                $actualEntries | Should -Be $layout.Entries -Because $layout.Name
                $paths = @($outcome.inventoryReport.entries | ForEach-Object { [string]$_.path })
                $mappedPaths = @($outcome.inventoryReport.candidateMappings | ForEach-Object { [string]$_.path })
                foreach ($unsupported in $layout.Unsupported) {
                    $paths | Should -Contain $unsupported
                    $mappedPaths | Should -Not -Contain $unsupported
                }
                $serialized = ConvertTo-Json -InputObject $outcome.inventoryReport -Depth 30 -Compress
                $serialized | Should -Not -Match ([regex]::Escape($fixture.Root))
                $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
                $after | Should -BeExactly $before -Because $layout.Name
            }
        }

        It 'excludes dot-prefixed and non-Markdown files while retaining suffixed directories and hidden Markdown' {
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.ignored.md' -Text "# Hidden`nMust not be inventoried.`n"
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.private/secret.md' -Text "# Secret`nMust not be inventoried.`n"
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Suffix.txt/Visible.md' -Text "# Visible`nEligible beneath a suffixed directory.`n"
            [System.IO.File]::WriteAllText((Join-Path $fixture.Root 'attachment.bin'), 'NONMARKER')
            [System.IO.File]::WriteAllText((Join-Path $fixture.Root 'readme.txt'), 'NONMARKER')
            [System.IO.File]::WriteAllText((Join-Path $fixture.Root 'map.png'), 'NONMARKER')
            $hiddenPath = Join-Path $fixture.Root 'Hidden.md'
            [System.IO.File]::WriteAllText($hiddenPath, "# Hidden Attribute`nEligible Markdown.`n")
            try { [System.IO.File]::SetAttributes($hiddenPath, [System.IO.FileAttributes]::Hidden -bor [System.IO.File]::GetAttributes($hiddenPath)) }
            catch { }
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Usable.md') }
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nAllow note inspection.`n"

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'OK'
            $paths = @($outcome.inventoryReport.entries | ForEach-Object { [string]$_.path })
            $paths | Should -Contain 'Suffix.txt'
            $paths | Should -Contain 'Suffix.txt/Visible.md'
            $paths | Should -Contain 'Hidden.md'
            $paths | Should -Not -Contain '.ignored.md'
            $paths | Should -Not -Contain '.private'
            $paths | Should -Not -Contain '.private/secret.md'
            $serialized = ConvertTo-Json -InputObject $outcome.inventoryReport -Depth 30 -Compress
            foreach ($name in @('attachment.bin', 'readme.txt', 'map.png')) {
                $serialized | Should -Not -Match ([regex]::Escape($name))
            }
            $outcome.inventoryReport.scan.dotPrefixedEntriesExcluded | Should -BeTrue
            $outcome.inventoryReport.scan.nonMarkdownEntriesExcluded | Should -BeTrue
            $outcome.inventoryReport.scan.nonDotMarkdownIncludedRegardlessOfOsAttributes | Should -BeTrue
            $outcome.inventoryReport.scan.nonMarkdownContentsRead | Should -BeFalse
            $outcome.inventoryReport.scan.attachmentContentsRead | Should -BeFalse
        }

        It 'does not follow a directory link during traversal' {
            $linkPath = Join-Path $fixture.Root 'Linked'
            try { [void][System.IO.Directory]::CreateSymbolicLink($linkPath, (Join-Path $fixture.Root 'Adventures')) }
            catch {
                try { $null = New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $fixture.Root 'Adventures') -ErrorAction Stop }
                catch { Set-ItResult -Skipped -Because 'directory links cannot be created here'; return }
            }
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'OK'
            $paths = @($outcome.inventoryReport.entries | ForEach-Object { [string]$_.path })
            $paths | Should -Contain 'Linked'
            $paths | Should -Not -Contain 'Linked/Synthetic Arc.md'
        }

        It 'uses a loaded local guidance source as the only gate for note-content inspection' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root

            $namesOnly = Invoke-DmInventory -Request $request

            $namesOnly.result.completionCode | Should -BeExactly 'OK'
            $namesOnly.inventoryReport.scan.contentInspected | Should -BeFalse
            $namesOnly.inventoryReport.candidateMappings | Should -Not -Contain 'markdown-content'

            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nA valid local source opens the inspection gate.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Usable.md') }
            $guided = Invoke-DmInventory -Request $request

            $guided.result.completionCode | Should -BeExactly 'OK'
            $guided.inventoryReport.scan.contentInspected | Should -BeTrue
            @($guided.inventoryReport.entries | ForEach-Object { [string]$_.path }) | Should -Contain 'Adventures/Synthetic Arc.md'
        }

        It 'returns only the documented ordered fields and evidence-backed mapping record shapes' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $outcome = Invoke-DmInventory -Request $request
            $report = $outcome.inventoryReport

            @($report.PSObject.Properties.Name) | Should -Be @(
                'schemaVersion', 'operation', 'scan', 'guidance', 'entries',
                'candidateMappings', 'ambiguities', 'profileProposal'
            )
            @($report.scan.PSObject.Properties.Name) | Should -Be @(
                'contentInspected', 'dotPrefixedEntriesExcluded', 'nonMarkdownEntriesExcluded',
                'nonDotMarkdownIncludedRegardlessOfOsAttributes', 'nonMarkdownContentsRead', 'attachmentContentsRead'
            )
            foreach ($entry in $report.entries) {
                @($entry.PSObject.Properties.Name) | Should -Be @('path', 'kind')
                $entry.kind | Should -BeIn @('directory', 'markdown')
            }
            foreach ($mapping in $report.candidateMappings) {
                @($mapping.PSObject.Properties.Name) | Should -Be @(
                    'role', 'path', 'classification', 'basis', 'evidence', 'uncertainty'
                )
                $mapping.role | Should -Not -BeNullOrEmpty
                $mapping.path | Should -Not -BeNullOrEmpty
                $mapping.classification | Should -BeIn @('observed', 'inferred')
                @($mapping.basis).Count | Should -BeGreaterThan 0
                @($mapping.evidence).Count | Should -BeGreaterThan 0
                foreach ($evidence in $mapping.evidence) {
                    @($evidence.PSObject.Properties.Name) | Should -Be @('basis', 'source', 'summary')
                    $mapping.basis | Should -Contain $evidence.basis
                    $evidence.summary | Should -Not -BeNullOrEmpty
                }
                if ($mapping.classification -ceq 'inferred') { $mapping.uncertainty | Should -Not -BeNullOrEmpty }
                else { $mapping.uncertainty | Should -BeNull }
            }
            $paths = [string[]]@($report.entries | ForEach-Object { [string]$_.path })
            $sortedPaths = [string[]]$paths.Clone()
            [Array]::Sort($sortedPaths, [System.StringComparer]::OrdinalIgnoreCase)
            $paths | Should -Be $sortedPaths
        }

        It 'reports an observed profile mapping and keeps conflicts informational for orientation' {
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nsections:`n  adventures: Chronicles`n")
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $request.requestId = [guid]::NewGuid().ToString()

            $first = Invoke-DmInventory -Request $request
            $first.result.completionCode | Should -BeExactly 'OK'
            $configured = @($first.inventoryReport.candidateMappings | Where-Object { $_.path -ceq 'Chronicles' -and $_.role -ceq 'Adventures' })
            $configured.Count | Should -Be 1
            $configured[0].classification | Should -BeExactly 'observed'
            $configured[0].basis | Should -Contain 'profile-configured'
            $first.inventoryReport.ambiguities.Count | Should -BeGreaterThan 0
            $first.inventoryReport.ambiguities[0].requiresDmDecision | Should -BeFalse
            @($first.inventoryReport.ambiguities[0].alternatives).Count | Should -BeGreaterOrEqual 2
            $id = [string]$first.inventoryReport.ambiguities[0].ambiguityId
            $request.requestId = [guid]::NewGuid().ToString()

            $second = Invoke-DmInventory -Request $request

            $second.inventoryReport.ambiguities[0].ambiguityId | Should -BeExactly $id
            $second.inventoryReport | ConvertTo-Json -Depth 30 -Compress | Should -Not -Match ([regex]::Escape($fixture.Root))
        }

        It 'uses explicit Markdown role evidence only after guidance opens the content gate' {
            [System.IO.File]::WriteAllText(
                $fixture.NotePaths[1],
                "---`ntype: location`n---`nThis note is an adventure.`nSynthetic content.`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Usable.md')
            }
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nExplicit local guidance permits note inspection.`n"

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'OK'
            $outcome.inventoryReport.scan.contentInspected | Should -BeTrue
            $loreNote = @($outcome.inventoryReport.candidateMappings | Where-Object { $_.path -ceq 'Lore/Invented Town.md' -and $_.role -ceq 'Lore/Locations' })
            $loreNote.Count | Should -Be 1
            $loreNote[0].basis | Should -Contain 'frontmatter'
            $loreNote[0].classification | Should -BeExactly 'inferred'
            $loreNote[0].evidence[0].summary | Should -Not -BeLike '*This note is an adventure*'
        }

        It 'does not read note contents in names-only mode and rechecks every note evidence version' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $readPaths = [System.Collections.Generic.List[string]]::new()
            $readMock = {
                param($Boundary, $Resolution)
                $readPaths.Add([string]$Resolution.path)
                $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
                [pscustomobject]@{
                    ok = $true
                    code = $null
                    reason = ''
                    bytes = $bytes
                    version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
                }
            }.GetNewClosure()
            Mock -ModuleName VaultInventory -CommandName Read-DmVaultTargetBytes -MockWith $readMock

            $namesOnly = Invoke-DmInventory -Request $request
            $namesOnly.result.completionCode | Should -BeExactly 'OK'
            $readPaths.Count | Should -Be 0

            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nPermit synthetic note inspection.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Usable.md') }
            $readPaths.Clear()
            $guided = Invoke-DmInventory -Request $request

            $guided.result.completionCode | Should -BeExactly 'OK'
            $guided.inventoryReport.scan.contentInspected | Should -BeTrue
            $readPaths | Should -Contain 'Adventures/Synthetic Arc.md'
            $readPaths | Should -Contain 'Lore/Invented Town.md'
            @($readPaths | Where-Object { $_ -ceq 'Selected/Usable.md' }).Count | Should -Be 1
        }

        It 'rechecks note evidence and returns no partial report when evidence changes' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nPermit synthetic note inspection.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Usable.md') }
            $racePath = 'Adventures/Synthetic Arc.md'
            $readCount = 0
            $readMock = {
                param($Boundary, $Resolution)
                if ([string]$Resolution.path -ceq $racePath) {
                    $script:inventoryRaceReadCount++
                    $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
                    if ($script:inventoryRaceReadCount -gt 1) { $bytes = [System.Text.Encoding]::UTF8.GetBytes('changed synthetic evidence') }
                    return [pscustomobject]@{
                        ok = $true
                        code = $null
                        reason = ''
                        bytes = $bytes
                        version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
                    }
                }
                $actualBytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
                [pscustomobject]@{
                    ok = $true
                    code = $null
                    reason = ''
                    bytes = $actualBytes
                    version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($actualBytes)).ToLowerInvariant()
                }
            }.GetNewClosure()
            $script:inventoryRaceReadCount = 0
            Mock -ModuleName VaultInventory -CommandName Read-DmVaultTargetBytes -MockWith $readMock

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
            $outcome.inventoryReport | Should -BeNull
        }

        It 'reports only contained Markdown file links and rejects escaping links before any outside read' {
            $secretPath = Join-Path $fixture.Root '.private\secret.md'
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($secretPath))
            [System.IO.File]::WriteAllText($secretPath, "# Private`nSynthetic private content.`n")
            $nonMarkdownPath = Join-Path $fixture.Root 'attachment.txt'
            [System.IO.File]::WriteAllText($nonMarkdownPath, 'NONMARKER')
            $safeLink = Join-Path $fixture.Root 'Alias.md'
            $nonMarkdownLink = Join-Path $fixture.Root 'NonMarkdownTarget.md'
            $dotTargetLink = Join-Path $fixture.Root 'DotTarget.md'
            if (-not (New-TestInventoryFileLink -Path $safeLink -Target $fixture.NotePaths[1]) -or
                -not (New-TestInventoryFileLink -Path $nonMarkdownLink -Target $nonMarkdownPath) -or
                -not (New-TestInventoryFileLink -Path $dotTargetLink -Target $secretPath)) {
                Set-ItResult -Skipped -Because $script:InventoryFileLinkSkipReason
                return
            }
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nPermit synthetic note inspection.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Usable.md') }

            $safeOutcome = Invoke-DmInventory -Request $request
            $safeOutcome.result.completionCode | Should -BeExactly 'OK'
            $safePaths = @($safeOutcome.inventoryReport.entries | ForEach-Object { [string]$_.path })
            $safePaths | Should -Contain 'Alias.md'
            $safePaths | Should -Not -Contain 'NonMarkdownTarget.md'
            $safePaths | Should -Not -Contain 'DotTarget.md'

            $escapeLink = Join-Path $fixture.Root 'Escape.md'
            if (-not (New-TestInventoryFileLink -Path $escapeLink -Target (Join-Path $fixture.OutsidePath 'secret.md'))) {
                Set-ItResult -Skipped -Because $script:InventoryFileLinkSkipReason
                return
            }
            $readPaths = [System.Collections.Generic.List[string]]::new()
            $readMock = {
                param($Boundary, $Resolution)
                $readPaths.Add([string]$Resolution.path)
                if (-not [string]$Resolution.resolvedPath.StartsWith([string]$Boundary.canonicalRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'An outside target was opened.'
                }
                $bytes = [System.IO.File]::ReadAllBytes([string]$Resolution.resolvedPath)
                [pscustomobject]@{
                    ok = $true
                    code = $null
                    reason = ''
                    bytes = $bytes
                    version = 'sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
                }
            }.GetNewClosure()
            Mock -ModuleName VaultInventory -CommandName Read-DmVaultTargetBytes -MockWith $readMock

            $escapeOutcome = Invoke-DmInventory -Request $request

            $escapeOutcome.result.completionCode | Should -BeExactly 'PATH_OUTSIDE_VAULT'
            $escapeOutcome.inventoryReport | Should -BeNull
            $readPaths | Should -Not -Contain 'Escape.md'

            [System.IO.File]::Delete($escapeLink)
            $cycleOne = Join-Path $fixture.Root 'CycleOne.md'
            $cycleTwo = Join-Path $fixture.Root 'CycleTwo.md'
            if (-not (New-TestInventoryFileLink -Path $cycleOne -Target 'CycleTwo.md') -or
                -not (New-TestInventoryFileLink -Path $cycleTwo -Target 'CycleOne.md')) {
                Set-ItResult -Skipped -Because $script:InventoryFileLinkSkipReason
                return
            }
            $cycleOutcome = Invoke-DmInventory -Request $request
            $cycleOutcome.result.completionCode | Should -BeExactly 'PATH_OUTSIDE_VAULT'
            $cycleOutcome.inventoryReport | Should -BeNull
        }

        It 'requires current DM direction for proposal-affecting alternatives and binds IDs to the vault' {
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nsections:`n  adventures: Chronicles`n")
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $request.arguments = [ordered]@{ proposeProfile = $true }

            $proposalRequest = Invoke-DmInventory -Request $request

            $proposalRequest.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $proposalRequest.inventoryReport | Should -Not -BeNull
            $proposalRequest.inventoryReport.ambiguities.Count | Should -BeGreaterThan 0
            $ambiguity = $proposalRequest.inventoryReport.ambiguities[0]
            $ambiguity.requiresDmDecision | Should -BeTrue
            @($ambiguity.alternatives).Count | Should -BeGreaterOrEqual 2
            $ambiguity.ambiguityId | Should -Match '^amb-[0-9a-f]{24}$'
            foreach ($alternative in $ambiguity.alternatives) {
                $alternative.alternativeId | Should -Match '^alt-[0-9a-f]{24}$'
                $alternative.path | Should -Not -Match ([regex]::Escape($fixture.Root))
            }

            $otherFixture = New-TestVaultFixture -ParentPath $TestDrive
            try {
                [void][System.IO.Directory]::CreateDirectory((Join-Path $otherFixture.Root 'Chronicles'))
                [System.IO.File]::WriteAllText($otherFixture.ProfilePath, "version: 1`nsections:`n  adventures: Chronicles`n")
                Enable-TestAuthorizationProvider -VaultRoot $otherFixture.Root
                $otherRequest = New-TestInventoryRequest -VaultRoot $otherFixture.Root -Arguments ([ordered]@{ proposeProfile = $true })
                $otherOutcome = Invoke-DmInventory -Request $otherRequest
                $otherOutcome.inventoryReport.ambiguities[0].ambiguityId | Should -Not -BeExactly $ambiguity.ambiguityId
            }
            finally { Remove-TestVaultFixture -Fixture $otherFixture }
        }

        It 'changes ambiguity IDs when note evidence changes even if the labels remain the same' {
            [System.IO.File]::WriteAllText(
                $fixture.NotePaths[1],
                "---`ntype: location`n---`nThis note is an adventure.`nOriginal synthetic note body.`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Usable.md' -Text "# Guidance`nPermit synthetic note inspection.`n"
            $request.arguments = [ordered]@{ selectedGuidance = [string[]]@('Selected/Usable.md') }

            $first = Invoke-DmInventory -Request $request
            $first.result.completionCode | Should -BeExactly 'OK'
            $ambiguous = @($first.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Lore/Invented Town.md' })
            $ambiguous.Count | Should -Be 1
            $firstId = [string]$ambiguous[0].ambiguityId

            [System.IO.File]::WriteAllText(
                $fixture.NotePaths[1],
                "---`ntype: location`n---`nThis note is an adventure.`nChanged synthetic note body.`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            $second = Invoke-DmInventory -Request $request
            $second.result.completionCode | Should -BeExactly 'OK'
            $secondAmbiguity = @($second.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Lore/Invented Town.md' })
            $secondAmbiguity.Count | Should -Be 1
            $secondAmbiguity[0].ambiguityId | Should -Not -BeExactly $firstId
        }

        It 'requires a decision for a renamed role that conflicts with conventional organization' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`n"
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $true
            }

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $conflict = @($outcome.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Adventures' })
            $conflict.Count | Should -Be 1
            $conflict[0].requiresDmDecision | Should -BeTrue
            @($conflict[0].alternatives | ForEach-Object { [string]$_.path }) | Should -Contain 'Chronicles'
            @($conflict[0].alternatives | ForEach-Object { [string]$_.path }) | Should -Contain 'Adventures'
        }

        It 'reports multiple guidance-assigned locations as competing proposal alternatives' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`nLegends contains adventures.`n"
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $true
            }

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $conflict = @($outcome.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Adventures' })
            $conflict.Count | Should -Be 1
            $conflict[0].requiresDmDecision | Should -BeTrue
            @($conflict[0].alternatives).Count | Should -Be 3
        }
    }

    Context 'US3 review-only profile proposals' {
        It 'keeps proposals opt-in and returns schema-valid unapproved content when fully determined' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            [System.IO.File]::WriteAllText(
                $fixture.ProfilePath,
                "version: 1`nsections:`n  adventures: Adventures`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            $orientation = Invoke-DmInventory -Request $request
            $orientation.result.completionCode | Should -BeExactly 'OK'
            $orientation.inventoryReport.profileProposal | Should -BeNull

            $request.arguments = [ordered]@{ proposeProfile = $false }
            $falseOptIn = Invoke-DmInventory -Request $request
            $falseOptIn.result.completionCode | Should -BeExactly 'OK'
            $falseOptIn.inventoryReport.profileProposal | Should -BeNull

            $request.arguments = [ordered]@{ proposeProfile = $true }
            $proposalOutcome = Invoke-DmInventory -Request $request

            $proposalOutcome.result.completionCode | Should -BeExactly 'OK'
            $proposal = $proposalOutcome.inventoryReport.profileProposal
            $proposal.status | Should -BeExactly 'drafted-unapproved'
            $proposal.content | Should -Not -BeNullOrEmpty
            $proposal.differences | Should -Not -BeNullOrEmpty
            @($proposal.evidence).Count | Should -BeGreaterThan 0
            @($proposal.decisionIssues).Count | Should -Be 0
            $classifications = @($proposal.evidence | Select-Object -ExpandProperty classification -Unique)
            $classifications | Should -Contain 'observed'
            $classifications | Should -Contain 'inferred'
            $parsed = ConvertFrom-DmVaultProfileYaml -Yaml $proposal.content
            $parsed.passed | Should -BeTrue
            (Test-DmProfileSchema -Profile $parsed.profile).passed | Should -BeTrue
            $proposal.content | Should -Not -Match '(^|\n)\s*(?:arc|adventure_arc|encounters)\s*:'
        }

        It 'requires fresh decisions and reports stale choices without echoing their identifiers' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`n"
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $true
            }

            $unresolved = Invoke-DmInventory -Request $request
            $unresolved.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $unresolved.inventoryReport.profileProposal.status | Should -BeExactly 'drafted-unapproved'
            $unresolved.inventoryReport.profileProposal.content | Should -BeNull
            $unresolved.inventoryReport.profileProposal.differences | Should -BeNull
            @($unresolved.inventoryReport.profileProposal.decisionIssues).Count | Should -Be 0

            $ambiguity = @($unresolved.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Adventures' })[0]
            $selected = @($ambiguity.alternatives | Where-Object { $_.path -ceq 'Chronicles' })[0]
            $request.arguments.mappingDecisions = @([ordered]@{
                ambiguityId = [string]$ambiguity.ambiguityId
                alternativeId = [string]$selected.alternativeId
            })
            $resolved = Invoke-DmInventory -Request $request
            $resolved.result.completionCode | Should -BeExactly 'OK'
            $resolved.inventoryReport.profileProposal.content | Should -Not -BeNullOrEmpty
            $resolved.inventoryReport.ambiguities |
                Where-Object { $_.ambiguityId -ceq $ambiguity.ambiguityId } |
                Select-Object -ExpandProperty selectedAlternativeId |
                Should -BeExactly $selected.alternativeId

            $request.arguments.mappingDecisions = @([ordered]@{
                ambiguityId = 'amb-000000000000000000000000'
                alternativeId = 'alt-111111111111111111111111'
            })
            $stale = Invoke-DmInventory -Request $request
            $stale.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $stale.inventoryReport.profileProposal.content | Should -BeNull
            $stale.inventoryReport.profileProposal.differences | Should -BeNull
            @($stale.inventoryReport.profileProposal.decisionIssues).Count | Should -Be 1
            $stale.inventoryReport.profileProposal.decisionIssues[0].decisionIndex | Should -Be 0
            $stale.inventoryReport.profileProposal.decisionIssues[0].reason | Should -BeExactly 'stale-or-unknown'
            ($stale.inventoryReport | ConvertTo-Json -Depth 30 -Compress) |
                Should -Not -Match 'amb-000000000000000000000000|alt-111111111111111111111111'
        }

        It 'preserves existing profile text and comments while exposing every proposed change' {
            $profileText = "# Synthetic profile comment`r`nversion: 1`r`nsections:`r`n  adventures: Adventures # retain this association`r`n  lore: Lore # unchanged section`r`nparty:`r`n  note: Lore/Invented Town.md`r`ntemplates:`r`n  adventure: .dmassist-templates/adventure.md`r`n"
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.dmassist-templates/adventure.md' -Text "# Synthetic template`n"
            [System.IO.File]::WriteAllText($fixture.ProfilePath, $profileText, [System.Text.UTF8Encoding]::new($false))
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`n"
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $true
            }
            $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

            $first = Invoke-DmInventory -Request $request
            $ambiguity = @($first.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Adventures' })[0]
            $alternative = @($ambiguity.alternatives | Where-Object { $_.path -ceq 'Chronicles' })[0]
            $request.arguments.mappingDecisions = @([ordered]@{
                ambiguityId = [string]$ambiguity.ambiguityId
                alternativeId = [string]$alternative.alternativeId
            })

            $outcome = Invoke-DmInventory -Request $request
            $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

            $outcome.result.completionCode | Should -BeExactly 'OK'
            $proposal = $outcome.inventoryReport.profileProposal
            $proposal.content | Should -Match '(?m)^# Synthetic profile comment\r?$'
            $proposal.content | Should -Match "(?m)^  adventures: 'Chronicles' # retain this association\r?$"
            $proposal.content | Should -Match '(?m)^  lore: Lore # unchanged section\r?$'
            $proposal.content | Should -Match 'note: Lore/Invented Town\.md'
            $proposal.content | Should -Match 'adventure: \.dmassist-templates/adventure\.md'
            $proposal.content | Should -Not -Match '(?<!\r)\n'
            $proposal.differences | Should -Match 'adventures: Adventures # retain this association'
            $proposal.differences | Should -Match "adventures: 'Chronicles' # retain this association"
            $before | Should -BeExactly $after
        }

        It 'fails safely rather than normalizing mixed profile line endings' {
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path '.dmassist-templates/adventure.md' -Text "# Synthetic template`n"
            [System.IO.File]::WriteAllText(
                $fixture.ProfilePath,
                "version: 1`r`nsections:`n  adventures: Adventures`r`nparty:`n  note: Lore/Invented Town.md`r`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`n"
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $false
            }
            $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

            $unresolved = Invoke-DmInventory -Request $request
            $unresolved.result.completionCode | Should -BeExactly 'OK'
            $ambiguity = @($unresolved.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Adventures' })[0]
            $alternative = @($ambiguity.alternatives | Where-Object { $_.path -ceq 'Chronicles' })[0]
            $request.arguments.proposeProfile = $true
            $request.arguments.mappingDecisions = @([ordered]@{
                ambiguityId = [string]$ambiguity.ambiguityId
                alternativeId = [string]$alternative.alternativeId
            })

            $outcome = Invoke-DmInventory -Request $request
            $after = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

            $outcome.result.completionCode | Should -BeExactly 'OPERATION_FAILED'
            $outcome.inventoryReport | Should -BeNull
            $before | Should -BeExactly $after
        }

        It 'fails safely when profile preservation would disclose an excluded filename' {
            [System.IO.File]::WriteAllText(
                $fixture.ProfilePath,
                "# Preserve notes about assets/map.png`nversion: 1`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`n"
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $true
            }

            $outcome = Invoke-DmInventory -Request $request

            $outcome.result.completionCode | Should -BeExactly 'OPERATION_FAILED'
            $outcome.inventoryReport | Should -BeNull
            $outcome.result.errorDetails.message | Should -Not -Match 'assets/map\.png'
        }

        It 'leaves ordinary, ambiguous, stale, and failed requests read-only with and without a profile' {
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            $beforeAbsent = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
            $ordinary = Invoke-DmInventory -Request $request
            $ordinary.result.completionCode | Should -BeExactly 'OK'
            $proposalRequest = New-TestInventoryRequest -VaultRoot $fixture.Root -Arguments ([ordered]@{ proposeProfile = $true })
            $ambiguous = Invoke-DmInventory -Request $proposalRequest
            $ambiguous.inventoryReport.profileProposal.status | Should -BeExactly 'drafted-unapproved'
            $proposalRequest.arguments.mappingDecisions = @([ordered]@{
                ambiguityId = 'amb-000000000000000000000000'
                alternativeId = 'alt-111111111111111111111111'
            })
            $stale = Invoke-DmInventory -Request $proposalRequest
            $stale.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $failedRequest = New-TestInventoryRequest -VaultRoot $fixture.Root
            $failedRequest.mode = 'preview'
            $failed = Invoke-DmInventory -Request $failedRequest
            $failed.result.completionCode | Should -BeExactly 'INVALID_REQUEST'
            $afterAbsent = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
            $afterAbsent | Should -BeExactly $beforeAbsent

            [System.IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`n", [System.Text.UTF8Encoding]::new($false))
            $beforePresent = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
            $profileRequest = New-TestInventoryRequest -VaultRoot $fixture.Root -Arguments ([ordered]@{ proposeProfile = $true })
            $withProfile = Invoke-DmInventory -Request $profileRequest
            $withProfile.result.completionCode | Should -BeExactly 'OK'
            $afterPresent = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
            $afterPresent | Should -BeExactly $beforePresent
        }

        It 'leaves an existing profile unchanged for unresolved and stale proposal decisions' {
            [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Chronicles'))
            [System.IO.File]::WriteAllText(
                $fixture.ProfilePath,
                "version: 1`nsections:`n  adventures: Adventures # synthetic user comment`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            Enable-TestAuthorizationProvider -VaultRoot $fixture.Root
            Set-TestGuidanceFile -VaultRoot $fixture.Root -Path 'Selected/Layout.md' -Text "Chronicles contains adventures.`n"
            $request.arguments = [ordered]@{
                selectedGuidance = [string[]]@('Selected/Layout.md')
                proposeProfile = $true
            }
            $before = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress

            $unresolved = Invoke-DmInventory -Request $request
            $unresolved.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $afterUnresolved = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
            $afterUnresolved | Should -BeExactly $before

            $ambiguity = @($unresolved.inventoryReport.ambiguities | Where-Object { $_.subject -ceq 'Adventures' })[0]
            $request.arguments.mappingDecisions = @([ordered]@{
                ambiguityId = [string]$ambiguity.ambiguityId
                alternativeId = 'alt-111111111111111111111111'
            })
            $stale = Invoke-DmInventory -Request $request
            $stale.result.completionCode | Should -BeExactly 'AMBIGUOUS_CONTEXT'
            $afterStale = ConvertTo-Json -InputObject (Get-TestOwnedVaultSnapshot -Fixture $fixture) -Depth 10 -Compress
            $afterStale | Should -BeExactly $before
        }
    }
}
