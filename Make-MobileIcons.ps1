<#
.SYNOPSIS
    Generate Android- and iOS-compliant app icon sets from a single source PNG.

.DESCRIPTION
    Right-click a .png in Windows Explorer -> "Generate Mobile App Icons".
    Produces an iOS AppIcon.appiconset (light / dark / tinted, 1024) plus an
    Android res/ tree (legacy mipmaps, adaptive foreground + monochrome layers,
    adaptive-icon XML, background color, Play Store 512).

    Requires ImageMagick ("magick"). Written for Windows PowerShell 5.1.

.PARAMETER Path
    Path to the source .png image.

.PARAMETER NoInteractive
    Suppress the end-of-run "Press Enter to close" prompt (used for automation).

.EXAMPLE
    .\Make-MobileIcons.ps1 -Path "C:\art\logo.png"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Path,

    [switch] $NoInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

function Write-Step {
    param([string] $Message)
    Write-Host ("  " + $Message)
}

function Resolve-Magick {
    # 1) Try PATH.
    $cmd = Get-Command magick -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    # 2) Fall back to a glob of the default install location.
    $candidates = Get-ChildItem -Path 'C:\Program Files\ImageMagick*\magick.exe' -ErrorAction SilentlyContinue
    if ($candidates) {
        $first = $candidates | Select-Object -First 1
        return $first.FullName
    }
    throw "ImageMagick 'magick.exe' was not found. Install it with: winget install --id ImageMagick.ImageMagick -e"
}

function Invoke-Magick {
    param([string[]] $MagickArgs)
    & $script:Magick @MagickArgs
    if ($LASTEXITCODE -ne 0) {
        throw ("ImageMagick failed (exit " + $LASTEXITCODE + ") for: magick " + ($MagickArgs -join ' '))
    }
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "Generate Mobile App Icons"
    Write-Host "========================="

    $script:Magick = Resolve-Magick
    Write-Step ("Using ImageMagick: " + $script:Magick)

    # --- Validate input ---------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "No -Path was supplied."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Source file does not exist: " + $Path)
    }

    $src = Get-Item -LiteralPath $Path
    if ($src.Extension.ToLowerInvariant() -ne '.png') {
        throw ("Source must be a .png file. Got: " + $src.Extension)
    }

    # Confirm ImageMagick agrees it is a PNG and read dimensions.
    $ident = & $script:Magick identify -format "%m %w %h\n" -- "$($src.FullName)"
    if ($LASTEXITCODE -ne 0) {
        throw ("ImageMagick could not read the image: " + $src.FullName)
    }
    if ($ident -is [array]) {
        $ident = $ident[0]
    }
    $parts = ($ident -split '\s+') | Where-Object { $_ -ne '' }
    $fmt = $parts[0]
    [int] $w = $parts[1]
    [int] $h = $parts[2]
    if ($fmt -notmatch 'PNG') {
        throw ("File does not appear to be a real PNG (ImageMagick reports '" + $fmt + "').")
    }
    Write-Step ("Source: " + $src.Name + " (" + $w + "x" + $h + ")")

    # --- Choose a non-colliding output folder -----------------------------
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src.Name)
    $parentDir = $src.DirectoryName
    $outName = $baseName + "-icons"
    $outDir = Join-Path $parentDir $outName
    if (Test-Path -LiteralPath $outDir) {
        $n = 2
        while ($true) {
            $candidate = Join-Path $parentDir ($baseName + "-icons-" + $n)
            if (-not (Test-Path -LiteralPath $candidate)) {
                $outDir = $candidate
                break
            }
            $n = $n + 1
        }
    }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Write-Step ("Output folder: " + $outDir)

    # --- Build a square, alpha-preserved master ---------------------------
    $wasPadded = $false
    $masterMax = [Math]::Max($w, $h)
    $masterPath = Join-Path $outDir "_master_square.png"
    if ($w -eq $h) {
        Invoke-Magick @("$($src.FullName)", ('PNG32:' + $masterPath))
    }
    else {
        $wasPadded = $true
        # Center the source on a transparent square canvas.
        Invoke-Magick @("$($src.FullName)", '-background', 'none', '-gravity', 'center',
            '-extent', ($masterMax.ToString() + 'x' + $masterMax.ToString()), ('PNG32:' + $masterPath))
        Write-Step ("Image was not square (" + $w + "x" + $h + ") -> padded to " + $masterMax + "x" + $masterMax + " with transparency.")
    }

    # --- Determine a background color (alpha-weighted average, default white)
    $bgHex = '#FFFFFF'
    try {
        $rgb = & $script:Magick "$masterPath" '-resize' '1x1!' '-alpha' 'off' `
            '-format' '%[fx:int(255*r+0.5)],%[fx:int(255*g+0.5)],%[fx:int(255*b+0.5)]' 'info:'
        if ($LASTEXITCODE -eq 0 -and $rgb -match '^\d+,\d+,\d+$') {
            $c = $rgb -split ','
            $bgHex = ('#{0:X2}{1:X2}{2:X2}' -f [int]$c[0], [int]$c[1], [int]$c[2])
        }
    }
    catch {
        $bgHex = '#FFFFFF'
    }
    Write-Step ("Background color (sampled): " + $bgHex)

    # ======================================================================
    # iOS
    # ======================================================================
    Write-Host ""
    Write-Host "iOS ..."
    $iosDir = Join-Path $outDir 'iOS'
    $appIconSet = Join-Path $iosDir 'AppIcon.appiconset'
    New-Item -ItemType Directory -Path $appIconSet -Force | Out-Null

    # Light / default 1024 (App Store rule: NO transparency -> flatten onto white).
    $iconLight = Join-Path $appIconSet 'icon_1024.png'
    Invoke-Magick @("$masterPath", '-resize', '1024x1024',
        '-background', 'white', '-alpha', 'remove', '-alpha', 'off', ('PNG24:' + $iconLight))
    Write-Step "AppIcon.appiconset/icon_1024.png (light, opaque)"

    # Dark variant: darken content slightly and flatten onto near-black.
    $iconDark = Join-Path $appIconSet 'icon_1024_dark.png'
    Invoke-Magick @("$masterPath", '-resize', '1024x1024', '-modulate', '90',
        '-background', 'black', '-alpha', 'remove', '-alpha', 'off', ('PNG24:' + $iconDark))
    Write-Step "AppIcon.appiconset/icon_1024_dark.png (dark)"

    # Tinted variant: grayscale, alpha preserved (system applies the tint).
    $iconTinted = Join-Path $appIconSet 'icon_1024_tinted.png'
    Invoke-Magick @("$masterPath", '-resize', '1024x1024',
        '-colorspace', 'Gray', ('PNG32:' + $iconTinted))
    Write-Step "AppIcon.appiconset/icon_1024_tinted.png (tinted grayscale, alpha)"

    # Contents.json (modern single-size, with appearance entries).
    $contents = @'
{
  "images" : [
    {
      "filename" : "icon_1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon_1024_dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon_1024_tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'@
    $contentsPath = Join-Path $appIconSet 'Contents.json'
    [System.IO.File]::WriteAllText($contentsPath, $contents, (New-Object System.Text.UTF8Encoding($false)))
    Write-Step "AppIcon.appiconset/Contents.json"

    # Plain App Store upload asset (opaque 1024).
    $appStore = Join-Path $iosDir 'AppStore-1024.png'
    Copy-Item -LiteralPath $iconLight -Destination $appStore -Force
    Write-Step "AppStore-1024.png (opaque)"

    # ======================================================================
    # Android
    # ======================================================================
    Write-Host ""
    Write-Host "Android ..."
    $andDir = Join-Path $outDir 'Android'
    $resDir = Join-Path $andDir 'res'

    # Density ladders.
    $legacy = @(
        @{ q = 'mdpi';    px = 48  },
        @{ q = 'hdpi';    px = 72  },
        @{ q = 'xhdpi';   px = 96  },
        @{ q = 'xxhdpi';  px = 144 },
        @{ q = 'xxxhdpi'; px = 192 }
    )
    $adaptive = @(
        @{ q = 'mdpi';    px = 108 },
        @{ q = 'hdpi';    px = 162 },
        @{ q = 'xhdpi';   px = 216 },
        @{ q = 'xxhdpi';  px = 324 },
        @{ q = 'xxxhdpi'; px = 432 }
    )

    # Legacy launcher icons: full-bleed square, opaque (flattened onto bg color).
    foreach ($d in $legacy) {
        $dir = Join-Path $resDir ('mipmap-' + $d.q)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $file = Join-Path $dir 'ic_launcher.png'
        $sz = $d.px.ToString()
        Invoke-Magick @("$masterPath", '-resize', ($sz + 'x' + $sz),
            '-background', $bgHex, '-alpha', 'remove', '-alpha', 'off', ('PNG24:' + $file))
    }
    Write-Step "res/mipmap-*/ic_launcher.png (legacy 48..192)"

    # Adaptive foreground + monochrome: artwork scaled to the 66/108 safe zone,
    # centered on a transparent canvas of the full adaptive size.
    foreach ($d in $adaptive) {
        $dir = Join-Path $resDir ('mipmap-' + $d.q)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $canvas = [int] $d.px
        $art = [int][Math]::Round($canvas * 66.0 / 108.0)
        $canvasS = $canvas.ToString()
        $artS = $art.ToString()

        $fg = Join-Path $dir 'ic_launcher_foreground.png'
        Invoke-Magick @("$masterPath", '-resize', ($artS + 'x' + $artS),
            '-background', 'none', '-gravity', 'center',
            '-extent', ($canvasS + 'x' + $canvasS), ('PNG32:' + $fg))

        $mono = Join-Path $dir 'ic_launcher_monochrome.png'
        Invoke-Magick @("$masterPath", '-resize', ($artS + 'x' + $artS),
            '-colorspace', 'Gray', '-background', 'none', '-gravity', 'center',
            '-extent', ($canvasS + 'x' + $canvasS), ('PNG32:' + $mono))
    }
    Write-Step "res/mipmap-*/ic_launcher_foreground.png (adaptive 108..432, 66/108 safe zone)"
    Write-Step "res/mipmap-*/ic_launcher_monochrome.png (themed/monochrome, alpha)"

    # adaptive-icon XML.
    $anydpiDir = Join-Path $resDir 'mipmap-anydpi-v26'
    New-Item -ItemType Directory -Path $anydpiDir -Force | Out-Null
    $adaptiveXml = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
'@
    $adaptiveXmlPath = Join-Path $anydpiDir 'ic_launcher.xml'
    [System.IO.File]::WriteAllText($adaptiveXmlPath, $adaptiveXml, (New-Object System.Text.UTF8Encoding($false)))
    Write-Step "res/mipmap-anydpi-v26/ic_launcher.xml"

    # Background color resource.
    $valuesDir = Join-Path $resDir 'values'
    New-Item -ItemType Directory -Path $valuesDir -Force | Out-Null
    $bgXml = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$bgHex</color>
</resources>
"@
    $bgXmlPath = Join-Path $valuesDir 'ic_launcher_background.xml'
    [System.IO.File]::WriteAllText($bgXmlPath, $bgXml, (New-Object System.Text.UTF8Encoding($false)))
    Write-Step ("res/values/ic_launcher_background.xml (" + $bgHex + ")")

    # Play Store listing icon: 512x512, opaque (no transparency), full-bleed.
    $play = Join-Path $andDir 'PlayStore-512.png'
    Invoke-Magick @("$masterPath", '-resize', '512x512',
        '-background', $bgHex, '-alpha', 'remove', '-alpha', 'off', ('PNG24:' + $play))
    Write-Step "PlayStore-512.png (opaque)"

    # --- Clean up the temporary master -----------------------------------
    Remove-Item -LiteralPath $masterPath -Force -ErrorAction SilentlyContinue

    # ======================================================================
    # Summary
    # ======================================================================
    Write-Host ""
    Write-Host "Done."
    Write-Host "-----"
    Write-Host ("Source          : " + $src.FullName)
    if ($wasPadded) {
        Write-Host ("Squared         : padded from " + $w + "x" + $h + " to " + $masterMax + "x" + $masterMax + " (transparent)")
    }
    else {
        Write-Host  "Squared         : source was already square"
    }
    Write-Host ("Background color : " + $bgHex)
    Write-Host ("Output folder   : " + $outDir)
    Write-Host ""
    Write-Host "iOS     : AppIcon.appiconset (light/dark/tinted 1024) + AppStore-1024.png"
    Write-Host "Android : res/ (legacy mipmaps, adaptive foreground+monochrome, XML) + PlayStore-512.png"
    Write-Host ""
    Write-Host "Note: iOS 26 'Liquid Glass' icons are ideally authored in Apple's Icon Composer"
    Write-Host "      (macOS). This tool produces the standard flat PNG fallbacks. See README.md."

    # Open the output folder for the user (context-menu runs).
    Start-Process explorer.exe -ArgumentList ('"' + $outDir + '"')

    if (-not $NoInteractive) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host ($_.Exception.Message) -ForegroundColor Red
    if (-not $NoInteractive) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    exit 1
}
