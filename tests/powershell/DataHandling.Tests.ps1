BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    Import-TestProductionModule -Name VaultPathValidation, VaultBoundary

    function Test-DmLiteralAuditArgument {
        param([System.Management.Automation.Language.Ast]$Expression)

        if ($Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $Expression -is [System.Management.Automation.Language.ConstantExpressionAst]) {
            return $true
        }
        if ($Expression -is [System.Management.Automation.Language.ArrayExpressionAst] -or
            $Expression -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            $dynamicParts = $Expression.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -or
                    $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
                    $node -is [System.Management.Automation.Language.CommandAst]
                }, $true)
            return @($dynamicParts).Count -eq 0
        }
        return $false
    }

    function Test-DmLocalScriptBlockInvocation {
        param(
            [System.Management.Automation.Language.CommandAst]$Command,
            [System.Management.Automation.Language.Ast]$Root
        )
        if ($Command.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Ampersand -or
            $Command.CommandElements.Count -eq 0) {
            return $false
        }
        $target = $Command.CommandElements[0]
        if ($target -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $target.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $target.Expression.VariablePath.UserPath -ceq 'registration' -and
            $target.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $target.Member.Value -ceq 'builder') {
            return $true
        }
        if ($target -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
        $name = $target.VariablePath.UserPath
        if ($name.Contains(':')) { return $false }
        $assignments = @($Root.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -ceq $name
                }, $true))
        if ($assignments.Count -eq 0) { return $false }
        foreach ($assignment in $assignments) {
            $expression = $assignment.Right
            if ($expression -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $expression = $expression.Expression
            }
            if ($expression -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
        }
        $true
    }

    function Get-DmStaticAuditViolation {
        param([Parameter(Mandatory)][string]$SourceText)

        $violations = [System.Collections.Generic.List[string]]::new()
        if ($SourceText -match '(?i)\btests[\\/]') {
            $violations.Add('tests-reference')
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($SourceText, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            $violations.Add('parse-error')
        }

        $fileSystemCommands = @(
            'Add-Content', 'Clear-Content', 'Copy-Item', 'Get-ChildItem', 'Get-Content', 'Get-Item',
            'Get-ItemProperty', 'Move-Item', 'New-Item', 'Out-File', 'Remove-Item', 'Rename-Item',
            'Resolve-Path', 'Set-Content', 'Set-ItemProperty', 'Test-Path'
        )
        $bannedCommands = @{
            'iex'                 = 'dynamic-execution'
            'invoke-expression'   = 'dynamic-execution'
            'invoke-command'      = 'dynamic-execution'
            'set-executionpolicy' = 'execution-policy'
            'unblock-file'        = 'execution-policy'
            'iwr'                 = 'network-api'
            'irm'                 = 'network-api'
            'invoke-webrequest'   = 'network-api'
            'invoke-restmethod'   = 'network-api'
            'install-module'      = 'module-install'
            'update-module'       = 'module-install'
        }

        foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $commandName = $command.GetCommandName()
            if ([string]::IsNullOrEmpty($commandName)) {
                if (-not (Test-DmLocalScriptBlockInvocation -Command $command -Root $ast)) {
                    $violations.Add('dynamic-execution')
                }
                continue
            }
            $normalizedName = [System.IO.Path]::GetFileName($commandName).ToLowerInvariant()
            $visitedAliases = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            while ($visitedAliases.Add($normalizedName)) {
                $alias = Get-Alias -Name $normalizedName -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $alias) { break }
                $normalizedName = [System.IO.Path]::GetFileName([string]$alias.Definition).ToLowerInvariant()
            }
            if ($bannedCommands.ContainsKey($normalizedName)) {
                $violations.Add($bannedCommands[$normalizedName])
            }

            $elements = @($command.CommandElements)
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $hostCommand = $normalizedName -in @('pwsh', 'pwsh.exe', 'powershell', 'powershell.exe')
                    if ($hostCommand) {
                        $executionParameters = @('Command', 'CommandWithArgs', 'EncodedCommand', 'EncodedArguments')
                        foreach ($parameter in $executionParameters) {
                            if ($parameter.StartsWith($element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $violations.Add('dynamic-execution')
                                break
                            }
                        }
                    }
                    if ($hostCommand -and $element.ParameterName -match '^(?i:e(x(ec(ution)?)?)?p(olicy)?)$' -and $index + 1 -lt $elements.Count) {
                        if ($elements[$index + 1].Extent.Text -match '(?i)^["'']?bypass["'']?$') {
                            $violations.Add('execution-policy')
                        }
                    }
                    if ($element.ParameterName -match '^(?i:arg(u(ment(list)?)?)?|args)$' -and $normalizedName -eq 'start-process' -and
                        $index + 1 -lt $elements.Count -and -not (Test-DmLiteralAuditArgument -Expression $elements[$index + 1])) {
                        $violations.Add('dynamic-execution')
                    }
                    if ($element.ParameterName -eq 'Path' -and $normalizedName -in $fileSystemCommands) {
                        $violations.Add('non-literal-filesystem-path')
                    }
                    if ($element.ParameterName -eq 'LiteralPath' -and $normalizedName -in $fileSystemCommands) {
                        if ($index + 1 -ge $elements.Count) { $violations.Add('non-literal-filesystem-path') }
                    }
                }
            }

            if ($normalizedName -in $fileSystemCommands) {
                $hasLiteralPath = @($elements | Where-Object {
                        $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'LiteralPath'
                    }).Count -gt 0
                if (-not $hasLiteralPath) {
                    $violations.Add('non-literal-filesystem-path')
                }
                foreach ($element in $elements | Select-Object -Skip 1) {
                    if ($element -isnot [System.Management.Automation.Language.CommandParameterAst] -and
                        $element -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $element -isnot [System.Management.Automation.Language.VariableExpressionAst] -and
                        $element -isnot [System.Management.Automation.Language.ExpandableStringExpressionAst] -and
                        $element -isnot [System.Management.Automation.Language.CommandAst] -and
                        $element -isnot [System.Management.Automation.Language.ParenExpressionAst]) {
                        continue
                    }
                    if (-not $hasLiteralPath -and $element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        $violations.Add('non-literal-filesystem-path')
                        break
                    }
                }
            }
        }

        foreach ($memberCall in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
            if ($memberCall.Member.Extent.Text -eq 'Create' -and
                $memberCall.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                $memberCall.Expression.TypeName.FullName -match '^(?i:scriptblock)$') {
                $violations.Add('dynamic-execution')
            }
        }
        $codeTokens = $tokens | Where-Object { $_.Kind -notin @('Comment', 'StringLiteral', 'HereStringLiteral') }
        if (($codeTokens | ForEach-Object { $_.Text }) -join ' ' -match '(?i)\bSystem\.Net(?:\.[A-Za-z_][A-Za-z0-9_]*)*') {
            $violations.Add('network-api')
        }

        @($violations | Sort-Object -Unique)
    }
}

Describe 'Inert note content and vault paths' {
    It 'reads executable-looking note text and command-like path names as literal data' {
        $markerPath = Join-Path -Path $TestDrive -ChildPath 'executed.marker'
        $fileName = '$(New-Item executed.marker).md'
        $noteContent = @'
$(New-Item executed.marker)
`$(New-Item executed.marker)
semi;colon | brackets [data] and wildcard *
'@
        $filePath = [System.IO.Path]::Combine($TestDrive, $fileName)
        [System.IO.File]::WriteAllText($filePath, $noteContent, [System.Text.UTF8Encoding]::new($false))
        $boundary = [pscustomobject]@{
            selectedRoot  = $TestDrive
            canonicalRoot = $TestDrive
            comparison    = [System.StringComparison]::OrdinalIgnoreCase
        }

        $resolution = Resolve-DmVaultTarget -Boundary $boundary -Path $fileName
        $resolution.status | Should -BeExactly 'resolved'
        $resolution.resolvedPath | Should -BeExactly $filePath
        $read = Read-DmVaultTargetBytes -Boundary $boundary -Resolution $resolution
        $read.ok | Should -BeTrue
        [System.Text.UTF8Encoding]::new($false).GetString($read.bytes) | Should -BeExactly $noteContent
        (Test-Path -LiteralPath $markerPath) | Should -BeFalse
    }

    It 'treats backticks and semicolons in paths literally while rejecting wildcard and pattern syntax' {
        $boundary = [pscustomobject]@{
            selectedRoot  = $TestDrive
            canonicalRoot = $TestDrive
            comparison    = [System.StringComparison]::OrdinalIgnoreCase
        }
        foreach ($name in @('literal`tick.md', 'semi;colon.md')) {
            $filePath = [System.IO.Path]::Combine($TestDrive, $name)
            [System.IO.File]::WriteAllText($filePath, 'inert')
            $resolution = Resolve-DmVaultTarget -Boundary $boundary -Path $name
            $resolution.status | Should -BeExactly 'resolved'
            $resolution.resolvedPath | Should -BeExactly $filePath
        }

        foreach ($path in @('pipe|name.md', 'left[bracket].md', 'wild*.md')) {
            $resolution = Resolve-DmVaultTarget -Boundary $boundary -Path $path
            $resolution.code | Should -BeExactly 'PATH_INVALID' -Because "path syntax must not be interpreted: $path"
        }
    }

    It 'rejects Windows superscript reserved device names, including extensions' {
        foreach ($path in @('COM¹', 'COM².txt', 'COM³.md', 'LPT¹', 'LPT².log', 'LPT³.note')) {
            (Test-DmVaultRelativePath -Path $path).isValid | Should -BeFalse -Because $path
        }
        foreach ($path in @('COM10.txt', 'LPT0.md', 'ordinary.md')) {
            (Test-DmVaultRelativePath -Path $path).isValid | Should -BeTrue -Because $path
        }
    }
}

Describe 'PowerShell production-script static audit' {
    It 'detects each prohibited API, command, path parameter, network access, and dynamic execution' {
        $cases = @(
            @{ Text = 'Invoke-Expression $data'; Rule = 'dynamic-execution' }
            @{ Text = 'iex $data'; Rule = 'dynamic-execution' }
            @{ Text = '$script = [scriptblock]::Create($data)'; Rule = 'dynamic-execution' }
            @{ Text = '& $noteContent'; Rule = 'dynamic-execution' }
            @{ Text = '& (Get-Command $noteContent)'; Rule = 'dynamic-execution' }
            @{ Text = 'pwsh -Command $data'; Rule = 'dynamic-execution' }
            @{ Text = 'pwsh -c $data'; Rule = 'dynamic-execution' }
            @{ Text = 'Start-Process pwsh -ArgumentList $arguments'; Rule = 'dynamic-execution' }
            @{ Text = 'Set-ExecutionPolicy Bypass'; Rule = 'execution-policy' }
            @{ Text = 'pwsh -ExecutionPolicy Bypass -NoProfile'; Rule = 'execution-policy' }
            @{ Text = 'pwsh -ep Bypass -NoProfile'; Rule = 'execution-policy' }
            @{ Text = 'Unblock-File -LiteralPath $path'; Rule = 'execution-policy' }
            @{ Text = 'Get-Item -Path $path'; Rule = 'non-literal-filesystem-path' }
            @{ Text = 'Get-Item $path'; Rule = 'non-literal-filesystem-path' }
            @{ Text = 'gc $path'; Rule = 'non-literal-filesystem-path' }
            @{ Text = 'cat -Path $path'; Rule = 'non-literal-filesystem-path' }
            @{ Text = 'gci $path'; Rule = 'non-literal-filesystem-path' }
            @{ Text = 'pwsh -EncodedCommand $data'; Rule = 'dynamic-execution' }
            @{ Text = 'pwsh -EncodedArguments $data'; Rule = 'dynamic-execution' }
            @{ Text = 'Invoke-WebRequest -Uri $uri'; Rule = 'network-api' }
            @{ Text = 'iwr -Uri $uri'; Rule = 'network-api' }
            @{ Text = 'Invoke-RestMethod -Uri $uri'; Rule = 'network-api' }
            @{ Text = 'irm -Uri $uri'; Rule = 'network-api' }
            @{ Text = '$client = [System.Net.WebClient]::new()'; Rule = 'network-api' }
            @{ Text = 'Install-Module Example'; Rule = 'module-install' }
            @{ Text = 'Update-Module Example'; Rule = 'module-install' }
            @{ Text = '# see tests/powershell/example'; Rule = 'tests-reference' }
        )
        foreach ($case in $cases) {
            (Get-DmStaticAuditViolation -SourceText $case.Text) | Should -Contain $case.Rule -Because $case.Text
        }
    }

    It 'allows literal-path access, .NET file IO, local scriptblock helpers, and the supported module import pattern' {
        $safeSource = @'
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1')
Get-Content -LiteralPath $path
[System.IO.File]::ReadAllBytes($path)
$helper = { param($value) $value }
& $helper 'literal'
$registration = [pscustomobject]@{ builder = { param($text) $text } }
& $registration.builder 'literal'
$process = [System.Diagnostics.ProcessStartInfo]::new('copilot')
foreach ($argument in @('mcp', 'get', $validatedId)) { $process.ArgumentList.Add($argument) }
'@
        (Get-DmStaticAuditViolation -SourceText $safeSource) | Should -BeNullOrEmpty
    }

    It 'audits every production script without false positives' {
        $scriptsPath = Join-Path -Path (Get-TestScriptsRoot) -ChildPath ''
        $scripts = @(Get-ChildItem -LiteralPath $scriptsPath -Filter '*.psm1' -File | Sort-Object Name)
        $scripts.Count | Should -BeGreaterThan 0
        foreach ($script in $scripts) {
            $source = [System.IO.File]::ReadAllText($script.FullName)
            $violations = Get-DmStaticAuditViolation -SourceText $source
            $violations | Should -BeNullOrEmpty -Because "$($script.Name) must comply with the static safety audit"
        }
    }
}
