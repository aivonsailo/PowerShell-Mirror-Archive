# 🛡️ PowerShell Robocopy Sync with Archiving

A robust PowerShell backup solution that keeps two directories in sync using `robocopy /MIR`. It ensures no data is lost by archiving files that would otherwise be deleted during synchronization.

## ✨ Features

*   **Mirror Sync:** Keeps the destination identical to the source.
*   **Smart Archiving:** If a file is deleted from the source, the script moves the destination's copy to an archive folder instead of deleting it permanently.
*   **Date-Stamped Files:** Archived files are renamed with a timestamp to prevent overwriting.
*   **Auto-Cleanup:** Automatically removes archives older than **X** days (default: 30).
*   **Windows Notifications:** Sends a native Toast notification to the Action Center upon completion.
*   **CSV Driven:** Manage multiple backup tasks easily via a simple CSV file.

---

## 🚀 Setup Instructions

### 1. Clone the repository
Download or clone this repository to your local machine (e.g., `C:\Scripts\Backup`).

### 2. Configure your folders
Create a file named `folders.csv` in the same directory as the script. Use the following format:

```csv
Source,Destination
C:\Users\Name\Documents,E:\Backup\Documents
D:\Projects,E:\Backup\Projects
```

### 3. Test the script
Run the script manually in PowerShell to ensure paths and permissions are correct:

```powershell
.\backup-script.ps1
```

### 4. Schedule the backup
Run the provided `setup-task.ps1` as **Administrator** to create a daily scheduled task at 18:00.

*   The task is set to *"Run as soon as possible if missed"*.
*   The PowerShell window will be hidden during execution.

---

## 📂 File Structure

*   `backup-script.ps1`: The main logic for syncing and archiving.
*   `setup-task.ps1`: Helper script to install the Windows Scheduled Task.
*   `folders.csv`: Your configuration file.
*   `logs/`: Directory where execution logs are stored.
*   `archive/`: Directory where deleted files are kept.

---

## ⚙️ Parameters

You can customize the execution by passing parameters to the script:


| Parameter | Description | Default |
| :--- | :--- | :--- |
| `-ConfigPath` | Path to your CSV file | `.\folders.csv` |
| `-LogPath` | Where to save the logs | `.\logs\` |
| `-DaysToKeep` | How many days to keep archives | `30` |

---

## 🛠️ Installation

1.  Right-click `setup-task.ps1`.
2.  Select **Run with PowerShell** (as Administrator).
3.  The script will automatically link to the backup logic in the same folder.

---

## 📄 License

This project is licensed under the **MIT License** - feel free to use and modify it.
