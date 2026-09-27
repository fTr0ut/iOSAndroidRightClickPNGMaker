<#
.SYNOPSIS
    Remove the IconRightClick tools from the .png right-click menu.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$keys = @(
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\MakeMobileIcons',
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot',
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot01',
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot02',
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot03',
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot04',
    'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot05'
)

$removed = 0
foreach ($key in $keys) {
    if (Test-Path -LiteralPath $key) {
        Remove-Item -LiteralPath $key -Recurse -Force
        Write-Host ("Removed: " + $key)
        $removed = $removed + 1
    }
}

if ($removed -eq 0) {
    Write-Host "Nothing to remove (IconRightClick registry keys were not present)."
}
