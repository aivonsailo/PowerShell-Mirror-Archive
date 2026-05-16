<#
.SYNOPSIS
    Robocopy-based backup script with pre-sync archiving.
.DESCRIPTION
    1. Reads source/destination pairs from a CSV file.
    2. Detects files that exist in destination but are missing from source.
    3. Moves those files to a timestamped archive instead of deleting them.
    4. Performs a 'robocopy /MIR' to synchronize the directories.
    5. Cleans up old archives and sends a Windows Toast notification.
#>

Param(
    [string]$ConfigPath = "$PSScriptRoot\folders.csv",
    [string]$LogPath    = "$PSScriptRoot\logs\BackupLog.txt",
    [string]$ArchiveDir = "$PSScriptRoot\archive",
    [int]$DaysToKeep    = 30
)

# --- INITIALIZATION ---

$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null }

$totalArchivedCount = 0
$failedFolders = @()
$globalSuccess = $true

# --- FUNCTIONS ---

function Log {
    param([string]$message, [string]$type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$type] $message"
    
    # Console output with colors based on log level
    $color = switch($type) { "ERROR" {"Red"} "WARNING" {"Yellow"} Default {"White"} }
    Write-Host $line -ForegroundColor $color
    
    # Write to log file
    $line | Add-Content -Path $LogPath
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

# --- MAIN PROCESS ---

Log "=== Backup Process Started ==="

if (-not (Test-Path $ConfigPath)) {
    Log "Configuration file not found at $ConfigPath" "ERROR"
    exit
}

$directories = Import-Csv -Path $ConfigPath

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

    # 1. ARCHIVING (Pre-Sync)
    Log "Scanning for files to archive..."
    $todayFolder = Join-Path $ArchiveDir ((Get-Date).ToString("yyyy-MM-dd"))
    $timeLabel = Get-Date -Format "HHmm"

    try {
        # .NET EnumerateFiles is significantly faster than Get-ChildItem for large directories
        $destFiles = [System.IO.Directory]::EnumerateFiles($dest, "*", [System.IO.SearchOption]::AllDirectories)
        
        foreach ($file in $destFiles) {
            # Calculate the relative path from the destination root
            $relativePath = $file.Substring($dest.Length).TrimStart('\')
            $sourcePath = Join-Path $src $relativePath

            # If the file exists in destination but no longer in source, move it to archive
            if (-not (Test-Path $sourcePath)) {
                $fileName = [System.IO.Path]::GetFileName($file)
                $ext = [System.IO.Path]::GetExtension($fileName)
                $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                $archiveName = "${base}_$((Get-Date).ToString('yyyyMMdd'))_$($timeLabel)$ext"
                
                $targetDir = Join-Path $todayFolder (Split-Path $relativePath -Parent)
                $targetPath = Join-Path $targetDir $archiveName

                try {
                    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                    # Using Move-Item for speed (instant pointer update on the same drive)
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

# 3. CLEANUP OLD ARCHIVES
if (Test-Path $ArchiveDir) {
    Log "Cleaning up archives older than $DaysToKeep days..."
    $limit = (Get-Date).AddDays(-$DaysToKeep)
    
    Get-ChildItem -Path $ArchiveDir -Directory | ForEach-Object {
        try {
            # Try to parse the folder name into a Date object. 
            # If the format doesn't match yyyy-MM-dd, ParseExact will throw a FormatException.
            $parsedDate = [DateTime]::ParseExact($_.Name, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
            
            if ($parsedDate -lt $limit) {
                Log "Removing old archive folder: $($_.Name)"
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch [System.FormatException] {
            # Silently ignore folders that do not match the expected date naming convention
        }
    }
}

Log "=== Backup Process Completed ==="

# --- FINAL NOTIFICATION ---

$status = if ($globalSuccess) { "Success" } else { "Errors in: $($failedFolders -join ', ')" }
$summary = "Status: $status`nArchived: $totalArchivedCount files.`nOld archives cleaned ($DaysToKeep days)."

Show-Notification -title "Backup Report" -message $summary