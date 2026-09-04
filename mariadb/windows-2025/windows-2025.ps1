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
# Enable TLS 1.2 for the whole install process (Windows PowerShell 5.1 defaults to TLS 1.0/1.1, which
# modern HTTPS download hosts reject). The scaffold sets it ONCE, correctly - the LLM install steps
# below must NOT re-set it (a wrong type name like [Net.SecurityProtocol] throws TypeNotFound and, under
# 'Stop', aborts the whole install - seen live on MariaDB WS2019). The type is [Net.SecurityProtocolType].
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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
Write-Stage "install: MariaDB Server (community) on win2025"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDI1LWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjUtc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDI1LWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyNS1pbnN0YWxsLmRvbmUnCgojIElmIHRoZSBpbnN0YWxsIGFscmVhZHkgZmluaXNoZWQsIGV4aXQgaW1tZWRpYXRlbHkuIFRoZSBub3RpY2UgdGFzayBub3cgaGFzIGEgcmVwZWF0aW5nIHRyaWdnZXIsIHNvCiMgYSB0aWNrIGNhbiBmaXJlIGluIHRoZSBicmllZiBnYXAgYmV0d2VlbiB0aGUgaW5zdGFsbCBzZXR0aW5nIC5kb25lIGFuZCB0aGUgRU5EIG9mIHRoZSBpbnN0YWxsIHNjcmlwdAojIHVucmVnaXN0ZXJpbmcgdGhlIHRhc2sgLSB3aXRob3V0IHRoaXMgZ3VhcmQgdGhhdCB0aWNrIHdvdWxkIGZsYXNoIGEgc3RhbGUgImluc3RhbGxpbmciIHdpbmRvdy4KaWYgKFRlc3QtUGF0aCAkZG9uZUZpbGUpIHsgcmV0dXJuIH0KCiMgQW5jaG9yIGVsYXBzZWQgdG8gdGhlIGluc3RhbGwncyByZWNvcmRlZCBzdGFydCB0aW1lIGlmIHByZXNlbnQgKHNvIHRoZSB0aW1lciByZWZsZWN0cyB0aGUgcmVhbAojIGluc3RhbGwgYWdlIGV2ZW4gaWYgdGhlIG9wZXJhdG9yIGxvZ2dlZCBpbiBsYXRlKSwgZWxzZSB0byBub3cuCnRyeSB7ICRzdGFydCA9IFtkYXRldGltZV06OlBhcnNlKChHZXQtQ29udGVudCAtUmF3ICRzdGFydEZpbGUpKSB9IGNhdGNoIHsgJHN0YXJ0ID0gR2V0LURhdGUgfQoKJGJhciA9ICcjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIycKIyBQb2xsIHVudGlsIHRoZSBpbnN0YWxsIHNpZ25hbHMgZG9uZSwgd2l0aCBhIGhhcmQgc2FmZXR5IGNhcCBzbyB0aGlzIGNhbiBuZXZlciBzcGluIGZvcmV2ZXIuCmZvciAoJGkgPSAwOyAkaSAtbHQgOTAwOyAkaSsrKSB7CiAgICAkZG9uZSA9IFRlc3QtUGF0aCAkZG9uZUZpbGUKICAgICRzdGFnZSA9IGlmIChUZXN0LVBhdGggJHN0YXR1c0ZpbGUpIHsgKEdldC1Db250ZW50IC1SYXcgJHN0YXR1c0ZpbGUpLlRyaW0oKSB9IGVsc2UgeyAnUHJlcGFyaW5nLi4uJyB9CiAgICAkZWxhcHNlZCA9IChHZXQtRGF0ZSkgLSAkc3RhcnQKICAgICRtbSA9IFtpbnRdJGVsYXBzZWQuVG90YWxNaW51dGVzCiAgICAkc3MgPSAkZWxhcHNlZC5TZWNvbmRzCgogICAgQ2xlYXItSG9zdAogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICgiIyAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChNYXJpYURCIFNlcnZlciAoY29tbXVuaXR5KSkgaXMgSU5TVEFMTElORyAtIHBsZWFzZSB3YWl0LiIpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICRiYXIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiIKICAgIGlmICgkZG9uZSkgewogICAgICAgIFdyaXRlLUhvc3QgKCIgIFN0YXR1cyA6IEluc3RhbGwgY29tcGxldGUuIikgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgKCIgIEVsYXBzZWQ6IHswfW0gezE6MDB9cyIgLWYgJG1tLCAkc3MpIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICIiCiAgICAgICAgV3JpdGUtSG9zdCAiICBUaGUgYXBwIGlzIHJlYWR5LiBUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIG5vdzsgYSAnZGVwbG95ZWQgc3VjY2Vzc2Z1bGx5JyIgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgIiAgbWVzc2FnZSB3aXRoIGFueSBjcmVkZW50aWFscyBmb2xsb3dzLiIgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDQKICAgICAgICBicmVhawogICAgfQogICAgV3JpdGUtSG9zdCAoIiAgU3RhdHVzIDogezB9IiAtZiAkc3RhZ2UpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICgiICBFbGFwc2VkOiB7MH1tIHsxOjAwfXMiIC1mICRtbSwgJHNzKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiIgogICAgV3JpdGUtSG9zdCAiICBJbnN0YWxsaW5nIGluIHRoZSBiYWNrZ3JvdW5kIChhIGZldyBtaW51dGVzIG9uIGEgZnJlc2ggVk0pLiBEbyBOT1QgcmVzdGFydCB0aGUgVk0uIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiICBUaGlzIHdpbmRvdyB1cGRhdGVzIGV2ZXJ5IGZldyBzZWNvbmRzIGFuZCBjbG9zZXMgYXV0b21hdGljYWxseSB3aGVuIHRoZSBhcHAgaXMgcmVhZHkuIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMwp9Cg==')
)
$notifyTask = 'markgen-windows-2025-installing'
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
# the operator's session). The notice script self-exits when windows-2025-install.done appears, and the
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
        "  MariaDB Server (community) - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Mariadb Root Password", $mariadb_root_password)
# ALSO write a MACHINE-READABLE `<raw_name>=<value>` line (Plan 20). A health-check command naturally
# greps the raw secret name (e.g. `sa_password`), but the human label above is title-cased with spaces
# (`Sa Password`) - that mismatch made an sa-login check read an EMPTY password and fail on a working
# SQL install. This line lets a check read the value by the raw name: e.g.
# `((Select-String -Path '<store>' -Pattern '^mariadb_root_password=').Line -split '=',2)[1]`.
Add-Content -Path 'C:\credentials.txt' -Value ("mariadb_root_password={0}" -f $mariadb_root_password)
Write-Stage "install: stored secret mariadb_root_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing MariaDB Server (community) and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$stage = 'C:\Temp\mariadb-stage'
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# --- Visual C++ 2015-2022 x64 Redistributable (unconditional; MariaDB binaries link the VC++ runtime) ---
Write-Output "installing Visual C++ 2015-2022 x64 redistributable..."
$vcPath = Join-Path $stage 'vc_redist.x64.exe'
$vcUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
$attempt = 0
while ($true) {
    $attempt++
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $vcUrl -OutFile $vcPath -TimeoutSec 300
        break
    } catch {
        if ($attempt -ge 4) { throw "failed to download VC++ redist after $attempt attempts: $_" }
        Write-Output "vc_redist download attempt $attempt failed, retrying..."
        Start-Sleep -Seconds 5
    }
}
$vcp = Start-Process -FilePath $vcPath -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
if ($vcp.ExitCode -notin 0,3010) { throw "vc_redist install failed: $($vcp.ExitCode)" }
Write-Output "VC++ redistributable installed (exit $($vcp.ExitCode))"

# --- Download MariaDB Server MSI ---
$msiPath = Join-Path $stage 'mariadb-11.4.13-winx64.msi'
$msiUrl = 'https://archive.mariadb.org/mariadb-11.4.13/winx64-packages/mariadb-11.4.13-winx64.msi'
if (-not (Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue)) {
    Write-Output "downloading MariaDB MSI..."
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $msiUrl -OutFile $msiPath -TimeoutSec 600
            break
        } catch {
            if ($attempt -ge 4) { throw "failed to download MariaDB MSI after $attempt attempts: $_" }
            Write-Output "MariaDB MSI download attempt $attempt failed, retrying..."
            Start-Sleep -Seconds 5
        }
    }

    # --- Silent MSI install (fully silent /qn; verbose log dumped on failure) ---
    Write-Output "installing MariaDB Server 11.4.13 (silent)..."
    $log = Join-Path $stage 'mariadb-install.log'
    $args = @(
        '/i', $msiPath,
        '/qn',
        '/L*v', $log,
        'SERVICENAME=MariaDB',
        'PORT=3306',
        ('PASSWORD=' + $mariadb_root_password),
        'ALLOWREMOTEROOTACCESS=1',
        'UTF8=1'
    )
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -notin 0,3010) {
        Write-Output "MariaDB MSI failed with exit code $($p.ExitCode); dumping install log tail:"
        if (Test-Path $log) {
            Get-Content $log -Tail 60 | ForEach-Object { Write-Output $_ }
        }
        throw "MariaDB MSI install failed: $($p.ExitCode)"
    }
    Write-Output "MariaDB MSI installed (exit $($p.ExitCode))"
} else {
    Write-Output "MariaDB service already present; skipping MSI install"
}

# --- Ensure the MariaDB service is running and set to start on boot ---
$svc = Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
if (-not $svc) { throw "MariaDB service not found after install" }
Set-Service -Name 'MariaDB' -StartupType Automatic
if ($svc.Status -ne 'Running') {
    Start-Service -Name 'MariaDB'
}
$svc = Get-Service -Name 'MariaDB'
if ($svc.Status -ne 'Running') { throw "MariaDB service failed to reach Running state" }
Write-Output "MariaDB service is Running and set to Automatic"

# --- Firewall: allow inbound TCP 3306 ---
if (-not (Get-NetFirewallRule -DisplayName 'MariaDB 3306' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'MariaDB 3306' -Direction Inbound -Protocol TCP -LocalPort 3306 -Action Allow | Out-Null
    Write-Output "opened inbound TCP 3306 in Windows Firewall"
}

# --- Verify mysqld is listening on 3306 (non-CIM socket probe with timeout) ---
$listening = $false
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    $probe = Test-NetConnection -ComputerName 127.0.0.1 -Port 3306 -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($probe) { $listening = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $listening) { throw "MariaDB is not listening on port 3306" }
Write-Output "MariaDB is listening on port 3306"

# --- Append connection details to the scaffold-owned credentials file (never overwrite) ---
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
Add-Content -Path 'C:\credentials.txt' -Value ""
Add-Content -Path 'C:\credentials.txt' -Value "MariaDB Server 11.4.13"
Add-Content -Path 'C:\credentials.txt' -Value "  Host    : $ip"
Add-Content -Path 'C:\credentials.txt' -Value "  Port    : 3306"
Add-Content -Path 'C:\credentials.txt' -Value "  User    : root (remote root@% access enabled)"
Add-Content -Path 'C:\credentials.txt' -Value "  Password: (see 'Mariadb Root Password' above)"
Add-Content -Path 'C:\credentials.txt' -Value "  Client  : C:\Program Files\MariaDB 11.4\bin\mysql.exe"

# --- Clean up staged installers ---
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
Write-Output "MariaDB deployment complete; staging directory cleaned up"
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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiAgU1VDQ0VTUyAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKE1hcmlhREIgU2VydmVyIChjb21tdW5pdHkpKSBoYXMgYmVlbiBkZXBsb3llZCBzdWNjZXNzZnVsbHkhIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiIKV3JpdGUtSG9zdCAiICBDcmVkZW50aWFscyBmb3IgdGhpcyBkZXBsb3ltZW50IChhbHNvIHNhdmVkIG9uIGRpc2spOiIgLUZvcmVncm91bmRDb2xvciBDeWFuCldyaXRlLUhvc3QgIiIKaWYgKFRlc3QtUGF0aCAnQzpcY3JlZGVudGlhbHMudHh0JykgewogICAgV3JpdGUtSG9zdCAiICBDOlxjcmVkZW50aWFscy50eHQiIC1Gb3JlZ3JvdW5kQ29sb3IgRGFya0dyYXkKICAgIEdldC1Db250ZW50ICdDOlxjcmVkZW50aWFscy50eHQnIHwgRm9yRWFjaC1PYmplY3QgeyBpZiAoJF8uVHJpbSgpKSB7IFdyaXRlLUhvc3QgIiAgICAkXyIgLUZvcmVncm91bmRDb2xvciBXaGl0ZSB9IH0KICAgIFdyaXRlLUhvc3QgIiIKfQpXcml0ZS1Ib3N0ICIgIFRoaXMgYmFubmVyIGFwcGVhcnMgb25jZSBhbmQgaXMgcmVtb3ZlZCBhZnRlciB0aGlzIGxvZ2luLiIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQpXcml0ZS1Ib3N0ICIiCgojIENsZWFudXAgdHJhY2VzIG9mIHRoZSBkZXBsb3ltZW50LgpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6U3lzdGVtRHJpdmVcQ2xvdWRiYXNlSW5pdFxsb2dcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlRFTVBcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKQ2xlYXItRXZlbnRMb2cgLUxvZ05hbWUgQXBwbGljYXRpb24sIFN5c3RlbSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQoKIyBHaXZlIHRoZSBvcGVyYXRvciB0aW1lIHRvIHJlYWQgdGhlIGJhbm5lciBiZWZvcmUgdGhlIHdpbmRvdyBjbG9zZXMgKGl0IHJ1bnMgaW4gdGhlaXIgc2Vzc2lvbikuCldyaXRlLUhvc3QgIiAgVGhpcyB3aW5kb3cgd2lsbCBjbG9zZSBpbiAyMCBzZWNvbmRzLiIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQpTdGFydC1TbGVlcCAtU2Vjb25kcyAyMAoKIyBVbnJlZ2lzdGVyIHRoZSBmaXJzdC1sb2dpbiBzY2hlZHVsZWQgdGFzayAocnVuLW9uY2Ugc2VtYW50aWNzKSArIGRlbGV0ZSB0aGlzIHNjcmlwdCBpdHNlbGYuClVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJ21hcmtnZW4td2luZG93cy0yMDI1LWNsZWFudXAnIC1Db25maXJtOiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQojIEFsc28gY2xlYXIgYW55IGxlZ2FjeSBSdW5PbmNlIGVudHJ5IGZyb20gb2xkZXIgaW5zdGFsbHMgKGhhcm1sZXNzIGlmIGFic2VudCkuClJlbW92ZS1JdGVtUHJvcGVydHkgLVBhdGggJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFJ1bk9uY2UnIC1OYW1lICd3aW5kb3dzLTIwMjVfY2xlYW51cCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLUZvcmNlICRQU0NvbW1hbmRQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCg==')
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
