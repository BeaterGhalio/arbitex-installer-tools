function Update-ConfigEAs {
    param(
        [string]$configDirEdge,
        [string]$configDirProp,
        [string]$url
    )
    Write-Log "Scarico ZIP EA per aggiornare cartelle config standard ($url)"
    $tempArchive = "$env:TEMP\arbitex_update.zip"
    $tempDir = "$env:TEMP\arbitex_update"

    try {
        Invoke-WebRequest -Uri $url -OutFile $tempArchive -UseBasicParsing
        Write-Log "Download EA config completato."
    } catch {
        Write-Log "ERRORE download EA zip: $_"
        return
    }

    if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
    Expand-Archive -Path $tempArchive -DestinationPath $tempDir -Force

    $eaHedge = 'Arbitex Hedge.ex5'
    $eaProp  = 'Arbitex Prop.ex5'
    $srcHedge = Get-ChildItem $tempDir -Recurse | Where-Object { $_.Name -eq $eaHedge } | Select-Object -First 1
    $srcProp  = Get-ChildItem $tempDir -Recurse | Where-Object { $_.Name -eq $eaProp } | Select-Object -First 1

    if (-not ($srcHedge -and $srcProp)) {
        Write-Log "EA non trovati nello zip! Controlla il pacchetto."
        return
    }

    $edgeExperts = Join-Path $configDirEdge "MQL5\Experts"
    $propExperts = Join-Path $configDirProp "MQL5\Experts"

    if (-not (Test-Path $edgeExperts)) { New-Item -ItemType Directory -Path $edgeExperts -Force | Out-Null }
    if (-not (Test-Path $propExperts)) { New-Item -ItemType Directory -Path $propExperts -Force | Out-Null }

    Copy-Item $srcHedge.FullName "$edgeExperts\$eaHedge" -Force
    Copy-Item $srcProp.FullName "$propExperts\$eaProp" -Force
    Write-Log "EA aggiornati dentro cartelle config."

    Remove-Item $tempArchive -Force
    Remove-Item $tempDir -Recurse -Force
}
