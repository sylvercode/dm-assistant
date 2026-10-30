BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.psm1') -Force
    $script:RuntimeSources = @(Get-ChildItem -LiteralPath (Get-TestScriptsRoot) -Recurse -File |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') })
}

Describe 'PowerShell runtime function help' {
    It 'parses every runtime PowerShell source without errors' {
        $script:RuntimeSources.Count | Should -BeGreaterThan 0
        foreach ($module in $script:RuntimeSources) {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($module.FullName, [ref]$tokens, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0 -Because "$($module.Name) must be valid PowerShell"
        }
    }

    It 'documents every function and exactly its declared parameters' {
        foreach ($module in $script:RuntimeSources) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($module.FullName, [ref]$tokens, [ref]$parseErrors)
            $functions = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)

            foreach ($function in $functions) {
                $help = $function.GetHelpContent()
                $help | Should -Not -BeNullOrEmpty -Because "$($module.Name):$($function.Name) needs comment-based help"
                [string]::IsNullOrWhiteSpace($help.Synopsis) | Should -BeFalse -Because "$($function.Name) needs a synopsis"
                $parameters = if ($function.Parameters) {
                    @($function.Parameters)
                }
                elseif ($function.Body.ParamBlock) {
                    @($function.Body.ParamBlock.Parameters)
                }
                else {
                    @()
                }
                $names = @($parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                foreach ($name in $names) {
                    $key = $name.ToUpperInvariant()
                    $help.Parameters.ContainsKey($key) | Should -BeTrue -Because "$($function.Name) must document $name"
                    [string]::IsNullOrWhiteSpace([string]$help.Parameters[$key]) |
                        Should -BeFalse -Because "$($function.Name) must describe $name"
                }
                foreach ($name in $help.Parameters.Keys) {
                    $name | Should -BeIn $names -Because "$($function.Name) must not document an unknown parameter"
                }
            }
        }
    }

    It 'exposes exported and private parameter descriptions through Get-Help' {
        Import-TestProductionModule -Name OperationRequest, VaultConfiguration
        $exported = Get-Help Register-DmOperation -Parameter Builder
        $exported.description.Text | Should -Match 'complete replacement text'

        $private = & (Get-Module VaultConfiguration) {
            Get-Help ConvertTo-DmProfileNormalizedValue -Parameter Value
        }
        $private.description.Text | Should -Match 'YAML mapping or scalar'
    }
}
