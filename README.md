# Fix-Notepad-File-Associations
This is a powershell script that will fix Notepad file associations when removing Windows Store Notepad that includes CoPilot

## How to use

1. Download script to a place familiar to you. I like to use Desktop or Downloads.
2. Open PowerShell as Admin.
3. Change directories to where you downloaded to script to. Run `.\Fix-TextFile-Assoc.ps1`

**When doing any modifications of the registry always make sure to have a backup.** This script will backup the reg keys it modifies to a folder called `Backup` in the same directory where the script was run. 
