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
$mgStatusFile = Join-Path $mgStatusDir 'windows-2022-status.txt'
$mgStartFile  = Join-Path $mgStatusDir 'windows-2022-install.start'
$mgDoneFile   = Join-Path $mgStatusDir 'windows-2022-install.done'
Remove-Item $mgDoneFile -Force -ErrorAction SilentlyContinue
Set-Content -Path $mgStartFile -Value (Get-Date -Format o) -Encoding ASCII
function Set-Status($msg) { try { Set-Content -Path $mgStatusFile -Value $msg -Encoding ASCII } catch {} }
function Write-Stage($msg) { Write-Output "[markgen] $msg"; Set-Status $msg }

Set-Status 'Starting install...'
Write-Stage "install: WordPress on IIS (Windows) on win2022"

# --- First-login "install in progress" notice (shown ONLY while installing) ---
# The install runs as SYSTEM on first boot and can take several minutes on a slow VM. An operator
# who RDPs in during that window would otherwise see a bare desktop and think it's broken (seen
# live). Register a scheduled task NOW (before the long install work) that shows a "still installing,
# please wait" banner in the interactive session; if a session is already active, fire it now. The
# END of this script unregisters it, so it only appears while the install is genuinely running.
$notifyDir = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $notifyDir | Out-Null
$notifyPath = Join-Path $notifyDir 'windows-2022-installing.ps1'
[System.IO.File]::WriteAllBytes(
    $notifyPath,
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDIyLWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjItc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDIyLWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyMi1pbnN0YWxsLmRvbmUnCgojIEFuY2hvciBlbGFwc2VkIHRvIHRoZSBpbnN0YWxsJ3MgcmVjb3JkZWQgc3RhcnQgdGltZSBpZiBwcmVzZW50IChzbyB0aGUgdGltZXIgcmVmbGVjdHMgdGhlIHJlYWwKIyBpbnN0YWxsIGFnZSBldmVuIGlmIHRoZSBvcGVyYXRvciBsb2dnZWQgaW4gbGF0ZSksIGVsc2UgdG8gbm93Lgp0cnkgeyAkc3RhcnQgPSBbZGF0ZXRpbWVdOjpQYXJzZSgoR2V0LUNvbnRlbnQgLVJhdyAkc3RhcnRGaWxlKSkgfSBjYXRjaCB7ICRzdGFydCA9IEdldC1EYXRlIH0KCiRiYXIgPSAnIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMnCiMgUG9sbCB1bnRpbCB0aGUgaW5zdGFsbCBzaWduYWxzIGRvbmUsIHdpdGggYSBoYXJkIHNhZmV0eSBjYXAgc28gdGhpcyBjYW4gbmV2ZXIgc3BpbiBmb3JldmVyLgpmb3IgKCRpID0gMDsgJGkgLWx0IDkwMDsgJGkrKykgewogICAgJGRvbmUgPSBUZXN0LVBhdGggJGRvbmVGaWxlCiAgICAkc3RhZ2UgPSBpZiAoVGVzdC1QYXRoICRzdGF0dXNGaWxlKSB7IChHZXQtQ29udGVudCAtUmF3ICRzdGF0dXNGaWxlKS5UcmltKCkgfSBlbHNlIHsgJ1ByZXBhcmluZy4uLicgfQogICAgJGVsYXBzZWQgPSAoR2V0LURhdGUpIC0gJHN0YXJ0CiAgICAkbW0gPSBbaW50XSRlbGFwc2VkLlRvdGFsTWludXRlcwogICAgJHNzID0gJGVsYXBzZWQuU2Vjb25kcwoKICAgIENsZWFyLUhvc3QKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiMgICBZb3VyIE1hcmtldHBsYWNlIEFwcCAoV29yZFByZXNzIG9uIElJUyAoV2luZG93cykpIGlzIElOU1RBTExJTkcgLSBwbGVhc2Ugd2FpdC4iKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBpZiAoJGRvbmUpIHsKICAgICAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiBJbnN0YWxsIGNvbXBsZXRlLiIpIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICgiICBFbGFwc2VkOiB7MH1tIHsxOjAwfXMiIC1mICRtbSwgJHNzKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiIgogICAgICAgIFdyaXRlLUhvc3QgIiAgVGhlIGFwcCBpcyByZWFkeS4gVGhpcyB3aW5kb3cgd2lsbCBjbG9zZSBub3c7IGEgJ2RlcGxveWVkIHN1Y2Nlc3NmdWxseSciIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICIgIG1lc3NhZ2Ugd2l0aCBhbnkgY3JlZGVudGlhbHMgZm9sbG93cy4iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgYnJlYWsKICAgIH0KICAgIFdyaXRlLUhvc3QgKCIgIFN0YXR1cyA6IHswfSIgLWYgJHN0YWdlKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiIKICAgIFdyaXRlLUhvc3QgIiAgSW5zdGFsbGluZyBpbiB0aGUgYmFja2dyb3VuZCAoYSBmZXcgbWludXRlcyBvbiBhIGZyZXNoIFZNKS4gRG8gTk9UIHJlc3RhcnQgdGhlIFZNLiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiAgVGhpcyB3aW5kb3cgdXBkYXRlcyBldmVyeSBmZXcgc2Vjb25kcyBhbmQgY2xvc2VzIGF1dG9tYXRpY2FsbHkgd2hlbiB0aGUgYXBwIGlzIHJlYWR5LiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDMKfQo=')
)
$notifyTask = 'markgen-windows-2022-installing'
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
# Each secret is written as a readable "Friendly Label : value" line under a titled header, so the
# operator opening the file (e.g. in Notepad) sees a clear credentials document, not terse key=value
# machine keys. Guards learned live:
#  - Only create the PARENT directory when there IS one below the drive root: Split-Path -Parent
#    'C:\credentials.txt' is 'C:\', and New-Item -ItemType Directory -Path 'C:\' throws "The path is
#    not of a legal form" (you can't create a drive root). Skip the mkdir for a root-level file.
#  - APPEND, don't Set-Content per secret: multiple secrets that share ONE store path (e.g. all to
#    C:\credentials.txt) would otherwise each overwrite it, leaving only the last. Write the header
#    once per distinct store file (tracked below), then append every secret's labeled line.
$mgSecretFilesInit = @{}
$mariadb_root_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  WordPress on IIS (Windows) - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Mariadb Root Password", $mariadb_root_password)
Write-Stage "install: stored secret mariadb_root_password at C:\credentials.txt"
$wordpress_db_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  WordPress on IIS (Windows) - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Wordpress Db Password", $wordpress_db_password)
Write-Stage "install: stored secret wordpress_db_password at C:\credentials.txt"
$wordpress_admin_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  WordPress on IIS (Windows) - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Wordpress Admin Password", $wordpress_admin_password)
Write-Stage "install: stored secret wordpress_admin_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing WordPress on IIS (Windows) and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$needed = 'Web-Server','Web-CGI','Web-Common-Http','Web-Default-Doc','Web-Static-Content','Web-Http-Errors','Web-Http-Logging','Web-Request-Monitor','Web-Mgmt-Console','Web-Mgmt-Tools'
$missing = $needed | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }
if ($missing) {
    Write-Output "installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing | Out-Null
}
Write-Output "IIS features installed"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Visual C++ 2015-2022 x64 runtime (required by php-cgi.exe) - install unconditionally ---
$vcExe = Join-Path $env:TEMP 'vc_redist.x64.exe'
Write-Output "downloading VC++ 2015-2022 x64 redistributable"
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcExe -UseBasicParsing
Start-Process -FilePath $vcExe -ArgumentList '/install','/quiet','/norestart' -Wait
Write-Output "VC++ runtime installed/updated"

# --- PHP 8.3.33 NTS -> C:\PHP ---
if (-not (Test-Path 'C:\PHP\php-cgi.exe')) {
    $phpZip = Join-Path $env:TEMP 'php.zip'
    Write-Output "downloading PHP 8.3.33 NTS"
    try {
        Invoke-WebRequest -Uri 'https://windows.php.net/downloads/releases/php-8.3.33-nts-Win32-vs16-x64.zip' -OutFile $phpZip -UseBasicParsing
    } catch {
        Invoke-WebRequest -Uri 'https://windows.php.net/downloads/releases/archives/php-8.3.33-nts-Win32-vs16-x64.zip' -OutFile $phpZip -UseBasicParsing
    }
    New-Item -ItemType Directory -Force -Path 'C:\PHP' | Out-Null
    Expand-Archive -Path $phpZip -DestinationPath 'C:\PHP' -Force
    Write-Output "PHP extracted to C:\PHP"
}

# --- Build php.ini from php.ini-production ---
Write-Output "configuring C:\PHP\php.ini"
Copy-Item 'C:\PHP\php.ini-production' 'C:\PHP\php.ini' -Force
$wantExt = 'mysqli','openssl','mbstring','curl','gd','exif','fileinfo','intl','sodium'
$seen = @{}
$iniLines = Get-Content 'C:\PHP\php.ini'
$outLines = New-Object System.Collections.Generic.List[string]
foreach ($line in $iniLines) {
    $m = [regex]::Match($line.Trim(), '^;?\s*extension\s*=\s*"?([a-z0-9_]+)"?')
    if ($m.Success -and ($wantExt -contains $m.Groups[1].Value)) {
        $name = $m.Groups[1].Value
        if ($seen.ContainsKey($name)) { continue }
        $seen[$name] = $true
        $outLines.Add("extension=$name")
        continue
    }
    $outLines.Add($line)
}
$outLines.Add('')
$outLines.Add('; --- Markgen overrides ---')
$outLines.Add('extension_dir = "C:\PHP\ext"')
$outLines.Add('cgi.fix_pathinfo=1')
$outLines.Add('upload_max_filesize=64M')
$outLines.Add('post_max_size=64M')
$outLines.Add('max_execution_time=300')
$outLines.Add('date.timezone=UTC')
[System.IO.File]::WriteAllLines('C:\PHP\php.ini', $outLines)
Write-Output "php.ini written"

# --- MariaDB 11.4.7 ---
if (-not (Get-Service -Name MariaDB -ErrorAction SilentlyContinue)) {
    $msi = Join-Path $env:TEMP 'mariadb.msi'
    Write-Output "downloading MariaDB 11.4.7 MSI"
    Invoke-WebRequest -Uri 'https://archive.mariadb.org/mariadb-11.4.7/winx64-packages/mariadb-11.4.7-winx64.msi' -OutFile $msi -UseBasicParsing
    Write-Output "installing MariaDB (service name MariaDB)"
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msi`" SERVICENAME=MariaDB PASSWORD=`"$mariadb_root_password`" /qn"
}
Start-Service MariaDB -ErrorAction SilentlyContinue
Set-Service MariaDB -StartupType Automatic
Write-Output "MariaDB service running"

# locate mysql client
$mysql = (Get-ChildItem 'C:\Program Files\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (-not $mysql) { throw "mysql.exe not found after MariaDB install" }

# wait for MariaDB to accept connections
$ready = $false
for ($i=0; $i -lt 30 -and -not $ready; $i++) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $mysql --user=root --password="$mariadb_root_password" -e 'SELECT 1;' 2>$null | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -eq 0) { $ready = $true } else { Start-Sleep -Seconds 2 }
}
if (-not $ready) { throw "MariaDB did not become ready" }

# --- create WordPress database + user ---
Write-Output "creating WordPress database and user"
$sql = "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; " +
       "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY '$wordpress_db_password'; " +
       "ALTER USER 'wpuser'@'localhost' IDENTIFIED BY '$wordpress_db_password'; " +
       "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost'; FLUSH PRIVILEGES;"
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $mysql --user=root --password="$mariadb_root_password" -e $sql 2>$null
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($code -ne 0) { throw "failed to create WordPress database (exit $code)" }
Write-Output "database ready"

# --- WordPress files ---
if (-not (Test-Path 'C:\inetpub\wordpress\wp-load.php')) {
    $wpZip = Join-Path $env:TEMP 'wordpress.zip'
    Write-Output "downloading WordPress"
    Invoke-WebRequest -Uri 'https://wordpress.org/latest.zip' -OutFile $wpZip -UseBasicParsing
    Expand-Archive -Path $wpZip -DestinationPath 'C:\inetpub' -Force
    Write-Output "WordPress extracted to C:\inetpub\wordpress"
}

# grant IIS_IUSRS rights on the site (FS_METHOD direct + uploads)
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
icacls 'C:\inetpub\wordpress' /grant 'IIS_IUSRS:(OI)(CI)(M)' /T 2>$null | Out-Null
$ErrorActionPreference = $prev

# --- wp-config.php (literal string replacement only, no -replace on PHP $) ---
Write-Output "writing wp-config.php"
$sample = Get-Content 'C:\inetpub\wordpress\wp-config-sample.php' -Raw
$sample = $sample.Replace('database_name_here','wordpress')
$sample = $sample.Replace('username_here','wpuser')
$sample = $sample.Replace('password_here', $wordpress_db_password)
$sample = $sample.Replace("define( 'DB_CHARSET', 'utf8' )","define( 'DB_CHARSET', 'utf8mb4' )")

# strip the sample salt defines
$saltNames = 'AUTH_KEY','SECURE_AUTH_KEY','LOGGED_IN_KEY','NONCE_KEY','AUTH_SALT','SECURE_AUTH_SALT','LOGGED_IN_SALT','NONCE_SALT'
$kept = foreach ($l in ($sample -split "`r?`n")) {
    $skip = $false
    foreach ($n in $saltNames) { if ($l.Contains("'$n'")) { $skip = $true; break } }
    if (-not $skip) { $l }
}
$sample = ($kept -join "`r`n")

# fetch fresh salts
$saltText = (Invoke-WebRequest -Uri 'https://api.wordpress.org/secret-key/1.1/salt/' -UseBasicParsing).Content

$phpBlock = @'
if ( isset($_SERVER['HTTP_HOST']) ) {
    $mg_scheme = ( ( isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ) || ( isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) ) ? 'https' : 'http';
    define( 'WP_HOME', $mg_scheme . '://' . $_SERVER['HTTP_HOST'] );
    define( 'WP_SITEURL', $mg_scheme . '://' . $_SERVER['HTTP_HOST'] );
}
define( 'FS_METHOD', 'direct' );
'@

$inject = $saltText + "`r`n" + $phpBlock + "`r`n`r`n/* That's all, stop editing! Happy publishing. */"
$sample = $sample.Replace("/* That's all, stop editing! Happy publishing. */", $inject)
[System.IO.File]::WriteAllText('C:\inetpub\wordpress\wp-config.php', $sample)
Write-Output "wp-config.php written (no BOM)"

# --- point Default Web Site at WordPress + configure PHP FastCGI ---
$appcmd = 'C:\Windows\System32\inetsrv\appcmd.exe'
$phpCgi = 'C:\PHP\php-cgi.exe'
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $appcmd set vdir 'Default Web Site/' /physicalPath:'C:\inetpub\wordpress' 2>$null | Out-Null
& $appcmd set config /section:system.webServer/fastCgi "/+[fullPath='$phpCgi',arguments='',maxInstances='4',instanceMaxRequests='10000']" /commit:apphost 2>$null | Out-Null
& $appcmd set config /section:system.webServer/handlers "/+[name='PHP_via_FastCGI',path='*.php',verb='*',modules='FastCgiModule',scriptProcessor='$phpCgi',resourceType='Either',requireAccess='Script']" /commit:apphost 2>$null | Out-Null
& $appcmd set config /section:system.webServer/defaultDocument "/+files.[value='index.php']" /commit:apphost 2>$null | Out-Null
$ErrorActionPreference = $prev
Write-Output "IIS site + PHP FastCGI handler configured"

# --- firewall ---
if (-not (Get-NetFirewallRule -DisplayName 'WordPress HTTP 80' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'WordPress HTTP 80' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
    Write-Output "firewall rule for TCP 80 added"
}

# --- ensure IIS running ---
Start-Service W3SVC
Set-Service W3SVC -StartupType Automatic
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
iisreset /restart 2>$null | Out-Null
$ErrorActionPreference = $prev
Start-Sleep -Seconds 5
Write-Output "IIS running"

# --- complete WordPress install via HTTP POST ---
Write-Output "running WordPress install wizard via HTTP POST"
$installBody = @{
    weblog_title       = 'WordPress'
    user_name          = 'admin'
    admin_password     = $wordpress_admin_password
    admin_password2    = $wordpress_admin_password
    pw_weak            = 'on'
    admin_email        = 'admin@example.com'
    Submit             = 'Install WordPress'
    language           = ''
}
$installed = $false
for ($i=0; $i -lt 20 -and -not $installed; $i++) {
    try {
        Invoke-WebRequest -Uri 'http://localhost/wp-admin/install.php?step=2' -Method POST -Body $installBody -UseBasicParsing -TimeoutSec 60 | Out-Null
        $login = Invoke-WebRequest -Uri 'http://localhost/wp-login.php' -UseBasicParsing -TimeoutSec 60
        if ($login.StatusCode -eq 200 -and $login.Content -match 'Log In') { $installed = $true }
    } catch {
        Start-Sleep -Seconds 5
    }
}
if ($installed) {
    Write-Output "WordPress install completed; wp-login.php returns login page"
} else {
    Write-Output "WARNING: WordPress install POST did not confirm login page"
}

# --- all-users desktop shortcuts ---
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
$wsh = New-Object -ComObject WScript.Shell

$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
if (Test-Path $inetMgr) {
    $sc = $wsh.CreateShortcut((Join-Path $publicDesktop 'IIS Manager.lnk'))
    $sc.TargetPath = $inetMgr
    $sc.Description = 'Internet Information Services (IIS) Manager'
    $sc.Save()
    Write-Output "created IIS Manager desktop shortcut"
}

$adminUrl = Join-Path $publicDesktop 'WordPress Admin.url'
[System.IO.File]::WriteAllText($adminUrl, "[InternetShortcut]`r`nURL=http://localhost/wp-admin/`r`n")
Write-Output "created WordPress Admin desktop shortcut"
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
$cleanupPath = Join-Path $cleanupDir 'windows-2022-cleanup.ps1'
[System.IO.File]::WriteAllBytes(
    $cleanupPath,
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiAgU1VDQ0VTUyAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKFdvcmRQcmVzcyBvbiBJSVMgKFdpbmRvd3MpKSBoYXMgYmVlbiBkZXBsb3llZCBzdWNjZXNzZnVsbHkhIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiIKV3JpdGUtSG9zdCAiICBDcmVkZW50aWFscyBmb3IgdGhpcyBkZXBsb3ltZW50IChhbHNvIHNhdmVkIG9uIGRpc2spOiIgLUZvcmVncm91bmRDb2xvciBDeWFuCldyaXRlLUhvc3QgIiIKaWYgKFRlc3QtUGF0aCAnQzpcY3JlZGVudGlhbHMudHh0JykgewogICAgV3JpdGUtSG9zdCAiICBDOlxjcmVkZW50aWFscy50eHQiIC1Gb3JlZ3JvdW5kQ29sb3IgRGFya0dyYXkKICAgIEdldC1Db250ZW50ICdDOlxjcmVkZW50aWFscy50eHQnIHwgRm9yRWFjaC1PYmplY3QgeyBpZiAoJF8uVHJpbSgpKSB7IFdyaXRlLUhvc3QgIiAgICAkXyIgLUZvcmVncm91bmRDb2xvciBXaGl0ZSB9IH0KICAgIFdyaXRlLUhvc3QgIiIKfQpXcml0ZS1Ib3N0ICIgIFRoaXMgYmFubmVyIGFwcGVhcnMgb25jZSBhbmQgaXMgcmVtb3ZlZCBhZnRlciB0aGlzIGxvZ2luLiIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQpXcml0ZS1Ib3N0ICIiCgojIENsZWFudXAgdHJhY2VzIG9mIHRoZSBkZXBsb3ltZW50LgpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6U3lzdGVtRHJpdmVcQ2xvdWRiYXNlSW5pdFxsb2dcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlRFTVBcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKQ2xlYXItRXZlbnRMb2cgLUxvZ05hbWUgQXBwbGljYXRpb24sIFN5c3RlbSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQoKIyBHaXZlIHRoZSBvcGVyYXRvciB0aW1lIHRvIHJlYWQgdGhlIGJhbm5lciBiZWZvcmUgdGhlIHdpbmRvdyBjbG9zZXMgKGl0IHJ1bnMgaW4gdGhlaXIgc2Vzc2lvbikuCldyaXRlLUhvc3QgIiAgVGhpcyB3aW5kb3cgd2lsbCBjbG9zZSBpbiAyMCBzZWNvbmRzLiIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQpTdGFydC1TbGVlcCAtU2Vjb25kcyAyMAoKIyBVbnJlZ2lzdGVyIHRoZSBmaXJzdC1sb2dpbiBzY2hlZHVsZWQgdGFzayAocnVuLW9uY2Ugc2VtYW50aWNzKSArIGRlbGV0ZSB0aGlzIHNjcmlwdCBpdHNlbGYuClVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJ21hcmtnZW4td2luZG93cy0yMDIyLWNsZWFudXAnIC1Db25maXJtOiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQojIEFsc28gY2xlYXIgYW55IGxlZ2FjeSBSdW5PbmNlIGVudHJ5IGZyb20gb2xkZXIgaW5zdGFsbHMgKGhhcm1sZXNzIGlmIGFic2VudCkuClJlbW92ZS1JdGVtUHJvcGVydHkgLVBhdGggJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFJ1bk9uY2UnIC1OYW1lICd3aW5kb3dzLTIwMjJfY2xlYW51cCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLUZvcmNlICRQU0NvbW1hbmRQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCg==')
)
# The task name MUST match the name the cleanup script unregisters (markgen-windows-2022-cleanup).
$taskName = 'markgen-windows-2022-cleanup'
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
Unregister-ScheduledTask -TaskName 'markgen-windows-2022-installing' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $env:ProgramData 'markgen\windows-2022-installing.ps1') -ErrorAction SilentlyContinue

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
