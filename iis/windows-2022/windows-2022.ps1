# requires -RunAsAdministrator
<#
  INVARIANT scaffold — the Windows marketplace install artifact (<app>.ps1).

  This is the cloudbase-init user-data script for a Windows guest: cloudbase-init runs it once on
  first boot as SYSTEM. Unlike Linux (bootstrap .sh that stages files + runs an Ansible playbook),
  the PowerShell IS the install logic — there is no separate playbook. The engine renders the
  invariant frame (strict errors, stage banners, secret storage, the completion marker) and splices
  in the LLM-generated install steps between the BEGIN/END markers.

  Markers MUST match runner._install_tasks_from_artifacts so a repair can recover the fragment.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Stage($msg) { Write-Output "[markgen] $msg" }

Write-Stage "install: IIS on win2022"


# ----- BEGIN app-specific tasks (LLM-generated from AppSpec) -----
$needed = 'Web-Server', 'Web-Mgmt-Console', 'Web-Mgmt-Tools'
$missing = $needed | Where-Object { -not (Get-WindowsFeature -Name $_).Installed }
if ($missing) {
    Write-Output "installing IIS features: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing -IncludeManagementTools | Out-Null
} else {
    Write-Output "IIS features already installed"
}

# Ensure a default site document exists so http://localhost/ responds.
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null
if (-not (Test-Path 'C:\inetpub\wwwroot\iisstart.htm') -and -not (Test-Path 'C:\inetpub\wwwroot\index.html')) {
    Set-Content -Path 'C:\inetpub\wwwroot\index.html' -Value '<h1>IIS Windows Server - Deployed by Markgen</h1>'
    Write-Output "wrote placeholder default document"
}

# Open the HTTP firewall rule (idempotent).
$fwRule = 'World Wide Web Services (HTTP Traffic-In)'
$existing = Get-NetFirewallRule -DisplayName $fwRule -ErrorAction SilentlyContinue
if ($existing) {
    Enable-NetFirewallRule -DisplayName $fwRule
    Write-Output "enabled firewall rule: $fwRule"
} else {
    New-NetFirewallRule -DisplayName $fwRule -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
    Write-Output "created firewall rule for TCP 80"
}

# Create an IIS Manager (inetmgr) shortcut on the ALL-USERS (Public) desktop. This runs under
# cloudbase-init on first boot before any interactive user profile exists, so target the Public
# desktop (always present) rather than a per-user path.
$inetMgr = Join-Path $env:windir 'System32\inetsrv\InetMgr.exe'
$publicDesktop = Join-Path $env:PUBLIC 'Desktop'
$lnk = Join-Path $publicDesktop 'IIS Manager.lnk'
if (Test-Path $inetMgr) {
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $inetMgr
    $sc.Description = 'Internet Information Services (IIS) Manager'
    $sc.Save()
    Write-Output "created IIS Manager shortcut on the all-users desktop"
} else {
    Write-Output "WARNING: InetMgr.exe not found at $inetMgr"
}

# Ensure the World Wide Web Publishing Service runs now and on every boot.
if ((Get-Service W3SVC).Status -ne 'Running') {
    Start-Service W3SVC
}
Set-Service W3SVC -StartupType Automatic
Write-Output "W3SVC is running (Automatic); IIS serving on port 80, IIS Manager installed"
# ----- END app-specific tasks -----

# --- Wire the first-login cleanup script (self-contained; no extra download) ---
# Drop <app>-cleanup.ps1 to disk (decoded from the embedded base64), then run it at the operator's
# first interactive login: it prints the "deployed successfully" banner + any stored credentials,
# wipes install traces, unregisters itself and self-deletes.
#
# We use a SCHEDULED TASK triggered at logon (NOT a RunOnce entry). RunOnce ran the script HIDDEN
# and/or got consumed by a non-interactive post-install logon, so the operator never SAW the banner
# (seen live). A scheduled task with an interactive-user principal runs powershell IN THE USER'S
# OWN SESSION with a VISIBLE console window — which is the whole point of the banner. The cleanup
# script unregisters this task on its first run, giving run-once semantics.
$cleanupDir = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $cleanupDir | Out-Null
$cleanupPath = Join-Path $cleanupDir 'windows-2022-cleanup.ps1'
[System.IO.File]::WriteAllBytes(
    $cleanupPath,
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQg4oCUIHRoZSBXaW5kb3dzIGZpcnN0LWxvZ2luIGNsZWFudXAgc2NyaXB0ICg8YXBwPi1jbGVhbnVwLnBzMSkuCiAgV2luZG93cyBhbmFsb2cgb2YgdGhlIExpbnV4IDxhcHA+X2NsZWFudXAuc2g6IG9uIGZpcnN0IGludGVyYWN0aXZlIGxvZ2luIGl0IHByaW50cyB0aGUgc3VjY2VzcwogIGJhbm5lciArIGFueSBzdG9yZWQgY3JlZGVudGlhbHMsIHRoZW4gd2lwZXMgaW5zdGFsbCB0cmFjZXMgKGNsb3VkYmFzZS1pbml0IGxvZ3MsIHRlbXApIGFuZAogIHNlbGYtZGVsZXRlcy4gUnVuIG9uY2UgdmlhIGEgc2NoZWR1bGVkIHRhc2sgKHRyaWdnZXI6IGF0LWxvZ29uKSB0aGF0IHRoZSBpbnN0YWxsIHNjcmlwdAogIHJlZ2lzdGVyZWQ7IHRoaXMgc2NyaXB0IHVucmVnaXN0ZXJzIHRoYXQgdGFzayBvbiBpdHMgZmlyc3QgcnVuIGZvciBydW4tb25jZSBzZW1hbnRpY3MuIFJ1bnMgaW4KICB0aGUgdXNlcidzIGludGVyYWN0aXZlIHNlc3Npb24gc28gdGhlIGJhbm5lciB3aW5kb3cgaXMgVklTSUJMRS4KIz4KJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTaWxlbnRseUNvbnRpbnVlJwoKV3JpdGUtSG9zdCAiIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIjICAgICAgICAgICAgWW91ciBNYXJrZXRwbGFjZSBBcHAgKElJUykgaGFzIGJlZW4gZGVwbG95ZWQgc3VjY2Vzc2Z1bGx5ISAgICAgICAgICAgICMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiMgICAgICAgICAgICBDcmVkZW50aWFscyAoaWYgYW55KSBhcmUgc2hvd24gYmVsb3cgYW5kIHN0b3JlZCBvbiBkaXNrLiAgICAgICAgICAgICAgICAgICAgICAgICAgIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIiCldyaXRlLUhvc3QgIlRoaXMgbWVzc2FnZSB3aWxsIGJlIHJlbW92ZWQgYWZ0ZXIgdGhpcyBsb2dpbi4iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiIKCgojIENsZWFudXAgdHJhY2VzIG9mIHRoZSBkZXBsb3ltZW50LgpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6U3lzdGVtRHJpdmVcQ2xvdWRiYXNlSW5pdFxsb2dcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKUmVtb3ZlLUl0ZW0gLVJlY3Vyc2UgLUZvcmNlICIkZW52OlRFTVBcKiIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKQ2xlYXItRXZlbnRMb2cgLUxvZ05hbWUgQXBwbGljYXRpb24sIFN5c3RlbSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQoKIyBHaXZlIHRoZSBvcGVyYXRvciB0aW1lIHRvIHJlYWQgdGhlIGJhbm5lciBiZWZvcmUgdGhlIHdpbmRvdyBjbG9zZXMgKGl0IHJ1bnMgaW4gdGhlaXIgc2Vzc2lvbikuCldyaXRlLUhvc3QgIlRoaXMgd2luZG93IHdpbGwgY2xvc2UgaW4gMjAgc2Vjb25kcy4iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkClN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIwCgojIFVucmVnaXN0ZXIgdGhlIGZpcnN0LWxvZ2luIHNjaGVkdWxlZCB0YXNrIChydW4tb25jZSBzZW1hbnRpY3MpICsgZGVsZXRlIHRoaXMgc2NyaXB0IGl0c2VsZi4KVW5yZWdpc3Rlci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAnbWFya2dlbi13aW5kb3dzLTIwMjItY2xlYW51cCcgLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiMgQWxzbyBjbGVhciBhbnkgbGVnYWN5IFJ1bk9uY2UgZW50cnkgZnJvbSBvbGRlciBpbnN0YWxscyAoaGFybWxlc3MgaWYgYWJzZW50KS4KUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cUnVuT25jZScgLU5hbWUgJ3dpbmRvd3MtMjAyMl9jbGVhbnVwJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtRm9yY2UgJFBTQ29tbWFuZFBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUK')
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

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
