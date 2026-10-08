<#
.SYNOPSIS
    Add mobile-store image tools to the right-click menu of .png, .jpg/.jpeg
    and .heic/.heif files (per-user, no admin).

.DESCRIPTION
    Registers classic shell verbs under HKCU so it needs no administrator rights.
    On Windows 11 they appear in the "Show more options" (Shift+F10) menu.
    Adds two submenus: the icon generator (Android + iOS, Android only, iOS only)
    and App Store Connect / Google Play Console screenshot presets. Every entry
    works on a selection of up to 100 images, processed together in one window;
    the output is always PNG. Run uninstall.ps1 to remove them.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Resolve paths relative to this script so it works wherever the folder lives.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir 'Make-MobileIcons.ps1'
$resizeTarget = Join-Path $scriptDir 'Resize-StoreScreenshot.ps1'

foreach ($required in @($target, $resizeTarget, (Join-Path $scriptDir 'BatchSupport.ps1'))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw ("Cannot find " + (Split-Path -Leaf $required) + " next to this installer: " + $required)
    }
}

# $SourceImageExtensions: the file types the scripts accept.
. (Join-Path $scriptDir 'BatchSupport.ps1')

$psExe = (Get-Command powershell.exe).Source
$iconValue = $psExe + ',0'

$assocRoot = 'HKCU:\Software\Classes\SystemFileAssociations'

function Register-CascadeMenu {
    # The parent carries only MUIVerb + an empty SubCommands value; its entries
    # live in its own "shell" subkey. Start from a clean key: a leftover
    # (default) value or "command" subkey from an earlier single-verb install
    # would turn it back into a plain verb on some Explorer builds.
    #
    # Command-line verbs default to MultiSelectModel=Document, which Explorer
    # hides once more than 15 files are selected. Player raises that to 100.
    # Explorer still starts one process per selected file; -FromExplorer makes
    # the scripts merge them into a single run.
    param(
        [string] $Key,
        [string] $Label,
        [object[]] $Items
    )

    if (Test-Path -LiteralPath $Key) {
        Remove-Item -LiteralPath $Key -Recurse -Force
    }
    # -Force creates missing parents, e.g. SystemFileAssociations\.heic\shell.
    New-Item -Path $Key -Force | Out-Null
    New-ItemProperty -Path $Key -Name 'MUIVerb' -Value $Label -PropertyType String | Out-Null
    New-ItemProperty -Path $Key -Name 'SubCommands' -Value '' -PropertyType String | Out-Null
    New-ItemProperty -Path $Key -Name 'Icon' -Value $script:iconValue -PropertyType String | Out-Null
    New-ItemProperty -Path $Key -Name 'MultiSelectModel' -Value 'Player' -PropertyType String | Out-Null

    foreach ($item in $Items) {
        $subKey = $Key + '\shell\' + $item.Id
        $subCommandKey = $subKey + '\command'

        New-Item -Path $subKey -Force | Out-Null
        Set-ItemProperty -Path $subKey -Name '(default)' -Value $item.Label
        Set-ItemProperty -Path $subKey -Name 'MUIVerb' -Value $item.Label
        Set-ItemProperty -Path $subKey -Name 'Icon' -Value $script:iconValue
        Set-ItemProperty -Path $subKey -Name 'MultiSelectModel' -Value 'Player'

        New-Item -Path $subCommandKey -Force | Out-Null
        Set-ItemProperty -Path $subCommandKey -Name '(default)' -Value $item.Command
    }
}

function New-VerbCommand {
    param([string] $Script, [string] $Arguments)
    return ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $Script + '" -Path "%1" ' + $Arguments + ' -FromExplorer')
}

# --- Generate Mobile App Icons > -------------------------------------------
$iconCommands = @(
    @{ Id = '01All';     Label = 'Android + iOS'; Platform = 'All' },
    @{ Id = '02Android'; Label = 'Android only';  Platform = 'Android' },
    @{ Id = '03iOS';     Label = 'iOS only';      Platform = 'iOS' }
)
foreach ($item in $iconCommands) {
    $item.Command = New-VerbCommand -Script $target -Arguments ('-Platform ' + $item.Platform)
}

# --- Resize Store Screenshot > ---------------------------------------------
# Labels name the portrait size; a landscape source gets the reversed size.
$resizeCommands = @(
    @{ Id = '01'; Label = 'Apple iPhone 6.9" - 1320 x 2868';               Preset = 'Apple-iPhone-1320x2868' },
    @{ Id = '02'; Label = 'Apple iPhone 6.3" - 1206 x 2622';               Preset = 'Apple-iPhone-1206x2622' },
    @{ Id = '03'; Label = 'Apple iPhone 6.5" - 1284 x 2778';               Preset = 'Apple-iPhone-1284x2778' },
    @{ Id = '04'; Label = 'Apple iPhone 6.5" - 1242 x 2688';               Preset = 'Apple-iPhone-1242x2688' },
    @{ Id = '05'; Label = 'Apple iPad 13" - 2064 x 2752';                  Preset = 'Apple-iPad-2064x2752' },
    @{ Id = '06'; Label = 'Apple iPad 13" - 2048 x 2732';                  Preset = 'Apple-iPad-2048x2732' },
    @{ Id = '07'; Label = 'Google Play phone - 1080 x 1920';               Preset = 'GooglePlay-1080x1920' },
    @{ Id = '08'; Label = 'Google Play tablet (7" and 10") - 1440 x 2560'; Preset = 'GooglePlay-Tablet-1440x2560' }
)
foreach ($item in $resizeCommands) {
    $item.Command = New-VerbCommand -Script $resizeTarget -Arguments ('-Preset ' + $item.Preset)
}

# An earlier install registered each preset as a direct .png verb.
foreach ($n in 1..5) {
    $oldVerbKey = $assocRoot + '\.png\shell\ResizeStoreScreenshot0' + $n
    if (Test-Path -LiteralPath $oldVerbKey) {
        Remove-Item -LiteralPath $oldVerbKey -Recurse -Force
    }
}

# The same verbs and commands for every file type. A batch is keyed on the
# script and its mode, so a selection that mixes types still runs as one batch.
foreach ($ext in $SourceImageExtensions) {
    $shellRoot = $assocRoot + '\' + $ext + '\shell'
    Register-CascadeMenu -Key ($shellRoot + '\MakeMobileIcons') -Label 'Generate Mobile App Icons' -Items $iconCommands
    Register-CascadeMenu -Key ($shellRoot + '\ResizeStoreScreenshot') -Label 'Resize Store Screenshot' -Items $resizeCommands
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

Write-Host ("Installed context-menu tools for " + ($SourceImageExtensions -join ', ') + " files:")
Write-Host "  Generate Mobile App Icons >"
foreach ($item in $iconCommands) {
    Write-Host ("      " + $item.Label)
}
Write-Host "  Resize Store Screenshot >   (orientation follows each source)"
foreach ($item in $resizeCommands) {
    Write-Host ("      " + $item.Label)
}
Write-Host ""
Write-Host "Select one image or up to 100 and they are processed together in one window."
Write-Host "Every output file is a PNG."
Write-Host "On Windows 11, right-click and choose 'Show more options'"
Write-Host "(or press Shift+F10) to see the installed tools."
