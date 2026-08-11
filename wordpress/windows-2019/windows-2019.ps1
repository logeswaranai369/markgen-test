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
Write-Stage "install: WordPress on IIS (Windows) on win2019"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDE5LWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMTktc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDE5LWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAxOS1pbnN0YWxsLmRvbmUnCgojIEFuY2hvciBlbGFwc2VkIHRvIHRoZSBpbnN0YWxsJ3MgcmVjb3JkZWQgc3RhcnQgdGltZSBpZiBwcmVzZW50IChzbyB0aGUgdGltZXIgcmVmbGVjdHMgdGhlIHJlYWwKIyBpbnN0YWxsIGFnZSBldmVuIGlmIHRoZSBvcGVyYXRvciBsb2dnZWQgaW4gbGF0ZSksIGVsc2UgdG8gbm93Lgp0cnkgeyAkc3RhcnQgPSBbZGF0ZXRpbWVdOjpQYXJzZSgoR2V0LUNvbnRlbnQgLVJhdyAkc3RhcnRGaWxlKSkgfSBjYXRjaCB7ICRzdGFydCA9IEdldC1EYXRlIH0KCiRiYXIgPSAnIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMnCiMgUG9sbCB1bnRpbCB0aGUgaW5zdGFsbCBzaWduYWxzIGRvbmUsIHdpdGggYSBoYXJkIHNhZmV0eSBjYXAgc28gdGhpcyBjYW4gbmV2ZXIgc3BpbiBmb3JldmVyLgpmb3IgKCRpID0gMDsgJGkgLWx0IDkwMDsgJGkrKykgewogICAgJGRvbmUgPSBUZXN0LVBhdGggJGRvbmVGaWxlCiAgICAkc3RhZ2UgPSBpZiAoVGVzdC1QYXRoICRzdGF0dXNGaWxlKSB7IChHZXQtQ29udGVudCAtUmF3ICRzdGF0dXNGaWxlKS5UcmltKCkgfSBlbHNlIHsgJ1ByZXBhcmluZy4uLicgfQogICAgJGVsYXBzZWQgPSAoR2V0LURhdGUpIC0gJHN0YXJ0CiAgICAkbW0gPSBbaW50XSRlbGFwc2VkLlRvdGFsTWludXRlcwogICAgJHNzID0gJGVsYXBzZWQuU2Vjb25kcwoKICAgIENsZWFyLUhvc3QKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiMgICBZb3VyIE1hcmtldHBsYWNlIEFwcCAoV29yZFByZXNzIG9uIElJUyAoV2luZG93cykpIGlzIElOU1RBTExJTkcgLSBwbGVhc2Ugd2FpdC4iKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBpZiAoJGRvbmUpIHsKICAgICAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiBJbnN0YWxsIGNvbXBsZXRlLiIpIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICgiICBFbGFwc2VkOiB7MH1tIHsxOjAwfXMiIC1mICRtbSwgJHNzKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiIgogICAgICAgIFdyaXRlLUhvc3QgIiAgVGhlIGFwcCBpcyByZWFkeS4gVGhpcyB3aW5kb3cgd2lsbCBjbG9zZSBub3c7IGEgJ2RlcGxveWVkIHN1Y2Nlc3NmdWxseSciIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICIgIG1lc3NhZ2Ugd2l0aCBhbnkgY3JlZGVudGlhbHMgZm9sbG93cy4iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgYnJlYWsKICAgIH0KICAgIFdyaXRlLUhvc3QgKCIgIFN0YXR1cyA6IHswfSIgLWYgJHN0YWdlKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiIKICAgIFdyaXRlLUhvc3QgIiAgSW5zdGFsbGluZyBpbiB0aGUgYmFja2dyb3VuZCAoYSBmZXcgbWludXRlcyBvbiBhIGZyZXNoIFZNKS4gRG8gTk9UIHJlc3RhcnQgdGhlIFZNLiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiAgVGhpcyB3aW5kb3cgdXBkYXRlcyBldmVyeSBmZXcgc2Vjb25kcyBhbmQgY2xvc2VzIGF1dG9tYXRpY2FsbHkgd2hlbiB0aGUgYXBwIGlzIHJlYWR5LiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDMKfQo=')
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

# --- Generated secrets (created before install so tasks can reference them) ---
# Each secret is appended as a `name=value` line to its store file. Two guards learned live:
#  - Only create the PARENT directory when there IS one below the drive root: Split-Path -Parent
#    'C:\credentials.txt' is 'C:\', and New-Item -ItemType Directory -Path 'C:\' throws "The path is
#    not of a legal form" (you can't create a drive root). Skip the mkdir for a root-level file.
#  - APPEND (name=value), don't Set-Content: multiple secrets that share ONE store path (e.g. all to
#    C:\credentials.txt) would otherwise each overwrite it, leaving only the last. Clear each distinct
#    store file once (tracked below) so a re-run starts fresh, then append every secret.
$mgSecretFilesInit = @{}
$mariadb_root_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    Set-Content -Path 'C:\credentials.txt' -Value '' -NoNewline
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value "mariadb_root_password=$mariadb_root_password"
Write-Stage "install: stored secret mariadb_root_password at C:\credentials.txt"
$wp_db_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    Set-Content -Path 'C:\credentials.txt' -Value '' -NoNewline
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value "wp_db_password=$wp_db_password"
Write-Stage "install: stored secret wp_db_password at C:\credentials.txt"
$wp_admin_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    Set-Content -Path 'C:\credentials.txt' -Value '' -NoNewline
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value "wp_admin_password=$wp_admin_password"
Write-Stage "install: stored secret wp_admin_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing WordPress on IIS (Windows) and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$features = 'Web-Server','Web-Common-Http','Web-Static-Content','Web-Default-Doc','Web-Http-Errors','Web-Http-Logging','Web-Stat-Compression','Web-Filtering','Web-CGI','Web-Mgmt-Tools','Web-Mgmt-Console'
$missing = $features | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }
if ($missing) {
    Write-Output "installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing | Out-Null
} else {
    Write-Output "all required IIS features already installed"
}

# Helper: run a native EXE without its stderr aborting the script; verdict = exit code only.
function Invoke-Native {
    param([scriptblock]$Script)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Script 2>&1 | ForEach-Object { Write-Output $_ } }
    finally { $ErrorActionPreference = $old }
}

# --- Visual C++ 2015-2022 x64 runtime (required by php-cgi.exe / mysql binaries). Idempotent. ---
Write-Output "installing Visual C++ 2015-2022 x64 redistributable"
$vcPath = Join-Path $env:TEMP 'vc_redist.x64.exe'
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcPath -UseBasicParsing
Start-Process -FilePath $vcPath -ArgumentList '/install','/quiet','/norestart' -Wait

# --- PHP 8.2.33 NTS ---
$phpDir = 'C:\PHP'
if (-not (Test-Path (Join-Path $phpDir 'php-cgi.exe'))) {
    Write-Output "downloading and installing PHP 8.2.33 NTS"
    $phpZip = Join-Path $env:TEMP 'php.zip'
    $phpUrls = @(
        'https://windows.php.net/downloads/releases/php-8.2.33-nts-Win32-vs16-x64.zip',
        'https://windows.php.net/downloads/releases/archives/php-8.2.33-nts-Win32-vs16-x64.zip'
    )
    $ok = $false
    foreach ($u in $phpUrls) {
        try { Invoke-WebRequest -Uri $u -OutFile $phpZip -UseBasicParsing; $ok = $true; Write-Output "fetched PHP from $u"; break }
        catch { Write-Output "PHP download failed from ${u}: $($_.Exception.Message)" }
    }
    if (-not $ok) { throw "unable to download PHP 8.2.33 NTS" }
    New-Item -ItemType Directory -Force -Path $phpDir | Out-Null
    Expand-Archive -Path $phpZip -DestinationPath $phpDir -Force
} else {
    Write-Output "PHP already present at $phpDir"
}

# Configure php.ini (append overrides to avoid the php.ini-production uncomment-regex traps)
$phpIni = Join-Path $phpDir 'php.ini'
Copy-Item -Path (Join-Path $phpDir 'php.ini-production') -Destination $phpIni -Force
$phpIniBlock = @"

; ---- Markgen deployment settings ----
extension_dir = "C:\PHP\ext"
cgi.fix_pathinfo = 1
fastcgi.impersonate = 1
fastcgi.logging = 0
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
memory_limit = 256M
date.timezone = "UTC"
extension=mysqli
extension=gd
extension=mbstring
extension=curl
extension=openssl
extension=exif
extension=fileinfo
extension=zip
extension=intl
"@
Add-Content -Path $phpIni -Value $phpIniBlock
Write-Output "php.ini configured"

# --- Register PHP with IIS via FastCGI ---
$appcmd = 'C:\Windows\System32\inetsrv\appcmd.exe'
$phpCgi = Join-Path $phpDir 'php-cgi.exe'
Invoke-Native { & $appcmd set config /section:system.webServer/fastCgi "/+[fullPath='$phpCgi']" /commit:apphost }
Invoke-Native { & $appcmd set config /section:system.webServer/handlers "/+[name='PHP_via_FastCGI',path='*.php',verb='*',modules='FastCgiModule',scriptProcessor='$phpCgi',resourceType='Either']" /commit:apphost }
Invoke-Native { & $appcmd set config /section:system.webServer/defaultDocument "/+files.[value='index.php']" /commit:apphost }
Write-Output "PHP registered with IIS FastCGI"

# --- MariaDB 10.11.10 ---
$mariaMsi = Join-Path $env:TEMP 'mariadb.msi'
if (-not (Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue)) {
    Write-Output "downloading and installing MariaDB 10.11.10"
    Invoke-WebRequest -Uri 'https://archive.mariadb.org/mariadb-10.11.10/winx64-packages/mariadb-10.11.10-winx64.msi' -OutFile $mariaMsi -UseBasicParsing
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$mariaMsi`" SERVICENAME=MariaDB PORT=3306 PASSWORD=`"$mariadb_root_password`" /qn"
} else {
    Write-Output "MariaDB service already present"
}
Start-Service MariaDB
Set-Service MariaDB -StartupType Automatic
Write-Output "MariaDB service running"

# Locate mysql.exe
$mysqlExe = Get-ChildItem -Path 'C:\Program Files\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $mysqlExe) { throw "mysql.exe not found after MariaDB install" }

# --- Create WordPress database and user ---
$sql = @"
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'wpuser'@'127.0.0.1' IDENTIFIED BY '$wp_db_password';
CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY '$wp_db_password';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
"@
$sqlFile = Join-Path $env:TEMP 'wp_setup.sql'
Set-Content -Path $sqlFile -Value $sql -Encoding ASCII
Write-Output "creating WordPress database and user"
Invoke-Native { & $mysqlExe "--user=root" "--password=$mariadb_root_password" "--execute=source $sqlFile" }
if ($LASTEXITCODE -ne 0) { throw "failed to create WordPress database (mysql exit $LASTEXITCODE)" }
Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue

# --- Deploy WordPress files ---
$wwwroot = 'C:\inetpub\wwwroot'
if (-not (Test-Path (Join-Path $wwwroot 'wp-load.php'))) {
    Write-Output "downloading and extracting WordPress"
    $wpZip = Join-Path $env:TEMP 'wordpress.zip'
    Invoke-WebRequest -Uri 'https://wordpress.org/latest.zip' -OutFile $wpZip -UseBasicParsing
    $wpTmp = Join-Path $env:TEMP 'wp_extract'
    if (Test-Path $wpTmp) { Remove-Item $wpTmp -Recurse -Force }
    Expand-Archive -Path $wpZip -DestinationPath $wpTmp -Force
    New-Item -ItemType Directory -Force -Path $wwwroot | Out-Null
    Get-ChildItem -Path $wwwroot -Force | Where-Object { $_.Name -eq 'index.html' -or $_.Name -eq 'iisstart.htm' -or $_.Name -eq 'iisstart.png' } | Remove-Item -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $wpTmp 'wordpress\*') -Destination $wwwroot -Recurse -Force
} else {
    Write-Output "WordPress files already present"
}

# Grant IIS the ability to read/write the site (uploads, etc.)
Invoke-Native { & icacls $wwwroot /grant "IIS_IUSRS:(OI)(CI)(M)" /T /C }

# --- Write wp-config.php inline with real values + fresh salts ---
$wpConfigPath = Join-Path $wwwroot 'wp-config.php'
$oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try { $salts = (Invoke-WebRequest -Uri 'https://api.wordpress.org/secret-key/1.1/salt/' -UseBasicParsing).Content }
catch { $salts = "define('AUTH_KEY','$([guid]::NewGuid())');`ndefine('SECURE_AUTH_KEY','$([guid]::NewGuid())');`ndefine('LOGGED_IN_KEY','$([guid]::NewGuid())');`ndefine('NONCE_KEY','$([guid]::NewGuid())');`ndefine('AUTH_SALT','$([guid]::NewGuid())');`ndefine('SECURE_AUTH_SALT','$([guid]::NewGuid())');`ndefine('LOGGED_IN_SALT','$([guid]::NewGuid())');`ndefine('NONCE_SALT','$([guid]::NewGuid())');" }
finally { $ErrorActionPreference = $oldEap }

$wpConfig = @"
<?php
define('DB_NAME', 'wordpress');
define('DB_USER', 'wpuser');
define('DB_PASSWORD', '$wp_db_password');
define('DB_HOST', '127.0.0.1');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

$salts

`$table_prefix = 'wp_';

if (isset(`$_SERVER['HTTP_HOST']) && !empty(`$_SERVER['HTTP_HOST'])) {
    define('WP_HOME', 'http://' . `$_SERVER['HTTP_HOST']);
    define('WP_SITEURL', 'http://' . `$_SERVER['HTTP_HOST']);
}

define('WP_DEBUG', false);

if ( !defined('ABSPATH') ) {
    define('ABSPATH', __DIR__ . '/');
}
require_once ABSPATH . 'wp-settings.php';
"@
Set-Content -Path $wpConfigPath -Value $wpConfig -Encoding UTF8
Write-Output "wp-config.php written"

# --- Run the WordPress core install via wp-cli so wp-login.php returns 200 ---
$phpExe = Join-Path $phpDir 'php.exe'
$wpCli = Join-Path $env:TEMP 'wp-cli.phar'
if (-not (Test-Path $wpCli)) {
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar' -OutFile $wpCli -UseBasicParsing
}

$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try {
    & $phpExe $wpCli --path="$wwwroot" core is-installed --allow-root 2>&1 | Out-Null
    $alreadyInstalled = ($LASTEXITCODE -eq 0)
    if (-not $alreadyInstalled) {
        Write-Output "running WordPress core install"
        & $phpExe $wpCli --path="$wwwroot" core install `
            --url="http://localhost" `
            --title="WordPress" `
            --admin_user="admin" `
            --admin_password="$wp_admin_password" `
            --admin_email="admin@example.com" `
            --skip-email --allow-root 2>&1 | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0) { throw "wp core install failed (exit $LASTEXITCODE)" }
    } else {
        Write-Output "WordPress already installed"
    }
}
finally { $ErrorActionPreference = $eap }

# --- Ensure IIS is running and starts on boot ---
Start-Service W3SVC
Set-Service W3SVC -StartupType Automatic
Write-Output "IIS (W3SVC) running"

# --- All-users desktop shortcuts ---
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
New-Item -ItemType Directory -Force -Path $publicDesktop | Out-Null

$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
if (Test-Path $inetMgr) {
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut((Join-Path $publicDesktop 'IIS Manager.lnk'))
    $sc.TargetPath = $inetMgr
    $sc.Description = 'Internet Information Services (IIS) Manager'
    $sc.Save()
    Write-Output "created IIS Manager desktop shortcut"
}

$wpUrl = @"
[InternetShortcut]
URL=http://localhost/wp-admin/
"@
Set-Content -Path (Join-Path $publicDesktop 'WordPress Admin.url') -Value $wpUrl -Encoding ASCII
Write-Output "created WordPress Admin desktop shortcut"

Write-Output "WordPress on IIS deployment complete"
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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyAgICAgICAgICAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChXb3JkUHJlc3Mgb24gSUlTIChXaW5kb3dzKSkgaGFzIGJlZW4gZGVwbG95ZWQgc3VjY2Vzc2Z1bGx5ISAgICAgICAgICAgICMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiMgICAgICAgICAgICBDcmVkZW50aWFscyAoaWYgYW55KSBhcmUgc2hvd24gYmVsb3cgYW5kIHN0b3JlZCBvbiBkaXNrLiAgICAgICAgICAgICAgICAgICAgICAgICAgIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIiCldyaXRlLUhvc3QgIlRoaXMgbWVzc2FnZSB3aWxsIGJlIHJlbW92ZWQgYWZ0ZXIgdGhpcyBsb2dpbi4iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiIKCldyaXRlLUhvc3QgIkNyZWRlbnRpYWw6IG1hcmlhZGJfcm9vdF9wYXNzd29yZCAoc3RvcmVkIGF0IEM6XGNyZWRlbnRpYWxzLnR4dCkiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCmlmIChUZXN0LVBhdGggJ0M6XGNyZWRlbnRpYWxzLnR4dCcpIHsgR2V0LUNvbnRlbnQgJ0M6XGNyZWRlbnRpYWxzLnR4dCcgfQpXcml0ZS1Ib3N0ICIiCldyaXRlLUhvc3QgIkNyZWRlbnRpYWw6IHdwX2RiX3Bhc3N3b3JkIChzdG9yZWQgYXQgQzpcY3JlZGVudGlhbHMudHh0KSIgLUZvcmVncm91bmRDb2xvciBSZWQKaWYgKFRlc3QtUGF0aCAnQzpcY3JlZGVudGlhbHMudHh0JykgeyBHZXQtQ29udGVudCAnQzpcY3JlZGVudGlhbHMudHh0JyB9CldyaXRlLUhvc3QgIiIKV3JpdGUtSG9zdCAiQ3JlZGVudGlhbDogd3BfYWRtaW5fcGFzc3dvcmQgKHN0b3JlZCBhdCBDOlxjcmVkZW50aWFscy50eHQpIiAtRm9yZWdyb3VuZENvbG9yIFJlZAppZiAoVGVzdC1QYXRoICdDOlxjcmVkZW50aWFscy50eHQnKSB7IEdldC1Db250ZW50ICdDOlxjcmVkZW50aWFscy50eHQnIH0KV3JpdGUtSG9zdCAiIgoKIyBDbGVhbnVwIHRyYWNlcyBvZiB0aGUgZGVwbG95bWVudC4KUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlN5c3RlbURyaXZlXENsb3VkYmFzZUluaXRcbG9nXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpURU1QXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCkNsZWFyLUV2ZW50TG9nIC1Mb2dOYW1lIEFwcGxpY2F0aW9uLCBTeXN0ZW0gLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKCiMgR2l2ZSB0aGUgb3BlcmF0b3IgdGltZSB0byByZWFkIHRoZSBiYW5uZXIgYmVmb3JlIHRoZSB3aW5kb3cgY2xvc2VzIChpdCBydW5zIGluIHRoZWlyIHNlc3Npb24pLgpXcml0ZS1Ib3N0ICJUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDIwIHNlY29uZHMuIiAtRm9yZWdyb3VuZENvbG9yIFJlZApTdGFydC1TbGVlcCAtU2Vjb25kcyAyMAoKIyBVbnJlZ2lzdGVyIHRoZSBmaXJzdC1sb2dpbiBzY2hlZHVsZWQgdGFzayAocnVuLW9uY2Ugc2VtYW50aWNzKSArIGRlbGV0ZSB0aGlzIHNjcmlwdCBpdHNlbGYuClVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJ21hcmtnZW4td2luZG93cy0yMDE5LWNsZWFudXAnIC1Db25maXJtOiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQojIEFsc28gY2xlYXIgYW55IGxlZ2FjeSBSdW5PbmNlIGVudHJ5IGZyb20gb2xkZXIgaW5zdGFsbHMgKGhhcm1sZXNzIGlmIGFic2VudCkuClJlbW92ZS1JdGVtUHJvcGVydHkgLVBhdGggJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFJ1bk9uY2UnIC1OYW1lICd3aW5kb3dzLTIwMTlfY2xlYW51cCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLUZvcmNlICRQU0NvbW1hbmRQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCg==')
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
