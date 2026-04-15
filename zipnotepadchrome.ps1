# ================================
# AUTO ELEVAÇÃO (ADMIN)
# ================================
if (-not ([Security.Principal.WindowsPrincipal] `
[Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
[Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "Reiniciando como administrador..."
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ================================
# FUNÇÃO LOG
# ================================
function Write-Log {
    param ($msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$time - $msg"
}

# ================================
# VERIFICA / INSTALA WINGET
# ================================
function Ensure-Winget {

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget já está instalado."
        return
    }

    Write-Log "Winget não encontrado. Instalando App Installer..."

    $url = "https://aka.ms/getwinget"
    $file = "$env:TEMP\winget.appxbundle"

    Invoke-WebRequest $url -OutFile $file

    Add-AppxPackage -Path $file

    Start-Sleep -Seconds 5

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget instalado com sucesso."
    } else {
        Write-Log "Falha ao instalar Winget. Verifique manualmente."
        exit
    }
}

# ================================
# BARRA DE PROGRESSO
# ================================
function Show-Progress {
    param ($Activity, $Status, $Percent)
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $Percent
}

# ================================
# INSTALAR / ATUALIZAR
# ================================
function Install-Or-Update {
    param ($Name, $Id)

    Show-Progress "Instalação de programas" "Processando $Name..." 0

    winget install -e --id $Id `
    --accept-package-agreements `
    --accept-source-agreements `
    --silent | Out-Null

    Show-Progress "Instalação de programas" "$Name instalado/verificado" 50

    winget upgrade -e --id $Id `
    --accept-package-agreements `
    --accept-source-agreements `
    --silent | Out-Null

    Show-Progress "Instalação de programas" "$Name atualizado" 100

    Write-Log "$Name finalizado."
}

# ================================
# EXECUÇÃO
# ================================
Write-Log "===== INÍCIO ====="

Ensure-Winget

Show-Progress "Instalação de programas" "Iniciando..." 5

Install-Or-Update "7-Zip" "7zip.7zip"
Show-Progress "Instalação de programas" "Indo para próximo..." 30

Install-Or-Update "Notepad++" "Notepad++.Notepad++"
Show-Progress "Instalação de programas" "Indo para próximo..." 60

Install-Or-Update "Google Chrome" "Google.Chrome"
Show-Progress "Instalação de programas" "Finalizando..." 100

Write-Progress -Activity "Instalação de programas" -Completed

Write-Log "===== FINALIZADO ====="
Write-Host "Tudo concluído com sucesso!"