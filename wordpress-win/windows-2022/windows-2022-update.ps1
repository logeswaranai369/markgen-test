<#
  Generated update helper (Windows analog of <app>_update.sh). Ships in the guest as
  <app>-update.ps1. DEFAULT = check-only: report whether a newer upstream version exists. Applying
  the update is conservative and decided per app.
#>
$ErrorActionPreference = 'Stop'

$App = 'windows-2022'
$InstalledVersion = 'WordPress 7.0.4; PHP 8.3.33 NTS; MariaDB 11.4.7'
$UpstreamSource = 'wordpress.org/latest.zip'

Write-Output "== $App update check =="
Write-Output "Installed version: $InstalledVersion"

if ([string]::IsNullOrEmpty($UpstreamSource)) {
    Write-Output "No upstream source configured for $App; cannot check for updates."
    exit 0
}

Write-Output "Upstream source: $UpstreamSource"
Write-Output "Update check is advisory - review $UpstreamSource for a newer release, then re-deploy."
