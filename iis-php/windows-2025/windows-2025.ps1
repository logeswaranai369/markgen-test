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
$mgStatusFile = Join-Path $mgStatusDir 'windows-2025-status.txt'
$mgStartFile  = Join-Path $mgStatusDir 'windows-2025-install.start'
$mgDoneFile   = Join-Path $mgStatusDir 'windows-2025-install.done'
Remove-Item $mgDoneFile -Force -ErrorAction SilentlyContinue
Set-Content -Path $mgStartFile -Value (Get-Date -Format o) -Encoding ASCII
function Set-Status($msg) { try { Set-Content -Path $mgStatusFile -Value $msg -Encoding ASCII } catch {} }
function Write-Stage($msg) { Write-Output "[markgen] $msg"; Set-Status $msg }

Set-Status 'Starting install...'
Write-Stage "install: Windows IIS + PHP (FastCGI) on win2025"

# --- First-login "install in progress" notice (shown ONLY while installing) ---
# The install runs as SYSTEM on first boot and can take several minutes on a slow VM. An operator
# who RDPs in during that window would otherwise see a bare desktop and think it's broken (seen
# live). Register a scheduled task NOW (before the long install work) that shows a "still installing,
# please wait" banner in the interactive session; if a session is already active, fire it now. The
# END of this script unregisters it, so it only appears while the install is genuinely running.
$notifyDir = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $notifyDir | Out-Null
$notifyPath = Join-Path $notifyDir 'windows-2025-installing.ps1'
[System.IO.File]::WriteAllBytes(
    $notifyPath,
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDI1LWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjUtc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDI1LWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyNS1pbnN0YWxsLmRvbmUnCgojIEFuY2hvciBlbGFwc2VkIHRvIHRoZSBpbnN0YWxsJ3MgcmVjb3JkZWQgc3RhcnQgdGltZSBpZiBwcmVzZW50IChzbyB0aGUgdGltZXIgcmVmbGVjdHMgdGhlIHJlYWwKIyBpbnN0YWxsIGFnZSBldmVuIGlmIHRoZSBvcGVyYXRvciBsb2dnZWQgaW4gbGF0ZSksIGVsc2UgdG8gbm93Lgp0cnkgeyAkc3RhcnQgPSBbZGF0ZXRpbWVdOjpQYXJzZSgoR2V0LUNvbnRlbnQgLVJhdyAkc3RhcnRGaWxlKSkgfSBjYXRjaCB7ICRzdGFydCA9IEdldC1EYXRlIH0KCiRiYXIgPSAnIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMnCiMgUG9sbCB1bnRpbCB0aGUgaW5zdGFsbCBzaWduYWxzIGRvbmUsIHdpdGggYSBoYXJkIHNhZmV0eSBjYXAgc28gdGhpcyBjYW4gbmV2ZXIgc3BpbiBmb3JldmVyLgpmb3IgKCRpID0gMDsgJGkgLWx0IDkwMDsgJGkrKykgewogICAgJGRvbmUgPSBUZXN0LVBhdGggJGRvbmVGaWxlCiAgICAkc3RhZ2UgPSBpZiAoVGVzdC1QYXRoICRzdGF0dXNGaWxlKSB7IChHZXQtQ29udGVudCAtUmF3ICRzdGF0dXNGaWxlKS5UcmltKCkgfSBlbHNlIHsgJ1ByZXBhcmluZy4uLicgfQogICAgJGVsYXBzZWQgPSAoR2V0LURhdGUpIC0gJHN0YXJ0CiAgICAkbW0gPSBbaW50XSRlbGFwc2VkLlRvdGFsTWludXRlcwogICAgJHNzID0gJGVsYXBzZWQuU2Vjb25kcwoKICAgIENsZWFyLUhvc3QKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiMgICBZb3VyIE1hcmtldHBsYWNlIEFwcCAoV2luZG93cyBJSVMgKyBQSFAgKEZhc3RDR0kpKSBpcyBJTlNUQUxMSU5HIC0gcGxlYXNlIHdhaXQuIikgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiIgogICAgaWYgKCRkb25lKSB7CiAgICAgICAgV3JpdGUtSG9zdCAoIiAgU3RhdHVzIDogSW5zdGFsbCBjb21wbGV0ZS4iKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgIiIKICAgICAgICBXcml0ZS1Ib3N0ICIgIFRoZSBhcHAgaXMgcmVhZHkuIFRoaXMgd2luZG93IHdpbGwgY2xvc2Ugbm93OyBhICdkZXBsb3llZCBzdWNjZXNzZnVsbHknIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiICBtZXNzYWdlIHdpdGggYW55IGNyZWRlbnRpYWxzIGZvbGxvd3MuIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgICAgIGJyZWFrCiAgICB9CiAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiB7MH0iIC1mICRzdGFnZSkgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgKCIgIEVsYXBzZWQ6IHswfW0gezE6MDB9cyIgLWYgJG1tLCAkc3MpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBXcml0ZS1Ib3N0ICIgIEluc3RhbGxpbmcgaW4gdGhlIGJhY2tncm91bmQgKGEgZmV3IG1pbnV0ZXMgb24gYSBmcmVzaCBWTSkuIERvIE5PVCByZXN0YXJ0IHRoZSBWTS4iIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIgIFRoaXMgd2luZG93IHVwZGF0ZXMgZXZlcnkgZmV3IHNlY29uZHMgYW5kIGNsb3NlcyBhdXRvbWF0aWNhbGx5IHdoZW4gdGhlIGFwcCBpcyByZWFkeS4iIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAzCn0K')
)
$notifyTask = 'markgen-windows-2025-installing'
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
Set-Status 'Installing Windows IIS + PHP (FastCGI) and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$needed = 'Web-Server', 'Web-Mgmt-Console', 'Web-Mgmt-Tools', 'Web-Scripting-Tools', 'Web-CGI'
$missing = $needed | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }
if ($missing) {
    Write-Output "installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing -IncludeManagementTools | Out-Null
}

# Verify the management console (inetmgr) actually landed
$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
if (-not (Test-Path $inetMgr)) {
    Write-Output "IIS Manager console missing after feature install; re-installing Web-Mgmt-Console"
    Install-WindowsFeature -Name Web-Mgmt-Console | Out-Null
}

# Install the VC++ 2015-2022 x64 redistributable BEFORE PHP. PHP 8.5 (VS17 build) links a newer
# vcruntime140.dll than the one shipped on WS2019/2022, so install it UNCONDITIONALLY (idempotent).
Write-Output "installing Visual C++ 2015-2022 x64 redistributable"
$vcPath = Join-Path $env:TEMP 'vc_redist.x64.exe'
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcPath
Start-Process -FilePath $vcPath -ArgumentList '/install', '/quiet', '/norestart' -Wait
Write-Output "VC++ redistributable installed"

# Download and unpack PHP 8.5.9 (NTS, VS17, x64)
$phpDir = 'C:\PHP'
$phpCgi = Join-Path $phpDir 'php-cgi.exe'
if (-not (Test-Path $phpCgi)) {
    Write-Output "downloading PHP 8.5.9 (NTS x64)"
    $phpZip = Join-Path $env:TEMP 'php-8.5.9.zip'
    $phpUrl = 'https://windows.php.net/downloads/releases/php-8.5.9-nts-Win32-vs17-x64.zip'
    Invoke-WebRequest -Uri $phpUrl -OutFile $phpZip
    New-Item -ItemType Directory -Force -Path $phpDir | Out-Null
    Expand-Archive -Path $phpZip -DestinationPath $phpDir -Force
    Write-Output "PHP extracted to $phpDir"
}

# Create php.ini from the production template if not already present
$phpIni = Join-Path $phpDir 'php.ini'
if (-not (Test-Path $phpIni)) {
    $iniSrc = Join-Path $phpDir 'php.ini-production'
    if (Test-Path $iniSrc) { Copy-Item $iniSrc $phpIni }
    else { New-Item -ItemType File -Path $phpIni | Out-Null }
    Add-Content -Path $phpIni -Value ''
    Add-Content -Path $phpIni -Value ('extension_dir = "' + (Join-Path $phpDir 'ext') + '"')
    Add-Content -Path $phpIni -Value 'cgi.force_redirect = 0'
    Add-Content -Path $phpIni -Value 'cgi.fix_pathinfo = 1'
    Add-Content -Path $phpIni -Value 'fastcgi.impersonate = 1'
    Write-Output "php.ini created"
}

$appcmd = 'C:\Windows\System32\inetsrv\appcmd.exe'

# Register the FastCGI application (idempotent)
$fcgiList = & $appcmd list config -section:system.webServer/fastCgi 2>$null
if ($fcgiList -notmatch [regex]::Escape($phpCgi)) {
    Write-Output "registering PHP FastCGI application"
    & $appcmd set config -section:system.webServer/fastCgi /+"[fullPath='$phpCgi']" /commit:apphost | Out-Null
}

# Register the FastCGI handler mapping for *.php (idempotent)
$handlers = & $appcmd list config -section:system.webServer/handlers 2>$null
if ($handlers -notmatch 'PHP_via_FastCGI') {
    Write-Output "registering PHP handler mapping"
    & $appcmd set config -section:system.webServer/handlers /+"[name='PHP_via_FastCGI',path='*.php',verb='*',modules='FastCgiModule',scriptProcessor='$phpCgi',resourceType='Either']" /commit:apphost | Out-Null
}

# Add index.php to the default document list (idempotent)
$defaultDocs = & $appcmd list config -section:system.webServer/defaultDocument 2>$null
if ($defaultDocs -notmatch 'index\.php') {
    & $appcmd set config -section:system.webServer/defaultDocument /+"files.[value='index.php']" /commit:apphost | Out-Null
}

# Deploy a phpinfo page so the health check can prove PHP+IIS integration
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null
Set-Content -Path 'C:\inetpub\wwwroot\index.php' -Value '<?php phpinfo(); ?>'
Write-Output "deployed index.php (phpinfo)"

# Open the firewall for HTTP on TCP 80 (idempotent)
if (-not (Get-NetFirewallRule -DisplayName 'Allow HTTP 80' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Allow HTTP 80' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
    Write-Output "firewall rule for TCP 80 created"
}

# All-users desktop shortcut for IIS Manager (Public desktop always exists on first boot)
if (Test-Path $inetMgr) {
    $publicDesktop = Join-Path $env:PUBLIC 'Desktop'
    $lnk = Join-Path $publicDesktop 'IIS Manager.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $inetMgr
    $sc.Description = 'Internet Information Services (IIS) Manager'
    $sc.Save()
    Write-Output "created IIS Manager shortcut on the all-users desktop"
}

# Ensure IIS services run now and on every boot
foreach ($svc in 'WAS', 'W3SVC') {
    Set-Service $svc -StartupType Automatic
    if ((Get-Service $svc).Status -ne 'Running') { Start-Service $svc }
    Write-Output "service ${svc}: running and set to automatic"
}

# Recycle to pick up the new handler config
& $appcmd stop site "Default Web Site" 2>$null | Out-Null
& $appcmd start site "Default Web Site" 2>$null | Out-Null
Write-Output "IIS + PHP 8.5.9 FastCGI ready; PHP served at http://localhost/index.php"
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
$cleanupPath = Join-Path $cleanupDir 'windows-2025-cleanup.ps1'
[System.IO.File]::WriteAllBytes(
    $cleanupPath,
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyAgICAgICAgICAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChXaW5kb3dzIElJUyArIFBIUCAoRmFzdENHSSkpIGhhcyBiZWVuIGRlcGxveWVkIHN1Y2Nlc3NmdWxseSEgICAgICAgICAgICAjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIjICAgICAgICAgICAgQ3JlZGVudGlhbHMgKGlmIGFueSkgYXJlIHNob3duIGJlbG93IGFuZCBzdG9yZWQgb24gZGlzay4gICAgICAgICAgICAgICAgICAgICAgICAgICMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICJUaGlzIG1lc3NhZ2Ugd2lsbCBiZSByZW1vdmVkIGFmdGVyIHRoaXMgbG9naW4uIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIiCgoKIyBDbGVhbnVwIHRyYWNlcyBvZiB0aGUgZGVwbG95bWVudC4KUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlN5c3RlbURyaXZlXENsb3VkYmFzZUluaXRcbG9nXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpURU1QXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCkNsZWFyLUV2ZW50TG9nIC1Mb2dOYW1lIEFwcGxpY2F0aW9uLCBTeXN0ZW0gLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKCiMgR2l2ZSB0aGUgb3BlcmF0b3IgdGltZSB0byByZWFkIHRoZSBiYW5uZXIgYmVmb3JlIHRoZSB3aW5kb3cgY2xvc2VzIChpdCBydW5zIGluIHRoZWlyIHNlc3Npb24pLgpXcml0ZS1Ib3N0ICJUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDIwIHNlY29uZHMuIiAtRm9yZWdyb3VuZENvbG9yIFJlZApTdGFydC1TbGVlcCAtU2Vjb25kcyAyMAoKIyBVbnJlZ2lzdGVyIHRoZSBmaXJzdC1sb2dpbiBzY2hlZHVsZWQgdGFzayAocnVuLW9uY2Ugc2VtYW50aWNzKSArIGRlbGV0ZSB0aGlzIHNjcmlwdCBpdHNlbGYuClVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJ21hcmtnZW4td2luZG93cy0yMDI1LWNsZWFudXAnIC1Db25maXJtOiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQojIEFsc28gY2xlYXIgYW55IGxlZ2FjeSBSdW5PbmNlIGVudHJ5IGZyb20gb2xkZXIgaW5zdGFsbHMgKGhhcm1sZXNzIGlmIGFic2VudCkuClJlbW92ZS1JdGVtUHJvcGVydHkgLVBhdGggJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFJ1bk9uY2UnIC1OYW1lICd3aW5kb3dzLTIwMjVfY2xlYW51cCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLUZvcmNlICRQU0NvbW1hbmRQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCg==')
)
# The task name MUST match the name the cleanup script unregisters (markgen-windows-2025-cleanup).
$taskName = 'markgen-windows-2025-cleanup'
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
Unregister-ScheduledTask -TaskName 'markgen-windows-2025-installing' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $env:ProgramData 'markgen\windows-2025-installing.ps1') -ErrorAction SilentlyContinue

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
