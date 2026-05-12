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

# Create log and archive directories if they don't exist
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
    
    # Console output with colors
    $color = switch($type) { "ERROR" {"Red"} "WARNING" {"Yellow"} Default {"White"} }
    Write-Host $line -ForegroundColor $color
    
    # Write to log file
    $line | Add-Content -Path $LogPath
}

function Show-Toast {
    param([string]$title, [string]$message)
    # Native Windows Toast Notification (Persists in Action Center)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $xml = "<toast><visual><binding template='ToastGeneric'><text>$title</text><text>$message</text></binding></visual></toast>"
        $xmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xmlDoc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDoc)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell").Show($toast)
    } catch {
        Log "Failed to send toast notification" "WARNING"
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
    $src  = $pair.Source.Trim().TrimEnd('\')
    $dest = $pair.Destination.Trim().TrimEnd('\')

    if (-not (Test-Path $src)) {
        Log "Source path not found: $src" "ERROR"
        $failedFolders += Split-Path $src -Leaf
        $globalSuccess = $false
        continue
    }

    Log "Processing: $src -> $dest"

    # Create destination if missing
    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    # 1. ARCHIVING (Pre-Sync)
    # Find files in destination that no longer exist in source
    Log "Scanning for files to archive..."
    $destFiles = Get-ChildItem -Path $dest -Recurse -File -ErrorAction SilentlyContinue
    $todayFolder = Join-Path $ArchiveDir ((Get-Date).ToString("yyyy-MM-dd"))
    $timeLabel = Get-Date -Format "HHmm"

    if ($null -ne $destFiles) {
        foreach ($file in $destFiles) {
            $relativePath = $file.FullName.Substring($dest.Length).TrimStart('\')
            $sourcePath = Join-Path $src $relativePath

            if (-not (Test-Path $sourcePath)) {
                $ext = [System.IO.Path]::GetExtension($file.Name)
                $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $archiveName = "${base}_$((Get-Date).ToString('yyyyMMdd'))_$($timeLabel)$ext"
                
                $targetDir = Join-Path $todayFolder (Split-Path $relativePath -Parent)
                $targetPath = Join-Path $targetDir $archiveName

                try {
                    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                    # Using Move-Item for speed (Instant pointer update on same drive)
                    Move-Item -Path $file.FullName -Destination $targetPath -Force -ErrorAction Stop
                    $totalArchivedCount++
                } catch {
                    Log "Failed to archive $relativePath : $($_.Exception.Message)" "WARNING"
                }
            }
        }
    }

    # 2. SYNCHRONIZATION (Robocopy Mirror)
    Log "Running Robocopy Sync..."
    $robocopyParams = @($src, $dest, "/MIR", "/XO", "/FFT", "/R:1", "/W:2", "/NP", "/NDL", "/NFL", "/NJH", "/NJS")
    & robocopy @robocopyParams | Out-Null
    
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
    Get-ChildItem -Path $ArchiveDir -Directory | Where-Object { $_.CreationTime -lt $limit } | ForEach-Object {
        Log "Removing old archive folder: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Log "=== Backup Process Completed ==="

# --- FINAL NOTIFICATION ---

$status = if ($globalSuccess) { "Success" } else { "Errors in: $($failedFolders -join ', ')" }
$summary = "Status: $status`nArchived: $totalArchivedCount files.`nOld archives cleaned ($DaysToKeep days)."

Show-Toast -title "Backup Report" -message $summary
