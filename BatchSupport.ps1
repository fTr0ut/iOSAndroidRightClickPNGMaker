<#
.SYNOPSIS
    Batch helpers shared by Make-MobileIcons.ps1 and Resize-StoreScreenshot.ps1.

.DESCRIPTION
    Dot-sourced by both scripts; not meant to be run on its own.

    Resolve-SourcePng expands -Path entries (files, folders, wildcards) into the
    .png files to process.

    Merge-ExplorerSelection turns a multi-file Explorer selection into one run.
    For a command-line verb, Explorer starts a separate process for every
    selected file, each with its own window. The first of them collects the
    paths of the others, which hand theirs over and exit.

    Written for Windows PowerShell 5.1.
#>

function Resolve-SourcePng {
    # A file is taken as given, a folder contributes the .png files directly
    # inside it (except names matching $SkipPattern, e.g. earlier output), and
    # anything else is treated as a wildcard. Duplicates are dropped.
    # Returns @{ Files = FileInfo[]; Errors = string[] }.
    param(
        [string[]] $Path,
        [string] $SkipPattern
    )

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $errors = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($p in $Path) {
        if ([string]::IsNullOrWhiteSpace($p)) {
            continue
        }

        $found = @()
        if (Test-Path -LiteralPath $p -PathType Container) {
            # -Filter alone would also match e.g. ".pngx" through 8.3 short names.
            $found = @(Get-ChildItem -LiteralPath $p -File -Filter '*.png' |
                Where-Object { $_.Extension -eq '.png' } |
                Where-Object { -not $SkipPattern -or $_.Name -notmatch $SkipPattern } |
                Sort-Object Name)
            if ($found.Count -eq 0) {
                $errors.Add("No .png files to process in folder: " + $p)
            }
        }
        elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $found = @(Get-Item -LiteralPath $p)
        }
        elseif ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($p)) {
            $found = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq '.png' } |
                Sort-Object FullName)
            if ($found.Count -eq 0) {
                $errors.Add("No .png files match: " + $p)
            }
        }
        else {
            $errors.Add("Source file does not exist: " + $p)
        }

        foreach ($f in $found) {
            if ($seen.Add($f.FullName)) {
                $files.Add($f)
            }
        }
    }

    return @{ Files = $files.ToArray(); Errors = $errors.ToArray() }
}

function Enter-BatchLock {
    param([System.Threading.Mutex] $Mutex)
    try {
        if (-not $Mutex.WaitOne(15000)) {
            throw "Timed out waiting for another IconRightClick window."
        }
    }
    catch {
        # A process that died while holding the lock hands it over as
        # "abandoned"; the lock is ours either way.
        $e = $_.Exception
        while ($e -and -not ($e -is [System.Threading.AbandonedMutexException])) {
            $e = $e.InnerException
        }
        if (-not $e) {
            throw
        }
    }
}

function Read-BatchLines {
    param([string] $File)
    if (-not (Test-Path -LiteralPath $File)) {
        return @()
    }
    return @([System.IO.File]::ReadAllLines($File) | Where-Object { $_ -ne '' })
}

function Test-BatchLeader {
    # True while the process recorded in $LeaderFile ("<pid> <start ticks>") is
    # still running. The start time guards against a reused process ID.
    param([string] $LeaderFile)
    try {
        $parts = @(Read-BatchLines $LeaderFile | Select-Object -First 1 | ForEach-Object { $_ -split ' ' })
        if ($parts.Count -lt 2) {
            return $false
        }
        $proc = Get-Process -Id ([int] $parts[0]) -ErrorAction SilentlyContinue
        if (-not $proc) {
            return $false
        }
        return ($proc.StartTime.ToUniversalTime().Ticks.ToString() -eq $parts[1])
    }
    catch {
        return $false
    }
}

function Get-PendingSiblingCount {
    # Processes Explorer started for the same verb that have not handed over
    # their path yet. Explorer can take several seconds to start them all, so
    # a quiet queue alone does not mean the selection is complete.
    param(
        [string] $ScriptName,
        [string] $Mode,
        [string[]] $Arrived
    )
    try {
        $procs = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction Stop)
    }
    catch {
        return 0
    }

    $modePattern = '\s' + [regex]::Escape($Mode) + '(\s|$)'
    $count = 0
    foreach ($p in $procs) {
        if ($p.ProcessId -eq $PID -or -not $p.CommandLine) {
            continue
        }
        if ($Arrived -contains $p.ProcessId.ToString()) {
            continue
        }
        $cl = $p.CommandLine
        if ($cl.IndexOf($ScriptName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $cl -match '\s-FromExplorer(\s|$)' -and $cl -match $modePattern) {
            $count = $count + 1
        }
    }
    return $count
}

function Merge-ExplorerSelection {
    # Called by every process Explorer starts for a multi-file selection. The
    # first to arrive becomes the leader and waits until the others have
    # handed over their paths. Returns all selected paths to the leader and
    # $null to the others, which should exit.
    # $Mode is the verb's distinguishing argument (e.g. '-Preset X'), so
    # different menu entries never merge into one batch.
    param(
        [string] $Path,
        [string] $ScriptName,
        [string] $Mode
    )

    $key = ($ScriptName + ' ' + $Mode) -replace '[^A-Za-z0-9]+', '-'
    $stateDir = Join-Path ([System.IO.Path]::GetTempPath()) 'IconRightClick'
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $queueFile = Join-Path $stateDir ($key + '.queue')       # handed-over paths, one per line
    $leaderFile = Join-Path $stateDir ($key + '.leader')     # "<pid> <start ticks>" of the collector
    $arrivedFile = Join-Path $stateDir ($key + '.arrived')   # PIDs that already got this far
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $selfTicks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()

    # All state files are only touched while holding this lock: concurrent
    # appends from separate processes otherwise lose lines.
    $mutex = New-Object System.Threading.Mutex($false, ('Local\IconRightClick-' + $key))
    try {
        Enter-BatchLock $mutex
        try {
            [System.IO.File]::AppendAllText($arrivedFile, ($PID.ToString() + "`r`n"), $utf8)
            if (Test-BatchLeader $leaderFile) {
                [System.IO.File]::AppendAllText($queueFile, ($Path + "`r`n"), $utf8)
                return $null
            }
            # No live collector: this process becomes it. A queue left behind by
            # one that crashed is stale, so start empty.
            [System.IO.File]::WriteAllText($leaderFile, ($PID.ToString() + ' ' + $selfTicks), $utf8)
            if (Test-Path -LiteralPath $queueFile) {
                Remove-Item -LiteralPath $queueFile -Force
            }
        }
        finally {
            $mutex.ReleaseMutex()
        }

        # Wait until the queue has been quiet for a while and no sibling process
        # is still starting up.
        $quietMs = 1500
        $deadline = (Get-Date).AddMinutes(3)
        $queued = 0
        $lastChange = Get-Date
        Write-Host -NoNewline "  Collecting selected files: 1"
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 200

            Enter-BatchLock $mutex
            try {
                $count = @(Read-BatchLines $queueFile).Count
                $arrived = @(Read-BatchLines $arrivedFile)
            }
            finally {
                $mutex.ReleaseMutex()
            }

            if ($count -ne $queued) {
                $queued = $count
                $lastChange = Get-Date
                Write-Host -NoNewline ("`r  Collecting selected files: " + ($queued + 1))
                continue
            }
            if (((Get-Date) - $lastChange).TotalMilliseconds -lt $quietMs) {
                continue
            }
            if ((Get-PendingSiblingCount -ScriptName $ScriptName -Mode $Mode -Arrived $arrived) -gt 0) {
                $lastChange = Get-Date
                continue
            }
            break
        }
        Write-Host ""

        $paths = New-Object System.Collections.Generic.List[string]
        $paths.Add($Path)
        Enter-BatchLock $mutex
        try {
            foreach ($line in (Read-BatchLines $queueFile)) {
                $paths.Add($line)
            }
            if (Test-Path -LiteralPath $queueFile) {
                Remove-Item -LiteralPath $queueFile -Force
            }
            Remove-Item -LiteralPath $leaderFile -Force -ErrorAction SilentlyContinue

            # Keep the PIDs that are still running (this window among them), so
            # the next batch does not wait for a window that is already busy.
            $alive = @()
            $ids = @(Read-BatchLines $arrivedFile | ForEach-Object { [int] $_ } | Sort-Object -Unique)
            if ($ids.Count -gt 0) {
                $alive = @(Get-Process -Id $ids -ErrorAction SilentlyContinue | ForEach-Object { $_.Id.ToString() })
            }
            [System.IO.File]::WriteAllLines($arrivedFile, [string[]] $alive, $utf8)
        }
        finally {
            $mutex.ReleaseMutex()
        }
        # Arrival order is random; process in name order.
        return [string[]] ($paths | Sort-Object)
    }
    finally {
        $mutex.Dispose()
    }
}
