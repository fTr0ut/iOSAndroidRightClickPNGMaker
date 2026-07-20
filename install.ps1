<#
.SYNOPSIS
    Add a right-click "Generate Mobile App Icons" verb for .png files (per-user, no admin).

.DESCRIPTION
    Registers a classic shell verb under HKCU so it needs no administrator rights.
    On Windows 11 this appears in the "Show more options" (Shift+F10) menu.
    Run uninstall.ps1 to remove it.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Resolve paths relative to this script so it works wherever the folder lives.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir 'Make-MobileIcons.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    throw ("Cannot find Make-MobileIcons.ps1 next to this installer: " + $target)
}

$psExe = (Get-Command powershell.exe).Source
$iconValue = $psExe + ',0'

$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $target + '" -Path "%1"'

$key = 'HKCU:\Software\Classes\SystemFileAssociations\.png\shell\MakeMobileIcons'
$cmdKey = $key + '\command'

New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name '(default)' -Value 'Generate Mobile App Icons'
Set-ItemProperty -Path $key -Name 'Icon' -Value $iconValue

New-Item -Path $cmdKey -Force | Out-Null
Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $command

Write-Host "Installed context-menu verb for .png files."
Write-Host ("  Key     : " + $key)
Write-Host ("  Command : " + $command)
Write-Host ""
Write-Host "On Windows 11, right-click a .png and choose 'Show more options'"
Write-Host "(or press Shift+F10) to see 'Generate Mobile App Icons'."
