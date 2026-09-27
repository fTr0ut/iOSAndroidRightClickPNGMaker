<#
.SYNOPSIS
    Add mobile-store image tools to the .png right-click menu (per-user, no admin).

.DESCRIPTION
    Registers a classic shell verb under HKCU so it needs no administrator rights.
    On Windows 11 this appears in the "Show more options" (Shift+F10) menu.
    Adds the existing icon generator plus direct App Store Connect and Google
    Play Console screenshot presets. Run uninstall.ps1 to remove them.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Resolve paths relative to this script so it works wherever the folder lives.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir 'Make-MobileIcons.ps1'
$resizeTarget = Join-Path $scriptDir 'Resize-StoreScreenshot.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    throw ("Cannot find Make-MobileIcons.ps1 next to this installer: " + $target)
}
if (-not (Test-Path -LiteralPath $resizeTarget)) {
    throw ("Cannot find Resize-StoreScreenshot.ps1 next to this installer: " + $resizeTarget)
}

$psExe = (Get-Command powershell.exe).Source
$iconValue = $psExe + ',0'

$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $target + '" -Path "%1"'

$pngShellRoot = 'HKCU:\Software\Classes\SystemFileAssociations\.png\shell'
$key = Join-Path $pngShellRoot 'MakeMobileIcons'
$cmdKey = $key + '\command'

New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name '(default)' -Value 'Generate Mobile App Icons'
Set-ItemProperty -Path $key -Name 'Icon' -Value $iconValue

New-Item -Path $cmdKey -Force | Out-Null
Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $command

# Register each resize preset as a direct verb. This uses the same broadly
# compatible shell layout as the existing icon generator.
$resizeCommands = @(
    @{ Id = 'ResizeStoreScreenshot01'; Label = 'Resize Screenshot - Apple iPhone - 1242 x 2688'; Preset = 'Apple-iPhone-1242x2688' },
    @{ Id = 'ResizeStoreScreenshot02'; Label = 'Resize Screenshot - Apple iPhone - 1284 x 2778'; Preset = 'Apple-iPhone-1284x2778' },
    @{ Id = 'ResizeStoreScreenshot03'; Label = 'Resize Screenshot - Apple iPad - 2064 x 2752'; Preset = 'Apple-iPad-2064x2752' },
    @{ Id = 'ResizeStoreScreenshot04'; Label = 'Resize Screenshot - Apple iPad - 2048 x 2732'; Preset = 'Apple-iPad-2048x2732' },
    @{ Id = 'ResizeStoreScreenshot05'; Label = 'Resize Screenshot - Google Play - 1080 x 1920'; Preset = 'GooglePlay-1080x1920' }
)

# Remove the earlier cascading-menu registration, which is not interpreted
# consistently by every Windows Explorer build.
$oldCascadeKey = Join-Path $pngShellRoot 'ResizeStoreScreenshot'
if (Test-Path -LiteralPath $oldCascadeKey) {
    Remove-Item -LiteralPath $oldCascadeKey -Recurse -Force
}

foreach ($item in $resizeCommands) {
    $verbKey = Join-Path $pngShellRoot $item.Id
    $verbCommandKey = $verbKey + '\command'
    $resizeCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $resizeTarget + '" -Path "%1" -Preset ' + $item.Preset

    New-Item -Path $verbKey -Force | Out-Null
    Set-ItemProperty -Path $verbKey -Name '(default)' -Value $item.Label
    Set-ItemProperty -Path $verbKey -Name 'Icon' -Value $iconValue

    New-Item -Path $verbCommandKey -Force | Out-Null
    Set-ItemProperty -Path $verbCommandKey -Name '(default)' -Value $resizeCommand
}

# Tell Explorer to discard cached file-association data so the new verbs are
# available immediately without restarting explorer.exe.
if (-not ('IconRightClick.ShellChangeNotifier' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace IconRightClick
{
    public static class ShellChangeNotifier
    {
        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(
            uint eventId,
            uint flags,
            IntPtr item1,
            IntPtr item2);

        public static void NotifyAssociationChanged()
        {
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
'@
}
[IconRightClick.ShellChangeNotifier]::NotifyAssociationChanged()

Write-Host "Installed context-menu tools for .png files:"
Write-Host "  Generate Mobile App Icons"
foreach ($item in $resizeCommands) {
    Write-Host ("  " + $item.Label + " (orientation follows source)")
}
Write-Host ""
Write-Host "On Windows 11, right-click a .png and choose 'Show more options'"
Write-Host "(or press Shift+F10) to see the installed tools."
