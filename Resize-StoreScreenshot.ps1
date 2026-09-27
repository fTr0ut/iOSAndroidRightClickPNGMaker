<#
.SYNOPSIS
    Resize a PNG screenshot for App Store Connect or Google Play Console.

.DESCRIPTION
    Right-click a .png in Windows Explorer and choose a preset under
    "Resize Store Screenshot". The source orientation is retained, the image is
    fitted without stretching, and white padding is added when its aspect ratio
    differs from the required canvas. Output is always an opaque 24-bit PNG.

    Requires ImageMagick ("magick"). Written for Windows PowerShell 5.1.

.PARAMETER Path
    Path to the source .png screenshot.

.PARAMETER Preset
    Store and portrait-size preset. Landscape dimensions are selected
    automatically when the source image is landscape.

.PARAMETER NoInteractive
    Suppress Explorer and the end-of-run prompt (used for automation/testing).

.EXAMPLE
    .\Resize-StoreScreenshot.ps1 -Path "C:\art\screen.png" -Preset Apple-iPhone-1284x2778
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Path,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateSet(
        'Apple-iPhone-1242x2688',
        'Apple-iPhone-1284x2778',
        'Apple-iPad-2064x2752',
        'Apple-iPad-2048x2732',
        'GooglePlay-1080x1920'
    )]
    [string] $Preset,

    [switch] $NoInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Host ("  " + $Message)
}

function Resolve-Magick {
    $cmd = Get-Command magick -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = Get-ChildItem -Path 'C:\Program Files\ImageMagick*\magick.exe' -ErrorAction SilentlyContinue
    if ($candidates) {
        return ($candidates | Select-Object -First 1).FullName
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

function Get-AvailableOutputPath {
    param(
        [string] $Directory,
        [string] $BaseName,
        [string] $Suffix
    )

    $candidate = Join-Path $Directory ($BaseName + '-' + $Suffix + '.png')
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $n = 2
    while ($true) {
        $candidate = Join-Path $Directory ($BaseName + '-' + $Suffix + '-' + $n + '.png')
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
        $n = $n + 1
    }
}

try {
    Write-Host ""
    Write-Host "Resize Store Screenshot"
    Write-Host "======================="

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

    $script:Magick = Resolve-Magick
    Write-Step ("Using ImageMagick: " + $script:Magick)

    $ident = & $script:Magick identify -format "%m %w %h\n" -- "$($src.FullName)"
    if ($LASTEXITCODE -ne 0) {
        throw ("ImageMagick could not read the image: " + $src.FullName)
    }
    if ($ident -is [array]) {
        $ident = $ident[0]
    }

    $parts = ($ident -split '\s+') | Where-Object { $_ -ne '' }
    if ($parts.Count -lt 3 -or $parts[0] -notmatch 'PNG') {
        throw ("File does not appear to be a real PNG: " + $src.FullName)
    }

    [int] $sourceWidth = $parts[1]
    [int] $sourceHeight = $parts[2]
    Write-Step ("Source: " + $src.Name + " (" + $sourceWidth + "x" + $sourceHeight + ")")

    $presetInfo = switch ($Preset) {
        'Apple-iPhone-1242x2688' {
            @{ Label = 'AppStore-iPhone'; Short = 1242; Long = 2688 }
        }
        'Apple-iPhone-1284x2778' {
            @{ Label = 'AppStore-iPhone'; Short = 1284; Long = 2778 }
        }
        'Apple-iPad-2064x2752' {
            @{ Label = 'AppStore-iPad'; Short = 2064; Long = 2752 }
        }
        'Apple-iPad-2048x2732' {
            @{ Label = 'AppStore-iPad'; Short = 2048; Long = 2732 }
        }
        'GooglePlay-1080x1920' {
            @{ Label = 'GooglePlay'; Short = 1080; Long = 1920 }
        }
        default {
            throw ("Unknown preset: " + $Preset)
        }
    }

    $orientation = 'portrait'
    [int] $targetWidth = $presetInfo.Short
    [int] $targetHeight = $presetInfo.Long
    if ($sourceWidth -gt $sourceHeight) {
        $orientation = 'landscape'
        $targetWidth = $presetInfo.Long
        $targetHeight = $presetInfo.Short
    }

    $geometry = $targetWidth.ToString() + 'x' + $targetHeight.ToString()
    $suffix = $presetInfo.Label + '-' + $geometry
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src.Name)
    $outputPath = Get-AvailableOutputPath -Directory $src.DirectoryName -BaseName $baseName -Suffix $suffix

    Write-Step ("Preset: " + $Preset)
    Write-Step ("Orientation: " + $orientation + " -> " + $geometry)

    # Fit inside the exact canvas instead of stretching. White padding is used
    # only when the source and target aspect ratios differ.
    Invoke-Magick @(
        "$($src.FullName)",
        '-auto-orient',
        '-resize', $geometry,
        '-background', 'white',
        '-gravity', 'center',
        '-extent', $geometry,
        '-alpha', 'remove',
        '-alpha', 'off',
        '-colorspace', 'sRGB',
        '-strip',
        ('PNG24:' + $outputPath)
    )

    $outputSize = & $script:Magick identify -format "%w %h" -- "$outputPath"
    if ($LASTEXITCODE -ne 0 -or $outputSize -ne ($targetWidth.ToString() + ' ' + $targetHeight.ToString())) {
        throw ("Generated file did not have the expected dimensions " + $geometry + ": " + $outputPath)
    }

    $wasPadded = ([long] $sourceWidth * [long] $targetHeight) -ne ([long] $sourceHeight * [long] $targetWidth)

    Write-Host ""
    Write-Host "Done."
    Write-Host "-----"
    Write-Host ("Output : " + $outputPath)
    Write-Host ("Size   : " + $geometry + " (opaque 24-bit PNG)")
    if ($wasPadded) {
        Write-Host "Fit    : aspect ratio preserved; white padding added"
    }
    else {
        Write-Host "Fit    : aspect ratio preserved; no padding needed"
    }

    if (-not $NoInteractive) {
        Start-Process explorer.exe -ArgumentList ('/select,"' + $outputPath + '"')
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
