<#
.SYNOPSIS
    Installation script for the Daily Backup Task.
.DESCRIPTION
    1. Creates a scheduled task named 'Daily_Backup_Task'.
    2. Runs daily at 18:00 (6 PM).
    3. Executes the backup script in a hidden window.
    4. Enables 'StartWhenAvailable' to run the task if the PC was off.
#>

# ===========================================
# CONFIGURATION
# ===========================================
$taskName   = "Daily_Backup_Task"
$scriptName = "backup-script.ps1" # Ensure this matches your main script file name
$scriptPath = Join-Path $PSScriptRoot $scriptName
$runTime    = "18:00"

# ===========================================
# TASK CREATION
# ===========================================

# Check if the backup script exists
if (-not (Test-Path $scriptPath)) {
    Write-Error "Backup script not found at: $scriptPath"
    Write-Host "Please ensure setup-task.ps1 is in the same folder as $scriptName" -ForegroundColor Yellow
    exit
}

# 1. Action: Execute PowerShell in a hidden window
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

# 2. Trigger: Daily at the specified time
$trigger = New-ScheduledTaskTrigger -Daily -At $runTime

# 3. Settings:
# - StartWhenAvailable: Run as soon as possible if the scheduled time was missed (PC off)
# - MultipleInstances Ignore: Prevent overlapping runs
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances Ignore

# 4. Registration (Requires Administrator privileges)
try {
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Force
    
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Task '$taskName' created successfully!" -ForegroundColor Green
    Write-Host "Execution Time: Daily at $runTime"
    Write-Host "Visibility: Hidden (Background process)"
    Write-Host "Missed Schedule: Will run immediately on startup"
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to create the task. Please run PowerShell as Administrator."
}
