#ps1_sysnative
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$Url='https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/mariadb/windows-2025/windows-2025.ps1'
$Script="$env:TEMP\markgen-install.ps1"
foreach($i in 1..8){ try{ Invoke-WebRequest $Url -OutFile $Script -UseBasicParsing -TimeoutSec 60; break }catch{ Start-Sleep 20 } }
& powershell -NoProfile -ExecutionPolicy Bypass -File $Script; exit $LASTEXITCODE
