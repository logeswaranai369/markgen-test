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

# Verify the management console (inetmgr) is actually present
$inetMgr = 'C:\Windows\System32\inetsrv\InetMgr.exe'
if (-not (Test-Path $inetMgr)) {
    Write-Output "InetMgr.exe missing; installing Web-Mgmt-Console explicitly"
    Install-WindowsFeature -Name Web-Mgmt-Console | Out-Null
}
if (Test-Path $inetMgr) {
    Write-Output "IIS Manager present at $inetMgr"
} else {
    throw "IIS Manager (InetMgr.exe) was not installed"
}

# Ensure a default page exists so http://localhost/ returns content
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null
if (-not (Test-Path 'C:\inetpub\wwwroot\iisstart.htm') -and -not (Test-Path 'C:\inetpub\wwwroot\index.html')) {
    Set-Content -Path 'C:\inetpub\wwwroot\index.html' -Value '<h1>IIS Windows Server - Deployed by Markgen</h1>'
    Write-Output "wrote placeholder default page"
}

# Create an IIS Manager shortcut on the Administrator desktop
$adminDesktop = 'C:\Users\Administrator\Desktop'
if (Test-Path $adminDesktop) {
    $shortcutPath = Join-Path $adminDesktop 'IIS Manager.lnk'
    if (-not (Test-Path $shortcutPath)) {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($shortcutPath)
        $sc.TargetPath = $inetMgr
        $sc.Description = 'Internet Information Services (IIS) Manager'
        $sc.Save()
        Write-Output "created IIS Manager shortcut on Administrator desktop"
    }
}

# Enable the inbound firewall rule for HTTP traffic on TCP 80
$httpRule = Get-NetFirewallRule -DisplayName 'World Wide Web Services (HTTP Traffic-In)' -ErrorAction SilentlyContinue
if ($httpRule) {
    Enable-NetFirewallRule -DisplayName 'World Wide Web Services (HTTP Traffic-In)'
    Write-Output "enabled built-in HTTP inbound firewall rule"
} else {
    if (-not (Get-NetFirewallRule -DisplayName 'IIS HTTP 80 Inbound' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'IIS HTTP 80 Inbound' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
        Write-Output "created custom HTTP inbound firewall rule on TCP 80"
    }
}

# Ensure the web service runs now and on every boot
Set-Service W3SVC -StartupType Automatic
if ((Get-Service W3SVC).Status -ne 'Running') {
    Start-Service W3SVC
}
Write-Output "IIS (W3SVC) is running and serving on port 80"
# ----- END app-specific tasks -----

Write-Stage "install: complete"
# Completion sentinel the test runner waits for (rc must be 0). Keep this the LAST line.
Write-Output "MARKGEN_DEPLOY_COMPLETE rc=0"
