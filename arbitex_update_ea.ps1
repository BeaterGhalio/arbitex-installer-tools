function Update-AllMT5EAs {
    param([string]$url)
    Write-Host "[EA UPDATE] Download ZIP aggiornamenti..."
    $tempArchive = "$env:TEMP\arbitex_update.zip"
    $tempDir = "$env:TEMP\arbitex_update"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tempArchive -UseBasicParsing
        Write-Host "   Download completato."
    } catch { Write-Host "❌ Errore download EA zip: $_"; return }
    if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
    Expand-Archive -Path $tempArchive -DestinationPath $tempDir -Force

    $eaHedge = 'Arbitex Hedge.ex5'
    $eaProp  = 'Arbitex Prop.ex5'
    $srcHedge = Get-ChildItem $tempDir -Recurse | Where-Object { $_.Name -eq $eaHedge } | Select-Object -First 1
    $srcProp  = Get-ChildItem $tempDir -Recurse | Where-Object { $_.Name -eq $eaProp } | Select-Object -First 1

    $root = "$env:APPDATA\MetaQuotes\Terminal"
    if (-not (Test-Path $root)) { Write-Host "❌ Directory MetaTrader 5 non trovata!"; return }
    $installationsFound = 0
    $updatesCount = 0

    Get-ChildItem $root -Directory | ForEach-Object {
        $expPath = "$($_.FullName)\MQL5\Experts"
        if (Test-Path $expPath) {
            $installationsFound++
            $updated = $false
            if (Test-Path "$expPath\$eaHedge") {
                Copy-Item $srcHedge.FullName "$expPath\$eaHedge" -Force
                $updated = $true
            }
            if (Test-Path "$expPath\$eaProp") {
                Copy-Item $srcProp.FullName "$expPath\$eaProp" -Force
                $updated = $true
            }
            if ($updated) { $updatesCount++ }
        }
    }
    Write-Host "Installazioni trovate: $installationsFound"
    Write-Host "Installazioni aggiornate: $updatesCount"
    Remove-Item $tempArchive -Force
    Remove-Item $tempDir -Recurse -Force
}
