korjaa tämä readme.md vastaamaan uusia muokkauksia ja anna vastauksena raaka md versio:

# 🛡️ PowerShell Robocopy Sync with Archiving

A robust PowerShell backup solution that keeps two directories in sync using `robocopy /MIR`. It ensures no data is lost by archiving files that would otherwise be deleted during synchronization.

## ✨ Features

* **Mirror Sync:** Keeps the destination identical to the source.
* **Optional Archiving:** Toggle archiving on or off. When enabled, files deleted from the source are moved to a timestamped archive folder instead of being lost.
* **Date-Stamped Files:** Archived files are automatically renamed with a precise timestamp to prevent overwriting older versions.
* **Auto-Cleanup:** Automatically purges archive folders older than **X** days to save space.
* **JSON Configuration:** Driven completely by a centralized configuration file instead of messy script parameters.
* **CSV Driven:** Manage multiple backup directory pairs easily via a simple CSV schema.
* **Windows Notifications:** Sends a native Windows balloon notification upon completion.

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

### 3. Configure your config.json file
Create a file named `folders.csv` in the same directory as the script. Use the following format:

```json
{
    "FoldersCsvPath": "./folders.csv",
    "LogPath": "./logs/BackupLog.txt",
    "ArchiveDir": "./archive",
    "DaysToKeep": 30,
    "EnableArchiving": true
}
```

### 4. Test the script
Run the script manually in PowerShell to ensure paths and permissions are correct:

```powershell
.\backup-script.ps1
```

### 5. Schedule the backup
Run the provided `setup-task.ps1` as **Administrator** to create a daily scheduled task at 18:00.

*   The task is set to *"Run as soon as possible if missed"*.
*   The PowerShell window will be hidden during execution.

---

## 📂 File Structure

*   `backup-script.ps1`: The main logic for syncing and archiving.
*   `config.json`: Centralized settings file (paths, retention, toggle for archiving).
*   `setup-task.ps1`: Helper script to install the Windows Scheduled Task.
*   `folders.csv`: Your configuration file.
*   `logs/`: Directory where execution logs are stored.
*   `archive/`: Directory where deleted files are kept.

---

## ⚙️ Parameters

The script now accepts only one optional parameter if you prefer to store your configuration file somewhere else:


| Parameter | Description | Default |
| :--- | :--- | :--- |
| `-ConfigPath` | Path to your custom JSON configuration file | `$PSScriptRoot\config.json` |


---

## ⚙️ Configuration Parameters (config.json)

You can customize the script behavior inside config.json:


| Key | Type | Description | Default |
| :--- | :--- | :--- | :--- |
| `FoldersCsvPath` | String | Path to the CSV file listing backup folders. | `./folders.csv` |
| `LogPath` | String | File path where execution logs are appended. | `./logs/BackupLog.txt` |
| `ArchiveDir` | String | Directory where archived files are stored. | `./archive` |
| `DaysToKeep` | Integer | Retention period: how many days old archives are kept. | `30` |
| `EnableArchiving` | Boolean | Set to true to archive deleted files, or false to just mirror. | `true` |


---

## 🛠️ Installation

1.  Right-click `setup-task.ps1`.
2.  Select **Run with PowerShell** (as Administrator).
3.  The script will automatically link to the backup logic in the same folder.

---

## 📄 License

This project is licensed under the **MIT License** - feel free to use and modify it.
