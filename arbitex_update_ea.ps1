function Update-AllMT5EAs {
    param([string]$url)

    $tempArchive = Join-Path $env:TEMP "arbitex_update.zip"
    $tempDir = Join-Path $env:TEMP "arbitex_update"

    Write-Log "Scarico ZIP EA per aggiornare tutte le installazioni MT5 ($url)"

    try {
        try
        {
            Invoke-WebRequest -Uri $url -OutFile $tempArchive -UseBasicParsing
            Write-Log "Download EA aggiornamento completato."
        }
        catch
        {
            Write-Log "ERRORE download EA zip: $( $_.Exception.Message )"
            Write-Host "❌ Errore download EA zip, verifica la connessione." -ForegroundColor Red
            return
        }

        if (Test-Path $tempDir)
        {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        Expand-Archive -Path $tempArchive -DestinationPath $tempDir -Force

        $eaHedge = 'Arbitex Hedge.ex5'
        $eaProp = 'Arbitex Prop.ex5'

        $srcHedge = Get-ChildItem $tempDir -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $eaHedge } | Select-Object -First 1
        $srcProp = Get-ChildItem $tempDir -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $eaProp } | Select-Object -First 1

        if (-not $srcHedge -or -not $srcProp)
        {
            Write-Log "EA non trovati nello zip! Attesi: '$eaHedge' e '$eaProp'"
            Write-Host "❌ EA non trovati nello zip di aggiornamento." -ForegroundColor Red
            return
        }

        $root = Join-Path $env:APPDATA "MetaQuotes\Terminal"
        if (-not (Test-Path $root))
        {
            Write-Log "❌ Directory MetaTrader 5 non trovata: $root"
            Write-Host "❌ Directory MetaTrader 5 non trovata." -ForegroundColor Red
            return
        }

        $profiles = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^[0-9A-Fa-f]{32}$' }

        $installationsFound = 0
        $updatesCount = 0

        foreach ($profile in $profiles)
        {
            $expertsPath = Join-Path $profile.FullName "MQL5\Experts"
            if (-not (Test-Path $expertsPath))
            {
                continue
            }

            $installationsFound++
            $updatedThisProfile = $false

            $hedgeTarget = Join-Path $expertsPath $eaHedge
            $propTarget = Join-Path $expertsPath $eaProp

            if (Test-Path $hedgeTarget)
            {
                try
                {
                    Copy-Item -Path $srcHedge.FullName -Destination $hedgeTarget -Force -ErrorAction Stop
                    Write-Log "EA HEDGE aggiornato in: $hedgeTarget"
                    $updatedThisProfile = $true
                }
                catch
                {
                    Write-Log "ERRORE aggiornamento EA HEDGE in $hedgeTarget : $( $_.Exception.Message )"
                }
            }

            if (Test-Path $propTarget)
            {
                try
                {
                    Copy-Item -Path $srcProp.FullName -Destination $propTarget -Force -ErrorAction Stop
                    Write-Log "EA PROP aggiornato in: $propTarget"
                    $updatedThisProfile = $true
                }
                catch
                {
                    Write-Log "ERRORE aggiornamento EA PROP in $propTarget : $( $_.Exception.Message )"
                }
            }

            if ($updatedThisProfile)
            {
                $updatesCount++
            }
        }

        Write-Log "Aggiornamento EA completato. Installazioni trovate: $installationsFound, aggiornate: $updatesCount"
        Write-Host "Installazioni trovate: $installationsFound" -ForegroundColor Cyan
        Write-Host "Installazioni aggiornate: $updatesCount" -ForegroundColor Green
    }
    finally
    {
        if (Test-Path $tempArchive)
        {
            Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempDir)
        {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
