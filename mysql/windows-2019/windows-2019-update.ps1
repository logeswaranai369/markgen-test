<#
  Generated update helper (Windows analog of <app>_update.sh). Ships in the guest as
  <app>-update.ps1. DEFAULT = check-only: report whether a newer upstream version exists. Applying
  the update is conservative and decided per app.
#>
$ErrorActionPreference = 'Stop'

$App = 'windows-2019'
$InstalledVersion = '8.4.10'
$UpstreamSource = 'https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.10-winx64.zip'

Write-Output "== $App update check =="
Write-Output "Installed version: $InstalledVersion"

if ([string]::IsNullOrEmpty($UpstreamSource)) {
    Write-Output "No upstream source configured for $App; cannot check for updates."
    exit 0
}

Write-Output "Upstream source: $UpstreamSource"
Write-Output "Update check is advisory - review $UpstreamSource for a newer release, then re-deploy."
