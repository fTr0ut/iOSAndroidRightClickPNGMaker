<#
.SYNOPSIS
    Remove the right-click "Generate Mobile App Icons" verb for .png files.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$key = 'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\MakeMobileIcons'

if (Test-Path -LiteralPath $key) {
    Remove-Item -Path $key -Recurse -Force
    Write-Host ("Removed: " + $key)
}
else {
    Write-Host ("Nothing to remove (key not present): " + $key)
}
