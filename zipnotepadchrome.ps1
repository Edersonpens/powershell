# ================================
# TLS
# ================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================================
# LOG
# ================================
$dataHora = Get-Date -Format "ddMMyyyy_HHmmss"
$desktop = [Environment]::GetFolderPath("Desktop")
$logErro = "$desktop\Log_erro_$dataHora.txt"

function Write-ErrorLog {
    param ($msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time - ERRO - $msg" | Out-File -Append -FilePath $logErro
}

function Write-HostLog {
    param ($msg)
    Write-Host $msg
}

# ================================
# TENTA INSTALAR WINGET
# ================================
function Try-Install-Winget {

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        return $true
    }

    try {
        $file = "$env:TEMP\winget.appxbundle"
        Invoke-WebRequest "https://aka.ms/getwinget" -OutFile $file -ErrorAction Stop
        Add-AppxPackage -Path $file -ErrorAction Stop

        Start-Sleep 5

        return (Get-Command winget -ErrorAction SilentlyContinue)
    }
    catch {
        Write-ErrorLog "Falha ao instalar Winget: $($_.Exception.Message)"
        return $false
    }
}

# ================================
# INSTALAÇÃO MANUAL (FALLBACK)
# ================================
function Install-Manual {

    Write-HostLog "Instalação manual iniciada..."

    try {
        $temp = "$env:TEMP\apps"
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        # 7-Zip
        $zip = "$temp\7zip.exe"
        Invoke-WebRequest "https://www.7-zip.org/a/7z2301-x64.exe" -OutFile $zip
        Start-Process $zip -ArgumentList "/S" -Wait

        # Notepad++
        $npp = "$temp\npp.exe"
        Invoke-WebRequest "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.x64.Installer.exe" -OutFile $npp
        Start-Process $npp -ArgumentList "/S" -Wait

        # Chrome
        $chrome = "$temp\chrome.exe"
        Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome/install_chrome.exe" -OutFile $chrome
        Start-Process $chrome -ArgumentList "/silent /install" -Wait

        Write-HostLog "Instalação manual concluída."
    }
    catch {
        Write-ErrorLog "Erro na instalação manual: $($_.Exception.Message)"
    }
}

# ================================
# EXECUÇÃO
# ================================
Write-Host "Iniciando..."

$wingetOK = Try-Install-Winget

if ($wingetOK) {
    Write-Host "Winget OK, usando instalação automática..."

    winget install -e --id 7zip.7zip --silent
    winget install -e --id Notepad++.Notepad++ --silent
    winget install -e --id Google.Chrome --silent
}
else {
    Write-Host "Winget falhou, usando modo manual..."
    Install-Manual
}

Write-Host "Finalizado!"
Write-Host "Log de erro: $logErro"
