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
Write-Stage "install: MySQL Community Server on win2022"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDIyLWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjItc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDIyLWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyMi1pbnN0YWxsLmRvbmUnCgojIElmIHRoZSBpbnN0YWxsIGFscmVhZHkgZmluaXNoZWQsIGV4aXQgaW1tZWRpYXRlbHkuIFRoZSBub3RpY2UgdGFzayBub3cgaGFzIGEgcmVwZWF0aW5nIHRyaWdnZXIsIHNvCiMgYSB0aWNrIGNhbiBmaXJlIGluIHRoZSBicmllZiBnYXAgYmV0d2VlbiB0aGUgaW5zdGFsbCBzZXR0aW5nIC5kb25lIGFuZCB0aGUgRU5EIG9mIHRoZSBpbnN0YWxsIHNjcmlwdAojIHVucmVnaXN0ZXJpbmcgdGhlIHRhc2sgLSB3aXRob3V0IHRoaXMgZ3VhcmQgdGhhdCB0aWNrIHdvdWxkIGZsYXNoIGEgc3RhbGUgImluc3RhbGxpbmciIHdpbmRvdy4KaWYgKFRlc3QtUGF0aCAkZG9uZUZpbGUpIHsgcmV0dXJuIH0KCiMgQW5jaG9yIGVsYXBzZWQgdG8gdGhlIGluc3RhbGwncyByZWNvcmRlZCBzdGFydCB0aW1lIGlmIHByZXNlbnQgKHNvIHRoZSB0aW1lciByZWZsZWN0cyB0aGUgcmVhbAojIGluc3RhbGwgYWdlIGV2ZW4gaWYgdGhlIG9wZXJhdG9yIGxvZ2dlZCBpbiBsYXRlKSwgZWxzZSB0byBub3cuCnRyeSB7ICRzdGFydCA9IFtkYXRldGltZV06OlBhcnNlKChHZXQtQ29udGVudCAtUmF3ICRzdGFydEZpbGUpKSB9IGNhdGNoIHsgJHN0YXJ0ID0gR2V0LURhdGUgfQoKJGJhciA9ICcjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIycKIyBQb2xsIHVudGlsIHRoZSBpbnN0YWxsIHNpZ25hbHMgZG9uZSwgd2l0aCBhIGhhcmQgc2FmZXR5IGNhcCBzbyB0aGlzIGNhbiBuZXZlciBzcGluIGZvcmV2ZXIuCmZvciAoJGkgPSAwOyAkaSAtbHQgOTAwOyAkaSsrKSB7CiAgICAkZG9uZSA9IFRlc3QtUGF0aCAkZG9uZUZpbGUKICAgICRzdGFnZSA9IGlmIChUZXN0LVBhdGggJHN0YXR1c0ZpbGUpIHsgKEdldC1Db250ZW50IC1SYXcgJHN0YXR1c0ZpbGUpLlRyaW0oKSB9IGVsc2UgeyAnUHJlcGFyaW5nLi4uJyB9CiAgICAkZWxhcHNlZCA9IChHZXQtRGF0ZSkgLSAkc3RhcnQKICAgICRtbSA9IFtpbnRdJGVsYXBzZWQuVG90YWxNaW51dGVzCiAgICAkc3MgPSAkZWxhcHNlZC5TZWNvbmRzCgogICAgQ2xlYXItSG9zdAogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICgiIyAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChNeVNRTCBDb21tdW5pdHkgU2VydmVyKSBpcyBJTlNUQUxMSU5HIC0gcGxlYXNlIHdhaXQuIikgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiIgogICAgaWYgKCRkb25lKSB7CiAgICAgICAgV3JpdGUtSG9zdCAoIiAgU3RhdHVzIDogSW5zdGFsbCBjb21wbGV0ZS4iKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgIiIKICAgICAgICBXcml0ZS1Ib3N0ICIgIFRoZSBhcHAgaXMgcmVhZHkuIFRoaXMgd2luZG93IHdpbGwgY2xvc2Ugbm93OyBhICdkZXBsb3llZCBzdWNjZXNzZnVsbHknIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiICBtZXNzYWdlIHdpdGggYW55IGNyZWRlbnRpYWxzIGZvbGxvd3MuIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgICAgIGJyZWFrCiAgICB9CiAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiB7MH0iIC1mICRzdGFnZSkgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgKCIgIEVsYXBzZWQ6IHswfW0gezE6MDB9cyIgLWYgJG1tLCAkc3MpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBXcml0ZS1Ib3N0ICIgIEluc3RhbGxpbmcgaW4gdGhlIGJhY2tncm91bmQgKGEgZmV3IG1pbnV0ZXMgb24gYSBmcmVzaCBWTSkuIERvIE5PVCByZXN0YXJ0IHRoZSBWTS4iIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIgIFRoaXMgd2luZG93IHVwZGF0ZXMgZXZlcnkgZmV3IHNlY29uZHMgYW5kIGNsb3NlcyBhdXRvbWF0aWNhbGx5IHdoZW4gdGhlIGFwcCBpcyByZWFkeS4iIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAzCn0K')
)
$notifyTask = 'markgen-windows-2022-installing'
$notifyAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $notifyPath + '"')
$notifyPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Highest
# Triggers cover EVERY way the operator can be present during the (SYSTEM, first-boot) install:
#   - AtLogOn: a fresh interactive logon.
#   - a repeating trigger (1 min = the minimum Windows Task Scheduler allows; a shorter interval makes
#     Register-ScheduledTask fail): catches an operator who RDPs in or RECONNECTS a disconnected
#     session MID-INSTALL. AtLogOn does NOT fire on a reconnect, and the one-shot immediate-start below
#     only helps if a session is already Active at this instant - so without the repeat, an operator
#     who connects a moment later never sees the window (seen live). With it, the notice appears within
#     <=1 min of them being present.
# MultipleInstances=IgnoreNew makes the task a SINGLETON: overlapping ticks are skipped, so the notice
# never stacks (validated live: repeated ticks + AtLogOn + immediate-start yield exactly one window in
# the operator's session). The notice script self-exits when windows-2022-install.done appears, and the
# END of this script unregisters the task, so a post-completion tick shows nothing.
$notifyTriggers = @(
    (New-ScheduledTaskTrigger -AtLogOn),
    (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Hours 2))
)
Register-ScheduledTask -TaskName $notifyTask -Action $notifyAction `
    -Trigger $notifyTriggers -Principal $notifyPrincipal `
    -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew) -Force | Out-Null
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
$mysql_root_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  MySQL Community Server - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Mysql Root Password", $mysql_root_password)
# ALSO write a MACHINE-READABLE `<raw_name>=<value>` line (Plan 20). A health-check command naturally
# greps the raw secret name (e.g. `sa_password`), but the human label above is title-cased with spaces
# (`Sa Password`) - that mismatch made an sa-login check read an EMPTY password and fail on a working
# SQL install. This line lets a check read the value by the raw name: e.g.
# `((Select-String -Path '<store>' -Pattern '^mysql_root_password=').Line -split '=',2)[1]`.
Add-Content -Path 'C:\credentials.txt' -Value ("mysql_root_password={0}" -f $mysql_root_password)
Write-Stage "install: stored secret mysql_root_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing MySQL Community Server and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
Write-Output "Installing Visual C++ 2015-2022 x64 Redistributable..."
$stage = 'C:\Temp\mysql-install'
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$vcPath = Join-Path $stage 'vc_redist.x64.exe'
$attempt = 0
while ($true) {
    $attempt++
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcPath -TimeoutSec 300
        break
    } catch {
        if ($attempt -ge 4) { throw "Failed to download VC++ redist: $_" }
        Write-Output "VC++ download attempt $attempt failed, retrying..."
        Start-Sleep -Seconds 5
    }
}
$p = Start-Process -FilePath $vcPath -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
if ($p.ExitCode -notin 0,3010) { throw "VC++ redist install failed: $($p.ExitCode)" }
Write-Output "VC++ redist installed (exit $($p.ExitCode))."

# --- Layout ---
$baseDir = 'C:\Program Files\MySQL\mysql-8.4.10-winx64'
$binDir  = Join-Path $baseDir 'bin'
$mysqld  = Join-Path $binDir 'mysqld.exe'
$mysql   = Join-Path $binDir 'mysql.exe'
$dataDir = 'C:\ProgramData\MySQL\data'
$iniPath = 'C:\ProgramData\MySQL\my.ini'

# --- Download + extract the MySQL ZIP (idempotent) ---
if (-not (Test-Path $mysqld)) {
    $zipPath = Join-Path $stage 'mysql-8.4.10-winx64.zip'
    if (-not (Test-Path $zipPath)) {
        Write-Output "Downloading MySQL Community Server 8.4.10 ZIP..."
        $attempt = 0
        while ($true) {
            $attempt++
            try {
                Invoke-WebRequest -UseBasicParsing -Uri 'https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.10-winx64.zip' -OutFile $zipPath -TimeoutSec 1200
                break
            } catch {
                if ($attempt -ge 4) { throw "Failed to download MySQL ZIP: $_" }
                Write-Output "MySQL ZIP download attempt $attempt failed, retrying..."
                Start-Sleep -Seconds 10
            }
        }
    }
    Write-Output "Extracting MySQL ZIP to C:\Program Files\MySQL ..."
    New-Item -ItemType Directory -Force -Path 'C:\Program Files\MySQL' | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath 'C:\Program Files\MySQL' -Force
}
if (-not (Test-Path $mysqld)) { throw "mysqld.exe not found at $mysqld after extraction" }

# --- Write my.ini (ASCII, no BOM) ---
New-Item -ItemType Directory -Force -Path 'C:\ProgramData\MySQL' | Out-Null
$iniContent = @"
[mysqld]
port=3306
bind-address=0.0.0.0
basedir=C:/Program Files/MySQL/mysql-8.4.10-winx64
datadir=C:/ProgramData/MySQL/data

[client]
port=3306
"@
[System.IO.File]::WriteAllText($iniPath, $iniContent, [System.Text.Encoding]::ASCII)
Write-Output "Wrote $iniPath"

# --- Initialize data dir (only if empty / absent) ---
$needInit = $true
if (Test-Path $dataDir) {
    if ((Get-ChildItem -Path $dataDir -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
        $needInit = $false
        Write-Output "Data directory already initialized; skipping --initialize-insecure."
    }
}
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

if ($needInit) {
    Write-Output "Initializing MySQL data directory (insecure, empty root password)..."
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $mysqld "--defaults-file=$iniPath" --initialize-insecure 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "mysqld --initialize-insecure failed (exit $code)" }
}

# --- Register + start the MySQL service ---
$svc = Get-Service -Name 'MySQL' -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Output "Registering MySQL Windows service..."
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $mysqld --install MySQL "--defaults-file=$iniPath" 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "mysqld --install failed (exit $code)" }
}

Set-Service -Name 'MySQL' -StartupType Automatic
if ((Get-Service -Name 'MySQL').Status -ne 'Running') {
    Start-Service -Name 'MySQL'
}

# Wait for the service to reach Running
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and (Get-Service -Name 'MySQL').Status -ne 'Running') {
    Start-Sleep -Seconds 3
}
if ((Get-Service -Name 'MySQL').Status -ne 'Running') { throw "MySQL service failed to reach Running state" }
Write-Output "MySQL service is Running."

# Wait for the port to accept connections (non-CIM socket probe)
$deadline = (Get-Date).AddSeconds(120)
$portUp = $false
while ((Get-Date) -lt $deadline) {
    try {
        $tc = New-Object System.Net.Sockets.TcpClient
        $iar = $tc.BeginConnect('127.0.0.1', 3306, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(3000) -and $tc.Connected) { $portUp = $true; $tc.Close(); break }
        $tc.Close()
    } catch {}
    Start-Sleep -Seconds 2
}
if (-not $portUp) { throw "mysqld is not listening on port 3306" }
Write-Output "mysqld is listening on 3306."

# --- Set root password and enable remote root (idempotent enough for a re-run) ---
Write-Output "Configuring root credentials..."
$sqlFile = Join-Path $stage 'init.sql'
$sql = @"
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$mysql_root_password';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"@
[System.IO.File]::WriteAllText($sqlFile, $sql, [System.Text.Encoding]::ASCII)

$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
# First try with empty password (fresh init); if that fails, retry with the configured password (re-run)
Get-Content $sqlFile | & $mysql -u root --host=127.0.0.1 --port=3306 2>&1 | ForEach-Object { Write-Host $_ }
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host "Empty-password login failed; retrying with configured root password..."
    Get-Content $sqlFile | & $mysql -u root "-p$mysql_root_password" --host=127.0.0.1 --port=3306 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
}
$ErrorActionPreference = $prev
if ($code -ne 0) { throw "Failed to configure root credentials (exit $code)" }
Write-Output "Root credentials configured."

# --- Firewall rule for 3306 ---
if (-not (Get-NetFirewallRule -DisplayName 'MySQL 3306' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'MySQL 3306' -Direction Inbound -Protocol TCP -LocalPort 3306 -Action Allow | Out-Null
    Write-Output "Opened inbound TCP 3306."
}

# --- Append connection info to the credentials file (never overwrite) ---
$ipInfo = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
Add-Content -Path 'C:\credentials.txt' -Value ""
Add-Content -Path 'C:\credentials.txt' -Value "--- MySQL Community Server 8.4.10 ---"
Add-Content -Path 'C:\credentials.txt' -Value "Server  : ${ipInfo}:3306"
Add-Content -Path 'C:\credentials.txt' -Value "Username: root"
Add-Content -Path 'C:\credentials.txt' -Value "Password: (see 'Mysql Root Password' above)"

# --- Clean up staging dir ---
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
Write-Output "MySQL 8.4.10 install complete."
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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiAgU1VDQ0VTUyAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKE15U1FMIENvbW11bml0eSBTZXJ2ZXIpIGhhcyBiZWVuIGRlcGxveWVkIHN1Y2Nlc3NmdWxseSEiIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KV3JpdGUtSG9zdCAiPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICIgIENyZWRlbnRpYWxzIGZvciB0aGlzIGRlcGxveW1lbnQgKGFsc28gc2F2ZWQgb24gZGlzayk6IiAtRm9yZWdyb3VuZENvbG9yIEN5YW4KV3JpdGUtSG9zdCAiIgppZiAoVGVzdC1QYXRoICdDOlxjcmVkZW50aWFscy50eHQnKSB7CiAgICBXcml0ZS1Ib3N0ICIgIEM6XGNyZWRlbnRpYWxzLnR4dCIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQogICAgR2V0LUNvbnRlbnQgJ0M6XGNyZWRlbnRpYWxzLnR4dCcgfCBGb3JFYWNoLU9iamVjdCB7IGlmICgkXy5UcmltKCkpIHsgV3JpdGUtSG9zdCAiICAgICRfIiAtRm9yZWdyb3VuZENvbG9yIFdoaXRlIH0gfQogICAgV3JpdGUtSG9zdCAiIgp9CldyaXRlLUhvc3QgIiAgVGhpcyBiYW5uZXIgYXBwZWFycyBvbmNlIGFuZCBpcyByZW1vdmVkIGFmdGVyIHRoaXMgbG9naW4uIiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5CldyaXRlLUhvc3QgIiIKCiMgQ2xlYW51cCB0cmFjZXMgb2YgdGhlIGRlcGxveW1lbnQuClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpTeXN0ZW1Ecml2ZVxDbG91ZGJhc2VJbml0XGxvZ1wqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6VEVNUFwqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpDbGVhci1FdmVudExvZyAtTG9nTmFtZSBBcHBsaWNhdGlvbiwgU3lzdGVtIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCgojIEdpdmUgdGhlIG9wZXJhdG9yIHRpbWUgdG8gcmVhZCB0aGUgYmFubmVyIGJlZm9yZSB0aGUgd2luZG93IGNsb3NlcyAoaXQgcnVucyBpbiB0aGVpciBzZXNzaW9uKS4KV3JpdGUtSG9zdCAiICBUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDIwIHNlY29uZHMuIiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5ClN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIwCgojIFVucmVnaXN0ZXIgdGhlIGZpcnN0LWxvZ2luIHNjaGVkdWxlZCB0YXNrIChydW4tb25jZSBzZW1hbnRpY3MpICsgZGVsZXRlIHRoaXMgc2NyaXB0IGl0c2VsZi4KVW5yZWdpc3Rlci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAnbWFya2dlbi13aW5kb3dzLTIwMjItY2xlYW51cCcgLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiMgQWxzbyBjbGVhciBhbnkgbGVnYWN5IFJ1bk9uY2UgZW50cnkgZnJvbSBvbGRlciBpbnN0YWxscyAoaGFybWxlc3MgaWYgYWJzZW50KS4KUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScgLU5hbWUgJ3dpbmRvd3MtMjAyMl9jbGVhbnVwJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtRm9yY2UgJFBTQ29tbWFuZFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK')
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
