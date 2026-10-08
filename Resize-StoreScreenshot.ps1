<#
.SYNOPSIS
    Resize PNG screenshots for App Store Connect or Google Play Console.

.DESCRIPTION
    Select one or more .png files in Windows Explorer, right-click and choose a
    preset under "Resize Store Screenshot". Each source keeps its orientation,
    is fitted without stretching, and gets white padding when its aspect ratio
    differs from the required canvas. Output is always an opaque 24-bit PNG,
    written beside its source.

    Requires ImageMagick ("magick"). Written for Windows PowerShell 5.1.

.PARAMETER Path
    One or more sources: .png files, folders (every .png directly inside,
    except earlier output of this script) or wildcards.

.PARAMETER Preset
    One or more store presets, named by their portrait size. Landscape
    dimensions are selected automatically when a source is landscape.

.PARAMETER NoInteractive
    Suppress Explorer and the end-of-run prompt (used for automation/testing).

.PARAMETER FromExplorer
    Set by the context menu. Explorer starts one process per selected file;
    this merges them into a single run in one window.

.EXAMPLE
    .\Resize-StoreScreenshot.ps1 -Path "C:\art\screen.png" -Preset Apple-iPhone-1320x2868

.EXAMPLE
    .\Resize-StoreScreenshot.ps1 -Path "C:\art\shots" -Preset Apple-iPad-2064x2752, GooglePlay-Tablet-1440x2560
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $Path,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateSet(
        'Apple-iPhone-1320x2868',
        'Apple-iPhone-1206x2622',
        'Apple-iPhone-1284x2778',
        'Apple-iPhone-1242x2688',
        'Apple-iPad-2064x2752',
        'Apple-iPad-2048x2732',
        'GooglePlay-1080x1920',
        'GooglePlay-Tablet-1440x2560'
    )]
    [string[]] $Preset,

    [switch] $NoInteractive,

    [switch] $FromExplorer
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'BatchSupport.ps1')

# Portrait canvas for each preset. Label becomes part of the output name.
$PresetSizes = @{
    'Apple-iPhone-1320x2868'      = @{ Label = 'AppStore-iPhone';   Short = 1320; Long = 2868 }
    'Apple-iPhone-1206x2622'      = @{ Label = 'AppStore-iPhone';   Short = 1206; Long = 2622 }
    'Apple-iPhone-1284x2778'      = @{ Label = 'AppStore-iPhone';   Short = 1284; Long = 2778 }
    'Apple-iPhone-1242x2688'      = @{ Label = 'AppStore-iPhone';   Short = 1242; Long = 2688 }
    'Apple-iPad-2064x2752'        = @{ Label = 'AppStore-iPad';     Short = 2064; Long = 2752 }
    'Apple-iPad-2048x2732'        = @{ Label = 'AppStore-iPad';     Short = 2048; Long = 2732 }
    'GooglePlay-1080x1920'        = @{ Label = 'GooglePlay';        Short = 1080; Long = 1920 }
    'GooglePlay-Tablet-1440x2560' = @{ Label = 'GooglePlay-Tablet'; Short = 1440; Long = 2560 }
}

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

function Get-PngSize {
    # Confirms the file is a real PNG and returns its dimensions.
    param([System.IO.FileInfo] $Source)

    if ($Source.Extension.ToLowerInvariant() -ne '.png') {
        throw ("Source must be a .png file. Got: " + $Source.Extension)
    }

    $ident = & $script:Magick identify -format "%m %w %h\n" -- "$($Source.FullName)"
    if ($LASTEXITCODE -ne 0) {
        throw ("ImageMagick could not read the image: " + $Source.FullName)
    }
    if ($ident -is [array]) {
        $ident = $ident[0]
    }

    $parts = @(($ident -split '\s+') | Where-Object { $_ -ne '' })
    if ($parts.Count -lt 3 -or $parts[0] -notmatch 'PNG') {
        throw ("File does not appear to be a real PNG: " + $Source.FullName)
    }

    return @{ Width = [int] $parts[1]; Height = [int] $parts[2] }
}

function Convert-Screenshot {
    # Fits one source onto one preset's canvas, beside the source.
    param(
        [System.IO.FileInfo] $Source,
        [int] $SourceWidth,
        [int] $SourceHeight,
        [string] $PresetName
    )

    $presetInfo = $PresetSizes[$PresetName]
    $orientation = 'portrait'
    [int] $targetWidth = $presetInfo.Short
    [int] $targetHeight = $presetInfo.Long
    if ($SourceWidth -gt $SourceHeight) {
        $orientation = 'landscape'
        $targetWidth = $presetInfo.Long
        $targetHeight = $presetInfo.Short
    }

    $geometry = $targetWidth.ToString() + 'x' + $targetHeight.ToString()
    $suffix = $presetInfo.Label + '-' + $geometry
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Source.Name)
    $outputPath = Get-AvailableOutputPath -Directory $Source.DirectoryName -BaseName $baseName -Suffix $suffix

    # Fit inside the exact canvas instead of stretching. White padding is used
    # only when the source and target aspect ratios differ.
    Invoke-Magick @(
        "$($Source.FullName)",
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

    return @{
        Output      = $outputPath
        Geometry    = $geometry
        Orientation = $orientation
        Padded      = ([long] $SourceWidth * [long] $targetHeight) -ne ([long] $SourceHeight * [long] $targetWidth)
    }
}

try {
    Write-Host ""
    Write-Host "Resize Store Screenshot"
    Write-Host "======================="

    if ($FromExplorer) {
        $selection = Merge-ExplorerSelection -Path $Path[0] -ScriptName 'Resize-StoreScreenshot.ps1' -Mode ('-Preset ' + $Preset[0])
        if ($null -eq $selection) {
            Write-Step "Added to the batch that another window is collecting."
            exit 0
        }
        $Path = $selection
    }

    $script:Magick = Resolve-Magick
    Write-Step ("Using ImageMagick: " + $script:Magick)

    # A folder given as a source skips files this script wrote earlier.
    $labels = @($PresetSizes.Values | ForEach-Object { [regex]::Escape($_.Label) } | Sort-Object -Unique) -join '|'
    $sources = Resolve-SourcePng -Path $Path -SkipPattern ('-(' + $labels + ')-\d+x\d+(-\d+)?\.png$')

    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($err in $sources.Errors) {
        $failures.Add($err)
    }
    $total = $sources.Files.Count
    if ($total -eq 0) {
        throw ("Nothing to resize. " + ($failures -join ' '))
    }

    Write-Step ("Preset: " + ($Preset -join ', ') + " (orientation follows each source)")
    Write-Step ("Sources: " + $total + " PNG file(s)")
    foreach ($err in $sources.Errors) {
        Write-Host ("  Skipped: " + $err) -ForegroundColor Yellow
    }
    Write-Host ""

    $written = New-Object System.Collections.Generic.List[string]
    $i = 0
    foreach ($src in $sources.Files) {
        $i = $i + 1
        Write-Host ("  [" + $i + "/" + $total + "] " + $src.FullName)
        try {
            $size = Get-PngSize -Source $src
            foreach ($p in $Preset) {
                $result = Convert-Screenshot -Source $src -SourceWidth $size.Width -SourceHeight $size.Height -PresetName $p
                $written.Add($result.Output)
                $fit = 'no padding needed'
                if ($result.Padded) {
                    $fit = 'white padding added'
                }
                Write-Step ("    " + $size.Width + "x" + $size.Height + " " + $result.Orientation + " -> " +
                    [System.IO.Path]::GetFileName($result.Output) + " (" + $fit + ")")
            }
        }
        catch {
            $failures.Add($src.Name + ": " + $_.Exception.Message)
            Write-Host ("      FAILED: " + $_.Exception.Message) -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Done."
    Write-Host "-----"
    if ($written.Count -eq 1) {
        Write-Host ("Output : " + $written[0])
    }
    else {
        Write-Host ("Output : " + $written.Count + " screenshots, each beside its source")
    }
    Write-Host "Format : opaque 24-bit PNG; aspect ratio preserved"
    if ($failures.Count -gt 0) {
        Write-Host ("Failed : " + $failures.Count) -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host ("  " + $f) -ForegroundColor Red
        }
    }

    if (-not $NoInteractive) {
        if ($written.Count -gt 0) {
            Start-Process explorer.exe -ArgumentList ('/select,"' + $written[0] + '"')
        }
        Write-Host ""
        Read-Host "Press Enter to close"
    }
    if ($failures.Count -gt 0) {
        exit 1
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
