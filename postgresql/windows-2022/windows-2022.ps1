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
Write-Stage "install: PostgreSQL (community) on win2022"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDIyLWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjItc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDIyLWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyMi1pbnN0YWxsLmRvbmUnCgojIElmIHRoZSBpbnN0YWxsIGFscmVhZHkgZmluaXNoZWQsIGV4aXQgaW1tZWRpYXRlbHkuIFRoZSBub3RpY2UgdGFzayBub3cgaGFzIGEgcmVwZWF0aW5nIHRyaWdnZXIsIHNvCiMgYSB0aWNrIGNhbiBmaXJlIGluIHRoZSBicmllZiBnYXAgYmV0d2VlbiB0aGUgaW5zdGFsbCBzZXR0aW5nIC5kb25lIGFuZCB0aGUgRU5EIG9mIHRoZSBpbnN0YWxsIHNjcmlwdAojIHVucmVnaXN0ZXJpbmcgdGhlIHRhc2sgLSB3aXRob3V0IHRoaXMgZ3VhcmQgdGhhdCB0aWNrIHdvdWxkIGZsYXNoIGEgc3RhbGUgImluc3RhbGxpbmciIHdpbmRvdy4KaWYgKFRlc3QtUGF0aCAkZG9uZUZpbGUpIHsgcmV0dXJuIH0KCiMgQW5jaG9yIGVsYXBzZWQgdG8gdGhlIGluc3RhbGwncyByZWNvcmRlZCBzdGFydCB0aW1lIGlmIHByZXNlbnQgKHNvIHRoZSB0aW1lciByZWZsZWN0cyB0aGUgcmVhbAojIGluc3RhbGwgYWdlIGV2ZW4gaWYgdGhlIG9wZXJhdG9yIGxvZ2dlZCBpbiBsYXRlKSwgZWxzZSB0byBub3cuCnRyeSB7ICRzdGFydCA9IFtkYXRldGltZV06OlBhcnNlKChHZXQtQ29udGVudCAtUmF3ICRzdGFydEZpbGUpKSB9IGNhdGNoIHsgJHN0YXJ0ID0gR2V0LURhdGUgfQoKJGJhciA9ICcjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIycKIyBQb2xsIHVudGlsIHRoZSBpbnN0YWxsIHNpZ25hbHMgZG9uZSwgd2l0aCBhIGhhcmQgc2FmZXR5IGNhcCBzbyB0aGlzIGNhbiBuZXZlciBzcGluIGZvcmV2ZXIuCmZvciAoJGkgPSAwOyAkaSAtbHQgOTAwOyAkaSsrKSB7CiAgICAkZG9uZSA9IFRlc3QtUGF0aCAkZG9uZUZpbGUKICAgICRzdGFnZSA9IGlmIChUZXN0LVBhdGggJHN0YXR1c0ZpbGUpIHsgKEdldC1Db250ZW50IC1SYXcgJHN0YXR1c0ZpbGUpLlRyaW0oKSB9IGVsc2UgeyAnUHJlcGFyaW5nLi4uJyB9CiAgICAkZWxhcHNlZCA9IChHZXQtRGF0ZSkgLSAkc3RhcnQKICAgICRtbSA9IFtpbnRdJGVsYXBzZWQuVG90YWxNaW51dGVzCiAgICAkc3MgPSAkZWxhcHNlZC5TZWNvbmRzCgogICAgQ2xlYXItSG9zdAogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICgiIyAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChQb3N0Z3JlU1FMIChjb21tdW5pdHkpKSBpcyBJTlNUQUxMSU5HIC0gcGxlYXNlIHdhaXQuIikgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiIgogICAgaWYgKCRkb25lKSB7CiAgICAgICAgV3JpdGUtSG9zdCAoIiAgU3RhdHVzIDogSW5zdGFsbCBjb21wbGV0ZS4iKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgIiIKICAgICAgICBXcml0ZS1Ib3N0ICIgIFRoZSBhcHAgaXMgcmVhZHkuIFRoaXMgd2luZG93IHdpbGwgY2xvc2Ugbm93OyBhICdkZXBsb3llZCBzdWNjZXNzZnVsbHknIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiICBtZXNzYWdlIHdpdGggYW55IGNyZWRlbnRpYWxzIGZvbGxvd3MuIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgNAogICAgICAgIGJyZWFrCiAgICB9CiAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiB7MH0iIC1mICRzdGFnZSkgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgKCIgIEVsYXBzZWQ6IHswfW0gezE6MDB9cyIgLWYgJG1tLCAkc3MpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBXcml0ZS1Ib3N0ICIgIEluc3RhbGxpbmcgaW4gdGhlIGJhY2tncm91bmQgKGEgZmV3IG1pbnV0ZXMgb24gYSBmcmVzaCBWTSkuIERvIE5PVCByZXN0YXJ0IHRoZSBWTS4iIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIgIFRoaXMgd2luZG93IHVwZGF0ZXMgZXZlcnkgZmV3IHNlY29uZHMgYW5kIGNsb3NlcyBhdXRvbWF0aWNhbGx5IHdoZW4gdGhlIGFwcCBpcyByZWFkeS4iIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAzCn0K')
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
$postgres_superuser_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  PostgreSQL (community) - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Postgres Superuser Password", $postgres_superuser_password)
# ALSO write a MACHINE-READABLE `<raw_name>=<value>` line (Plan 20). A health-check command naturally
# greps the raw secret name (e.g. `sa_password`), but the human label above is title-cased with spaces
# (`Sa Password`) - that mismatch made an sa-login check read an EMPTY password and fail on a working
# SQL install. This line lets a check read the value by the raw name: e.g.
# `((Select-String -Path '<store>' -Pattern '^postgres_superuser_password=').Line -split '=',2)[1]`.
Add-Content -Path 'C:\credentials.txt' -Value ("postgres_superuser_password={0}" -f $postgres_superuser_password)
Write-Stage "install: stored secret postgres_superuser_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing PostgreSQL (community) and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$ErrPref = $ErrorActionPreference

Write-Output "Installing Visual C++ 2015-2022 x64 Redistributable (required by PostgreSQL native binaries)..."
$staging = 'C:\Temp\pg-install'
New-Item -ItemType Directory -Force -Path $staging | Out-Null

$vcPath = Join-Path $staging 'vc_redist.x64.exe'
$attempt = 0
while ($true) {
    try {
        $attempt++
        Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcPath -TimeoutSec 300
        break
    } catch {
        if ($attempt -ge 4) { throw "Failed to download vc_redist.x64.exe: $_" }
        Start-Sleep -Seconds 10
    }
}
$vcProc = Start-Process -FilePath $vcPath -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
if ($vcProc.ExitCode -notin 0,3010) { throw "vc_redist install failed: $($vcProc.ExitCode)" }
Write-Output "VC++ redistributable installed (exit $($vcProc.ExitCode))."

# --- Download PostgreSQL 18.6 EDB binaries ZIP ---
$installBase = 'C:\Program Files\PostgreSQL\18'
$binDir      = Join-Path $installBase 'bin'
$dataDir     = 'C:\ProgramData\PostgreSQL\18\data'
$serviceName = 'postgresql'

if (-not (Test-Path (Join-Path $binDir 'postgres.exe'))) {
    $zipPath = Join-Path $staging 'postgresql-18.6-binaries.zip'
    Write-Output "Downloading PostgreSQL 18.6 binaries ZIP..."
    $attempt = 0
    while ($true) {
        try {
            $attempt++
            Invoke-WebRequest -UseBasicParsing -Uri 'https://get.enterprisedb.com/postgresql/postgresql-18.6-1-windows-x64-binaries.zip' -OutFile $zipPath -TimeoutSec 1200
            break
        } catch {
            if ($attempt -ge 4) { throw "Failed to download PostgreSQL ZIP: $_" }
            Start-Sleep -Seconds 15
        }
    }

    Write-Output "Extracting PostgreSQL ZIP..."
    $extractDir = Join-Path $staging 'extract'
    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # The ZIP contains a top-level "pgsql" folder with bin/lib/share.
    $pgsql = Join-Path $extractDir 'pgsql'
    if (-not (Test-Path $pgsql)) { throw "Expected 'pgsql' folder not found in extracted ZIP." }

    New-Item -ItemType Directory -Force -Path $installBase | Out-Null
    Write-Output "Copying binaries to $installBase ..."
    Copy-Item -Path (Join-Path $pgsql '*') -Destination $installBase -Recurse -Force
}

if (-not (Test-Path (Join-Path $binDir 'postgres.exe'))) { throw "postgres.exe not found at $binDir after install." }

# --- Initialize the data directory (only if not already initialized) ---
if (-not (Test-Path (Join-Path $dataDir 'PG_VERSION'))) {
    Write-Output "Initializing PostgreSQL data directory at $dataDir ..."
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    # Grant NetworkService (the service account) full control over the data dir tree.
    & icacls.exe (Split-Path $dataDir -Parent) /grant '"NT AUTHORITY\NetworkService":(OI)(CI)F' /T /C | Out-Null

    # Password file for initdb (no BOM, ASCII); removed immediately after.
    $pwFile = Join-Path $staging 'pgpw.txt'
    [System.IO.File]::WriteAllText($pwFile, $postgres_superuser_password)

    $initdb = Join-Path $binDir 'initdb.exe'
    $ErrorActionPreference = 'Continue'
    & $initdb -D $dataDir -U postgres --auth-host=scram-sha-256 --auth-local=scram-sha-256 --pwfile=$pwFile --encoding=UTF8 2>&1 | ForEach-Object { Write-Host $_ }
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $ErrPref
    Remove-Item -Force $pwFile -ErrorAction SilentlyContinue
    if ($rc -ne 0) { throw "initdb failed with exit code $rc" }
}

# --- Grant service account access (idempotent, in case of re-run) ---
& icacls.exe 'C:\ProgramData\PostgreSQL\18' /grant '"NT AUTHORITY\NetworkService":(OI)(CI)F' /T /C | Out-Null

# --- Configure remote access ---
$confFile = Join-Path $dataDir 'postgresql.conf'
$hbaFile  = Join-Path $dataDir 'pg_hba.conf'

Write-Output "Configuring listen_addresses and port in postgresql.conf ..."
$conf = Get-Content -Path $confFile -Raw
$conf = $conf -replace "(?m)^\s*#?\s*listen_addresses\s*=.*$", "listen_addresses = '*'"
$conf = $conf -replace "(?m)^\s*#?\s*port\s*=.*$", "port = 5432"
if ($conf -notmatch "(?m)^\s*listen_addresses\s*=") { $conf += "`nlisten_addresses = '*'`n" }
if ($conf -notmatch "(?m)^\s*port\s*=")            { $conf += "`nport = 5432`n" }
[System.IO.File]::WriteAllText($confFile, $conf)

Write-Output "Adding remote host rule to pg_hba.conf ..."
$hba = Get-Content -Path $hbaFile -Raw
if ($hba -notmatch "0\.0\.0\.0/0\s+scram-sha-256") {
    $hba += "`n# Allow remote connections (all addresses) with SCRAM auth`nhost    all    all    0.0.0.0/0    scram-sha-256`n"
    [System.IO.File]::WriteAllText($hbaFile, $hba)
}

# --- Register the Windows service (running as NT AUTHORITY\NetworkService) ---
$pgctl = Join-Path $binDir 'pg_ctl.exe'
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Output "Registering '$serviceName' Windows service..."
    $ErrorActionPreference = 'Continue'
    & $pgctl register -N $serviceName -D $dataDir -U 'NT AUTHORITY\NetworkService' 2>&1 | ForEach-Object { Write-Host $_ }
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $ErrPref
    if ($rc -ne 0) { throw "pg_ctl register failed with exit code $rc" }
    Start-Sleep -Seconds 3
}

# --- Firewall rule for 5432 ---
if (-not (Get-NetFirewallRule -DisplayName 'PostgreSQL 5432' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'PostgreSQL 5432' -Direction Inbound -Protocol TCP -LocalPort 5432 -Action Allow | Out-Null
    Write-Output "Firewall rule for TCP 5432 created."
}

# --- Ensure service is running and set to start on boot ---
Set-Service -Name $serviceName -StartupType Automatic
Start-Service -Name $serviceName
Start-Sleep -Seconds 5
if ((Get-Service -Name $serviceName).Status -ne 'Running') {
    throw "PostgreSQL service '$serviceName' failed to reach Running state."
}
Write-Output "PostgreSQL service is Running."

# --- Verify the port is listening (non-CIM probe) ---
$deadline = (Get-Date).AddSeconds(60)
$listening = $false
while ((Get-Date) -lt $deadline) {
    if (netstat -ano | Select-String ':5432\s') { $listening = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $listening) { throw "PostgreSQL is not listening on port 5432." }
Write-Output "PostgreSQL is listening on port 5432."

# --- Append connection details to credentials file (never overwrite) ---
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
Add-Content -Path 'C:\credentials.txt' -Value ""
Add-Content -Path 'C:\credentials.txt' -Value "--- PostgreSQL 18.6 Connection ---"
Add-Content -Path 'C:\credentials.txt' -Value "Host       : $ip"
Add-Content -Path 'C:\credentials.txt' -Value "Port       : 5432"
Add-Content -Path 'C:\credentials.txt' -Value "Database   : postgres"
Add-Content -Path 'C:\credentials.txt' -Value "Superuser  : postgres"
Add-Content -Path 'C:\credentials.txt' -Value "Password   : (see 'Postgres Superuser Password' above)"
Add-Content -Path 'C:\credentials.txt' -Value "Conn string: postgresql://postgres@${ip}:5432/postgres"

# --- Clean up staging/download temp ---
Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue

Write-Output "PostgreSQL 18.6 install and configuration complete."
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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiAgU1VDQ0VTUyAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKFBvc3RncmVTUUwgKGNvbW11bml0eSkpIGhhcyBiZWVuIGRlcGxveWVkIHN1Y2Nlc3NmdWxseSEiIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KV3JpdGUtSG9zdCAiPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICIgIENyZWRlbnRpYWxzIGZvciB0aGlzIGRlcGxveW1lbnQgKGFsc28gc2F2ZWQgb24gZGlzayk6IiAtRm9yZWdyb3VuZENvbG9yIEN5YW4KV3JpdGUtSG9zdCAiIgppZiAoVGVzdC1QYXRoICdDOlxjcmVkZW50aWFscy50eHQnKSB7CiAgICBXcml0ZS1Ib3N0ICIgIEM6XGNyZWRlbnRpYWxzLnR4dCIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQogICAgR2V0LUNvbnRlbnQgJ0M6XGNyZWRlbnRpYWxzLnR4dCcgfCBGb3JFYWNoLU9iamVjdCB7IGlmICgkXy5UcmltKCkpIHsgV3JpdGUtSG9zdCAiICAgICRfIiAtRm9yZWdyb3VuZENvbG9yIFdoaXRlIH0gfQogICAgV3JpdGUtSG9zdCAiIgp9CldyaXRlLUhvc3QgIiAgVGhpcyBiYW5uZXIgYXBwZWFycyBvbmNlIGFuZCBpcyByZW1vdmVkIGFmdGVyIHRoaXMgbG9naW4uIiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5CldyaXRlLUhvc3QgIiIKCiMgQ2xlYW51cCB0cmFjZXMgb2YgdGhlIGRlcGxveW1lbnQuClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpTeXN0ZW1Ecml2ZVxDbG91ZGJhc2VJbml0XGxvZ1wqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6VEVNUFwqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpDbGVhci1FdmVudExvZyAtTG9nTmFtZSBBcHBsaWNhdGlvbiwgU3lzdGVtIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCgojIEdpdmUgdGhlIG9wZXJhdG9yIHRpbWUgdG8gcmVhZCB0aGUgYmFubmVyIGJlZm9yZSB0aGUgd2luZG93IGNsb3NlcyAoaXQgcnVucyBpbiB0aGVpciBzZXNzaW9uKS4KV3JpdGUtSG9zdCAiICBUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDIwIHNlY29uZHMuIiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5ClN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIwCgojIFVucmVnaXN0ZXIgdGhlIGZpcnN0LWxvZ2luIHNjaGVkdWxlZCB0YXNrIChydW4tb25jZSBzZW1hbnRpY3MpICsgZGVsZXRlIHRoaXMgc2NyaXB0IGl0c2VsZi4KVW5yZWdpc3Rlci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAnbWFya2dlbi13aW5kb3dzLTIwMjItY2xlYW51cCcgLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiMgQWxzbyBjbGVhciBhbnkgbGVnYWN5IFJ1bk9uY2UgZW50cnkgZnJvbSBvbGRlciBpbnN0YWxscyAoaGFybWxlc3MgaWYgYWJzZW50KS4KUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScgLU5hbWUgJ3dpbmRvd3MtMjAyMl9jbGVhbnVwJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtRm9yY2UgJFBTQ29tbWFuZFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK')
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
