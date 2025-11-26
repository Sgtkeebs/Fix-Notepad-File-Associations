<#
.SYNOPSIS
  Repairs broken text-like associations (.txt, .log, .cfg, .ini, .nfo) to Notepad,
  restores "New → Text Document" for .txt, and creates backups of related registry keys.

.NOTES
  Run this script in an elevated (Run as Administrator) PowerShell session.

  Backups created (per run, timestamped) for:
    - HKEY_CLASSES_ROOT\.txt
    - HKEY_CLASSES_ROOT\.log
    - HKEY_CLASSES_ROOT\.cfg
    - HKEY_CLASSES_ROOT\.ini
    - HKEY_CLASSES_ROOT\.nfo
    - HKEY_CLASSES_ROOT\txtfile
    - HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt/.log/.cfg/.ini/.nfo
#>

param(
    [switch]$SkipExplorerRestart
)

Write-Host "=== Repairing text file associations to Notepad ===" -ForegroundColor Cyan

# Extensions we want to map to txtfile
$extensions = @(".txt", ".log", ".cfg", ".ini", ".nfo")

# ---------- Backup Section ----------
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $PSScriptRoot "Backup"

if (-not (Test-Path $backupDir)) {
    New-Item -Path $backupDir -ItemType Directory | Out-Null
}

function Backup-RegistryKey {
    param(
        [string]$RegPath,
        [string]$FileName
    )

    $fullPath = Join-Path $backupDir $FileName
    Write-Host "Backing up '$RegPath' to '$fullPath'..." -ForegroundColor Yellow

    # Use proper argument array so reg.exe gets correct params
    $args = @("export", $RegPath, $fullPath, "/y")
    $proc = Start-Process -FilePath reg.exe -ArgumentList $args -NoNewWindow -PassThru -Wait

    if ($proc.ExitCode -eq 0) {
        Write-Host "✔ Backup successful: $fullPath" -ForegroundColor Green
    } else {
        Write-Host "✖ Backup failed for $RegPath (exit code $($proc.ExitCode)). It may not exist." -ForegroundColor DarkYellow
    }
}

# Backup HKCR for each extension
foreach ($ext in $extensions) {
    $cleanExt = $ext.TrimStart('.')
    Backup-RegistryKey -RegPath "HKEY_CLASSES_ROOT\$ext" -FileName "HKCR_${cleanExt}_$timestamp.reg"
}

# Backup txtfile ProgID
Backup-RegistryKey -RegPath "HKEY_CLASSES_ROOT\txtfile" -FileName "HKCR_txtfile_$timestamp.reg"

# Backup HKCU FileExts for each extension
foreach ($ext in $extensions) {
    $cleanExt = $ext.TrimStart('.')
    Backup-RegistryKey -RegPath "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext" -FileName "HKCU_FileExts_${cleanExt}_$timestamp.reg"
}

Write-Host "`nBackups stored in: $backupDir`n" -ForegroundColor Cyan

# ---------- Helper for safe registry writes ----------
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value
    )

    try {
        Write-Host "Setting '$Path' ('$Name') to '$Value'..." -ForegroundColor Yellow
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -ErrorAction Stop
        Write-Host "✔ Updated $Path" -ForegroundColor Green
    }
    catch {
        Write-Host "✖ Failed to update $Path : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------- Fix Associations for each extension ----------
foreach ($ext in $extensions) {
    $extKey = "Registry::HKEY_CLASSES_ROOT\$ext"
    Write-Host "`n--- Processing $ext ---" -ForegroundColor Cyan
    Set-RegistryValue -Path $extKey -Name "(default)" -Value "txtfile"

    # Only .txt gets ShellNew for "New -> Text Document"
    if ($ext -eq ".txt") {
        Write-Host "Ensuring ShellNew for .txt exists..." -ForegroundColor Yellow
        $shellNewKey = "Registry::HKEY_CLASSES_ROOT\.txt\ShellNew"

        if (-not (Test-Path $shellNewKey)) {
            New-Item -Path $shellNewKey -Force | Out-Null
            Write-Host "  Created ShellNew key for .txt" -ForegroundColor Green
        }

        try {
            New-ItemProperty -Path $shellNewKey -Name "NullFile" -Value "" -PropertyType String -Force | Out-Null
            Write-Host "  Set NullFile on ShellNew (.txt)" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✖ Failed to set ShellNew NullFile: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Ensure txtfile open command is correct (shared by all these extensions)
$txtFileCmdKey = "Registry::HKEY_CLASSES_ROOT\txtfile\shell\open\command"
Set-RegistryValue -Path $txtFileCmdKey -Name "(default)" -Value "%SystemRoot%\system32\NOTEPAD.EXE %1"

# Classic assoc/ftype for all extensions
Write-Host "`nRunning assoc / ftype commands..." -ForegroundColor Yellow
foreach ($ext in $extensions) {
    cmd /c "assoc $ext=txtfile" | Out-Null
}
cmd /c 'ftype txtfile="%SystemRoot%\system32\NOTEPAD.EXE" "%1"' | Out-Null
Write-Host "✔ assoc/ftype updated for .txt, .log, .cfg, .ini, .nfo" -ForegroundColor Green

# Optional: show summary
Write-Host "`nCurrent effective settings (sample):" -ForegroundColor Cyan
try {
    $txtExtKey = "Registry::HKEY_CLASSES_ROOT\.txt"
    $extDefault = (Get-ItemProperty $txtExtKey)."(default)"
    $cmdDefault = (Get-ItemProperty $txtFileCmdKey)."(default)"
    Write-Host "  .txt default : $extDefault"
    Write-Host "  txtfile open : $cmdDefault"
}
catch {
    Write-Host "  (Could not read back one or more keys: $($_.Exception.Message))" -ForegroundColor DarkYellow
}

# 4) Restart Explorer (optional)
if (-not $SkipExplorerRestart) {
    Write-Host "`nRestarting Explorer to apply changes..." -ForegroundColor Yellow
    try {
        Stop-Process -Name explorer -Force -ErrorAction Stop
        Write-Host "✔ Explorer restarted." -ForegroundColor Green
        Write-Host "Try double-clicking .txt/.log/.cfg/.ini/.nfo and 'New → Text Document'." -ForegroundColor Green
    }
    catch {
        Write-Host "✖ Failed to restart Explorer: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You may want to log off/on or reboot to ensure changes fully apply." -ForegroundColor DarkYellow
    }
}
else {
    Write-Host "`nSkipping Explorer restart per parameter. You may need to log off/on or restart Explorer manually." -ForegroundColor DarkYellow
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
