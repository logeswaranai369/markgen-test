<#
  Generated update helper (Windows analog of <app>_update.sh). Ships in the guest as
  <app>-update.ps1. DEFAULT = check-only: report whether a newer upstream version exists. Applying
  the update is conservative and decided per app.
#>
$ErrorActionPreference = 'Stop'

$App = 'windows-2025'
$InstalledVersion = 'SQL Server 2022 Express 16.0.1000.6; SSMS 22'
$UpstreamSource = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLEXPR_x64_ENU.exe ; https://aka.ms/ssms/22/release/vs_SSMS.exe'

Write-Output "== $App update check =="
Write-Output "Installed version: $InstalledVersion"

if ([string]::IsNullOrEmpty($UpstreamSource)) {
    Write-Output "No upstream source configured for $App; cannot check for updates."
    exit 0
}

Write-Output "Upstream source: $UpstreamSource"
Write-Output "Update check is advisory - review $UpstreamSource for a newer release, then re-deploy."
