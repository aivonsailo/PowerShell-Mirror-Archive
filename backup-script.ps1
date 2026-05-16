<#
.SYNOPSIS
    Robocopy-based backup script driven by a JSON configuration file.
.DESCRIPTION
    1. Loads settings from a JSON configuration file.
    2. Reads source/destination pairs from a CSV file.
    3. If archiving is enabled, moves modified/deleted destination files to a timestamped archive.
    4. Performs a 'robocopy /MIR' to synchronize directories.
    5. Cleans up old archives (if archiving is enabled) and sends a Windows notification.
#>

Param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

# --- FUNCTIONS ---

function Log {
    param([string]$message, [string]$type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$type] $message"
    
    # Console output with colors based on log level
    $color = switch($type) { "ERROR" {"Red"} "WARNING" {"Yellow"} Default {"White"} }
    Write-Host $line -ForegroundColor $color
    
    # Write to log file if the log path is initialized
    if ($global:LogPath) {
        $line | Add-Content -Path $global:LogPath
    }
}

function Show-Notification {
    param([string]$title, [string]$message)
    try {
        # Native Windows Forms balloon notification (no external modules required)
        Add-Type -AssemblyName System.Windows.Forms
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $path = (Get-Process -id $pid).Path
        $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.BalloonTipText = $message
        $balloon.BalloonTipTitle = $title
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(5000)
    } catch {
        Log "Could not display Windows notification: $($_.Exception.Message)" "WARNING"
    }
}

function Resolve-ScriptPath {
    param([string]$Path)
    # If the path is already absolute, return it; otherwise, resolve it relative to the script root
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

# --- CONFIGURATION LOADING ---

if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Configuration file not found at: $ConfigPath" -ForegroundColor Red
    exit
}

try {
    # Parse JSON configuration file
    $jsonConfig = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    
    # Resolve absolute paths safely
    $FoldersCsvPath  = Resolve-ScriptPath $jsonConfig.FoldersCsvPath
    $global:LogPath  = Resolve-ScriptPath $jsonConfig.LogPath
    $ArchiveDir      = Resolve-ScriptPath $jsonConfig.ArchiveDir
    $DaysToKeep      = [int]$jsonConfig.DaysToKeep
    $EnableArchiving = [bool]$jsonConfig.EnableArchiving
} catch {
    Write-Host "[ERROR] Failed to parse configuration file: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# --- INITIALIZATION ---

# Ensure log directory exists
$logDir = Split-Path $global:LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Ensure archive directory exists ONLY if archiving feature is enabled
if ($EnableArchiving -and -not (Test-Path $ArchiveDir)) { 
    New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null 
}

$totalArchivedCount = 0
$failedFolders = @()
$globalSuccess = $true

# --- MAIN PROCESS ---

Log "=== Backup Process Started ==="
Log "Archiving feature status: $(if ($EnableArchiving) { 'ENABLED' } else { 'DISABLED' })"

if (-not (Test-Path $FoldersCsvPath)) {
    Log "Folders CSV file not found at $FoldersCsvPath" "ERROR"
    exit
}

$directories = Import-Csv -Path $FoldersCsvPath

foreach ($pair in $directories) {
    # Guard against empty rows in the CSV
    if ([string]::IsNullOrWhiteSpace($pair.Source) -or [string]::IsNullOrWhiteSpace($pair.Destination)) { continue }
    
    $src  = $pair.Source.Trim()
    $dest = $pair.Destination.Trim()

    # Prevent TrimEnd from breaking drive roots (e.g., preserving 'C:\' instead of turning it into 'C:')
    if ($src.EndsWith('\') -and $src.Length -gt 3) { $src = $src.TrimEnd('\') }
    if ($dest.EndsWith('\') -and $dest.Length -gt 3) { $dest = $dest.TrimEnd('\') }

    if (-not (Test-Path $src)) {
        Log "Source path not found: $src" "ERROR"
        $failedFolders += Split-Path $src -Leaf
        $globalSuccess = $false
        continue
    }

    Log "Processing: $src -> $dest"

    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    # 1. ARCHIVING (Pre-Sync) - Only executed if enabled in config
    if ($EnableArchiving) {
        Log "Scanning for files to archive..."
        $todayFolder = Join-Path $ArchiveDir ((Get-Date).ToString("yyyy-MM-dd"))
        $timeLabel = Get-Date -Format "HHmm"

        try {
            # .NET EnumerateFiles is significantly faster than Get-ChildItem for large directories
            $destFiles = [System.IO.Directory]::EnumerateFiles($dest, "*", [System.IO.SearchOption]::AllDirectories)
            
            foreach ($file in $destFiles) {
                $relativePath = $file.Substring($dest.Length).TrimStart('\')
                $sourcePath = Join-Path $src $relativePath

                # If file exists in destination but no longer in source, safely move to archive
                if (-not (Test-Path $sourcePath)) {
                    $fileName = [System.IO.Path]::GetFileName($file)
                    $ext = [System.IO.Path]::GetExtension($fileName)
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    $archiveName = "${base}_$((Get-Date).ToString('yyyyMMdd'))_$($timeLabel)$ext"
                    
                    $targetDir = Join-Path $todayFolder (Split-Path $relativePath -Parent)
                    $targetPath = Join-Path $targetDir $archiveName

                    try {
                        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                        Move-Item -Path $file -Destination $targetPath -Force -ErrorAction Stop
                        $totalArchivedCount++
                    } catch {
                        Log "Failed to archive $relativePath : $($_.Exception.Message)" "WARNING"
                    }
                }
            }
        } catch {
            Log "Error scanning destination directory $dest : $($_.Exception.Message)" "ERROR"
        }
    } else {
        Log "Archiving is disabled. Skipping scanning step."
    }

    # 2. SYNCHRONIZATION (Robocopy Mirror)
    Log "Running Robocopy Sync..."
    $robocopyParams = @($src, $dest, "/MIR", "/XO", "/FFT", "/R:1", "/W:2", "/NP", "/NDL", "/NFL", "/NJH", "/NJS")
    & robocopy @robocopyParams | Out-Null
    
    # Robocopy exit codes 0-7 indicate success (0=No changes, 1=Files copied, etc.)
    if ($LASTEXITCODE -ge 8) {
        Log "Robocopy encountered errors in $src (Exit Code: $LASTEXITCODE)" "ERROR"
        $failedFolders += Split-Path $src -Leaf
        $globalSuccess = $false
    }
}

# 3. CLEANUP OLD ARCHIVES - Only executed if archiving is enabled and directory exists
if ($EnableArchiving -and (Test-Path $ArchiveDir)) {
    Log "Cleaning up archives older than $DaysToKeep days..."
    $limit = (Get-Date).AddDays(-$DaysToKeep)
    
    Get-ChildItem -Path $ArchiveDir -Directory | ForEach-Object {
        try {
            # Try to parse folder name into a Date object. Throws FormatException if it doesn't match yyyy-MM-dd
            $parsedDate = [DateTime]::ParseExact($_.Name, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
            
            if ($parsedDate -lt $limit) {
                Log "Removing old archive folder: $($_.Name)"
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch [System.FormatException] {
            # Silently ignore non-date folders inside the archive root
        }
    }
}

Log "=== Backup Process Completed ==="

# --- FINAL NOTIFICATION ---

$status = if ($globalSuccess) { "Success" } else { "Errors in: $($failedFolders -join ', ')" }
$archiveSummary = if ($EnableArchiving) { "Archived: $totalArchivedCount files.`nOld archives cleaned ($DaysToKeep days)." } else { "Archiving: Disabled." }
$summary = "Status: $status`n$archiveSummary"

Show-Notification -title "Backup Report" -message $summary