# ================================
# TLS
# ================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================================
# LOG
# ================================
$dataHora = Get-Date -Format "ddMMyyyy_HHmmss"
$desktop = [Environment]::GetFolderPath("Desktop")
$logPath = "$desktop\Log_Install_$dataHora.txt"

function Write-Log {
    param ($tipo, $msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linha = "$time [$tipo] $msg"
    $linha | Out-File -Append -FilePath $logPath
    Write-Host $linha
}

# ================================
# ADMIN
# ================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ================================
# FUNÇÃO DE DOWNLOAD COM RETRY
# ================================
function Download-With-Retry {
    param (
        [string]$Url,
        [string]$OutFile,
        [int]$MaxAttempts = 3
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            Write-Log "INFO" "Baixando ($i/$MaxAttempts): $Url"
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 60 -ErrorAction Stop
            if (Test-Path $OutFile) {
                Write-Log "SUCESSO" "Download concluído: $([math]::Round((Get-Item $OutFile).Length / 1MB, 2)) MB"
                return $true
            }
        }
        catch {
            Write-Log "ERRO" "Tentativa $i falhou: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
    Write-Log "ERRO" "Falha ao baixar após $MaxAttempts tentativas: $Url"
    return $false
}

# ================================
# WINGET
# ================================
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "SUCESSO" "Winget já instalado"
        return $true
    }

    Write-Log "INFO" "Tentando instalar Winget..."
    $file = "$env:TEMP\winget.appxbundle"

    try {
        # Tenta baixar com retry
        if (Download-With-Retry -Url "https://aka.ms/getwinget" -OutFile $file) {
            Add-AppxPackage -Path $file -ErrorAction Stop
            Start-Sleep 8
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Log "SUCESSO" "Winget instalado com sucesso"
                return $true
            }
        }
    }
    catch {
        Write-Log "ERRO" "Winget falhou: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    }
    return $false
}

# ================================
# WINGET INSTALL
# ================================
function Install-Winget {
    param ($Name, $Id)
    try {
        Write-Log "INFO" "Instalando $Name via Winget"
        winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements | Out-Null
        Write-Log "SUCESSO" "$Name instalado via Winget"
    }
    catch {
        Write-Log "ERRO" "$Name falhou via Winget: $($_.Exception.Message)"
    }
}

# ================================
# INSTALAÇÃO MANUAL (fallback)
# ================================
function Install-Manual {
    Write-Log "INFO" "===== TENTATIVA 2 - MANUAL ====="
    $temp = "$env:TEMP\apps_install"
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    # 7-Zip (versão atual 2026)
    $7zipUrl = "https://github.com/ip7z/7zip/releases/download/26.00/7z2600-x64.exe"
    $7zipFile = "$temp\7zip.exe"
    if (Download-With-Retry $7zipUrl $7zipFile) {
        try {
            Write-Log "INFO" "Instalando 7-Zip"
            $p = Start-Process $7zipFile -ArgumentList "/S" -Wait -PassThru
            if ($p.ExitCode -eq 0) { Write-Log "SUCESSO" "7-Zip instalado" }
            else { Write-Log "ERRO" "7-Zip - Código de saída $($p.ExitCode)" }
        }
        catch { Write-Log "ERRO" "7-Zip falhou: $($_.Exception.Message)" }
    }

    # Notepad++ (URL dinâmica oficial)
    try {
        Write-Log "INFO" "Obtendo URL do Notepad++ mais recente"
        $xml = Invoke-WebRequest "https://notepad-plus-plus.org/update/getDownloadUrl.php?version=8&param=x64" -UseBasicParsing
        $nppUrl = ($xml.Content | Select-Xml -XPath "/GUP/Location").Node.InnerText

        $nppFile = "$temp\npp_installer.exe"
        if (Download-With-Retry $nppUrl $nppFile) {
            Write-Log "INFO" "Instalando Notepad++"
            $p = Start-Process $nppFile -ArgumentList "/S" -Wait -PassThru
            if ($p.ExitCode -eq 0) { Write-Log "SUCESSO" "Notepad++ instalado" }
            else { Write-Log "ERRO" "Notepad++ - Código de saída $($p.ExitCode)" }
        }
    }
    catch { Write-Log "ERRO" "Notepad++ falhou: $($_.Exception.Message)" }

    # Google Chrome (Offline Installer)
    $chromeUrl = "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe"
    $chromeFile = "$temp\chrome_setup.exe"
    if (Download-With-Retry $chromeUrl $chromeFile) {
        try {
            Write-Log "INFO" "Instalando Chrome (offline)"
            $p = Start-Process $chromeFile -ArgumentList "/silent /install" -Wait -PassThru
            if ($p.ExitCode -eq 0) { Write-Log "SUCESSO" "Chrome instalado" }
            else { Write-Log "ERRO" "Chrome - Código de saída $($p.ExitCode)" }
        }
        catch { Write-Log "ERRO" "Chrome falhou: $($_.Exception.Message)" }
    }

    # Limpeza
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "INFO" "===== FIM TENTATIVA 2 ====="
}

# ================================
# EXECUÇÃO PRINCIPAL
# ================================
Write-Log "INFO" "===== INÍCIO ====="

$wingetOK = Ensure-Winget

if ($wingetOK) {
    Write-Log "INFO" "===== TENTATIVA 1 - WINGET ====="
    Install-Winget "7-Zip"      "7zip.7zip"
    Install-Winget "Notepad++"  "Notepad++.Notepad++"
    Install-Winget "Google Chrome" "Google.Chrome"
} else {
    Write-Log "INFO" "Winget indisponível ou falhou → usando instalação manual"
    Install-Manual
}

Write-Log "INFO" "===== FINALIZADO ====="
Write-Host "`nScript finalizado!" -ForegroundColor Green
Write-Host "Log salvo em: $logPath" -ForegroundColor Cyan
