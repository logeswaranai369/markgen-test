<#
  INVARIANT — the Windows first-login cleanup script (<app>-cleanup.ps1).
  Windows analog of the Linux <app>_cleanup.sh: on first interactive login it prints the success
  banner + any stored credentials, then wipes install traces (cloudbase-init logs, temp) and
  self-deletes. Wired to run once via a RunOnce registry entry set by the install script.
#>
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "################################################################################################" -ForegroundColor Red
Write-Host "#            Your Marketplace App (IIS) has been deployed successfully!            #" -ForegroundColor Red
Write-Host "#            Credentials (if any) are shown below and stored on disk.                          #" -ForegroundColor Red
Write-Host "################################################################################################" -ForegroundColor Red
Write-Host ""
Write-Host "This message will be removed after this login." -ForegroundColor Red
Write-Host ""


# Cleanup traces of the deployment.
Remove-Item -Recurse -Force "$env:SystemDrive\CloudbaseInit\log\*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:TEMP\*" -ErrorAction SilentlyContinue
Clear-EventLog -LogName Application, System -ErrorAction SilentlyContinue

# Remove the RunOnce hook + this script itself.
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'windows-2022_cleanup' -ErrorAction SilentlyContinue
Remove-Item -Force $PSCommandPath -ErrorAction SilentlyContinue
