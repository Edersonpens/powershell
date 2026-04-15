function Ensure-Winget {

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget já está instalado."
        return
    }

    Write-Log "Winget não encontrado. Instalando dependências..."

    try {
        $temp = "$env:TEMP\winget_install"
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        # URLs oficiais
        $vclibs = "$temp\vclibs.appx"
        $xaml = "$temp\xaml.appx"
        $winget = "$temp\winget.appxbundle"

        Invoke-WebRequest "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $vclibs -ErrorAction Stop
        Invoke-WebRequest "https://github.com/microsoft/microsoft-ui-xaml/releases/latest/download/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile $xaml -ErrorAction Stop
        Invoke-WebRequest "https://aka.ms/getwinget" -OutFile $winget -ErrorAction Stop

        # Instala na ordem correta
        Add-AppxPackage -Path $vclibs -ErrorAction Stop
        Add-AppxPackage -Path $xaml -ErrorAction Stop
        Add-AppxPackage -Path $winget -ErrorAction Stop

        Start-Sleep -Seconds 5

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Winget instalado com sucesso."
        }
        else {
            throw "Winget não foi reconhecido após instalação."
        }
    }
    catch {
        Write-ErrorLog "Erro ao instalar Winget: $($_.Exception.Message)"
        Write-Host "Falha ao instalar Winget. Veja o log."
        exit
    }
}
