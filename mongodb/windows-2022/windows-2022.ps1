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
Write-Stage "install: MongoDB Community Server + mongosh on win2022"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIExJVkUgU1RBVFVTIHdpbmRvdyAod2luZG93cy0yMDIyLWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUy4KCiAgVGhlIGluc3RhbGwgKFNZU1RFTSkgYW5kIHRoaXMgd2luZG93IChpbnRlcmFjdGl2ZSB1c2VyKSBhcmUgc2VwYXJhdGUgcHJvY2Vzc2VzLCBzbyB0aGlzIGNhbid0IHJlYWQKICB0aGUgaW5zdGFsbCdzIGxpdmUgc3Rkb3V0LiBJbnN0ZWFkIHRoZSBpbnN0YWxsIHB1Ymxpc2hlcyBicmVhZGNydW1iIGZpbGVzIHVuZGVyIEM6XFByb2dyYW1EYXRhXAogIG1hcmtnZW5cIHRoYXQgdGhpcyB3aW5kb3cgUE9MTFMgZXZlcnkgZmV3IHNlY29uZHM6IHRoZSBjdXJyZW50IHN0YWdlICg8YXBwPi1zdGF0dXMudHh0KSwgdGhlIHN0YXJ0CiAgdGltZSAoPGFwcD4taW5zdGFsbC5zdGFydCksIGFuZCBhIGNvbXBsZXRpb24gZmxhZyAoPGFwcD4taW5zdGFsbC5kb25lKS4gVGhpcyB3aW5kb3cgc3RheXMgb3BlbiBhbmQKICByZWZyZXNoZXMgYW4gZWxhcHNlZCB0aW1lciArIGN1cnJlbnQgc3RhZ2UgdW50aWwgaXQgc2VlcyB0aGUgLmRvbmUgZmxhZywgdGhlbiBzaG93cyBhIGJyaWVmCiAgImNvbXBsZXRlIiBsaW5lIGFuZCBleGl0cyAtIHNvIHRoZSBvcGVyYXRvciBhbHdheXMga25vd3MgaXQncyBwcm9ncmVzc2luZyBhbmQgaG93IGxvbmcgaXQncyB0YWtlbi4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKJGRpciAgICAgICA9IEpvaW4tUGF0aCAkZW52OlByb2dyYW1EYXRhICdtYXJrZ2VuJwokc3RhdHVzRmlsZSA9IEpvaW4tUGF0aCAkZGlyICd3aW5kb3dzLTIwMjItc3RhdHVzLnR4dCcKJHN0YXJ0RmlsZSAgPSBKb2luLVBhdGggJGRpciAnd2luZG93cy0yMDIyLWluc3RhbGwuc3RhcnQnCiRkb25lRmlsZSAgID0gSm9pbi1QYXRoICRkaXIgJ3dpbmRvd3MtMjAyMi1pbnN0YWxsLmRvbmUnCgojIEFuY2hvciBlbGFwc2VkIHRvIHRoZSBpbnN0YWxsJ3MgcmVjb3JkZWQgc3RhcnQgdGltZSBpZiBwcmVzZW50IChzbyB0aGUgdGltZXIgcmVmbGVjdHMgdGhlIHJlYWwKIyBpbnN0YWxsIGFnZSBldmVuIGlmIHRoZSBvcGVyYXRvciBsb2dnZWQgaW4gbGF0ZSksIGVsc2UgdG8gbm93Lgp0cnkgeyAkc3RhcnQgPSBbZGF0ZXRpbWVdOjpQYXJzZSgoR2V0LUNvbnRlbnQgLVJhdyAkc3RhcnRGaWxlKSkgfSBjYXRjaCB7ICRzdGFydCA9IEdldC1EYXRlIH0KCiRiYXIgPSAnIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMnCiMgUG9sbCB1bnRpbCB0aGUgaW5zdGFsbCBzaWduYWxzIGRvbmUsIHdpdGggYSBoYXJkIHNhZmV0eSBjYXAgc28gdGhpcyBjYW4gbmV2ZXIgc3BpbiBmb3JldmVyLgpmb3IgKCRpID0gMDsgJGkgLWx0IDkwMDsgJGkrKykgewogICAgJGRvbmUgPSBUZXN0LVBhdGggJGRvbmVGaWxlCiAgICAkc3RhZ2UgPSBpZiAoVGVzdC1QYXRoICRzdGF0dXNGaWxlKSB7IChHZXQtQ29udGVudCAtUmF3ICRzdGF0dXNGaWxlKS5UcmltKCkgfSBlbHNlIHsgJ1ByZXBhcmluZy4uLicgfQogICAgJGVsYXBzZWQgPSAoR2V0LURhdGUpIC0gJHN0YXJ0CiAgICAkbW0gPSBbaW50XSRlbGFwc2VkLlRvdGFsTWludXRlcwogICAgJHNzID0gJGVsYXBzZWQuU2Vjb25kcwoKICAgIENsZWFyLUhvc3QKICAgIFdyaXRlLUhvc3QgJGJhciAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAoIiMgICBZb3VyIE1hcmtldHBsYWNlIEFwcCAoTW9uZ29EQiBDb21tdW5pdHkgU2VydmVyICsgbW9uZ29zaCkgaXMgSU5TVEFMTElORyAtIHBsZWFzZSB3YWl0LiIpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICRiYXIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKICAgIFdyaXRlLUhvc3QgIiIKICAgIGlmICgkZG9uZSkgewogICAgICAgIFdyaXRlLUhvc3QgKCIgIFN0YXR1cyA6IEluc3RhbGwgY29tcGxldGUuIikgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgKCIgIEVsYXBzZWQ6IHswfW0gezE6MDB9cyIgLWYgJG1tLCAkc3MpIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KICAgICAgICBXcml0ZS1Ib3N0ICIiCiAgICAgICAgV3JpdGUtSG9zdCAiICBUaGUgYXBwIGlzIHJlYWR5LiBUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIG5vdzsgYSAnZGVwbG95ZWQgc3VjY2Vzc2Z1bGx5JyIgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFdyaXRlLUhvc3QgIiAgbWVzc2FnZSB3aXRoIGFueSBjcmVkZW50aWFscyBmb2xsb3dzLiIgLUZvcmVncm91bmRDb2xvciBHcmVlbgogICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDQKICAgICAgICBicmVhawogICAgfQogICAgV3JpdGUtSG9zdCAoIiAgU3RhdHVzIDogezB9IiAtZiAkc3RhZ2UpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CiAgICBXcml0ZS1Ib3N0ICgiICBFbGFwc2VkOiB7MH1tIHsxOjAwfXMiIC1mICRtbSwgJHNzKSAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiIgogICAgV3JpdGUtSG9zdCAiICBJbnN0YWxsaW5nIGluIHRoZSBiYWNrZ3JvdW5kIChhIGZldyBtaW51dGVzIG9uIGEgZnJlc2ggVk0pLiBEbyBOT1QgcmVzdGFydCB0aGUgVk0uIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgV3JpdGUtSG9zdCAiICBUaGlzIHdpbmRvdyB1cGRhdGVzIGV2ZXJ5IGZldyBzZWNvbmRzIGFuZCBjbG9zZXMgYXV0b21hdGljYWxseSB3aGVuIHRoZSBhcHAgaXMgcmVhZHkuIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMwp9Cg==')
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
$mongodb_admin_password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$mgSecretDir = Split-Path -Parent 'C:\credentials.txt'
# Skip an empty parent OR a drive root ('C:\' / 'C:/'): New-Item -ItemType Directory on a drive root
# throws "The path is not of a legal form". Only mkdir a real subdirectory that doesn't exist yet.
if ($mgSecretDir -and $mgSecretDir -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path $mgSecretDir)) {
    New-Item -ItemType Directory -Force -Path $mgSecretDir | Out-Null
}
if (-not $mgSecretFilesInit.ContainsKey('C:\credentials.txt')) {
    $mgCredHeader = @(
        "==================================================================",
        "  MongoDB Community Server + mongosh - deployment credentials",
        "  Generated on this server at first boot. Keep this file secure.",
        "=================================================================="
    )
    Set-Content -Path 'C:\credentials.txt' -Value $mgCredHeader
    Add-Content -Path 'C:\credentials.txt' -Value ""
    $mgSecretFilesInit['C:\credentials.txt'] = $true
}
Add-Content -Path 'C:\credentials.txt' -Value ("  {0,-24}: {1}" -f "Mongodb Admin Password", $mongodb_admin_password)
# ALSO write a MACHINE-READABLE `<raw_name>=<value>` line (Plan 20). A health-check command naturally
# greps the raw secret name (e.g. `sa_password`), but the human label above is title-cased with spaces
# (`Sa Password`) - that mismatch made an sa-login check read an EMPTY password and fail on a working
# SQL install. This line lets a check read the value by the raw name: e.g.
# `((Select-String -Path '<store>' -Pattern '^mongodb_admin_password=').Line -split '=',2)[1]`.
Add-Content -Path 'C:\credentials.txt' -Value ("mongodb_admin_password={0}" -f $mongodb_admin_password)
Write-Stage "install: stored secret mongodb_admin_password at C:\credentials.txt"

# Set a clean, human-readable status for the live "installing" window right before the app work
# begins. The LLM install steps below use Write-Output (not Write-Stage), so they don't update the
# status breadcrumb - without this the notice would sit on the internal "registered 'installing'
# notice" wiring line for the whole install. This gives the operator a meaningful stage instead.
Set-Status 'Installing MongoDB Community Server + mongosh and dependencies (this can take a few minutes)...'

# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$staging = 'C:\Temp\mongodb-install'
New-Item -ItemType Directory -Force -Path $staging | Out-Null

function Get-RemoteFile($url, $dest) {
    for ($i = 1; $i -le 4; $i++) {
        try {
            Write-Output "downloading $url (attempt $i)"
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 900
            if (Test-Path $dest) { return }
        } catch {
            Write-Output "download attempt $i failed: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
    throw "failed to download $url after 4 attempts"
}

# --- (1) Install MongoDB Community Server (ServerService) silently -----------------
$serverMsi = Join-Path $staging 'mongodb-server-8.0.29.msi'
Get-RemoteFile 'https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-8.0.29-signed.msi' $serverMsi

Write-Output "installing MongoDB Community Server 8.0.29 (ServerService)..."
$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/i', "`"$serverMsi`"", '/qn', '/norestart', 'ADDLOCAL=ServerService', 'SHOULD_INSTALL_COMPASS=0'
if ($p.ExitCode -notin 0, 3010) { throw "MongoDB server MSI failed with exit code $($p.ExitCode)" }
Write-Output "MongoDB server MSI installed (exit $($p.ExitCode))"

# --- (2) Install mongosh per-machine to C:\Program Files\mongosh\bin ---------------
# Use the ZIP/portable distribution so files land deterministically machine-wide
# (mongosh's MSI can install per-user, which vanishes under the SYSTEM account).
$mongoshExe = 'C:\Program Files\mongosh\bin\mongosh.exe'
if (-not (Test-Path $mongoshExe)) {
    $zip = Join-Path $staging 'mongosh-2.10.0-win32-x64.zip'
    Get-RemoteFile 'https://downloads.mongodb.com/compass/mongosh-2.10.0-win32-x64.zip' $zip
    $extract = Join-Path $staging 'mongosh-extract'
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $found = Get-ChildItem -Path $extract -Recurse -Filter 'mongosh.exe' | Select-Object -First 1
    if (-not $found) { throw 'mongosh.exe not found in downloaded ZIP' }
    $srcBin = Split-Path $found.FullName -Parent
    New-Item -ItemType Directory -Force -Path 'C:\Program Files\mongosh\bin' | Out-Null
    Copy-Item -Path (Join-Path $srcBin '*') -Destination 'C:\Program Files\mongosh\bin' -Recurse -Force
}
if (-not (Test-Path $mongoshExe)) { throw "mongosh.exe missing at $mongoshExe after install" }
Write-Output "mongosh installed at $mongoshExe"

# --- Ensure the MongoDB service is running (default 127.0.0.1 / no-auth) -----------
Set-Service -Name MongoDB -StartupType Automatic
if ((Get-Service MongoDB).Status -ne 'Running') { Start-Service MongoDB }
Write-Output "MongoDB service started (default config, localhost exception active)"

# --- Wait for mongod to accept local connections -----------------------------------
$ready = $false
for ($i = 1; $i -le 30; $i++) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $mongoshExe --host 127.0.0.1 --port 27017 --quiet --eval 'db.runCommand({ping:1}).ok' 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -eq 0 -and ("$out" -match '1')) { $ready = $true; break }
    Write-Output "waiting for mongod to be ready (attempt $i)..."
    Start-Sleep -Seconds 3
}
if (-not $ready) { throw 'mongod did not become ready on 127.0.0.1:27017' }

# --- (3) Create the root admin user via the localhost exception --------------------
# Pass the password through an env var so special characters need no JS escaping.
$env:MONGO_ADMIN_PW = $mongodb_admin_password
$createJs = "db.getSiblingDB('admin').createUser({ user: 'mongoadmin', pwd: process.env.MONGO_ADMIN_PW, roles: [ { role: 'root', db: 'admin' } ] })"
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out = & $mongoshExe --host 127.0.0.1 --port 27017 --quiet --eval $createJs 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
Write-Output ("createUser output: " + ("$out"))
if ($code -ne 0 -and ("$out" -notmatch 'already exists')) {
    throw "failed to create admin user 'mongoadmin' (exit $code)"
}
Remove-Item Env:\MONGO_ADMIN_PW -ErrorAction SilentlyContinue
Write-Output "root admin user 'mongoadmin' ensured"

# --- (4) Rewrite mongod.cfg: bind all interfaces + enable authorization ------------
$cfgPath = 'C:\Program Files\MongoDB\Server\8.0\bin\mongod.cfg'
$cfg = @"
# mongod.conf
storage:
  dbPath: C:\Program Files\MongoDB\Server\8.0\data
systemLog:
  destination: file
  logAppend: true
  path: C:\Program Files\MongoDB\Server\8.0\log\mongod.log
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
"@
[System.IO.File]::WriteAllText($cfgPath, $cfg)
Write-Output "wrote mongod.cfg (bindIp 0.0.0.0, authorization enabled)"

# --- (5) Restart MongoDB to apply auth + bind-all ----------------------------------
Restart-Service MongoDB
Set-Service -Name MongoDB -StartupType Automatic
Write-Output "MongoDB service restarted with authentication enabled"

# --- (6) Open firewall for TCP 27017 (any profile) ---------------------------------
if (-not (Get-NetFirewallRule -DisplayName 'MongoDB 27017' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'MongoDB 27017' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 27017 -Profile Any | Out-Null
    Write-Output "opened inbound firewall rule for TCP 27017"
}

# --- Append connection info to the scaffold-owned credentials file (APPEND only) ----
$hostIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
Add-Content -Path 'C:\credentials.txt' -Value ""
Add-Content -Path 'C:\credentials.txt' -Value "--- MongoDB Connection Info ---"
Add-Content -Path 'C:\credentials.txt' -Value "Admin Username : mongoadmin"
Add-Content -Path 'C:\credentials.txt' -Value "Admin Password : (see 'Mongodb Admin Password' above)"
Add-Content -Path 'C:\credentials.txt' -Value "Connection String : mongodb://mongoadmin@${hostIp}:27017/?authSource=admin"
Add-Content -Path 'C:\credentials.txt' -Value "Shell : & 'C:\Program Files\mongosh\bin\mongosh.exe' --host $hostIp --port 27017 -u mongoadmin -p <password> --authenticationDatabase admin"

# --- Clean up staging downloads ----------------------------------------------------
Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
Write-Output "MongoDB 8.0.29 + mongosh deployment complete"
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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuCldyaXRlLUhvc3QgIiAgU1VDQ0VTUyAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKE1vbmdvREIgQ29tbXVuaXR5IFNlcnZlciArIG1vbmdvc2gpIGhhcyBiZWVuIGRlcGxveWVkIHN1Y2Nlc3NmdWxseSEiIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KV3JpdGUtSG9zdCAiPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICIgIENyZWRlbnRpYWxzIGZvciB0aGlzIGRlcGxveW1lbnQgKGFsc28gc2F2ZWQgb24gZGlzayk6IiAtRm9yZWdyb3VuZENvbG9yIEN5YW4KV3JpdGUtSG9zdCAiIgppZiAoVGVzdC1QYXRoICdDOlxjcmVkZW50aWFscy50eHQnKSB7CiAgICBXcml0ZS1Ib3N0ICIgIEM6XGNyZWRlbnRpYWxzLnR4dCIgLUZvcmVncm91bmRDb2xvciBEYXJrR3JheQogICAgR2V0LUNvbnRlbnQgJ0M6XGNyZWRlbnRpYWxzLnR4dCcgfCBGb3JFYWNoLU9iamVjdCB7IGlmICgkXy5UcmltKCkpIHsgV3JpdGUtSG9zdCAiICAgICRfIiAtRm9yZWdyb3VuZENvbG9yIFdoaXRlIH0gfQogICAgV3JpdGUtSG9zdCAiIgp9CldyaXRlLUhvc3QgIiAgVGhpcyBiYW5uZXIgYXBwZWFycyBvbmNlIGFuZCBpcyByZW1vdmVkIGFmdGVyIHRoaXMgbG9naW4uIiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5CldyaXRlLUhvc3QgIiIKCiMgQ2xlYW51cCB0cmFjZXMgb2YgdGhlIGRlcGxveW1lbnQuClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpTeXN0ZW1Ecml2ZVxDbG91ZGJhc2VJbml0XGxvZ1wqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6VEVNUFwqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpDbGVhci1FdmVudExvZyAtTG9nTmFtZSBBcHBsaWNhdGlvbiwgU3lzdGVtIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCgojIEdpdmUgdGhlIG9wZXJhdG9yIHRpbWUgdG8gcmVhZCB0aGUgYmFubmVyIGJlZm9yZSB0aGUgd2luZG93IGNsb3NlcyAoaXQgcnVucyBpbiB0aGVpciBzZXNzaW9uKS4KV3JpdGUtSG9zdCAiICBUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDIwIHNlY29uZHMuIiAtRm9yZWdyb3VuZENvbG9yIERhcmtHcmF5ClN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIwCgojIFVucmVnaXN0ZXIgdGhlIGZpcnN0LWxvZ2luIHNjaGVkdWxlZCB0YXNrIChydW4tb25jZSBzZW1hbnRpY3MpICsgZGVsZXRlIHRoaXMgc2NyaXB0IGl0c2VsZi4KVW5yZWdpc3Rlci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAnbWFya2dlbi13aW5kb3dzLTIwMjItY2xlYW51cCcgLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiMgQWxzbyBjbGVhciBhbnkgbGVnYWN5IFJ1bk9uY2UgZW50cnkgZnJvbSBvbGRlciBpbnN0YWxscyAoaGFybWxlc3MgaWYgYWJzZW50KS4KUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScgLU5hbWUgJ3dpbmRvd3MtMjAyMl9jbGVhbnVwJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtRm9yY2UgJFBTQ29tbWFuZFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK')
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
