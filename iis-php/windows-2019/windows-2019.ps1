# requires -RunAsAdministrator
<#
  INVARIANT scaffold - the Windows marketplace install artifact (<app>.ps1).

  This is the cloudbase-init user-data script for a Windows guest: cloudbase-init runs it once on
  first boot as SYSTEM. Unlike Linux (bootstrap .sh that stages files + runs an Ansible playbook),
  the PowerShell IS the install logic - there is no separate playbook. The engine renders the
  invariant frame (strict errors, stage banners, secret storage, the completion marker) and splices
  in the LLM-generated install steps between the BEGIN/END markers.

  Markers MUST match runner._install_tasks_from_artifacts so a repair can recover the fragment.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Live-status breadcrumbs for the first-login "installing" notice window (Option A). That notice runs
# as the INTERACTIVE user and cannot see this SYSTEM process's output, so we publish the current
# stage + a start timestamp to small files it polls. Set-Status overwrites the current stage; the
# notice shows it + elapsed and closes when the .done flag appears. Write-Stage now also updates the
# status so every existing stage line becomes a live breadcrumb.
$mgStatusDir  = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $mgStatusDir | Out-Null
$mgStatusFile = Join-Path $mgStatusDir 'windows-2019-status.txt'
$mgStartFile  = Join-Path $mgStatusDir 'windows-2019-install.start'
$mgDoneFile   = Join-Path $mgStatusDir 'windows-2019-install.done'
Remove-Item $mgDoneFile -Force -ErrorAction SilentlyContinue
Set-Content -Path $mgStartFile -Value (Get-Date -Format o) -Encoding ASCII
function Set-Status($msg) { try { Set-Content -Path $mgStatusFile -Value $msg -Encoding ASCII } catch {} }
function Write-Stage($msg) { Write-Output "[markgen] $msg"; Set-Status $msg }

Set-Status 'Starting install...'
Write-Stage "install: Windows IIS + PHP on win2019"

# --- First-login "install in progress" notice (shown ONLY while installing) ---
# The install runs as SYSTEM on first boot and can take several minutes on a slow VM. An operator
# who RDPs in during that window would otherwise see a bare desktop and think it's broken (seen
# live). Register a scheduled task NOW (before the long install work) that shows a "still installing,
# please wait" banner in the interactive session; if a session is already active, fire it now. The
# END of this script unregisters it, so it only appears while the install is genuinely running.
$notifyDir = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $notifyDir | Out-Null
$notifyPath = Join-Path $notifyDir 'windows-2019-installing.ps1'
[System.IO.File]::WriteAllBytes(
    $notifyPath,
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDE5LWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMTktc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDE5LWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAxOS1pbnN0YWxsLmRvbmUnCgojIEFuY2hvciBlbGFwc2VkIHRvIHRoZSBpbnN0YWxsJ3MgcmVjb3JkZWQgc3RhcnQgdGltZSBpZiBwcmVzZW50IChzbyB0aGUgdGltZXIgcmVmbGVjdHMgdGhlIHJlYWwKIyBpbnN0YWxsIGFnZSBldmVuIGlmIHRoZSBvcGVyYXRvciBsb2dnZWQgaW4gbGF0ZSksIGVsc2UgdG8gbm93Lgp0cnkgeyAkc3RhcnQgPSBbZGF0ZXRpbWVdOjpQYXJzZSgoR2V0LUNvbnRlbnQgLVJhdyAkc3RhcnRGaWxlKSkgfSBjYXRjaCB7ICRzdGFydCA9IEdldC1EYXRlIH0KCiRiYXIgPSAnIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMnCiMgUG9sbCB1bnRpbCB0aGUgaW5zdGFsbCBzaWduYWxzIGRvbmUsIHdpdGggYSBoYXJkIHNhZmV0eSBjYXAgc28gdGhpcyBjYW4gbmV2ZXIgc3BpbiBmb3JldmVyLgpmb3IgKCRpID0gMDsgJGkgLWx0IDkwMDsgJGkrKykgewogICAgJGRvbmUgPSBUZXN0LVBhdGggJGRvbmVGaWxlCiAgICAkc3RhZ2UgPSBpZiAoVGVzdC1QYXRoICRzdGF0dXNGaWxlKSB7IChHZXQtQ29udGVudCAtUmF3ICRzdGF0dXNGaWxlKS5UcmltKCkgfSBlbHNlIHsgJ1ByZXBhcmluZy4uLicgfQogICAgJGVsYXBzZWQgPSAoR2V0LURhdGUpIC0gJHN0YXJ0CiAgICAkbW0gPSBbaW50XSRlbGFwc2VkLlRvdGFsTWludXRlcwogICAgJHNzID0gJGVsYXBzZWQuU2Vjb25kcwoKICAgIENsZWFyLUhvc3QKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiMgICBZb3VyIE1hcmtldHBsYWNlIEFwcCAoV2luZG93cyBJSVMgKyBQSFApIGlzIElOU1RBTExJTkcgLSBwbGVhc2Ugd2FpdC4iKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBpZiAoJGRvbmUpIHsKICAgICAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiBJbnN0YWxsIGNvbXBsZXRlLiIpIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICgiICBFbGFwc2VkOiB7MH1tIHsxOjAwfXMiIC1mICRtbSwgJHNzKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiIgogICAgICAgIFdyaXRlLUhvc3QgIiAgVGhlIGFwcCBpcyByZWFkeS4gVGhpcyB3aW5kb3cgd2lsbCBjbG9zZSBub3c7IGEgJ2RlcGxveWVkIHN1Y2Nlc3NmdWxseSciIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICIgIG1lc3NhZ2Ugd2l0aCBhbnkgY3JlZGVudGlhbHMgZm9sbG93cy4iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgYnJlYWsKICAgIH0KICAgIFdyaXRlLUhvc3QgKCIgIFN0YXR1cyA6IHswfSIgLWYgJHN0YWdlKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiIKICAgIFdyaXRlLUhvc3QgIiAgSW5zdGFsbGluZyBpbiB0aGUgYmFja2dyb3VuZCAoYSBmZXcgbWludXRlcyBvbiBhIGZyZXNoIFZNKS4gRG8gTk9UIHJlc3RhcnQgdGhlIFZNLiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiAgVGhpcyB3aW5kb3cgdXBkYXRlcyBldmVyeSBmZXcgc2Vjb25kcyBhbmQgY2xvc2VzIGF1dG9tYXRpY2FsbHkgd2hlbiB0aGUgYXBwIGlzIHJlYWR5LiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDMKfQo=')
)
$notifyTask = 'markgen-windows-2019-installing'
$notifyAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $notifyPath + '"')
$notifyPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Highest
Register-ScheduledTask -TaskName $notifyTask -Action $notifyAction `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $notifyPrincipal `
    -Settings (New-ScheduledTaskSettingsSet) -Force | Out-Null
if (& query.exe session 2>$null | Select-String -Pattern '\bActive\b') {
    Start-ScheduledTask -TaskName $notifyTask -ErrorAction SilentlyContinue
}
Write-Stage "install: registered 'installing' notice ($notifyTask)"


# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing Windows IIS + PHP and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$needed = 'Web-Server', 'Web-CGI', 'Web-Mgmt-Console', 'Web-Mgmt-Tools'
$missing = $needed | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }
if ($missing) {
    Write-Output "installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing -IncludeManagementTools | Out-Null
} else {
    Write-Output "IIS features already installed"
}

# VC++ 2015-2022 x64 redistributable is MANDATORY for the PHP vs17 build.
# Run it unconditionally - the installer is idempotent and upgrades any stale runtime.
Write-Output "installing Visual C++ 2015-2022 x64 redistributable"
$vcPath = Join-Path $env:TEMP 'vc_redist.x64.exe'
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcPath -UseBasicParsing
Start-Process -FilePath $vcPath -ArgumentList '/install', '/quiet', '/norestart' -Wait
Write-Output "VC++ redistributable installed"

# Download and extract PHP 8.5.9 NTS vs17 x64
$phpDir = 'C:\PHP'
if (-not (Test-Path (Join-Path $phpDir 'php-cgi.exe'))) {
    Write-Output "downloading PHP 8.5.9 NTS vs17 x64"
    $phpZip = Join-Path $env:TEMP 'php.zip'
    $phpUrl = 'https://windows.php.net/downloads/releases/php-8.5.9-nts-Win32-vs17-x64.zip'
    Invoke-WebRequest -Uri $phpUrl -OutFile $phpZip -UseBasicParsing
    New-Item -ItemType Directory -Force -Path $phpDir | Out-Null
    Write-Output "extracting PHP to $phpDir"
    Expand-Archive -Path $phpZip -DestinationPath $phpDir -Force
} else {
    Write-Output "PHP already extracted to $phpDir"
}

# Derive php.ini from the shipped php.ini-production for THIS exact PHP version.
$phpIni = Join-Path $phpDir 'php.ini'
$phpIniProd = Join-Path $phpDir 'php.ini-production'
Write-Output "creating php.ini from php.ini-production"
Copy-Item -Path $phpIniProd -Destination $phpIni -Force
$ini = Get-Content $phpIni
$ini = $ini -replace '^;?\s*extension_dir\s*=.*', 'extension_dir = "C:\PHP\ext"'
$ini = $ini -replace '^;?\s*cgi\.fix_pathinfo\s*=.*', 'cgi.fix_pathinfo=1'
$extensions = @'

; Extensions enabled by Markgen deployment
extension=mbstring
extension=openssl
extension=curl
extension=mysqli
extension=gd
'@
Set-Content -Path $phpIni -Value $ini
Add-Content -Path $phpIni -Value $extensions
Write-Output "php.ini configured"

# Register the FastCGI application and the *.php handler with appcmd (idempotent).
$appcmd = Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
$phpCgi = Join-Path $phpDir 'php-cgi.exe'

$fastcgiExists = & $appcmd list config -section:system.webServer/fastCgi 2>$null | Select-String -SimpleMatch $phpCgi
if (-not $fastcgiExists) {
    Write-Output "registering FastCGI application for php-cgi.exe"
    & $appcmd set config /section:system.webServer/fastCgi "/+[fullPath='$phpCgi']" | Out-Null
} else {
    Write-Output "FastCGI application already registered"
}

$handlerExists = & $appcmd list config -section:system.webServer/handlers 2>$null | Select-String -SimpleMatch 'PHP_via_FastCGI'
if (-not $handlerExists) {
    Write-Output "registering *.php FastCGI handler"
    & $appcmd set config /section:system.webServer/handlers "/+[name='PHP_via_FastCGI',path='*.php',verb='*',modules='FastCgiModule',scriptProcessor='$phpCgi',resourceType='Either']" | Out-Null
} else {
    Write-Output "*.php handler already registered"
}

# Add index.php as a default document
$defDocExists = & $appcmd list config -section:system.webServer/defaultDocument 2>$null | Select-String -SimpleMatch 'index.php'
if (-not $defDocExists) {
    Write-Output "adding index.php to default documents"
    & $appcmd set config /section:system.webServer/defaultDocument "/+files.[value='index.php']" | Out-Null
} else {
    Write-Output "index.php already a default document"
}

# Landing/health page proving PHP executes through IIS
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null
Set-Content -Path 'C:\inetpub\wwwroot\index.php' -Value "<?php echo 'MARKGEN_PHP_OK ' . phpversion(); ?>"
Write-Output "deployed index.php landing page"

# IIS Manager shortcut on the ALL-USERS (Public) desktop
$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
$lnk = Join-Path $publicDesktop 'IIS Manager.lnk'
if ((Test-Path $inetMgr) -and (-not (Test-Path $lnk))) {
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $inetMgr
    $sc.Description = 'Internet Information Services (IIS) Manager'
    $sc.Save()
    Write-Output "created IIS Manager shortcut on the all-users desktop"
}

# Ensure the web service runs now and on every boot
Start-Service W3SVC
Set-Service W3SVC -StartupType Automatic
Write-Output "IIS is serving on port 80 with PHP 8.5.9 via FastCGI"

# Restart to pick up the new handler/config
Restart-Service W3SVC
Write-Output "W3SVC restarted; deployment complete"
# ----- END app-specific tasks -----

Set-Status 'Finalizing (service, firewall, shortcut)...'

# --- Wire the first-login cleanup script (self-contained; no extra download) ---
# Drop <app>-cleanup.ps1 to disk (decoded from the embedded base64), then run it at the operator's
# first interactive login: it prints the "deployed successfully" banner + any stored credentials,
# wipes install traces, unregisters itself and self-deletes.
#
# We use a SCHEDULED TASK triggered at logon (NOT a RunOnce entry). RunOnce ran the script HIDDEN
# and/or got consumed by a non-interactive post-install logon, so the operator never SAW the banner
# (seen live). A scheduled task with an interactive-user principal runs powershell IN THE USER'S
# OWN SESSION with a VISIBLE console window - which is the whole point of the banner. The cleanup
# script unregisters this task on its first run, giving run-once semantics.
#
# BELT-AND-SUSPENDERS for the "operator logged in DURING the install" race: install can take several
# minutes as SYSTEM, and an operator often RDPs in before it finishes - so the AtLogOn trigger has
# no NEW logon to fire against (they were already logged in when the task was created), and the
# banner never shows until they log off/on. So: register the AtLogOn task (covers future logons) AND,
# if an interactive session is ALREADY active right now, Start the task immediately so it runs in
# that live session. Whoever is present after install completes sees the banner either way.
$cleanupDir = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $cleanupDir | Out-Null
$cleanupPath = Join-Path $cleanupDir 'windows-2019-cleanup.ps1'
[System.IO.File]::WriteAllBytes(
    $cleanupPath,
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyAgICAgICAgICAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChXaW5kb3dzIElJUyArIFBIUCkgaGFzIGJlZW4gZGVwbG95ZWQgc3VjY2Vzc2Z1bGx5ISAgICAgICAgICAgICMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiMgICAgICAgICAgICBDcmVkZW50aWFscyAoaWYgYW55KSBhcmUgc2hvd24gYmVsb3cgYW5kIHN0b3JlZCBvbiBkaXNrLiAgICAgICAgICAgICAgICAgICAgICAgICAgIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIiCldyaXRlLUhvc3QgIlRoaXMgbWVzc2FnZSB3aWxsIGJlIHJlbW92ZWQgYWZ0ZXIgdGhpcyBsb2dpbi4iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiIKCgojIENsZWFudXAgdHJhY2VzIG9mIHRoZSBkZXBsb3ltZW50LgpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6U3lzdGVtRHJpdmVcQ2xvdWRiYXNlSW5pdFxsb2dcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlRFTVBcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKQ2xlYXItRXZlbnRMb2cgLUxvZ05hbWUgQXBwbGljYXRpb24sIFN5c3RlbSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQoKIyBHaXZlIHRoZSBvcGVyYXRvciB0aW1lIHRvIHJlYWQgdGhlIGJhbm5lciBiZWZvcmUgdGhlIHdpbmRvdyBjbG9zZXMgKGl0IHJ1bnMgaW4gdGhlaXIgc2Vzc2lvbikuCldyaXRlLUhvc3QgIlRoaXMgd2luZG93IHdpbGwgY2xvc2UgaW4gMjAgc2Vjb25kcy4iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkClN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIwCgojIFVucmVnaXN0ZXIgdGhlIGZpcnN0LWxvZ2luIHNjaGVkdWxlZCB0YXNrIChydW4tb25jZSBzZW1hbnRpY3MpICsgZGVsZXRlIHRoaXMgc2NyaXB0IGl0c2VsZi4KVW5yZWdpc3Rlci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAnbWFya2dlbi13aW5kb3dzLTIwMTktY2xlYW51cCcgLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiMgQWxzbyBjbGVhciBhbnkgbGVnYWN5IFJ1bk9uY2UgZW50cnkgZnJvbSBvbGRlciBpbnN0YWxscyAoaGFybWxlc3MgaWYgYWJzZW50KS4KUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScgLU5hbWUgJ3dpbmRvd3MtMjAxOV9jbGVhbnVwJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtRm9yY2UgJFBTQ29tbWFuZFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK')
)
# The task name MUST match the name the cleanup script unregisters (markgen-windows-2019-cleanup).
$taskName = 'markgen-windows-2019-cleanup'
$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $cleanupPath + '"')
$taskTrigger = New-ScheduledTaskTrigger -AtLogOn
# BUILTIN\Users (SID S-1-5-32-545) + RunLevel Highest -> runs in the interactive session with an
# elevated token (needed for Clear-EventLog / HKLM cleanup), window visible to the logged-in user.
$taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger `
    -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null
Write-Stage "install: registered first-login cleanup task ($taskName)"
# If someone is ALREADY logged in (they beat the install), fire it now in their live session.
$activeSession = (& query.exe session 2>$null | Select-String -Pattern '\bActive\b')
if ($activeSession) {
    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Write-Stage "install: an interactive session is active - started cleanup banner now"
}

Set-Status 'Install complete.'
# Signal the live "installing" notice window that we're done - it detects this flag, shows a brief
# "complete" line, and exits its poll loop on its own (so the operator's window closes cleanly).
Set-Content -Path $mgDoneFile -Value (Get-Date -Format o) -Encoding ASCII

# Install is done - remove the "installing" notice task so a LATER login doesn't re-show it (the
# already-running notice window exits itself via the .done flag above). Then the cleanup banner
# ("deployed successfully") takes over.
Unregister-ScheduledTask -TaskName 'markgen-windows-2019-installing' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $env:ProgramData 'markgen\windows-2019-installing.ps1') -ErrorAction SilentlyContinue

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
