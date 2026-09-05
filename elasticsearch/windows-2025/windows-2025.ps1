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
Write-Stage "install: Elasticsearch (Elastic, single-node) on win2025"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDI1LWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjUtc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDI1LWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyNS1pbnN0YWxsLmRvbmUnCgojIElmIHRoZSBpbnN0YWxsIGFscmVhZHkgZmluaXNoZWQsIGV4aXQgaW1tZWRpYXRlbHkuIFRoZSBub3RpY2UgdGFzayBub3cgaGFzIGEgcmVwZWF0aW5nIHRyaWdnZXIsIHNvCiMgYSB0aWNrIGNhbiBmaXJlIGluIHRoZSBicmllZiBnYXAgYmV0d2VlbiB0aGUgaW5zdGFsbCBzZXR0aW5nIC5kb25lIGFuZCB0aGUgRU5EIG9mIHRoZSBpbnN0YWxsIHNjcmlwdAojIHVucmVnaXN0ZXJpbmcgdGhlIHRhc2sgLSB3aXRob3V0IHRoaXMgZ3VhcmQgdGhhdCB0aWNrIHdvdWxkIGZsYXNoIGEgc3RhbGUgImluc3RhbGxpbmciIHdpbmRvdy4KaWYgKFRlc3QtUGF0aCAkZG9uZUZpbGUpIHsgcmV0dXJuIH0KCiMgQW5jaG9yIGVsYXBzZWQgdG8gdGhlIGluc3RhbGwncyByZWNvcmRlZCBzdGFydCB0aW1lIGlmIHByZXNlbnQgKHNvIHRoZSB0aW1lciByZWZsZWN0cyB0aGUgcmVhbAojIGluc3RhbGwgYWdlIGV2ZW4gaWYgdGhlIG9wZXJhdG9yIGxvZ2dlZCBpbiBsYXRlKSwgZWxzZSB0byBub3cuCnRyeSB7ICRzdGFydCA9IFtkYXRldGltZV06OlBhcnNlKChHZXQtQ29udGVudCAtUmF3ICRzdGFydEZpbGUpKSB9IGNhdGNoIHsgJHN0YXJ0ID0gR2V0LURhdGUgfQoKJGJhciA9ICcjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIycKIyBQb2xsIHVudGlsIHRoZSBpbnN0YWxsIHNpZ25hbHMgZG9uZSwgd2l0aCBhIGhhcmQgc2FmZXR5IGNhcCBzbyB0aGlzIGNhbiBuZXZlciBzcGluIGZvcmV2ZXIuCmZvciAoJGkgPSAwOyAkaSAtbHQgOTAwOyAkaSsrKSB7CiAgICAkZG9uZSA9IFRlc3QtUGF0aCAkZG9uZUZpbGUKICAgICRzdGFnZSA9IGlmIChUZXN0LVBhdGggJHN0YXR1c0ZpbGUpIHsgKEdldC1Db250ZW50IC1SYXcgJHN0YXR1c0ZpbGUpLlRyaW0oKSB9IGVsc2UgeyAnUHJlcGFyaW5nLi4uJyB9CiAgICAkZWxhcHNlZCA9IChHZXQtRGF0ZSkgLSAkc3RhcnQKICAgICRtbSA9IFtpbnRdJGVsYXBzZWQuVG90YWxNaW51dGVzCiAgICAkc3MgPSAkZWxhcHNlZC5TZWNvbmRzCgogICAgQ2xlYXItSG9zdAogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICgiIyAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChFbGFzdGljc2VhcmNoIChFbGFzdGljLCBzaW5nbGUtbm9kZSkpIGlzIElOU1RBTExJTkcgLSBwbGVhc2Ugd2FpdC4iKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAkYmFyIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICIiCiAgICBpZiAoJGRvbmUpIHsKICAgICAgICBXcml0ZS1Ib3N0ICgiICBTdGF0dXMgOiBJbnN0YWxsIGNvbXBsZXRlLiIpIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICgiICBFbGFwc2VkOiB7MH1tIHsxOjAwfXMiIC1mICRtbSwgJHNzKSAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCiAgICAgICAgV3JpdGUtSG9zdCAiIgogICAgICAgIFdyaXRlLUhvc3QgIiAgVGhlIGFwcCBpcyByZWFkeS4gVGhpcyB3aW5kb3cgd2lsbCBjbG9zZSBub3c7IGEgJ2RlcGxveWVkIHN1Y2Nlc3NmdWxseSciIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICIgIG1lc3NhZ2Ugd2l0aCBhbnkgY3JlZGVudGlhbHMgZm9sbG93cy4iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA0CiAgICAgICAgYnJlYWsKICAgIH0KICAgIFdyaXRlLUhvc3QgKCIgIFN0YXR1cyA6IHswfSIgLWYgJHN0YWdlKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiAgRWxhcHNlZDogezB9bSB7MTowMH1zIiAtZiAkbW0sICRzcykgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiIKICAgIFdyaXRlLUhvc3QgIiAgSW5zdGFsbGluZyBpbiB0aGUgYmFja2dyb3VuZCAoYSBmZXcgbWludXRlcyBvbiBhIGZyZXNoIFZNKS4gRG8gTk9UIHJlc3RhcnQgdGhlIFZNLiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiAgVGhpcyB3aW5kb3cgdXBkYXRlcyBldmVyeSBmZXcgc2Vjb25kcyBhbmQgY2xvc2VzIGF1dG9tYXRpY2FsbHkgd2hlbiB0aGUgYXBwIGlzIHJlYWR5LiIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDMKfQo=')
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
$elastic_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  Elasticsearch (Elastic, single-node) - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Elastic Password", $elastic_password)
# ALSO write a MACHINE-READABLE `<raw_name>=<value>` line (Plan 20). A health-check command naturally
# greps the raw secret name (e.g. `sa_password`), but the human label above is title-cased with spaces
# (`Sa Password`) - that mismatch made an sa-login check read an EMPTY password and fail on a working
# SQL install. This line lets a check read the value by the raw name: e.g.
# `((Select-String -Path '<store>' -Pattern '^elastic_password=').Line -split '=',2)[1]`.
Add-Content -Path 'C:\credentials.txt' -Value ("elastic_password={0}" -f $elastic_password)
Write-Stage "install: stored secret elastic_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing Elasticsearch (Elastic, single-node) and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$esVersion = '9.5.3'
$esHome    = "C:\Elasticsearch\$esVersion"
$esConf    = Join-Path $esHome 'config'
$stageDir  = 'C:\Temp\es-stage'
$zipPath   = Join-Path $stageDir "elasticsearch-$esVersion-windows-x86_64.zip"
$zipUrl    = "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$esVersion-windows-x86_64.zip"

if (-not (Test-Path (Join-Path $esHome 'bin\elasticsearch-service.bat'))) {
    Write-Output "Staging Elasticsearch $esVersion download..."
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

    if (-not (Test-Path $zipPath)) {
        $ok = $false
        for ($i = 1; $i -le 4 -and -not $ok; $i++) {
            try {
                Write-Output "Downloading $zipUrl (attempt $i)..."
                Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zipPath -TimeoutSec 1800
                $ok = $true
            } catch {
                Write-Output "Download attempt $i failed: $($_.Exception.Message)"
                Start-Sleep -Seconds 10
            }
        }
        if (-not $ok) { throw "Failed to download Elasticsearch after multiple attempts" }
    }

    Write-Output "Expanding archive..."
    $extractDir = Join-Path $stageDir 'extracted'
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $nested = Get-ChildItem -Path $extractDir -Directory | Where-Object { $_.Name -like 'elasticsearch-*' } | Select-Object -First 1
    if (-not $nested) { throw "Could not find nested elasticsearch folder in archive" }

    New-Item -ItemType Directory -Force -Path (Split-Path $esHome -Parent) | Out-Null
    if (Test-Path $esHome) { Remove-Item -Recurse -Force $esHome -ErrorAction SilentlyContinue }
    Move-Item -Path $nested.FullName -Destination $esHome
    Write-Output "Elasticsearch extracted to $esHome"
} else {
    Write-Output "Elasticsearch already present at $esHome"
}

# --- Write elasticsearch.yml (inline, no BOM) ---
New-Item -ItemType Directory -Force -Path $esConf | Out-Null
$ymlPath = Join-Path $esConf 'elasticsearch.yml'
$yml = @"
cluster.name: es-marketplace
node.name: es-node-1
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
"@
[System.IO.File]::WriteAllText($ymlPath, $yml)
Write-Output "Wrote $ymlPath"

# --- Write heap.options (inline, no BOM), heap ~50% RAM capped 31g ---
$heapDir = Join-Path $esConf 'jvm.options.d'
New-Item -ItemType Directory -Force -Path $heapDir | Out-Null
$totalBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$totalGB    = [math]::Floor($totalBytes / 1GB)
$heapGB     = [math]::Floor($totalGB / 2)
if ($heapGB -lt 1)  { $heapGB = 1 }
if ($heapGB -gt 31) { $heapGB = 31 }
$heapPath = Join-Path $heapDir 'heap.options'
$heap = "-Xms${heapGB}g`n-Xmx${heapGB}g`n"
[System.IO.File]::WriteAllText($heapPath, $heap)
Write-Output "Wrote $heapPath (heap ${heapGB}g)"

# --- Environment (process + Machine) ---
[Environment]::SetEnvironmentVariable('ES_HOME', $esHome, 'Machine')
[Environment]::SetEnvironmentVariable('ES_PATH_CONF', $esConf, 'Machine')
$env:ES_HOME = $esHome
$env:ES_PATH_CONF = $esConf

$binDir       = Join-Path $esHome 'bin'
$keystoreBat  = Join-Path $binDir 'elasticsearch-keystore.bat'
$serviceBat   = Join-Path $binDir 'elasticsearch-service.bat'

# --- Create keystore and seed bootstrap.password (becomes the elastic user password) ---
$keystoreFile = Join-Path $esConf 'elasticsearch.keystore'
$pwFile = 'C:\pw.txt'
[System.IO.File]::WriteAllText($pwFile, $elastic_password)

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    if (-not (Test-Path $keystoreFile)) {
        Write-Output "Creating Elasticsearch keystore..."
        & $keystoreBat create 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "elasticsearch-keystore create failed: $LASTEXITCODE" }
    }
    Write-Output "Adding bootstrap.password to keystore..."
    Get-Content $pwFile | & $keystoreBat add -x -f 'bootstrap.password' 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "elasticsearch-keystore add bootstrap.password failed: $LASTEXITCODE" }
} finally {
    $ErrorActionPreference = $prevEAP
}

# --- Install and start the Windows service ---
$svcName = 'elasticsearch-service-x64'
$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Output "Installing Elasticsearch Windows service..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $serviceBat install 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "elasticsearch-service install failed: $LASTEXITCODE" }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
} else {
    Write-Output "Service $svcName already installed"
}

Set-Service -Name $svcName -StartupType Automatic
if ((Get-Service -Name $svcName).Status -ne 'Running') {
    Write-Output "Starting $svcName..."
    Start-Service -Name $svcName
}
if ((Get-Service -Name $svcName).Status -ne 'Running') {
    throw "$svcName failed to reach Running state"
}
Write-Output "$svcName is Running"

# --- Firewall: allow inbound TCP 9200 ---
if (-not (Get-NetFirewallRule -DisplayName 'Elasticsearch 9200' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Elasticsearch 9200' -Direction Inbound -Protocol TCP -LocalPort 9200 -Action Allow | Out-Null
    Write-Output "Firewall rule for TCP 9200 created"
}

# --- Poll until 9200 is listening (non-CIM socket probe with a deadline) ---
$deadline = (Get-Date).AddSeconds(180)
$listening = $false
while ((Get-Date) -lt $deadline -and -not $listening) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', 9200, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(3000) -and $client.Connected) {
            $listening = $true
        }
        $client.Close()
    } catch { }
    if (-not $listening) { Start-Sleep -Seconds 5 }
}
if (-not $listening) { throw "Elasticsearch did not start listening on 9200 within timeout" }
Write-Output "Elasticsearch is listening on 9200"

# --- Append connection info to credentials file (scaffold already wrote the secret) ---
$primaryIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
Add-Content -Path 'C:\credentials.txt' -Value ""
Add-Content -Path 'C:\credentials.txt' -Value "Elasticsearch URL : http://${primaryIp}:9200/"
Add-Content -Path 'C:\credentials.txt' -Value "Elasticsearch user: elastic  (password = see 'Elastic Password' above)"

# --- Clean up temp secret file and download staging ---
Remove-Item -Path $pwFile -Force -ErrorAction SilentlyContinue
Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "Elasticsearch $esVersion install complete"
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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiAgU1VDQ0VTUyAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKEVsYXN0aWNzZWFyY2ggKEVsYXN0aWMsIHNpbmdsZS1ub2RlKSkgaGFzIGJlZW4gZGVwbG95ZWQgc3VjY2Vzc2Z1bGx5ISIgLUZvcmVncm91bmRDb2xvciBHcmVlbgpXcml0ZS1Ib3N0ICI9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSIgLUZvcmVncm91bmRDb2xvciBHcmVlbgpXcml0ZS1Ib3N0ICIiCldyaXRlLUhvc3QgIiAgQ3JlZGVudGlhbHMgZm9yIHRoaXMgZGVwbG95bWVudCAoYWxzbyBzYXZlZCBvbiBkaXNrKToiIC1Gb3JlZ3JvdW5kQ29sb3IgQ3lhbgpXcml0ZS1Ib3N0ICIiCmlmIChUZXN0LVBhdGggJ0M6XGNyZWRlbnRpYWxzLnR4dCcpIHsKICAgIFdyaXRlLUhvc3QgIiAgQzpcY3JlZGVudGlhbHMudHh0IiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5CiAgICBHZXQtQ29udGVudCAnQzpcY3JlZGVudGlhbHMudHh0JyB8IEZvckVhY2gtT2JqZWN0IHsgaWYgKCRfLlRyaW0oKSkgeyBXcml0ZS1Ib3N0ICIgICAgJF8iIC1Gb3JlZ3JvdW5kQ29sb3IgV2hpdGUgfSB9CiAgICBXcml0ZS1Ib3N0ICIiCn0KV3JpdGUtSG9zdCAiICBUaGlzIGJhbm5lciBhcHBlYXJzIG9uY2UgYW5kIGlzIHJlbW92ZWQgYWZ0ZXIgdGhpcyBsb2dpbi4iIC1Gb3JlZ3JvdW5kQ29sb3IgRGFya0dyYXkKV3JpdGUtSG9zdCAiIgoKIyBDbGVhbnVwIHRyYWNlcyBvZiB0aGUgZGVwbG95bWVudC4KUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlN5c3RlbURyaXZlXENsb3VkYmFzZUluaXRcbG9nXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpURU1QXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCkNsZWFyLUV2ZW50TG9nIC1Mb2dOYW1lIEFwcGxpY2F0aW9uLCBTeXN0ZW0gLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKCiMgR2l2ZSB0aGUgb3BlcmF0b3IgdGltZSB0byByZWFkIHRoZSBiYW5uZXIgYmVmb3JlIHRoZSB3aW5kb3cgY2xvc2VzIChpdCBydW5zIGluIHRoZWlyIHNlc3Npb24pLgpXcml0ZS1Ib3N0ICIgIFRoaXMgd2luZG93IHdpbGwgY2xvc2UgaW4gMjAgc2Vjb25kcy4iIC1Gb3JlZ3JvdW5kQ29sb3IgRGFya0dyYXkKU3RhcnQtU2xlZXAgLVNlY29uZHMgMjAKCiMgVW5yZWdpc3RlciB0aGUgZmlyc3QtbG9naW4gc2NoZWR1bGVkIHRhc2sgKHJ1bi1vbmNlIHNlbWFudGljcykgKyBkZWxldGUgdGhpcyBzY3JpcHQgaXRzZWxmLgpVbnJlZ2lzdGVyLVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICdtYXJrZ2VuLXdpbmRvd3MtMjAyNS1jbGVhbnVwJyAtQ29uZmlybTokZmFsc2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKIyBBbHNvIGNsZWFyIGFueSBsZWdhY3kgUnVuT25jZSBlbnRyeSBmcm9tIG9sZGVyIGluc3RhbGxzIChoYXJtbGVzcyBpZiBhYnNlbnQpLgpSZW1vdmUtSXRlbVByb3BlcnR5IC1QYXRoICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW5PbmNlJyAtTmFtZSAnd2luZG93cy0yMDI1X2NsZWFudXAnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlClJlbW92ZS1JdGVtIC1Gb3JjZSAkUFNDb21tYW5kUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQo=')
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
