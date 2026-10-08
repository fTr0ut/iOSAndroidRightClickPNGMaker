<#
.SYNOPSIS
    Generate Android- and iOS-compliant app icon sets from a single source PNG.

.DESCRIPTION
    Select one or more .png files in Windows Explorer, right-click ->
    "Generate Mobile App Icons" and pick "Android + iOS", "Android only" or
    "iOS only". Each source gets its own output folder.
    Produces an iOS AppIcon.appiconset (light / dark / tinted, 1024) and/or an
    Android res/ tree (legacy + round mipmaps, adaptive foreground + monochrome
    layers, adaptive-icon XML, background color, Play Store 512).

    Requires ImageMagick ("magick"). Written for Windows PowerShell 5.1.

.PARAMETER Path
    One or more sources: .png files, folders (every .png directly inside) or
    wildcards.

.PARAMETER Platform
    Which icon set to generate: All (default), Android or iOS.

.PARAMETER NoInteractive
    Suppress Explorer and the end-of-run "Press Enter to close" prompt (used for
    automation/testing).

.PARAMETER FromExplorer
    Set by the context menu. Explorer starts one process per selected file;
    this merges them into a single run in one window.

.EXAMPLE
    .\Make-MobileIcons.ps1 -Path "C:\art\logo.png"

.EXAMPLE
    .\Make-MobileIcons.ps1 -Path "C:\art\logo.png", "C:\art\logo-beta.png" -Platform Android
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $Path,

    [ValidateSet('All', 'Android', 'iOS')]
    [string] $Platform = 'All',

    [switch] $NoInteractive,

    [switch] $FromExplorer
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'BatchSupport.ps1')

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

function Get-MagickOutput {
    param([string[]] $MagickArgs)
    $out = & $script:Magick @MagickArgs
    if ($LASTEXITCODE -ne 0) {
        throw ("ImageMagick failed (exit " + $LASTEXITCODE + ") for: magick " + ($MagickArgs -join ' '))
    }
    return (($out | Out-String).Trim())
}

function ConvertTo-Double {
    param([string] $Text)
    return [double]::Parse($Text, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-MeanColorHex {
    # Alpha-weighted average color of an image, as #RRGGBB.
    param([string] $ImagePath)
    $rgb = Get-MagickOutput @("$ImagePath", '-resize', '1x1!', '-alpha', 'off',
        '-format', '%[fx:int(255*r+0.5)],%[fx:int(255*g+0.5)],%[fx:int(255*b+0.5)]', 'info:')
    if ($rgb -notmatch '^\d+,\d+,\d+$') {
        return '#FFFFFF'
    }
    $c = $rgb -split ','
    return ('#{0:X2}{1:X2}{2:X2}' -f [int]$c[0], [int]$c[1], [int]$c[2])
}

function Measure-ContentRadius {
    # How far the visible content reaches from the image center, in multiples of
    # the image's half-width: 1.0 touches the middle of each edge, 1.414 reaches
    # the corners. $MaskArgs must produce a white-on-black content mask.
    param([string[]] $MaskArgs, [int] $Size)
    $fx = 'p>0.5 ? hypot(i+0.5-w/2,j+0.5-h/2)/hypot(w/2,h/2) : 0'
    $text = Get-MagickOutput ($MaskArgs + @('-fx', $fx, '-format', '%[fx:maxima]', 'info:'))
    $halfDiagonals = ConvertTo-Double $text
    if ($halfDiagonals -le 0) {
        # Nothing stands out: treat the whole square as content.
        return [Math]::Sqrt(2.0)
    }
    # Convert to half-width units and add one analysis pixel of margin.
    return ($halfDiagonals * [Math]::Sqrt(2.0) + 2.0 / $Size)
}

function Measure-Artwork {
    # Works out where the artwork's visible content sits and what background the
    # Android adaptive icon should use behind it.
    #   Transparent source      : content = non-transparent pixels, background =
    #                             average color.
    #   Opaque, flat border     : background = the border color, content = pixels
    #                             that differ from it (e.g. a logo on a plain tile).
    #   Opaque, varied border   : the whole square is content (gradients, photos),
    #                             background = average border color.
    param([string] $MasterPath, [string] $WorkDir)

    $n = 512
    $band = 5         # outer ~1% is ignored: stray export slivers live there
    $ringDepth = 13   # border sample runs from ~1% to ~3.5% in from each edge
    $sizeArg = $n.ToString() + 'x' + $n.ToString() + '!'
    $an = Join-Path $WorkDir 'analysis.png'
    Invoke-Magick @("$MasterPath", '-resize', $sizeArg, ('PNG32:' + $an))

    $isOpaque = (Get-MagickOutput @("$an", '-format', '%[opaque]', 'info:')) -eq 'True'
    if (-not $isOpaque) {
        $radius = Measure-ContentRadius -Size $n -MaskArgs @("$an", '-alpha', 'extract', '-threshold', '10%')
        return @{ Kind = 'transparent'; Background = (Get-MeanColorHex $MasterPath); Radius = $radius }
    }

    # Sample a ring just inside the edges.
    $far = $n - $band - $ringDepth
    $ring = Join-Path $WorkDir 'ring.png'
    Invoke-Magick @("$an", '-alpha', 'off',
        '(', '-clone', '0', '-crop', ('{0}x{1}+0+{2}' -f $n, $ringDepth, $band), '+repage', ')',
        '(', '-clone', '0', '-crop', ('{0}x{1}+0+{2}' -f $n, $ringDepth, $far), '+repage', ')',
        '(', '-clone', '0', '-crop', ('{0}x{1}+{2}+0' -f $ringDepth, $n, $band), '+repage', '-rotate', '90', ')',
        '(', '-clone', '0', '-crop', ('{0}x{1}+{2}+0' -f $ringDepth, $n, $far), '+repage', '-rotate', '90', ')',
        '-delete', '0', '-append', ('PNG24:' + $ring))

    # Dominant border color, and how much of the ring does not match it.
    $hist = Get-MagickOutput @("$ring", '+dither', '-colors', '8', '-depth', '8', '-format', '%c', 'histogram:info:')
    $dominant = $null
    $best = [int64]0
    foreach ($line in ($hist -split "`n")) {
        if ($line -match '^\s*(\d+):.*?(#[0-9A-Fa-f]{6})') {
            if ([int64]$matches[1] -gt $best) {
                $best = [int64]$matches[1]
                $dominant = $matches[2].ToUpperInvariant()
            }
        }
    }
    $mismatch = 1.0
    if ($dominant) {
        $mismatch = ConvertTo-Double (Get-MagickOutput @("$ring",
            '(', '+clone', '-fill', $dominant, '-colorize', '100', ')',
            '-compose', 'difference', '-composite', '-alpha', 'off',
            '-separate', '-evaluate-sequence', 'max', '-threshold', '8%',
            '-format', '%[fx:mean]', 'info:'))
    }

    if ($mismatch -gt 0.25) {
        return @{ Kind = 'opaque, varied border'; Background = (Get-MeanColorHex $ring); Radius = [Math]::Sqrt(2.0) }
    }

    $radius = Measure-ContentRadius -Size $n -MaskArgs @("$an", '-alpha', 'off',
        '(', '+clone', '-fill', $dominant, '-colorize', '100', ')',
        '-compose', 'difference', '-composite', '-compose', 'over', '-alpha', 'off',
        '-separate', '-evaluate-sequence', 'max', '-threshold', '10%',
        '-shave', ($band.ToString() + 'x' + $band.ToString()),
        '-bordercolor', 'black', '-border', ($band.ToString() + 'x' + $band.ToString()))
    return @{ Kind = 'opaque, flat border'; Background = $dominant; Radius = $radius }
}

# --------------------------------------------------------------------------
# One source -> one icon set
# --------------------------------------------------------------------------

function New-MobileIconSet {
    # Generates the icon set(s) for one source PNG into a new sibling folder
    # and returns that folder. Uses $doIos / $doAndroid from the main block.
    param([System.IO.FileInfo] $Source)

    # --- Validate input ---------------------------------------------------
    $src = $Source
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
    if ($Platform -ne 'All') {
        $outName = $outName + "-" + $Platform.ToLowerInvariant()
    }
    $outDir = Join-Path $parentDir $outName
    if (Test-Path -LiteralPath $outDir) {
        $n = 2
        while ($true) {
            $candidate = Join-Path $parentDir ($outName + "-" + $n)
            if (-not (Test-Path -LiteralPath $candidate)) {
                $outDir = $candidate
                break
            }
            $n = $n + 1
        }
    }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Write-Step ("Output folder: " + $outDir)

    # Scratch files live here and are deleted at the end (by the caller if
    # this throws).
    $workDir = Join-Path $outDir '_work'
    $script:WorkDir = $workDir
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    # --- Build a square, alpha-preserved master ---------------------------
    $wasPadded = $false
    $masterMax = [Math]::Max($w, $h)
    $masterPath = Join-Path $workDir "master_square.png"
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

    # ======================================================================
    # iOS
    # ======================================================================
    if ($doIos) {
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
    }

    # ======================================================================
    # Android
    # ======================================================================
    if ($doAndroid) {
        Write-Host ""
        Write-Host "Android ..."
        $andDir = Join-Path $outDir 'Android'
        $resDir = Join-Path $andDir 'res'

        # Adaptive icon geometry (dp). Both layers are 108x108. Launchers mask the
        # inner 72x72 with an OEM shape (circle, squircle, rounded square, ...), and
        # only the centered 66dp safe zone survives every mask plus the parallax /
        # pulse effects. A circle is the tightest mask, so the artwork is scaled until
        # its farthest visible pixel sits on the 66dp safe-zone circle. Scaling the
        # whole square to 66dp instead lets the mask cut into full-bleed artwork.
        $layerDp = 108.0
        $safeDp = 66.0
        $viewportDp = 72.0

        $art = Measure-Artwork -MasterPath $masterPath -WorkDir $workDir
        $bgHex = $art.Background
        $radius = [Math]::Max(0.3, $art.Radius)
        $artDp = $safeDp / $radius
        $artFraction = $artDp / $layerDp
        Write-Step ("Artwork: " + $art.Kind + "; content reaches " + $radius.ToString('0.00') +
            "x its half-width -> drawn at " + $artDp.ToString('0.0') + "dp of the 108dp layer")
        Write-Step ("Background color: " + $bgHex)

        # Prepare the artwork for placement on the adaptive canvas.
        $prep = Join-Path $workDir 'android_art.png'
        $masterSize = $masterMax
        if ($art.Kind -eq 'opaque, flat border') {
            # Paint the outer 1% with the border color so stray slivers along the
            # edges never show; the square's edges then vanish into the background.
            $b = [int][Math]::Ceiling($masterSize * 0.01)
            $bS = $b.ToString() + 'x' + $b.ToString()
            Invoke-Magick @("$masterPath", '-alpha', 'off', '-shave', $bS,
                '-bordercolor', $bgHex, '-border', $bS, ('PNG32:' + $prep))
        }
        elseif ($art.Kind -eq 'opaque, varied border') {
            # Feather the edges so the square blends into the background color.
            $inset = [int][Math]::Round($masterSize * 0.02)
            $sigma = [Math]::Max(0.5, $masterSize * 0.0075)
            $far = $masterSize - 1 - $inset
            Invoke-Magick @("$masterPath",
                '(', '-size', ($masterSize.ToString() + 'x' + $masterSize.ToString()), 'xc:black', '-fill', 'white',
                '-draw', ('rectangle {0},{0} {1},{1}' -f $inset, $far),
                '-blur', ('0x' + $sigma.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)), ')',
                '-alpha', 'off', '-compose', 'CopyOpacity', '-composite', ('PNG32:' + $prep))
        }
        else {
            Copy-Item -LiteralPath $masterPath -Destination $prep -Force
        }

        # Monochrome (themed icon) source. The system keeps only the alpha channel
        # and tints it, so an opaque square would render as a solid blob. For art on
        # a flat tile, keep only what stands out from the tile.
        $monoSrc = Join-Path $workDir 'android_mono.png'
        if ($art.Kind -eq 'opaque, flat border') {
            $monoAlpha = Join-Path $workDir 'android_mono_alpha.png'
            Invoke-Magick @("$prep", '-alpha', 'off',
                '(', '+clone', '-fill', $bgHex, '-colorize', '100', ')',
                '-compose', 'difference', '-composite', '-alpha', 'off',
                '-separate', '-evaluate-sequence', 'max', '-level', '10%,25%', ('PNG24:' + $monoAlpha))
            Invoke-Magick @("$prep", '-colorspace', 'Gray', "$monoAlpha",
                '-alpha', 'off', '-compose', 'CopyOpacity', '-composite', ('PNG32:' + $monoSrc))
        }
        else {
            Invoke-Magick @("$prep", '-colorspace', 'Gray', ('PNG32:' + $monoSrc))
        }

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

        # Adaptive foreground + monochrome layers.
        foreach ($d in $adaptive) {
            $dir = Join-Path $resDir ('mipmap-' + $d.q)
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $canvas = [int] $d.px
            $artPx = [int][Math]::Round($canvas * $artFraction)
            $canvasS = $canvas.ToString() + 'x' + $canvas.ToString()
            $artS = $artPx.ToString() + 'x' + $artPx.ToString()

            $fg = Join-Path $dir 'ic_launcher_foreground.png'
            Invoke-Magick @("$prep", '-resize', $artS,
                '-background', 'none', '-gravity', 'center', '-extent', $canvasS, ('PNG32:' + $fg))

            $mono = Join-Path $dir 'ic_launcher_monochrome.png'
            Invoke-Magick @("$monoSrc", '-resize', $artS,
                '-background', 'none', '-gravity', 'center', '-extent', $canvasS, ('PNG32:' + $mono))
        }
        Write-Step "res/mipmap-*/ic_launcher_foreground.png (adaptive 108..432, fitted to the 66dp safe zone)"
        Write-Step "res/mipmap-*/ic_launcher_monochrome.png (themed/monochrome, alpha)"

        # What a launcher shows: background + foreground, cropped to the 72dp
        # viewport. Legacy and Play Store icons are rendered from this so every
        # surface frames the artwork the same way.
        $vpLayerPx = 1536
        $vpPx = [int][Math]::Round($vpLayerPx * $viewportDp / $layerDp)
        $vpArtPx = [int][Math]::Round($vpLayerPx * $artFraction)
        $viewport = Join-Path $workDir 'android_viewport.png'
        Invoke-Magick @('-size', ($vpLayerPx.ToString() + 'x' + $vpLayerPx.ToString()), ('xc:' + $bgHex),
            '(', "$prep", '-resize', ($vpArtPx.ToString() + 'x' + $vpArtPx.ToString()), ')',
            '-gravity', 'center', '-compose', 'over', '-composite',
            '-crop', ($vpPx.ToString() + 'x' + $vpPx.ToString() + '+0+0'), '+repage',
            '-alpha', 'off', ('PNG24:' + $viewport))

        $vpC = (($vpPx - 1) / 2.0).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
        $viewportRound = Join-Path $workDir 'android_viewport_round.png'
        Invoke-Magick @("$viewport",
            '(', '-size', ($vpPx.ToString() + 'x' + $vpPx.ToString()), 'xc:black', '-fill', 'white',
            '-draw', ('circle {0},{0} {0},-0.5' -f $vpC), ')',
            '-alpha', 'off', '-compose', 'CopyOpacity', '-composite', ('PNG32:' + $viewportRound))

        # Legacy launcher icons (pre-Android 8): square opaque + round.
        foreach ($d in $legacy) {
            $dir = Join-Path $resDir ('mipmap-' + $d.q)
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $sz = $d.px.ToString() + 'x' + $d.px.ToString()
            Invoke-Magick @("$viewport", '-resize', $sz, ('PNG24:' + (Join-Path $dir 'ic_launcher.png')))
            Invoke-Magick @("$viewportRound", '-resize', $sz, ('PNG32:' + (Join-Path $dir 'ic_launcher_round.png')))
        }
        Write-Step "res/mipmap-*/ic_launcher.png + ic_launcher_round.png (legacy 48..192)"

        # adaptive-icon XML, for both android:icon and android:roundIcon.
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
        foreach ($xmlName in @('ic_launcher.xml', 'ic_launcher_round.xml')) {
            [System.IO.File]::WriteAllText((Join-Path $anydpiDir $xmlName), $adaptiveXml, (New-Object System.Text.UTF8Encoding($false)))
        }
        Write-Step "res/mipmap-anydpi-v26/ic_launcher.xml + ic_launcher_round.xml"

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

        # Play Store listing icon: 512x512, opaque, full square. Play rounds the
        # corners itself (30% radius), so the launcher framing keeps the art clear.
        $play = Join-Path $andDir 'PlayStore-512.png'
        Invoke-Magick @("$viewport", '-resize', '512x512', ('PNG24:' + $play))
        Write-Step "PlayStore-512.png (opaque)"
    }

    # --- Clean up scratch files -------------------------------------------
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    $script:WorkDir = $null

    # --- Per-source summary -----------------------------------------------
    Write-Host ""
    if ($wasPadded) {
        Write-Host ("Squared          : padded from " + $w + "x" + $h + " to " + $masterMax + "x" + $masterMax + " (transparent)")
    }
    else {
        Write-Host  "Squared          : source was already square"
    }
    if ($doAndroid) {
        Write-Host ("Background color : " + $bgHex)
    }
    Write-Host ("Output folder    : " + $outDir)

    return $outDir
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

$script:WorkDir = $null
try {
    $doIos = ($Platform -eq 'All' -or $Platform -eq 'iOS')
    $doAndroid = ($Platform -eq 'All' -or $Platform -eq 'Android')

    Write-Host ""
    Write-Host "Generate Mobile App Icons"
    Write-Host "========================="

    if ($FromExplorer) {
        $selection = Merge-ExplorerSelection -Path $Path[0] -ScriptName 'Make-MobileIcons.ps1' -Mode ('-Platform ' + $Platform)
        if ($null -eq $selection) {
            Write-Step "Added to the batch that another window is collecting."
            exit 0
        }
        $Path = $selection
    }

    $script:Magick = Resolve-Magick
    Write-Step ("Using ImageMagick: " + $script:Magick)
    Write-Step ("Platform: " + $Platform)

    $sources = Resolve-SourcePng -Path $Path
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($err in $sources.Errors) {
        $failures.Add($err)
        Write-Host ("  Skipped: " + $err) -ForegroundColor Yellow
    }
    $total = $sources.Files.Count
    if ($total -eq 0) {
        throw ("Nothing to generate. " + ($failures -join ' '))
    }

    $outDirs = New-Object System.Collections.Generic.List[string]
    $i = 0
    foreach ($src in $sources.Files) {
        $i = $i + 1
        Write-Host ""
        Write-Host ("[" + $i + "/" + $total + "] " + $src.FullName)
        try {
            $outDirs.Add((New-MobileIconSet -Source $src))
        }
        catch {
            if ($script:WorkDir) {
                Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
                $script:WorkDir = $null
            }
            $failures.Add($src.Name + ": " + $_.Exception.Message)
            Write-Host ("  FAILED: " + $_.Exception.Message) -ForegroundColor Red
        }
    }

    # ======================================================================
    # Summary
    # ======================================================================
    Write-Host ""
    Write-Host "Done."
    Write-Host "-----"
    if ($total -gt 1) {
        Write-Host ("Icon sets : " + $outDirs.Count + " of " + $total + " generated, each in a folder beside its source")
    }
    if ($doIos) {
        Write-Host "iOS       : AppIcon.appiconset (light/dark/tinted 1024) + AppStore-1024.png"
    }
    if ($doAndroid) {
        Write-Host "Android   : res/ (legacy + round mipmaps, adaptive foreground+monochrome, XML) + PlayStore-512.png"
    }
    if ($failures.Count -gt 0) {
        Write-Host ("Failed    : " + $failures.Count) -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host ("  " + $f) -ForegroundColor Red
        }
    }
    if ($doIos) {
        Write-Host ""
        Write-Host "Note: iOS 26 'Liquid Glass' icons are ideally authored in Apple's Icon Composer"
        Write-Host "      (macOS). This tool produces the standard flat PNG fallbacks. See README.md."
    }

    if (-not $NoInteractive) {
        # Show the output (context-menu runs): the folder itself for one
        # source, or the parent folder with the first set selected for several.
        if ($outDirs.Count -eq 1) {
            Start-Process explorer.exe -ArgumentList ('"' + $outDirs[0] + '"')
        }
        elseif ($outDirs.Count -gt 1) {
            Start-Process explorer.exe -ArgumentList ('/select,"' + $outDirs[0] + '"')
        }
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    if ($failures.Count -gt 0) {
        exit 1
    }
}
catch {
    if ($script:WorkDir) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host ($_.Exception.Message) -ForegroundColor Red
    if (-not $NoInteractive) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    exit 1
}
