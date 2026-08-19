#Requires -RunAsAdministrator
# ================================
# CONFIGURAÇÃO
# ================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = 'Stop'
$dataHora  = Get-Date -Format "ddMMyyyy_HHmmss"
$logPath   = Join-Path ([Environment]::GetFolderPath("Desktop")) "Log_Install_$dataHora.txt"
$tempDir   = Join-Path $env:TEMP "apps_install"

# ================================
# FUNÇÕES AUXILIARES
# ================================
function Write-Log {
    param([ValidateSet('INFO','SUCESSO','ERRO')][string]$Tipo, [string]$Mensagem)
    $prefix = switch ($Tipo) { 'SUCESSO' {'[SUCESSO]'} 'ERRO' {'[ERRO]  '} default {'[INFO]  '} }
    $linha  = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $prefix $Mensagem"
    $linha | Out-File -Append -FilePath $logPath -Encoding UTF8
    Write-Host $linha
}

function Write-Separator {
    param([string]$Titulo)
    $linha = '=' * 80
    $linha, $(if ($Titulo) {"=== $Titulo ==="}), $linha | ForEach-Object {
        $_ | Out-File -Append -FilePath $logPath -Encoding UTF8
        Write-Host $_ -ForegroundColor Yellow
    }
    Write-Host
}

function Test-AppInstalled {
    param(
        [string]$Name,
        [string[]]$ExePaths,
        [string[]]$RegPaths
    )
    foreach ($p in $ExePaths) {
        if (Test-Path $p) {
            Write-Log SUCESSO "$Name já instalado: $p"
            return $true
        }
    }
    foreach ($r in $RegPaths) {
        if (Test-Path $r) {
            Write-Log SUCESSO "$Name já instalado (registro)"
            return $true
        }
    }
    Write-Log INFO "$Name não está instalado"
    return $false
}

function Download-WithRetry {
    param([string]$Url, [string]$OutFile, [int]$MaxAttempts = 3)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-Log ERRO "URL vazia"
        return $false
    }

    try {
        $uri = [Uri]$Url
        if ($uri.Scheme -notin 'http','https' -or [string]::IsNullOrWhiteSpace($uri.Host)) {
            throw "URL inválida"
        }
    } catch {
        Write-Log ERRO "URL inválida: $Url"
        return $false
    }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            Write-Log INFO "Baixando ($i/$MaxAttempts): $Url"
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 120 -UseBasicParsing -ErrorAction Stop

            $item = Get-Item $OutFile -ErrorAction Stop
            if ($item.Length -lt 100KB) { throw "Arquivo muito pequeno ($([math]::Round($item.Length/1KB,1)) KB)" }

            Write-Log SUCESSO "Download OK: $([math]::Round($item.Length/1MB,2)) MB"
            return $true
        }
        catch {
            Write-Log ERRO "Tentativa $i falhou: $($_.Exception.Message)"
            if ($i -lt $MaxAttempts) {
                Write-Log INFO "Aguardando 5s..."
                Start-Sleep 5
            }
        }
    }
    Write-Log ERRO "Falha após $MaxAttempts tentativas"
    return $false
}

function Get-GitHubAssetUrl {
    param(
        [string]$Repo,          # ex: "ip7z/7zip"
        [string]$NamePattern,   # regex do nome do arquivo
        [string]$AppName
    )
    try {
        Write-Log INFO "Obtendo versão mais recente do $AppName"
        $headers = @{ 'User-Agent' = 'PowerShell'; 'Accept' = 'application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                                     -Headers $headers -UseBasicParsing

        $asset = $release.assets | Where-Object { $_.name -match $NamePattern } | Select-Object -First 1
        if (-not $asset -or [string]::IsNullOrWhiteSpace($asset.browser_download_url)) {
            throw "Asset não encontrado com o padrão '$NamePattern'"
        }

        Write-Log SUCESSO "Versão: $($release.tag_name) → $($asset.name)"
        return $asset.browser_download_url
    }
    catch {
        Write-Log ERRO "Falha ao obter URL do $AppName`: $($_.Exception.Message)"
        return $null
    }
}

function Install-WithWinget {
    param([string]$Name, [string]$Id)

    Write-Log INFO "Instalando $Name via Winget..."
    try {
        $null = winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Log SUCESSO "$Name instalado via Winget"
            return $true
        }
        throw "Exit code: $LASTEXITCODE"
    }
    catch {
        Write-Log ERRO "$Name falhou via Winget: $($_.Exception.Message)"
        return $false
    }
}

function Install-AppManual {
    param(
        [string]$Name,
        [string]$Temp,
        [scriptblock]$IsInstalled,
        [string]$Repo,
        [string]$NamePattern,
        [string]$InstallerArgs = '/S'
    )

    if (& $IsInstalled) {
        Write-Log INFO "$Name já instalado. Ignorando."
        return $true
    }

    Write-Log INFO "Iniciando instalação manual do $Name"
    $url = Get-GitHubAssetUrl -Repo $Repo -NamePattern $NamePattern -AppName $Name
    if (-not $url) { return $false }

    $file = Join-Path $Temp "$($Name -replace '[^\w]','_')_installer.exe"
    if (-not (Download-WithRetry $url $file)) { return $false }

    try {
        Write-Log INFO "Executando instalador do $Name..."
        $proc = Start-Process -FilePath $file -ArgumentList $InstallerArgs -Wait -PassThru
        Start-Sleep 2

        if ($proc.ExitCode -eq 0 -and (& $IsInstalled)) {
            Write-Log SUCESSO "$Name instalado com sucesso"
            return $true
        }
        Write-Log ERRO "$Name falhou (ExitCode: $($proc.ExitCode) ou não detectado após instalação)"
        return $false
    }
    catch {
        Write-Log ERRO "Erro ao instalar $Name`: $($_.Exception.Message)"
        return $false
    }
}

# ================================
# DEFINIÇÕES DOS APLICATIVOS
# ================================
$apps = @(
    @{
        Name         = '7-Zip'
        WingetId     = '7zip.7zip'
        ExePaths     = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")
        RegPaths     = @('HKLM:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\WOW6432Node\7-Zip')
        Repo         = 'ip7z/7zip'
        NamePattern  = 'x64\.exe$'
    },
    @{
        Name         = 'Notepad++'
        WingetId     = 'Notepad++.Notepad++'
        ExePaths     = @("$env:ProgramFiles\Notepad++\notepad++.exe", "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe")
        RegPaths     = @('HKLM:\SOFTWARE\Notepad++', 'HKLM:\SOFTWARE\WOW6432Node\Notepad++')
        Repo         = 'notepad-plus-plus/notepad-plus-plus'
        NamePattern  = 'Installer\.x64\.exe$'   # fallback interno se necessário
    }
)

# ================================
# EXECUÇÃO PRINCIPAL
# ================================
Write-Separator "INÍCIO DA INSTALAÇÃO"

# Verificação inicial
$alreadyInstalled = @{}
foreach ($app in $apps) {
    $alreadyInstalled[$app.Name] = Test-AppInstalled -Name $app.Name -ExePaths $app.ExePaths -RegPaths $app.RegPaths
}

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if ($hasWinget) { Write-Log SUCESSO "Winget disponível" } else { Write-Log INFO "Winget não encontrado" }

# Pasta temporária
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

if ($hasWinget) {
    Write-Separator "INSTALAÇÃO VIA WINGET"

    foreach ($app in $apps) {
        if ($alreadyInstalled[$app.Name]) {
            Write-Log INFO "$($app.Name) já instalado. Pulando."
            continue
        }

        $ok = Install-WithWinget -Name $app.Name -Id $app.WingetId
        if (-not $ok) {
            Write-Log INFO "Fallback manual para $($app.Name)"
            Install-AppManual -Name $app.Name -Temp $tempDir `
                -IsInstalled { Test-AppInstalled -Name $app.Name -ExePaths $app.ExePaths -RegPaths $app.RegPaths } `
                -Repo $app.Repo -NamePattern $app.NamePattern
        }
        Write-Host
    }
}
else {
    Write-Separator "WINGET NÃO INSTALADO - INSTALAÇÃO MANUAL"
    foreach ($app in $apps) {
        Install-AppManual -Name $app.Name -Temp $tempDir `
            -IsInstalled { Test-AppInstalled -Name $app.Name -ExePaths $app.ExePaths -RegPaths $app.RegPaths } `
            -Repo $app.Repo -NamePattern $app.NamePattern
        Write-Host
    }
}

# Limpeza
Write-Log INFO "Limpando arquivos temporários"
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Verificação final
Write-Separator "VERIFICAÇÃO FINAL"
foreach ($app in $apps) {
    if (Test-AppInstalled -Name $app.Name -ExePaths $app.ExePaths -RegPaths $app.RegPaths) {
        Write-Log SUCESSO "$($app.Name): INSTALADO"
    } else {
        Write-Log ERRO "$($app.Name): NÃO INSTALADO"
    }
}

Write-Separator "INSTALAÇÃO FINALIZADA"
Write-Host "Processo concluído!" -ForegroundColor Green
Write-Host "Log salvo em: $logPath" -ForegroundColor Cyan
Write-Host
