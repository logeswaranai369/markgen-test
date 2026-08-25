<#
  INVARIANT - the Windows first-login cleanup script (<app>-cleanup.ps1).
  Windows analog of the Linux <app>_cleanup.sh: on first interactive login it prints the success
  banner + any stored credentials, then wipes install traces (cloudbase-init logs, temp) and
  self-deletes. Run once via a scheduled task (trigger: at-logon) that the install script
  registered; this script unregisters that task on its first run for run-once semantics. Runs in
  the user's interactive session so the banner window is VISIBLE.
#>
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "================================================================================" -ForegroundColor Green
Write-Host "  SUCCESS  Your Marketplace App (MongoDB Community Server + mongosh) has been deployed successfully!" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Credentials for this deployment (also saved on disk):" -ForegroundColor Cyan
Write-Host ""
if (Test-Path 'C:\credentials.txt') {
    Write-Host "  C:\credentials.txt" -ForegroundColor DarkGray
    Get-Content 'C:\credentials.txt' | ForEach-Object { if ($_.Trim()) { Write-Host "    $_" -ForegroundColor White } }
    Write-Host ""
}
Write-Host "  This banner appears once and is removed after this login." -ForegroundColor DarkGray
Write-Host ""

# Cleanup traces of the deployment.
Remove-Item -Recurse -Force "$env:SystemDrive\CloudbaseInit\log\*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:TEMP\*" -ErrorAction SilentlyContinue
Clear-EventLog -LogName Application, System -ErrorAction SilentlyContinue

# Give the operator time to read the banner before the window closes (it runs in their session).
Write-Host "  This window will close in 20 seconds." -ForegroundColor DarkGray
Start-Sleep -Seconds 20

# Unregister the first-login scheduled task (run-once semantics) + delete this script itself.
Unregister-ScheduledTask -TaskName 'markgen-windows-2019-cleanup' -Confirm:$false -ErrorAction SilentlyContinue
# Also clear any legacy RunOnce entry from older installs (harmless if absent).
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'windows-2019_cleanup' -ErrorAction SilentlyContinue
Remove-Item -Force $PSCommandPath -ErrorAction SilentlyContinue
