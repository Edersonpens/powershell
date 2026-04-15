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
    param (
        [string]$Tipo,
        [string]$Mensagem
    )

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Tipo) {
        "INFO"    { $prefixo = "[INFO]   " }
        "SUCESSO" { $prefixo = "[SUCESSO]" }
        "ERRO"    { $prefixo = "[ERRO]   " }
        default   { $prefixo = "[INFO]   " }
    }

    $linha = "$time $prefixo $Mensagem"
    
    $linha | Out-File -Append -FilePath $logPath -Encoding UTF8
    Write-Host $linha
}

# Separador bonito
function Write-Separator {
    param ([string]$Titulo)
    
    $linha = "=" * 80
    $linha | Out-File -Append -FilePath $logPath -Encoding UTF8
    Write-Host $linha -ForegroundColor Yellow
    
    if ($Titulo) {
        $tituloLinha = "=== $Titulo ==="
        $tituloLinha | Out-File -Append -FilePath $logPath -Encoding UTF8
        Write-Host $tituloLinha -ForegroundColor Yellow
    }
    
    $linha | Out-File -Append -FilePath $logPath -Encoding UTF8
    Write-Host $linha -ForegroundColor Yellow
    Write-Host ""
}

# ================================
# ADMIN
# ================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ================================
# DOWNLOAD COM RETRY (usado apenas na instalação manual)
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
            Write-Log "SUCESSO" "Download concluído: $([math]::Round((Get-Item $OutFile).Length / 1MB, 2)) MB"
            return $true
        }
        catch {
            Write-Log "ERRO" "Tentativa $i falhou: $($_.Exception.Message)"
            if ($i -lt $MaxAttempts) { Start-Sleep -Seconds 5 }
        }
    }
    Write-Log "ERRO" "Falha ao baixar após $MaxAttempts tentativas"
    return $false
}

# ================================
# VERIFICA SE WINGET ESTÁ INSTALADO
# ================================
function Test-WingetInstalled {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "SUCESSO" "Winget está instalado"
        return $true
    }
    Write-Log "ERRO" "Winget não está instalado"
    return $false
}

# ================================
# INSTALAÇÃO VIA WINGET
# ================================
function Install-With-Winget {
    param ($Name, $Id)

    Write-Log "INFO" "Instalando $Name via Winget"
    try {
        winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements | Out-Null
        Write-Log "SUCESSO" "$Name instalado com sucesso via Winget"
    }
    catch {
        Write-Log "ERRO" "$Name falhou na instalação via Winget: $($_.Exception.Message)"
    }
}

# ================================
# INSTALAÇÃO MANUAL (quando Winget não existe)
# ================================
function Install-Manual {
    Write-Separator "WINGET NÃO ESTÁ INSTALADO - INSTALANDO MANUALMENTE"

    $temp = "$env:TEMP\apps_install"
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    # ==================== 7-ZIP ====================
    $7zipUrl = "https://github.com/ip7z/7zip/releases/download/26.00/7z2600-x64.exe"
    $7zipFile = "$temp\7zip.exe"
    if (Download-With-Retry $7zipUrl $7zipFile) {
        try {
            Write-Log "INFO" "Instalando 7-Zip (manual)"
            $p = Start-Process $7zipFile -ArgumentList "/S" -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-Log "SUCESSO" "7-Zip instalado com sucesso (manual)"
            } else {
                Write-Log "ERRO" "7-Zip falhou (código $($p.ExitCode))"
            }
        }
        catch {
            Write-Log "ERRO" "7-Zip: $($_.Exception.Message)"
        }
    }
    Write-Host ""

    # ==================== NOTEPAD++ ====================
    try {
        Write-Log "INFO" "Obtendo URL do Notepad++"
        $xml = Invoke-WebRequest "https://notepad-plus-plus.org/update/getDownloadUrl.php?version=8&param=x64" -UseBasicParsing
        $nppUrl = ($xml.Content | Select-Xml -XPath "/GUP/Location").Node.InnerText

        $nppFile = "$temp\npp_installer.exe"
        if (Download-With-Retry $nppUrl $nppFile) {
            Write-Log "INFO" "Instalando Notepad++ (manual)"
            $p = Start-Process $nppFile -ArgumentList "/S" -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-Log "SUCESSO" "Notepad++ instalado com sucesso (manual)"
            } else {
                Write-Log "ERRO" "Notepad++ falhou (código $($p.ExitCode))"
            }
        }
    }
    catch {
        Write-Log "ERRO" "Notepad++: $($_.Exception.Message)"
    }

    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Separator "FIM DA INSTALAÇÃO MANUAL"
}

# ================================
# EXECUÇÃO PRINCIPAL
# ================================
Write-Separator "INÍCIO DA INSTALAÇÃO"

$wingetOK = Test-WingetInstalled

if ($wingetOK) {
    Write-Separator "INSTALAÇÃO VIA WINGET"
    
    # ==================== PROGRAMAS VIA WINGET ====================
    Install-With-Winget "7-Zip"     "7zip.7zip"
    Write-Host ""
    Install-With-Winget "Notepad++" "Notepad++.Notepad++"
    
} else {
    Write-Separator "WINGET NÃO INSTALADO - USANDO MÉTODO MANUAL"
    Install-Manual
}

Write-Separator "INSTALAÇÃO FINALIZADA"
Write-Host "`n✅ Processo concluído!" -ForegroundColor Green
Write-Host "📄 Log salvo em: $logPath" -ForegroundColor Cyan
