function Get-LocalInstallerVersion
{
    $versionFilePath = Join-Path $PSScriptRoot "installer_version.txt"

    if (-not (Test-Path $versionFilePath))
    {
        Write-Log "File versione locale installer non trovato: $versionFilePath"
        return $null
    }

    try
    {
        $firstLine = (Get-Content -Path $versionFilePath -First 1 -ErrorAction Stop).Trim()
        if (-not $firstLine)
        {
            Write-Log "File versione locale vuoto: $versionFilePath"
            return $null
        }

        $localVersion = [Version]$firstLine
        Write-Log "Versione locale installer: $localVersion"
        return $localVersion
    }
    catch
    {
        Write-Log "ERRORE lettura versione locale installer: $( $_.Exception.Message )"
        return $null
    }
}

function Get-RemoteInstallerVersion
{
    param(
        [string]$versionUrl
    )

    if (-not $versionUrl)
    {
        Write-Log "URL versione remota installer non configurato."
        return $null
    }

    try
    {
        $response = Invoke-WebRequest -Uri $versionUrl -UseBasicParsing -TimeoutSec 15
        $firstLine = $response.Content.Split("`n")[0].Trim()

        if (-not $firstLine)
        {
            Write-Log "Risposta versione remota vuota da: $versionUrl"
            return $null
        }

        $remoteVersion = [Version]$firstLine
        Write-Log "Versione remota installer: $remoteVersion"
        return $remoteVersion
    }
    catch
    {
        Write-Log "ERRORE lettura versione remota installer da $versionUrl : $( $_.Exception.Message )"
        return $null
    }
}

function Invoke-ArbitexSelfUpdate
{
    param(
        [string]$zipUrl,
        [string]$versionUrl
    )

    Write-Log "Verifica aggiornamenti per Arbitex VPS Installer..."

    $localVersion = Get-LocalInstallerVersion
    $remoteVersion = Get-RemoteInstallerVersion -versionUrl $versionUrl

    if ($localVersion -and $remoteVersion)
    {
        if ($remoteVersion -le $localVersion)
        {
            Write-Log "Installer gia aggiornato (locale=$localVersion, remoto=$remoteVersion)"
            Write-Host "Installer gia aggiornato (versione $localVersion)." -ForegroundColor Green
            return
        }

        Write-Log "Disponibile nuova versione installer: locale=$localVersion, remoto=$remoteVersion"
    }
    elseif ($remoteVersion)
    {
        Write-Log "Versione remota disponibile: $remoteVersion (versione locale non rilevata)"
    }
    else
    {
        Write-Log "Impossibile determinare la versione remota dell'installer, procedo comunque con il download se possibile."
    }

    if (-not $zipUrl)
    {
        Write-Log "Nessun URL ZIP configurato per self-update dell'installer."
        Write-Host "Nessun URL di aggiornamento configurato." -ForegroundColor Yellow
        return
    }

    $tempDirPath = Join-Path $env:TEMP "arbitex_installer_update"
    $tempZipPath = Join-Path $env:TEMP "arbitex_installer_update.zip"

    if (Test-Path $tempDirPath)
    {
        Remove-Item -Path $tempDirPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $tempZipPath)
    {
        Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Scarico nuovo installer da: $zipUrl"

    try
    {
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZipPath -UseBasicParsing -TimeoutSec 120
        Write-Log "Download pacchetto installer completato."
    }
    catch
    {
        Write-Log "ERRORE download installer ZIP da $zipUrl : $( $_.Exception.Message )"
        Write-Host "Errore nel download del pacchetto di aggiornamento." -ForegroundColor Red
        return
    }

    try
    {
        Expand-Archive -Path $tempZipPath -DestinationPath $tempDirPath -Force
        Write-Log "Archivio installer estratto in: $tempDirPath"
    }
    catch
    {
        Write-Log "ERRORE estrazione archivio installer: $( $_.Exception.Message )"
        Write-Host "Errore nell'estrazione del pacchetto di aggiornamento." -ForegroundColor Red
        return
    }

    $extractedRoot = Get-ChildItem -Path $tempDirPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $extractedRoot)
    {
        Write-Log "ERRORE: nessuna directory radice trovata dopo l'estrazione dell'installer."
        Write-Host "Pacchetto di aggiornamento non valido." -ForegroundColor Red
        return
    }

    $sourceRoot = $extractedRoot.FullName
    $targetRoot = $PSScriptRoot

    Write-Log "Copia nuovi file installer da $sourceRoot a $targetRoot"

    try
    {
        Get-ChildItem -Path $sourceRoot -Force | ForEach-Object {
            $sourcePath = $_.FullName
            $destinationPath = Join-Path $targetRoot $_.Name

            Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force -ErrorAction Stop
        }

        Write-Log "Self-update Arbitex VPS Installer completato con successo."
        Write-Host "Aggiornamento Arbitex VPS Installer completato. Riavvia lo script per usare la nuova versione." -ForegroundColor Green
    }
    catch
    {
        Write-Log "ERRORE durante la copia dei file di aggiornamento: $( $_.Exception.Message )"
        Write-Host "Errore durante l'applicazione dell'aggiornamento." -ForegroundColor Red
    }
    finally
    {
        if (Test-Path $tempDirPath)
        {
            Remove-Item -Path $tempDirPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempZipPath)
        {
            Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
        }
    }
}
