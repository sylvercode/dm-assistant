BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name RuntimeContract, DependencyPreflight, VaultPathValidation, VaultBoundary, VaultConfiguration, PluginResources, SafeNoteWriter, RuntimePreflight, OperationRequest, ChangePreview, ApplyNoteChanges, VaultInspection

    $script:TemplateDirectory = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Join($PSScriptRoot, '..', '..', 'skills', 'article-authoring', 'templates')
    )
    $script:BuiltInTypes = @(
        'adventure',
        'character',
        'handout',
        'location',
        'monster',
        'party',
        'persona',
        'rule',
        'session'
    )

    function Get-TestArticleInputVersion {
        param([Parameter(Mandatory)][string]$Path)
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
        'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
    }

    function New-TestArticleFreshnessFixture {
        $profile = @"
version: 1
guidance:
  path: ".dmassist-guidance.md"
templates:
  adventure: ".dmassist-templates/adventure.md"
"@
        $fixture = New-TestVaultFixture -ParentPath (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))) `
            -ProfileText $profile -Notes ([ordered]@{
                '.dmassist-guidance.md' = "Synthetic designated guidance.`n"
                '.dmassist-templates/adventure.md' = "# Synthetic selected template`n"
                'Lore/Relevant Context.md' = "Synthetic relevant campaign context.`n"
                'Articles/New Adventure.md' = "# Original article`nOriginal content.`n"
            })

        $canonicalRoot = [System.IO.Path]::GetFullPath($fixture.Root)
        if ($canonicalRoot.Length -gt [System.IO.Path]::GetPathRoot($canonicalRoot).Length) {
            $canonicalRoot = $canonicalRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        }
        $fixture | Add-Member -NotePropertyName Boundary -NotePropertyValue ([pscustomobject][ordered]@{
            selectedRoot = $fixture.Root
            canonicalRoot = $canonicalRoot
            comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        })
        $fixture | Add-Member -NotePropertyName GuidancePath -NotePropertyValue (Join-Path $fixture.Root '.dmassist-guidance.md')
        $fixture | Add-Member -NotePropertyName TemplatePath -NotePropertyValue (Join-Path $fixture.Root '.dmassist-templates\adventure.md')
        $fixture | Add-Member -NotePropertyName ContextPath -NotePropertyValue (Join-Path $fixture.Root 'Lore\Relevant Context.md')
        $fixture | Add-Member -NotePropertyName DestinationRelativePath -NotePropertyValue 'Articles/New Adventure.md'
        $fixture | Add-Member -NotePropertyName DestinationPath -NotePropertyValue (Join-Path $fixture.Root 'Articles\New Adventure.md')
        $fixture | Add-Member -NotePropertyName DestinationParent -NotePropertyValue (Join-Path $fixture.Root 'Articles')
        [void][System.IO.Directory]::CreateDirectory($fixture.DestinationParent)
        $fixture
    }

    function New-TestArticleInputTarget {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$Identity,
            [Parameter(Mandatory)][string]$RelativePath
        )
        $resolution = Resolve-DmVaultTarget -Boundary $Fixture.Boundary -Path $RelativePath
        $observedVersion = switch ([string]$resolution.status) {
            'resolved' {
                if ($resolution.itemType -ceq 'file') {
                    $snapshot = Read-DmVaultTargetBytes -Boundary $Fixture.Boundary -Resolution $resolution
                    if (-not $snapshot.ok) { throw "Unable to snapshot synthetic input '$Identity'." }
                    $snapshot.version
                }
                elseif ($resolution.itemType -ceq 'directory') { 'directory' }
                else { throw "Unsupported synthetic input '$Identity'." }
            }
            'missing' { 'absent' }
            default { throw "Unable to resolve synthetic input '$Identity'." }
        }
        [pscustomobject][ordered]@{
            identity = $Identity
            resolution = $resolution
            observedVersion = [string]$observedVersion
        }
    }

    function New-TestArticleAuthoringSnapshot {
        param([Parameter(Mandatory)]$Fixture)
        [object[]]@(
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'profile' -RelativePath '.dmassist.yaml')
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'selected-template-mapping' -RelativePath '.dmassist.yaml')
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'designated-guidance' -RelativePath '.dmassist-guidance.md')
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'selected-template' -RelativePath '.dmassist-templates/adventure.md')
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'relevant-context' -RelativePath 'Lore/Relevant Context.md')
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'destination' -RelativePath $Fixture.DestinationRelativePath)
            (New-TestArticleInputTarget -Fixture $Fixture -Identity 'destination-parent' -RelativePath 'Articles')
        )
    }

    function New-TestArticleCreateRequest {
        param(
            [Parameter(Mandatory)]$Fixture,
            [string]$Operation = 'note.create-article',
            [string]$Mode = 'preview',
            [string]$TargetPath = 'Articles/Created Adventure.md',
            [string]$Content = "# Synthetic article`n"
        )
        $authoringInputs = [System.Collections.Generic.List[object]]::new()
        foreach ($inputSpec in @(
                @{ identity = 'profile'; path = '.dmassist.yaml' }
                @{ identity = 'designated-guidance'; path = '.dmassist-guidance.md' }
                @{ identity = 'selected-template'; path = '.dmassist-templates/adventure.md' }
                @{ identity = 'relevant-context'; path = 'Lore/Relevant Context.md' }
            )) {
            $inputPath = Join-Path -Path $Fixture.Root -ChildPath $inputSpec.path.Replace('/', '\')
            $authoringInputs.Add([pscustomobject][ordered]@{
                    identity = $inputSpec.identity
                    path = $inputSpec.path
                    version = Get-TestArticleInputVersion -Path $inputPath
                })
        }
        $authoringInputs.Add([pscustomobject][ordered]@{ identity = 'destination'; path = $TargetPath; version = 'absent' })
        $separator = $TargetPath.LastIndexOf('/')
        if ($separator -ge 0) {
            $parentPath = $TargetPath.Substring(0, $separator)
            $authoringInputs.Add([pscustomobject][ordered]@{ identity = 'destination-parent'; path = $parentPath; version = 'directory' })
        }
        New-TestOperationRequest -VaultRoot $Fixture.Root -Operation $Operation -Mode $Mode -Targets @($TargetPath) `
            -Arguments ([ordered]@{ content = $Content }) -Extra @{ authoringInputs = [object[]]$authoringInputs.ToArray() }
    }

    function New-TestArticleWriteTarget {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][object[]]$ExpectedInputs
        )
        $destination = @($ExpectedInputs | Where-Object { $_.identity -ceq 'destination' }) | Select-Object -First 1
        if ($null -eq $destination) { throw 'Unable to prepare the synthetic write target.' }
        [pscustomobject][ordered]@{
            path = $Fixture.DestinationRelativePath
            resolution = $destination.resolution
            observedVersion = $destination.observedVersion
            replacementBytes = [System.Text.UTF8Encoding]::new($false).GetBytes("# Must not be written`n")
        }
    }

    function New-TestArticleWriteRequest {
        param([Parameter(Mandatory)]$Fixture)
        New-TestOperationRequest -VaultRoot $Fixture.Root -Operation 'note.replace-text' -Mode 'apply' `
            -Targets @($Fixture.DestinationRelativePath) -Arguments ([ordered]@{ oldText = 'Original'; newText = 'Changed' })
    }

    function Assert-TestArticleAuthoringStale {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][object[]]$ExpectedInputs,
            $Request = $(New-TestArticleWriteRequest -Fixture $Fixture),
            $Target
        )
        $before = @(Get-TestVaultSnapshot -Path $Fixture.Root)
        $expectedDependencies = Get-DmCurrentChangeDependencyVersions -Boundary $Fixture.Boundary -Profile $null
        if ($null -eq $Target) { $Target = New-TestArticleWriteTarget -Fixture $Fixture -ExpectedInputs $ExpectedInputs }
        $result = Invoke-DmSafeNoteWrite -Boundary $Fixture.Boundary -Target $Target `
            -ExpectedDependencies $expectedDependencies -ExpectedInputTargets $ExpectedInputs -Request $Request

        $result.ok | Should -BeFalse
        $result.code | Should -BeIn @('TARGET_CONFLICT', 'VAULT_AUTHORIZATION_UNPROVEN', 'PREREQUISITE_MISSING', 'READ_FAILED', 'PATH_OUTSIDE_VAULT')
        @(Get-TestVaultSnapshot -Path $Fixture.Root) | Should -Be $before
    }
}

Describe 'Article-authoring source package layout (not installed-client resource lookup)' {
    It 'keeps installed skill guidance independent of repository feature specifications' {
        $skillRoot = Join-Path (Get-TestRepositoryRoot) 'skills'
        $skillFiles = @(Get-ChildItem -LiteralPath $skillRoot -Directory | ForEach-Object {
                $path = Join-Path $_.FullName 'SKILL.md'
                if (Test-Path -LiteralPath $path -PathType Leaf) { $path }
            })
        $skillFiles.Count | Should -BeGreaterThan 0
        foreach ($skillFile in $skillFiles) {
            $content = [System.IO.File]::ReadAllText($skillFile)
            $content | Should -Not -Match '(?i)\bfeature\s+(?:0*\d+|specification|spec\b)'
            $content | Should -Not -Match '(?i)specs[/\\]'
            $content | Should -Not -Match '(?i)`docs[/\\]'
            $content | Should -Not -Match 'https?://'
        }

        $orientation = [System.IO.File]::ReadAllText((Join-Path $skillRoot 'vault-orientation\SKILL.md'))
        $authoring = [System.IO.File]::ReadAllText((Join-Path $skillRoot 'article-authoring\SKILL.md'))
        $reference = [System.IO.File]::ReadAllText((Join-Path $skillRoot 'vault-orientation\VAULT-REFERENCE.md'))
        $orientation | Should -Match 'assets/runtime-dependencies\.json'
        $authoring | Should -Match '(?s)schema bundled with `vault-orientation`'
        $reference | Should -Not -Match 'https?://'
        Test-Path -LiteralPath (Join-Path $skillRoot 'vault-orientation\assets\runtime-dependencies.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $skillRoot 'vault-orientation\assets\dmassist.schema.json') -PathType Leaf | Should -BeTrue
    }

    It 'documents same-session vault-check reuse and its invalidation conditions' {
        $skillRoot = Join-Path (Get-TestRepositoryRoot) 'skills'
        $orientation = [IO.File]::ReadAllText((Join-Path $skillRoot 'vault-orientation\SKILL.md'))
        $authoring = [IO.File]::ReadAllText((Join-Path $skillRoot 'article-authoring\SKILL.md'))
        $orientation | Should -Match '(?s)reused across operations.*same active client session and exact vault'
        $orientation | Should -Match '(?s)new session or different vault\s+requires a new check'
        $orientation | Should -Match '(?s)configuration or authorized roots change.*fresh session'
        $orientation | Should -Match '(?s)dependency becomes unavailable.*stop and recheck'
        $orientation | Should -Match '(?s)unnoticed\s+change may go undetected'
        $authoring | Should -Match '(?s)live\s+Resolver call is not required again solely for apply'
    }

    It 'requires a human response to the exact preview when using native approval' {
        $skillRoot = Join-Path (Get-TestRepositoryRoot) 'skills'
        $orientation = [IO.File]::ReadAllText((Join-Path $skillRoot 'vault-orientation\SKILL.md')) -replace '\s+', ' '
        $reference = [IO.File]::ReadAllText((Join-Path $skillRoot 'vault-orientation\VAULT-REFERENCE.md')) -replace '\s+', ' '
        $authoring = [IO.File]::ReadAllText((Join-Path $skillRoot 'article-authoring\SKILL.md')) -replace '\s+', ' '
        foreach ($guidance in @($orientation, $reference)) {
            $guidance | Should -Match 'exact (scoped )?preview'
            $guidance | Should -Match '`ask_user`'
            $guidance | Should -Match 'human response cannot be established'
            $guidance | Should -Match 'later DM message'
            $guidance | Should -Match 'decline or cancellation must not apply'
        }
        $authoring | Should -Match 'never treat an autonomous guess, tool permission approval, or an unconfirmed response as DM approval'
        $authoring | Should -Match 'Show the complete proposed Markdown and destination'
        $authoring | Should -Match 'include the full draft in the `ask_user` question'
        $authoring | Should -Match 'If the client cannot present it completely, stop without applying'
        $authoring | Should -Match 'On `TARGET_CONFLICT` or any stale or mismatched preparation, stop and report the conflict without automatically restarting'
        $authoring | Should -Match 'Select the latter when the new article records actual-play events or outcomes'
        $authoring | Should -Match 'runtime trusts the caller.s operation choice'
    }

    It 'contains exactly one Markdown default for each built-in type' {
        Test-Path -LiteralPath $script:TemplateDirectory -PathType Container | Should -BeTrue

        $markdownFiles = @(
            Get-ChildItem -LiteralPath $script:TemplateDirectory -File -Filter '*.md' -Recurse
        )
        $markdownFiles.Count | Should -Be $script:BuiltInTypes.Count

        foreach ($type in $script:BuiltInTypes) {
            $expectedPath = [System.IO.Path]::GetFullPath(
                (Join-Path -Path $script:TemplateDirectory -ChildPath "$type.md")
            )
            @(
                $markdownFiles | Where-Object {
                    [System.IO.Path]::GetFullPath($_.FullName) -ceq $expectedPath
                }
            ).Count | Should -Be 1
        }
    }

    Describe 'Article-authoring freshness immediately before safe writes' {
        BeforeEach {
            $script:ArticleFixture = New-TestArticleFreshnessFixture
            Enable-TestAuthorizationProvider -VaultRoot $script:ArticleFixture.Root
        }
        AfterEach {
            if ($null -ne $script:ArticleFixture) {
                Remove-TestVaultFixture -Fixture $script:ArticleFixture
                $script:ArticleFixture = $null
            }
        }

        It 'invalidates stale profile bytes and the selected mapping without writing' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            [System.IO.File]::AppendAllText($script:ArticleFixture.ProfilePath, "# changed after validation`n", [System.Text.UTF8Encoding]::new($false))

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'invalidates changed designated guidance after it was read' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            [System.IO.File]::AppendAllText($script:ArticleFixture.GuidancePath, "Changed guidance.`n", [System.Text.UTF8Encoding]::new($false))

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'invalidates a changed selected template after it was read' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            [System.IO.File]::AppendAllText($script:ArticleFixture.TemplatePath, "Changed template.`n", [System.Text.UTF8Encoding]::new($false))

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'invalidates changed relevant campaign context after it was read' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            [System.IO.File]::AppendAllText($script:ArticleFixture.ContextPath, "Changed campaign context.`n", [System.Text.UTF8Encoding]::new($false))

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'rechecks exact-vault authorization before writing' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $request = New-TestArticleWriteRequest -Fixture $script:ArticleFixture
            $request.vaultRoot = $script:ArticleFixture.OutsidePath

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected -Request $request
        }

        It 'rechecks boundary evidence again immediately before replacement' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $script:BoundaryRecheckCount = 0
            Mock -ModuleName SafeNoteWriter -CommandName Test-DmSafeWritePreflight -MockWith {
                $script:BoundaryRecheckCount++
                if ($script:BoundaryRecheckCount -eq 1) {
                    [pscustomobject][ordered]@{ passed = $true; code = $null }
                }
                else {
                    [pscustomobject][ordered]@{ passed = $false; code = 'TARGET_CONFLICT' }
                }
            }

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'fails closed when consumed inputs are not paired with an authorization request' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $before = @(Get-TestVaultSnapshot -Path $script:ArticleFixture.Root)
            $target = New-TestArticleWriteTarget -Fixture $script:ArticleFixture -ExpectedInputs $expected
            $dependencies = Get-DmCurrentChangeDependencyVersions -Boundary $script:ArticleFixture.Boundary -Profile $null

            $result = Invoke-DmSafeNoteWrite -Boundary $script:ArticleFixture.Boundary -Target $target `
                -ExpectedDependencies $dependencies -ExpectedInputTargets $expected

            $result.ok | Should -BeFalse
            $result.code | Should -BeExactly 'TARGET_CONFLICT'
            @(Get-TestVaultSnapshot -Path $script:ArticleFixture.Root) | Should -Be $before
        }

        It 'invalidates a destination identity different from the one validated' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $writeTarget = New-TestArticleWriteTarget -Fixture $script:ArticleFixture -ExpectedInputs $expected
            $otherDestination = New-TestArticleInputTarget -Fixture $script:ArticleFixture -Identity 'destination' `
                -RelativePath 'Lore/Relevant Context.md'
            $expected = @($expected | Where-Object { $_.identity -cne 'destination' }) + @($otherDestination)

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected -Target $writeTarget
        }

        It 'invalidates a destination canonical resolution changed after preview while the lexical path is unchanged' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $destination = @($expected | Where-Object { $_.identity -ceq 'destination' }) | Select-Object -First 1
            $writeTarget = New-TestArticleWriteTarget -Fixture $script:ArticleFixture -ExpectedInputs $expected

            $retargetedResolution = $destination.resolution.PSObject.Copy()
            $retargetedResolution.resolvedPath = Join-Path $script:ArticleFixture.Root 'Lore\Retargeted Article.md'
            $retargetedDestination = [pscustomobject][ordered]@{
                identity = 'destination'
                resolution = $retargetedResolution
                observedVersion = [string]$destination.observedVersion
                canonicalPath = [string]$retargetedResolution.resolvedPath
            }
            $expected = @($expected | Where-Object { $_.identity -cne 'destination' }) + @($retargetedDestination)

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected -Target $writeTarget
        }

        It 'invalidates a destination that disappeared after validation' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            [System.IO.File]::Delete($script:ArticleFixture.DestinationPath)

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'invalidates a destination parent that disappeared after validation' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $renamedParent = Join-Path $script:ArticleFixture.Root 'Articles-renamed'
            [System.IO.Directory]::Move($script:ArticleFixture.DestinationParent, $renamedParent)

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }

        It 'rejects an input that changes after the first recheck and before replacement' {
            $expected = New-TestArticleAuthoringSnapshot -Fixture $script:ArticleFixture
            $script:FreshnessRecheckCount = 0
            Mock -ModuleName SafeNoteWriter -CommandName Test-DmExpectedInputTargets -MockWith {
                $script:FreshnessRecheckCount++
                if ($script:FreshnessRecheckCount -eq 1) {
                    [pscustomobject][ordered]@{ matches = $true; changedIdentities = @() }
                }
                else {
                    [pscustomobject][ordered]@{ matches = $false; changedIdentities = @('selected-template') }
                }
            }

            Assert-TestArticleAuthoringStale -Fixture $script:ArticleFixture -ExpectedInputs $expected
        }
    }
}

Describe 'Bundled article template static syntax' {
    It 'requires asking instead of filling ambiguous required markers with placeholders' {
        $skillPath = Join-Path (Split-Path $script:TemplateDirectory) 'SKILL.md'
        $skill = [System.IO.File]::ReadAllText($skillPath)
        $normalized = $skill -replace '\s+', ' '

        $normalized | Should -Match 'If it is missing, undecided, or has competing alternatives, stop and ask the DM for the value before previewing or applying'
        $normalized | Should -Match 'Do not replace a required marker with a placeholder'
        $normalized | Should -Match '“unknown,” “undecided,” “TBD,” a list of alternatives'
    }

    It 'uses only exact required and optional fill-in comments in every bundled template' {
        foreach ($type in $script:BuiltInTypes) {
            $path = Join-Path -Path $script:TemplateDirectory -ChildPath "$type.md"
            $content = [System.IO.File]::ReadAllText($path)
            $comments = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)<!--.*?-->')
            $openCommentCount = [System.Text.RegularExpressions.Regex]::Matches($content, '<!--').Count
            $closeCommentCount = [System.Text.RegularExpressions.Regex]::Matches($content, '-->').Count

            $openCommentCount | Should -Be $comments.Count -Because "$type.md must not contain an unclosed or malformed HTML comment"
            $closeCommentCount | Should -Be $comments.Count -Because "$type.md must not contain an unmatched HTML comment terminator"

            $requiredCount = 0
            $optionalCount = 0
            $invalidComments = [System.Collections.Generic.List[string]]::new()
            foreach ($comment in $comments) {
                $marker = [string]$comment.Value
                if (-not [System.Text.RegularExpressions.Regex]::IsMatch(
                    $marker,
                    '\A<!-- fill-in: (?:required|optional) [^<>\s](?:[^<>\r\n]*[^<>\s])? -->\z'
                )) {
                    $invalidComments.Add($marker)
                    continue
                }

                $kind = [System.Text.RegularExpressions.Regex]::Match(
                    $marker,
                    '\A<!-- fill-in: (required|optional) '
                ).Groups[1].Value
                if ($kind -ceq 'required') { $requiredCount++ }
                if ($kind -ceq 'optional') { $optionalCount++ }
            }

            $invalidComments.Count | Should -Be 0 -Because "$type.md may use only the exact lowercase required/optional marker syntax"
            $requiredCount | Should -BeGreaterThan 0 -Because "$type.md must define required fill-in guidance"
            $optionalCount | Should -BeGreaterThan 0 -Because "$type.md must define optional fill-in guidance"
        }
    }

    Describe 'Article-authoring shared preflight and containment contracts' {
        BeforeEach {
            $script:ArticleSafetyFixture = New-TestVaultFixture `
                -ParentPath (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))) `
                -ProfileText "version: 1`n" `
                -Notes ([ordered]@{
                    'Articles/Existing Article.md' = "# Existing synthetic article`nDo not overwrite.`n"
                    'Lore/Context.md' = "Synthetic relevant context.`n"
                })
            Enable-TestAuthorizationProvider -VaultRoot $script:ArticleSafetyFixture.Root
            Set-TestDependencyReadiness -State ready
            $script:ArticleSafetyRequest = New-TestOperationRequest -VaultRoot $script:ArticleSafetyFixture.Root `
                -Targets @('Lore/Context.md')
            $script:ArticleSafetyBefore = @(Get-TestVaultSnapshot -Path $script:ArticleSafetyFixture.ParentPath)
        }

        AfterEach {
            @(Get-TestVaultSnapshot -Path $script:ArticleSafetyFixture.ParentPath) |
                Should -Be $script:ArticleSafetyBefore -Because 'blocked authoring prerequisites and unsafe paths must preserve the complete synthetic fixture'
            Remove-TestVaultFixture -Fixture $script:ArticleSafetyFixture
            $script:ArticleSafetyFixture = $null
        }

        It 'stops after a failed dependency preflight before profile, note, or write access' {
            Set-TestDependencyReadiness -State missing
            Mock -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -MockWith {
                throw 'A profile was read after dependency preflight failed.'
            }
            Mock -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -MockWith {
                throw 'A campaign note was read after dependency preflight failed.'
            }
            Mock -ModuleName SafeNoteWriter -CommandName Invoke-DmSafeNoteWrite -MockWith {
                throw 'A write was attempted after dependency preflight failed.'
            }

            $outcome = Invoke-DmInspect -Request $script:ArticleSafetyRequest

            $outcome.result.completionCode | Should -BeExactly 'PREREQUISITE_MISSING'
            $outcome.result.completionStatus | Should -BeExactly 'not completed'
            Should -Invoke -ModuleName VaultConfiguration -CommandName Read-DmVaultProfile -Times 0 -Exactly -Scope It
            Should -Invoke -ModuleName VaultInspection -CommandName Read-DmVaultTargetBytes -Times 0 -Exactly -Scope It
            Should -Invoke -ModuleName SafeNoteWriter -CommandName Invoke-DmSafeNoteWrite -Times 0 -Exactly -Scope It
        }

        It 'keeps destination conflict and missing-parent observations read-only' {
            $preflight = Invoke-DmPreflight -Request $script:ArticleSafetyRequest
            $preflight.passed | Should -BeTrue

            $existing = Resolve-DmVaultTarget -Boundary $preflight.boundary -Path 'Articles/Existing Article.md'
            $missingParent = Resolve-DmVaultTarget -Boundary $preflight.boundary -Path 'Missing Parent/New Article.md'

            $existing.status | Should -BeExactly 'resolved'
            $existing.itemType | Should -BeExactly 'file'
            $missingParent.status | Should -BeExactly 'missing'
            $missingParent.itemType | Should -BeExactly 'missing'
            @(Get-TestVaultSnapshot -Path $script:ArticleSafetyFixture.ParentPath) | Should -Be $script:ArticleSafetyBefore
        }

        It 'requires one DM-supplied path and does not infer a destination from section or template mappings' {
            $skillPath = Join-Path -Path (Get-TestRepositoryRoot) -ChildPath 'skills\article-authoring\SKILL.md'
            $skill = [System.IO.File]::ReadAllText($skillPath)
            $normalizedSkill = $skill -replace '\s+', ' '

            $normalizedSkill | Should -Match 'DM explicitly supplies exactly one Markdown path'
            $normalizedSkill | Should -Match 'its parent already exists'
            $normalizedSkill | Should -Match 'Profile section-folder and template mappings do not identify article destinations'
            $normalizedSkill | Should -Match 'never infer a path'
        }
    }

    Describe 'Caller-confirmed article creation without an authorization test provider' {
        BeforeEach {
            $script:CallerArticleFixture = New-TestArticleFreshnessFixture
            $script:CallerArticleRequest = New-TestArticleCreateRequest -Fixture $script:CallerArticleFixture -Mode apply
            $script:CallerArticleRequest.callerPreflight = [ordered]@{
                vaultRoot = $script:CallerArticleFixture.Root
                dependenciesReady = $true
                vaultAuthorized = $true
            }
        }

        AfterEach {
            Remove-TestVaultFixture -Fixture $script:CallerArticleFixture
        }

        It 'creates one article through the production preview and writer path without probing Copilot' {
            $request = $script:CallerArticleRequest
            $beforeExisting = [System.IO.File]::ReadAllBytes($script:CallerArticleFixture.DestinationPath)
            (Invoke-DmApply -Request $request).result.completionCode | Should -BeExactly 'OK'
            [System.IO.File]::ReadAllText((Join-Path $script:CallerArticleFixture.Root 'Articles\Created Adventure.md')) |
                Should -BeExactly "# Synthetic article`n"
            [System.IO.File]::ReadAllBytes($script:CallerArticleFixture.DestinationPath) | Should -Be $beforeExisting
            (Invoke-DmApply -Request $request).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
        }

        It 'rechecks the caller confirmation at the safe-writer boundary' {
            $request = $script:CallerArticleRequest
            $preflight = Invoke-DmPreflight -Request $request
            $preflight.passed | Should -BeTrue
            $context = Get-DmPreNoteContext -Preflight $preflight
            $plan = Get-DmChangePlan -Preflight $preflight -Context $context
            $plan.ok | Should -BeTrue
            $request.callerPreflight.vaultAuthorized = $false
            $outcome = Invoke-DmSafeNoteWrite -Boundary $preflight.boundary -Target $plan.plan[0] `
                -ExpectedDependencies $plan.dependencies -ExpectedInputTargets $plan.expectedInputTargets `
                -Profile $context.profile -Request $request
            $outcome.ok | Should -BeFalse
            $outcome.code | Should -BeExactly 'VAULT_AUTHORIZATION_UNPROVEN'
            Test-Path -LiteralPath (Join-Path $script:CallerArticleFixture.Root 'Articles\Created Adventure.md') | Should -BeFalse
        }
    }

    Describe 'Shipped prepare, preview, and apply entry point' {
        BeforeAll {
            $entryPoint = Join-Path (Split-Path $script:TemplateDirectory) 'scripts\Invoke-DmArticleAuthoring.ps1'
            function Invoke-TestArticleStage($Action, $Request) {
                $json = ConvertTo-Json -InputObject $Request -Depth 10 -Compress
                $output = $json | & (Get-Process -Id $PID).Path -NoProfile -File $entryPoint -Action $Action
                $LASTEXITCODE | Should -Be 0
                $output | ConvertFrom-Json
            }
        }
        BeforeEach {
            $fixture = New-TestVaultFixture -Notes @{ '.dmassist-guidance.md' = 'Use the synthetic vault conventions.' }
            $request = [ordered]@{
                vaultRoot = $fixture.Root
                callerPreflight = @{ vaultRoot = $fixture.Root; dependenciesReady = $true; vaultAuthorized = $true }
                campaignGroup = @{ campaign = 'Test'; group = 'Test' }
                articleType = 'character'
                destination = 'New Character.md'
                operation = 'note.create-article'
            }
            $destination = Join-Path $fixture.Root $request.destination
            Push-Location -LiteralPath $fixture.Root
        }
        AfterEach {
            Pop-Location
            Remove-TestVaultFixture -Fixture $fixture
        }

        It 'returns default guidance and the bundled template before draft and writes only the exact preview' {
            $prepared = Invoke-TestArticleStage prepare $request
            $prepared.guidance.text | Should -BeExactly 'Use the synthetic vault conventions.'
            $prepared.template.source.path | Should -BeExactly 'templates/character.md'
            $prepared.template.text | Should -Match '<!-- fill-in: required Character name -->'
            $request.preparationId = $prepared.preparationId
            $request.content = $prepared.template.text.Replace('<!-- fill-in: required Character name -->', 'Ash Fen')
            $preview = Invoke-TestArticleStage preview $request
            $preview.result.completionCode | Should -BeExactly 'OK'
            Test-Path -LiteralPath $destination | Should -BeFalse
            $request.previewId = $preview.preview.previewId
            $draft = $request.content
            $request.content = '# Different character'
            (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
            Test-Path -LiteralPath $destination | Should -BeFalse
            $request.content = $draft
            (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'OK'
            [IO.File]::ReadAllText($destination) | Should -BeExactly $draft
        }

        It 'rejects only complete case-sensitive required markers' {
            $markers = @(
                @{ destination = 'Uppercase Marker.md'; content = '# <!-- fill-in: REQUIRED title -->' }
                @{ destination = 'Missing Description.md'; content = '# <!-- fill-in: required -->' }
                @{ destination = 'Unterminated Marker.md'; content = '# <!-- fill-in: required title' }
            )
            foreach ($marker in $markers) {
                $caseRequest = [ordered]@{}
                foreach ($key in $request.Keys) { $caseRequest[$key] = $request[$key] }
                $caseRequest.destination = $marker.destination
                $prepared = Invoke-TestArticleStage prepare $caseRequest
                $prepared.preparationId | Should -Not -BeNullOrEmpty
                $caseRequest.preparationId = $prepared.preparationId
                $caseRequest.content = $marker.content

                $preview = Invoke-TestArticleStage preview $caseRequest
                $preview.result.completionCode | Should -BeExactly 'OK'
                $caseRequest.previewId = $preview.preview.previewId
                (Invoke-TestArticleStage apply $caseRequest).result.completionCode | Should -BeExactly 'OK'
                [IO.File]::ReadAllText((Join-Path $fixture.Root $marker.destination)) | Should -BeExactly $marker.content
            }

            $request.preparationId = (Invoke-TestArticleStage prepare $request).preparationId
            $request.content = '# <!-- fill-in: required title -->'
            (Invoke-TestArticleStage preview $request).result.completionCode | Should -BeExactly 'INVALID_REQUEST'
        }

        It 'revalidates a bundled template edit before apply' {
            $templatePath = Join-Path $script:TemplateDirectory 'character.md'
            $originalBytes = [System.IO.File]::ReadAllBytes($templatePath)
            try {
                $prepared = Invoke-TestArticleStage prepare $request
                $request.preparationId = $prepared.preparationId
                $request.content = $prepared.template.text.Replace('<!-- fill-in: required Character name -->', 'Ash Fen')
                $preview = Invoke-TestArticleStage preview $request
                $preview.result.completionCode | Should -BeExactly 'OK'

                [System.IO.File]::AppendAllText(
                    $templatePath,
                    "`n<!-- edited after preview -->`n",
                    [System.Text.UTF8Encoding]::new($false)
                )

                $request.previewId = $preview.preview.previewId
                (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
                Test-Path -LiteralPath $destination | Should -BeFalse
            }
            finally {
                [System.IO.File]::WriteAllBytes($templatePath, $originalBytes)
            }
        }

        It 'accepts an in-vault absolute destination and binds equivalent relative paths across stages' {
            [void][IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'Articles'))
            $destination = Join-Path $fixture.Root 'Articles\New Character.md'
            $request.destination = $destination
            $request.preparationId = (Invoke-TestArticleStage prepare $request).preparationId
            $request.destination = 'Articles/New Character.md'
            $request.content = '# Ash Fen'
            $preview = Invoke-TestArticleStage preview $request
            $preview.result.completionCode | Should -BeExactly 'OK'
            $request.destination = $destination
            $request.previewId = $preview.preview.previewId
            (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'OK'
            [IO.File]::ReadAllText($destination) | Should -BeExactly '# Ash Fen'
        }

        It 'preserves Unicode in JSON piped to every authoring stage' {
            $request.preparationId = (Invoke-TestArticleStage prepare $request).preparationId
            $request.content = '# The King' + [char]0x2019 + 's caf' + [char]0x00E9 + ' ' + [char]::ConvertFromUtf32(0x1F409)
            $preview = Invoke-TestArticleStage preview $request
            $preview.result.completionCode | Should -BeExactly 'OK'
            $request.previewId = $preview.preview.previewId
            (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'OK'
            [IO.File]::ReadAllText($destination, [Text.UTF8Encoding]::new($false, $true)) |
                Should -BeExactly $request.content
        }

        It 'rejects absolute paths outside the vault and paths containing traversal' {
            $outside = Join-Path (Split-Path $fixture.Root -Parent) 'Outside Character.md'
            $siblingPrefix = "$($fixture.Root)-other$([IO.Path]::DirectorySeparatorChar)Character.md"
            $traversal = Join-Path $fixture.Root '..\Outside Character.md'
            foreach ($path in @($outside, $siblingPrefix, $traversal)) {
                $request.destination = $path
                (Invoke-TestArticleStage prepare $request).result.completionCode | Should -BeExactly 'INVALID_REQUEST'
            }
            Test-Path -LiteralPath $outside | Should -BeFalse
            Test-Path -LiteralPath $destination | Should -BeFalse
        }

        It 'rejects an absolute destination through an escaping directory link' {
            $link = Join-Path $fixture.Root 'Escaping Link'
            try {
                try {
                    [void][IO.Directory]::CreateSymbolicLink($link, $fixture.OutsidePath)
                }
                catch {
                    try {
                        $null = New-Item -ItemType Junction -Path $link -Target $fixture.OutsidePath -ErrorAction Stop
                    }
                    catch {
                        Set-ItResult -Skipped -Because 'directory symbolic links and junctions are unavailable in this environment'
                        return
                    }
                }
                $request.destination = Join-Path $link 'New Character.md'
                (Invoke-TestArticleStage prepare $request).result.completionCode | Should -BeExactly 'PATH_OUTSIDE_VAULT'
                Test-Path -LiteralPath (Join-Path $fixture.OutsidePath 'New Character.md') | Should -BeFalse
            }
            finally {
                if ([IO.Directory]::Exists($link)) { [IO.Directory]::Delete($link, $false) }
            }
        }

        It 'blocks before returning resources when readiness is missing' {
            $request.callerPreflight.dependenciesReady = $false
            $response = Invoke-TestArticleStage prepare $request
            $response.result.completionCode | Should -BeExactly 'PREREQUISITE_MISSING'
            $response.PSObject.Properties.Name | Should -Be @('result')
        }

        It 'honors an explicit guidance path and does not fall back from an invalid override' {
            [IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`nguidance:`n  path: Guide.md`ntemplates:`n  character: Override.md`n")
            [IO.File]::WriteAllText((Join-Path $fixture.Root 'Guide.md'), 'Use the explicit guide.')
            [IO.File]::WriteAllText((Join-Path $fixture.Root 'Override.md'), '# Custom character')
            $prepared = Invoke-TestArticleStage prepare $request
            $prepared.guidance.text | Should -BeExactly 'Use the explicit guide.'
            $prepared.template.source.kind | Should -BeExactly 'configured'
            [IO.File]::WriteAllText((Join-Path $fixture.Root 'Override.md'), '')
            $response = Invoke-TestArticleStage prepare $request
            $response.result.completionCode | Should -BeExactly 'RESOURCE_INCOMPATIBLE'
            $response.PSObject.Properties.Name | Should -Be @('result')
        }

        It 'resolves a custom article type named custom from the custom mapping' {
            $templateDirectory = Join-Path $fixture.Root '.dmassist-templates'
            [void][IO.Directory]::CreateDirectory($templateDirectory)
            [IO.File]::WriteAllText(
                (Join-Path $templateDirectory 'custom.md'),
                '# <!-- fill-in: required custom article title -->'
            )
            [IO.File]::WriteAllText(
                $fixture.ProfilePath,
                "version: 1`ntemplates:`n  custom:`n    custom: .dmassist-templates/custom.md`n"
            )
            $request.articleType = 'custom'

            $prepared = Invoke-TestArticleStage prepare $request

            $prepared.template.source.kind | Should -BeExactly 'configured'
            $prepared.template.source.path | Should -BeExactly '.dmassist-templates/custom.md'
            $prepared.template.text | Should -BeExactly '# <!-- fill-in: required custom article title -->'
        }

        It 'reports a missing configured template without fallback and rejects its disappearance after preparation' {
            [IO.File]::WriteAllText($fixture.ProfilePath, "version: 1`ntemplates:`n  character: Override.md`n")
            $override = Join-Path $fixture.Root 'Override.md'
            $response = Invoke-TestArticleStage prepare $request
            $response.result.completionCode | Should -BeExactly 'REFERENCE_UNAVAILABLE'
            $response.PSObject.Properties.Name | Should -Be @('result')
            Test-Path -LiteralPath $destination | Should -BeFalse

            [IO.File]::WriteAllText($override, '# Custom character')
            $request.preparationId = (Invoke-TestArticleStage prepare $request).preparationId
            $request.content = '# Ash Fen'
            Remove-Item -LiteralPath $override
            $stale = Invoke-TestArticleStage preview $request
            $stale.result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
            $stale.result.remainingWork | Should -Match 'ask the DM how to proceed; do not automatically retry'
            Test-Path -LiteralPath $destination | Should -BeFalse
        }

        It 'requires explicit exact approval and rejects guidance changes after preview' {
            $request.operation = 'note.create-article-fact-change'
            $request.preparationId = (Invoke-TestArticleStage prepare $request).preparationId
            $request.content = '# Established character'
            $preview = Invoke-TestArticleStage preview $request
            $preview.preview.requiresApproval | Should -BeTrue
            $request.previewId = $preview.preview.previewId
            (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'CONFIRMATION_REQUIRED'
            $request.approvedPreviewId = $request.previewId
            [IO.File]::WriteAllText((Join-Path $fixture.Root '.dmassist-guidance.md'), 'Changed guidance')
            (Invoke-TestArticleStage apply $request).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
            Test-Path -LiteralPath $destination | Should -BeFalse
        }
    }

    Describe 'Article-specific destination and approval runtime contract' {
        BeforeEach {
            $script:ArticleCreateFixture = New-TestArticleFreshnessFixture
            Enable-TestAuthorizationProvider -VaultRoot $script:ArticleCreateFixture.Root
            Set-TestDependencyReadiness -State ready
        }

        AfterEach {
            Remove-TestVaultFixture -Fixture $script:ArticleCreateFixture
            $script:ArticleCreateFixture = $null
        }

        It 'blocks occupied destinations, missing parents, and ambiguous target sets without writing' {
            $fixture = $script:ArticleCreateFixture
            $before = @(Get-TestVaultSnapshot -Path $fixture.Root)
            $occupiedRequest = New-TestArticleCreateRequest -Fixture $fixture -TargetPath $fixture.DestinationRelativePath
            (Invoke-DmPreview -Request $occupiedRequest).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'

            $missingParentRequest = New-TestArticleCreateRequest -Fixture $fixture -TargetPath 'Missing Parent/New Article.md'
            (Invoke-DmPreview -Request $missingParentRequest).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'

            $nonMarkdownRequest = New-TestArticleCreateRequest -Fixture $fixture -TargetPath 'Articles/Unsupported.txt'
            (Invoke-DmPreview -Request $nonMarkdownRequest).result.completionCode | Should -BeExactly 'PATH_INVALID'

            $ambiguousRequest = New-TestArticleCreateRequest -Fixture $fixture
            $ambiguousRequest.targets = @('Articles/First.md', 'Articles/Second.md')
            (Invoke-DmPreview -Request $ambiguousRequest).result.completionCode | Should -BeExactly 'INVALID_REQUEST'
            Test-Path -LiteralPath (Join-Path $fixture.Root 'Articles\Created Adventure.md') | Should -BeFalse
            [System.IO.File]::ReadAllText($fixture.DestinationPath) | Should -Match 'Original article'
            @(Get-TestVaultSnapshot -Path $fixture.Root) | Should -Be $before
        }

        It 'allows a page-local article without approval but requires exact preview approval for fact changes' {
            $fixture = $script:ArticleCreateFixture
            $pageLocalRequest = New-TestArticleCreateRequest -Fixture $fixture
            $pageLocalPreview = Invoke-DmPreview -Request $pageLocalRequest
            $pageLocalPreview.result.completionCode | Should -BeExactly 'OK'
            $pageLocalPreview.preview.requiresApproval | Should -BeFalse

            $pageLocalApply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.create-article' -Mode apply `
                -Targets @($pageLocalRequest.targets) -Arguments $pageLocalRequest.arguments `
                -Extra @{ authoringInputs = $pageLocalRequest.authoringInputs }
            $pageLocalOutcome = Invoke-DmApply -Request $pageLocalApply
            $pageLocalOutcome.result.completionCode | Should -BeExactly 'OK' -Because ($pageLocalOutcome.result | ConvertTo-Json -Depth 8)
            [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'Articles\Created Adventure.md')) | Should -BeExactly "# Synthetic article`n"

            $rootRequest = New-TestArticleCreateRequest -Fixture $fixture -TargetPath 'Root Article.md' -Content "# Root article`n"
            $rootApply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.create-article' -Mode apply `
                -Targets @($rootRequest.targets) -Arguments $rootRequest.arguments `
                -Extra @{ authoringInputs = $rootRequest.authoringInputs }
            (Invoke-DmApply -Request $rootApply).result.completionCode | Should -BeExactly 'OK'
            [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'Root Article.md')) | Should -BeExactly "# Root article`n"

            $factChangeRequest = New-TestArticleCreateRequest -Fixture $fixture -Operation 'note.create-article-fact-change' `
                -TargetPath 'Articles/Established Arc.md' -Content "# Changes established continuity`n"
            $factChangePreview = Invoke-DmPreview -Request $factChangeRequest
            $factChangePreview.result.completionCode | Should -BeExactly 'OK'
            $factChangePreview.preview.requiresApproval | Should -BeTrue

            $unapprovedApply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.create-article-fact-change' -Mode apply `
                -Targets @($factChangeRequest.targets) -Arguments $factChangeRequest.arguments `
                -Extra @{ authoringInputs = $factChangeRequest.authoringInputs }
            (Invoke-DmApply -Request $unapprovedApply).result.completionCode | Should -BeExactly 'CONFIRMATION_REQUIRED'
            Test-Path -LiteralPath (Join-Path $fixture.Root 'Articles\Established Arc.md') | Should -BeFalse

            $approvedApply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation 'note.create-article-fact-change' -Mode apply `
                -Targets @($factChangeRequest.targets) -Arguments $factChangeRequest.arguments `
                -Extra @{
                    authoringInputs = $factChangeRequest.authoringInputs
                    approvedPreviewId = $factChangePreview.preview.previewId
                    reviewedVersions = $factChangePreview.preview.reviewedVersions
                    reviewedDependencyVersions = $factChangePreview.preview.reviewedDependencyVersions
                }
            (Invoke-DmApply -Request $approvedApply).result.completionCode | Should -BeExactly 'OK'
            [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'Articles\Established Arc.md')) | Should -BeExactly "# Changes established continuity`n"
        }

        It 'invalidates approval when consumed inputs or the proposed content change' {
            $fixture = $script:ArticleCreateFixture
            $previewRequest = New-TestArticleCreateRequest -Fixture $fixture -Operation 'note.create-article-fact-change' `
                -TargetPath 'Articles/Reviewed Article.md' -Content "# Reviewed proposal`n"
            $previewOutcome = Invoke-DmPreview -Request $previewRequest
            $previewOutcome.result.completionCode | Should -BeExactly 'OK'

            [System.IO.File]::WriteAllText($fixture.TemplatePath, "# Changed template`n")
            $staleInputApply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation $previewRequest.operation -Mode apply `
                -Targets @($previewRequest.targets) -Arguments $previewRequest.arguments `
                -Extra @{
                    authoringInputs = $previewRequest.authoringInputs
                    approvedPreviewId = $previewOutcome.preview.previewId
                    reviewedVersions = $previewOutcome.preview.reviewedVersions
                    reviewedDependencyVersions = $previewOutcome.preview.reviewedDependencyVersions
                }
            (Invoke-DmApply -Request $staleInputApply).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'

            $changedProposalApply = New-TestOperationRequest -VaultRoot $fixture.Root -Operation $previewRequest.operation -Mode apply `
                -Targets @($previewRequest.targets) -Arguments ([ordered]@{ content = "# Changed proposal`n" }) `
                -Extra @{
                    authoringInputs = $previewRequest.authoringInputs
                    approvedPreviewId = $previewOutcome.preview.previewId
                    reviewedVersions = $previewOutcome.preview.reviewedVersions
                    reviewedDependencyVersions = $previewOutcome.preview.reviewedDependencyVersions
                }
            (Invoke-DmApply -Request $changedProposalApply).result.completionCode | Should -BeExactly 'TARGET_CONFLICT'
            Test-Path -LiteralPath (Join-Path $fixture.Root 'Articles\Reviewed Article.md') | Should -BeFalse
        }
    }

    Describe 'Article path containment through the shared vault modules' {
        BeforeEach {
            $script:ArticleFixture = New-TestArticleFreshnessFixture
            Enable-TestAuthorizationProvider -VaultRoot $script:ArticleFixture.Root
        }

        AfterEach {
            if ($null -ne $script:ArticleFixture) {
                Remove-TestVaultFixture -Fixture $script:ArticleFixture
                $script:ArticleFixture = $null
            }
        }

        It 'rejects absolute and traversal template and destination paths before reading' {
            $outsidePath = ([string]$script:ArticleFixture.OutsidePath).Replace('\', '/') + '/secret.md'
            $invalidPaths = @(
                '../outside/secret.md'
                $outsidePath
                'Articles/../../outside/New Article.md'
                'C:/outside/New Article.md'
            )

            foreach ($path in $invalidPaths) {
                (Test-DmVaultRelativePath -Path $path).isValid | Should -BeFalse
                $resolution = Resolve-DmVaultTarget -Boundary $script:ArticleFixture.Boundary -Path $path
                $resolution.code | Should -BeExactly 'PATH_INVALID'

                $read = Read-DmVaultTargetBytes -Boundary $script:ArticleFixture.Boundary -Resolution $resolution
                $read.ok | Should -BeFalse
                $read.code | Should -BeExactly 'PATH_INVALID'
            }
        }

        It 'rejects template and destination paths that resolve through an escaping directory link before reading' {
            $templateLink = Join-Path $script:ArticleFixture.Root 'article-template-link'
            $destinationLink = Join-Path $script:ArticleFixture.Root 'article-destination-link'
            $linksCreated = [System.Collections.Generic.List[string]]::new()

            try {
                foreach ($linkPath in @($templateLink, $destinationLink)) {
                    try {
                        [void][System.IO.Directory]::CreateSymbolicLink($linkPath, $script:ArticleFixture.OutsidePath)
                    }
                    catch {
                        try {
                            $null = New-Item -ItemType Junction -Path $linkPath `
                                -Target $script:ArticleFixture.OutsidePath -ErrorAction Stop
                        }
                        catch {
                            Set-ItResult -Skipped -Because 'directory symbolic links and junctions are unavailable in this environment'
                            return
                        }
                    }
                    $linksCreated.Add($linkPath)
                }

                Mock -ModuleName VaultBoundary -CommandName Read-DmVaultFileHandleSnapshot -MockWith {
                    throw 'An escaping article path must not reach the file reader.'
                }

                foreach ($path in @('article-template-link/secret.md', 'article-destination-link/New Article.md')) {
                    $resolution = Resolve-DmVaultTarget -Boundary $script:ArticleFixture.Boundary -Path $path
                    $resolution.status | Should -BeExactly 'outside'
                    $resolution.code | Should -BeExactly 'PATH_OUTSIDE_VAULT'

                    $read = Read-DmVaultTargetBytes -Boundary $script:ArticleFixture.Boundary -Resolution $resolution
                    $read.ok | Should -BeFalse
                    $read.code | Should -BeExactly 'PATH_OUTSIDE_VAULT'
                }

                Should -Invoke -ModuleName VaultBoundary -CommandName Read-DmVaultFileHandleSnapshot -Times 0
            }
            finally {
                foreach ($linkPath in $linksCreated) {
                    try { [System.IO.Directory]::Delete($linkPath, $false) } catch { $null = $_ }
                }
            }
        }

        It 'defers Resolver symlink qualification without relaxing script containment' {
            $skillPath = Join-Path $PSScriptRoot '..\..\skills\article-authoring\SKILL.md'
            $skill = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($skillPath))

            $skill | Should -Match '(?s)deferred to the vault owner, not an authoring gate'
            $skill | Should -Match 'PowerShell target containment remains mandatory'
        }
    }

    It 'contains no executable or dynamic Markdown syntax in any bundled template' {
        $forbiddenPatterns = @(
            '\{\{'
            '\}\}'
            '\{%|%\}'
            '<%|%>'
            '\$\{'
            '(?m)^[ \t]*```[ \t]*dataview(?:js)?\b'
            '(?im)(?:^|[ \t])=[ \t]*(?:this\.|dv\.|file\.)'
            '(?i)\bjavascript\s*:'
            '(?is)<\s*(?:script|iframe|object|embed)\b'
            '(?i)\bon[a-z][a-z0-9_-]*\s*='
        )

        foreach ($type in $script:BuiltInTypes) {
            $path = Join-Path -Path $script:TemplateDirectory -ChildPath "$type.md"
            $content = [System.IO.File]::ReadAllText($path)
            foreach ($pattern in $forbiddenPatterns) {
                $match = [System.Text.RegularExpressions.Regex]::Match($content, $pattern)
                $match.Success | Should -BeFalse -Because "$type.md must remain static Markdown; found '$($match.Value)'"
            }
        }
    }
}
