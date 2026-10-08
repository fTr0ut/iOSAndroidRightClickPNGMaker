<#
.SYNOPSIS
    Remove the IconRightClick tools from the right-click menu of every file
    type they were installed for (.png, .jpg/.jpeg, .heic/.heif).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$assocRoot = 'HKCU:\Software\Classes\SystemFileAssociations'

# Both submenus, under whichever file types carry them.
$keys = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $assocRoot) {
    foreach ($assoc in @(Get-ChildItem -LiteralPath $assocRoot)) {
        foreach ($name in @('MakeMobileIcons', 'ResizeStoreScreenshot')) {
            $keys.Add($assocRoot + '\' + $assoc.PSChildName + '\shell\' + $name)
        }
    }
}
# Direct .png verbs registered by an earlier version.
foreach ($n in 1..5) {
    $keys.Add($assocRoot + '\.png\shell\ResizeStoreScreenshot0' + $n)
}

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
