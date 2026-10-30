#Requires -Version 7.4
<#
Runs the Feature 003 acceptance suite with the pinned test-only Pester 6.2.0.
Never uses the Windows built-in Pester 3.4.0 and never installs anything.
Usage: pwsh -NoProfile -File tests/powershell/Invoke-Tests.ps1 [-Path <test file or folder>]
#>
[CmdletBinding()]
param(
    [string[]]$Path = @($PSScriptRoot),
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')][string]$Output = 'Detailed'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pesterVersion = [version]'6.2.0'
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq $pesterVersion })) {
    Write-Error "Pester $pesterVersion is required for the acceptance tests. See docs/powershell-runtime-support.md." -ErrorAction Continue
    exit 2
}
Import-Module -Name Pester -RequiredVersion $pesterVersion -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path = $Path
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = $Output
$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { exit 1 }
exit 0
