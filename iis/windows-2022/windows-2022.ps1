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

# Ensure the default site content directory exists
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null

# Ensure the HTTP inbound firewall rule is enabled (default IIS rule group)
try {
    Enable-NetFirewallRule -DisplayGroup 'World Wide Web Services (HTTP)' -ErrorAction SilentlyContinue
} catch { }
if (-not (Get-NetFirewallRule -DisplayName 'Markgen IIS HTTP 80' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Markgen IIS HTTP 80' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
    Write-Output "opened TCP 80 inbound firewall rule"
}

# Create an IIS Manager (inetmgr) shortcut on the ALL-USERS (Public) desktop so every operator
# sees it. This runs under cloudbase-init on first boot BEFORE any interactive user logs on, so
# per-user paths like C:\Users\Administrator do NOT exist yet — always use the Public desktop.
$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
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

# Ensure the IIS web publishing service runs now and on every boot
if ((Get-Service W3SVC).Status -ne 'Running') {
    Start-Service W3SVC
}
Set-Service W3SVC -StartupType Automatic
Write-Output "IIS W3SVC is running and serving on port 80"

# Verify the default site responds locally
try {
    $resp = Invoke-WebRequest -Uri 'http://localhost/' -UseBasicParsing -TimeoutSec 30
    Write-Output "IIS default site responded with HTTP $($resp.StatusCode)"
} catch {
    Write-Output "WARNING: local HTTP check failed: $($_.Exception.Message)"
}
# ----- END app-specific tasks -----

# --- Wire the first-login cleanup script (self-contained; no extra download) ---
# Drop <app>-cleanup.ps1 to disk (decoded from the embedded base64) and register a RunOnce entry so
# it runs ONCE at the operator's first interactive login: it prints the "deployed successfully"
# banner + any stored credentials, wipes install traces, then removes the hook and self-deletes.
# RunOnce (per-machine HKLM) fires for the first user who logs on — the marketplace convention.
$cleanupDir = Join-Path $env:ProgramData 'markgen'
New-Item -ItemType Directory -Force -Path $cleanupDir | Out-Null
$cleanupPath = Join-Path $cleanupDir 'windows-2022-cleanup.ps1'
[System.IO.File]::WriteAllBytes(
    $cleanupPath,
    [System.Convert]::FromBase64String('PCMKICBJTlZBUklBTlQg4oCUIHRoZSBXaW5kb3dzIGZpcnN0LWxvZ2luIGNsZWFudXAgc2NyaXB0ICg8YXBwPi1jbGVhbnVwLnBzMSkuCiAgV2luZG93cyBhbmFsb2cgb2YgdGhlIExpbnV4IDxhcHA+X2NsZWFudXAuc2g6IG9uIGZpcnN0IGludGVyYWN0aXZlIGxvZ2luIGl0IHByaW50cyB0aGUgc3VjY2VzcwogIGJhbm5lciArIGFueSBzdG9yZWQgY3JlZGVudGlhbHMsIHRoZW4gd2lwZXMgaW5zdGFsbCB0cmFjZXMgKGNsb3VkYmFzZS1pbml0IGxvZ3MsIHRlbXApIGFuZAogIHNlbGYtZGVsZXRlcy4gV2lyZWQgdG8gcnVuIG9uY2UgdmlhIGEgUnVuT25jZSByZWdpc3RyeSBlbnRyeSBzZXQgYnkgdGhlIGluc3RhbGwgc2NyaXB0LgojPgokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnCgpXcml0ZS1Ib3N0ICIjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiMgICAgICAgICAgICBZb3VyIE1hcmtldHBsYWNlIEFwcCAoSUlTKSBoYXMgYmVlbiBkZXBsb3llZCBzdWNjZXNzZnVsbHkhICAgICAgICAgICAgIyIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIyAgICAgICAgICAgIENyZWRlbnRpYWxzIChpZiBhbnkpIGFyZSBzaG93biBiZWxvdyBhbmQgc3RvcmVkIG9uIGRpc2suICAgICAgICAgICAgICAgICAgICAgICAgICAjIiAtRm9yZWdyb3VuZENvbG9yIFJlZApXcml0ZS1Ib3N0ICIjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCldyaXRlLUhvc3QgIiIKV3JpdGUtSG9zdCAiVGhpcyBtZXNzYWdlIHdpbGwgYmUgcmVtb3ZlZCBhZnRlciB0aGlzIGxvZ2luLiIgLUZvcmVncm91bmRDb2xvciBSZWQKV3JpdGUtSG9zdCAiIgoKCiMgQ2xlYW51cCB0cmFjZXMgb2YgdGhlIGRlcGxveW1lbnQuClJlbW92ZS1JdGVtIC1SZWN1cnNlIC1Gb3JjZSAiJGVudjpTeXN0ZW1Ecml2ZVxDbG91ZGJhc2VJbml0XGxvZ1wqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpSZW1vdmUtSXRlbSAtUmVjdXJzZSAtRm9yY2UgIiRlbnY6VEVNUFwqIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQpDbGVhci1FdmVudExvZyAtTG9nTmFtZSBBcHBsaWNhdGlvbiwgU3lzdGVtIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCgojIFJlbW92ZSB0aGUgUnVuT25jZSBob29rICsgdGhpcyBzY3JpcHQgaXRzZWxmLgpSZW1vdmUtSXRlbVByb3BlcnR5IC1QYXRoICdIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxSdW5PbmNlJyAtTmFtZSAnd2luZG93cy0yMDIyX2NsZWFudXAnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlClJlbW92ZS1JdGVtIC1Gb3JjZSAkUFNDb21tYW5kUGF0aCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQo=')
)
# RunOnce value: run the cleanup script hidden, bypassing execution policy. The name MUST match the
# key the cleanup script removes (windows-2022_cleanup).
$runOnce = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
New-Item -Path $runOnce -Force | Out-Null
Set-ItemProperty -Path $runOnce -Name 'windows-2022_cleanup' `
    -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $cleanupPath + '"')
Write-Stage "install: registered first-login cleanup (windows-2022_cleanup)"

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
