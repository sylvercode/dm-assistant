[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$operation = 'vault.orientation.inventory'
$runtimePath = Join-Path -Path $PSScriptRoot -ChildPath 'RuntimeContract.psm1'
$inventoryPath = Join-Path -Path $PSScriptRoot -ChildPath 'VaultInventory.psm1'
Import-Module -Name $runtimePath -ErrorAction Stop
Import-Module -Name $inventoryPath -ErrorAction Stop

<#
.SYNOPSIS
Creates the standard blocked response for invalid inventory entry-point input.

.PARAMETER Code
The runtime completion code to return.

.PARAMETER Message
The safe diagnostic message to return.
#>
function New-InventoryEntryBlock([string]$Code, [string]$Message) {
    @{
        result = New-DmBlockedResult -Operation $operation -CompletionCode $Code -Targets @() `
            -Message $Message -RemainingWork @('Correct the inventory input, then retry.')
        inventoryReport = $null
    }
}

$requestJson = ''
try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false, $true)
    $requestJson = [Console]::In.ReadToEnd()
}
catch [System.Text.DecoderFallbackException] {
    New-InventoryEntryBlock 'INVALID_REQUEST' 'Standard input must contain valid UTF-8 JSON.' |
        ConvertTo-Json -Depth 40 -Compress
    exit 0
}

if ([string]::IsNullOrWhiteSpace($requestJson)) {
    New-InventoryEntryBlock 'INVALID_REQUEST' 'Supply one JSON inventory input object on standard input.' |
        ConvertTo-Json -Depth 40 -Compress
    exit 0
}

try {
    $inputData = ConvertFrom-Json -InputObject $requestJson -AsHashtable -NoEnumerate -ErrorAction Stop
}
catch {
    New-InventoryEntryBlock 'INVALID_REQUEST' 'Supply a valid JSON inventory input object.' |
        ConvertTo-Json -Depth 40 -Compress
    exit 0
}

$allowedFields = @('vaultRoot', 'callerPreflight', 'selectedGuidance', 'optionalGuidance', 'proposeProfile', 'mappingDecisions')
if ($inputData -isnot [System.Collections.IDictionary] -or
    @($inputData.Keys.Where({ $_ -cnotin $allowedFields })).Count -gt 0) {
    New-InventoryEntryBlock 'INVALID_REQUEST' 'The JSON fields do not match the inventory input contract.' |
        ConvertTo-Json -Depth 40 -Compress
    exit 0
}

$arguments = [ordered]@{}
foreach ($name in @('selectedGuidance', 'optionalGuidance', 'proposeProfile', 'mappingDecisions')) {
    if ($inputData.Contains($name)) { $arguments[$name] = $inputData[$name] }
}

$request = [ordered]@{
    contractVersion = Get-DmContractVersion
    requestId = [guid]::NewGuid().ToString()
    operation = $operation
    vaultRoot = $inputData['vaultRoot']
    campaignGroup = [ordered]@{ campaign = $null; group = $null }
    mode = 'inspect'
    arguments = $arguments
    targets = @()
}
if ($inputData.Contains('callerPreflight')) {
    $request['callerPreflight'] = $inputData['callerPreflight']
}

Invoke-DmInventory -Request $request | ConvertTo-Json -Depth 40 -Compress
