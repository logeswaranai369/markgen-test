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

function Write-Stage($msg) { Write-Output "[markgen] $msg" }

Write-Stage "install: IIS on win2022"

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
    [System.Convert]::FromBase64String('PCMKICBHZW5lcmF0ZWQgZmlyc3QtbG9naW4gImluc3RhbGwgaW4gcHJvZ3Jlc3MiIG5vdGljZSAod2luZG93cy0yMDIyLWluc3RhbGxpbmcucHMxKS4KICBTaG93biB0byBhbiBvcGVyYXRvciB3aG8gUkRQcyBpbiBXSElMRSB0aGUgbWFya2V0cGxhY2UgaW5zdGFsbCBpcyBzdGlsbCBydW5uaW5nIChpdCBydW5zIGFzIFNZU1RFTQogIG9uIGZpcnN0IGJvb3QgYW5kIGNhbiB0YWtlIHNldmVyYWwgbWludXRlcyBvbiBhIHNsb3cgVk0pLiBUaGUgaW5zdGFsbCBzY3JpcHQgcmVnaXN0ZXJzIGEgc2NoZWR1bGVkCiAgdGFzayAodHJpZ2dlcjogYXQtbG9nb24sIGludGVyYWN0aXZlKSB0aGF0IHJ1bnMgVEhJUywgc28gYSBsb2dpbiBkdXJpbmcgaW5zdGFsbCBzZWVzIGEgY2xlYXIKICAicGxlYXNlIHdhaXQiIG1lc3NhZ2UgaW5zdGVhZCBvZiBhIGJhcmUgZGVza3RvcCB0aGF0IGxvb2tzIGJyb2tlbi4gVGhlIGluc3RhbGwgc2NyaXB0IFVOUkVHSVNURVJTCiAgdGhpcyB0YXNrIHRoZSBtb21lbnQgaXQgY29tcGxldGVzLCBzbyBpdCBvbmx5IGFwcGVhcnMgd2hpbGUgZ2VudWluZWx5IGluc3RhbGxpbmcuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKV3JpdGUtSG9zdCAiIyAgICAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKElJUykgaXMgU1RJTEwgSU5TVEFMTElORyAtIHBsZWFzZSB3YWl0LiAgICAgICAgICAgICAgICAjIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwpXcml0ZS1Ib3N0ICIjICAgICBUaGlzIHJ1bnMgaW4gdGhlIGJhY2tncm91bmQgKGEgZmV3IG1pbnV0ZXMpLiBEbyBub3QgcmVzdGFydCB0aGUgVk0uICAgICAgICAgICAgICAgICAgICAgICAjIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwpXcml0ZS1Ib3N0ICIjICAgICBBICdkZXBsb3llZCBzdWNjZXNzZnVsbHknIG1lc3NhZ2Ugd2lsbCBhcHBlYXIgYXV0b21hdGljYWxseSB3aGVuIGl0IGZpbmlzaGVzLiAgICAgICAgICAgICMiIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93CldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cKV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICJUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDMwIHNlY29uZHMuIElmIHRoZSBhcHAgc3RpbGwgaXNuJ3QgcmVhZHksIGxvZyBvZmYgYW5kIGJhY2sgb24uIiAtRm9yZWdyb3VuZENvbG9yIFllbGxvdwpTdGFydC1TbGVlcCAtU2Vjb25kcyAzMAo=')
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


# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$needed = 'Web-Server', 'Web-Mgmt-Console', 'Web-Mgmt-Tools'
$missing = $needed | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }
if ($missing) {
    Write-Output "installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing -IncludeManagementTools | Out-Null
} else {
    Write-Output "IIS features already installed"
}

# Verify the management console is present
$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
if (-not (Test-Path $inetMgr)) {
    Write-Output "InetMgr.exe missing after install; forcing Web-Mgmt-Console"
    Install-WindowsFeature -Name Web-Mgmt-Console | Out-Null
}

# Ensure default site root and a welcome page exist
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null
if (-not (Test-Path 'C:\inetpub\wwwroot\iisstart.htm') -and -not (Test-Path 'C:\inetpub\wwwroot\index.html')) {
    Set-Content -Path 'C:\inetpub\wwwroot\index.html' -Value '<h1>IIS Windows Server - Deployed by Markgen</h1>'
    Write-Output "created default landing page"
}

# Create an IIS Manager shortcut on the ALL-USERS (Public) desktop.
# Runs under cloudbase-init on first boot before any interactive user exists,
# so C:\Users\Administrator is absent - always use the Public desktop.
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
$lnk = Join-Path $publicDesktop 'IIS Manager.lnk'
if (Test-Path $inetMgr) {
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $inetMgr
    $sc.IconLocation = "$inetMgr,0"
    $sc.Description = 'Internet Information Services (IIS) Manager'
    $sc.Save()
    Write-Output "created IIS Manager shortcut on the all-users desktop"
} else {
    Write-Output "WARNING: InetMgr.exe not found; skipping shortcut"
}

# Ensure the HTTP firewall rule is enabled
$rule = Get-NetFirewallRule -DisplayName 'World Wide Web Services (HTTP Traffic-In)' -ErrorAction SilentlyContinue
if ($rule) {
    Enable-NetFirewallRule -DisplayName 'World Wide Web Services (HTTP Traffic-In)' | Out-Null
    Write-Output "enabled HTTP firewall rule (TCP 80)"
}

# Ensure the web service runs now and on every boot
Set-Service W3SVC -StartupType Automatic
if ((Get-Service W3SVC).Status -ne 'Running') {
    Start-Service W3SVC
}
Write-Output "IIS is serving on port 80; IIS Manager (inetmgr) is installed"
# ----- END app-specific tasks -----

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
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQgLSB0aGUgV2luZG93cyBmaXJzdC1sb2dpbiBjbGVhbnVwIHNjcmlwdCAoPGFwcD4tY2xlYW51cC5wczEpLgogIFdpbmRvd3MgYW5hbG9nIG9mIHRoZSBMaW51eCA8YXBwPl9jbGVhbnVwLnNoOiBvbiBmaXJzdCBpbnRlcmFjdGl2ZSBsb2dpbiBpdCBwcmludHMgdGhlIHN1Y2Nlc3MKICBiYW5uZXIgKyBhbnkgc3RvcmVkIGNyZWRlbnRpYWxzLCB0aGVuIHdpcGVzIGluc3RhbGwgdHJhY2VzIChjbG91ZGJhc2UtaW5pdCBsb2dzLCB0ZW1wKSBhbmQKICBzZWxmLWRlbGV0ZXMuIFJ1biBvbmNlIHZpYSBhIHNjaGVkdWxlZCB0YXNrICh0cmlnZ2VyOiBhdC1sb2dvbikgdGhhdCB0aGUgaW5zdGFsbCBzY3JpcHQKICByZWdpc3RlcmVkOyB0aGlzIHNjcmlwdCB1bnJlZ2lzdGVycyB0aGF0IHRhc2sgb24gaXRzIGZpcnN0IHJ1biBmb3IgcnVuLW9uY2Ugc2VtYW50aWNzLiBSdW5zIGluCiAgdGhlIHVzZXIncyBpbnRlcmFjdGl2ZSBzZXNzaW9uIHNvIHRoZSBiYW5uZXIgd2luZG93IGlzIFZJU0lCTEUuCiM+CiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU2lsZW50bHlDb250aW51ZScKCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyAgICAgICAgICAgIFlvdXIgTWFya2V0cGxhY2UgQXBwIChJSVMpIGhhcyBiZWVuIGRlcGxveWVkIHN1Y2Nlc3NmdWxseSEgICAgICAgICAgICAjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIjICAgICAgICAgICAgQ3JlZGVudGlhbHMgKGlmIGFueSkgYXJlIHNob3duIGJlbG93IGFuZCBzdG9yZWQgb24gZGlzay4gICAgICAgICAgICAgICAgICAgICAgICAgICMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICJUaGlzIG1lc3NhZ2Ugd2lsbCBiZSByZW1vdmVkIGFmdGVyIHRoaXMgbG9naW4uIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIiCgoKIyBDbGVhbnVwIHRyYWNlcyBvZiB0aGUgZGVwbG95bWVudC4KUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlN5c3RlbURyaXZlXENsb3VkYmFzZUluaXRcbG9nXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpURU1QXCoiIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCkNsZWFyLUV2ZW50TG9nIC1Mb2dOYW1lIEFwcGxpY2F0aW9uLCBTeXN0ZW0gLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKCiMgR2l2ZSB0aGUgb3BlcmF0b3IgdGltZSB0byByZWFkIHRoZSBiYW5uZXIgYmVmb3JlIHRoZSB3aW5kb3cgY2xvc2VzIChpdCBydW5zIGluIHRoZWlyIHNlc3Npb24pLgpXcml0ZS1Ib3N0ICJUaGlzIHdpbmRvdyB3aWxsIGNsb3NlIGluIDIwIHNlY29uZHMuIiAtRm9yZWdyb3VuZENvbG9yIFJlZApTdGFydC1TbGVlcCAtU2Vjb25kcyAyMAoKIyBVbnJlZ2lzdGVyIHRoZSBmaXJzdC1sb2dpbiBzY2hlZHVsZWQgdGFzayAocnVuLW9uY2Ugc2VtYW50aWNzKSArIGRlbGV0ZSB0aGlzIHNjcmlwdCBpdHNlbGYuClVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJ21hcmtnZW4td2luZG93cy0yMDIyLWNsZWFudXAnIC1Db25maXJtOiRmYWxzZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQojIEFsc28gY2xlYXIgYW55IGxlZ2FjeSBSdW5PbmNlIGVudHJ5IGZyb20gb2xkZXIgaW5zdGFsbHMgKGhhcm1sZXNzIGlmIGFic2VudCkuClJlbW92ZS1JdGVtUHJvcGVydHkgLVBhdGggJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFJ1bk9uY2UnIC1OYW1lICd3aW5kb3dzLTIwMjJfY2xlYW51cCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLUZvcmNlICRQU0NvbW1hbmRQYXRoIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCg==')
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

# Install is done - remove the "installing" notice task (and stop it if it's showing) so the next
# login sees the "deployed successfully" cleanup banner, not the "still installing" one.
Stop-ScheduledTask -TaskName 'markgen-windows-2022-installing' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'markgen-windows-2022-installing' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $env:ProgramData 'markgen\windows-2022-installing.ps1') -ErrorAction SilentlyContinue

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
