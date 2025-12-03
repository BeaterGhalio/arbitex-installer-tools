# =========================================
# ARBITEX VPS - Cleanup (CON APPDATA CLEANUP)
# =========================================

function Stop-AllMT5Processes {
    Write-Log "Terminazione processi MT5..."
    $processes = @("terminal", "terminal64", "metaeditor", "metaeditor64")
    
    foreach ($processName in $processes) {
        try {
            Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log "Processo terminato: $processName"
        } catch {}
    }
    
    Start-Sleep -Seconds 2
}

function Remove-Safely {
    param([string]$path)
    
    if (-not (Test-Path $path)) {
        return $true
    }
    
    try {
        # Rimuovi attributi di sistema/readonly
        Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Attributes = 'Normal' } catch {}
        }
        
        # Primo tentativo
        Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        # Secondo tentativo dopo delay
        Start-Sleep -Seconds 2
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }
}

function Show-InstallationList {
    param([string]$baseInstallPath)
    
    $installations = @()
    
    if (Test-Path $baseInstallPath) {
        $folders = Get-ChildItem -Path $baseInstallPath -Directory -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            $installations += @{
                Name = $folder.Name
                Path = $folder.FullName
                Size = (Get-ChildItem -Path $folder.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
            }
        }
    }
    
    return $installations
}

function Show-SelectiveRemovalMenu {
    param([array]$installations, [string]$baseInstallPath)
    
    if ($installations.Count -eq 0) {
        Write-Host "Nessuna istanza MT5 trovata in: $baseInstallPath" -ForegroundColor Yellow
        return @()
    }
    
    $selected = @()
    $continue = $true
    
    while ($continue) {
        Clear-Host
        Write-Host "=================================================="
        Write-Host "  SELEZIONE ISTANZE DA RIMUOVERE"
        Write-Host "=================================================="
        Write-Host ""
        
        for ($i = 0; $i -lt $installations.Count; $i++) {
            $inst = $installations[$i]
            $size = [Math]::Round($inst.Size, 2)
            
            if ($selected -contains $i) {
                Write-Host "[X] ($($i+1)) $($inst.Name) - ${size} MB" -ForegroundColor Green
            } else {
                Write-Host "[ ] ($($i+1)) $($inst.Name) - ${size} MB"
            }
        }
        
        Write-Host ""
        Write-Host "[0] Conferma selezione"
        Write-Host "[a] Seleziona tutto"
        Write-Host "[c] Cancella selezione"
        Write-Host ""
        
        $choice = (Read-Host "Scelta [1-$($installations.Count)], [0] Conferma, [a] Tutto, [c] Cancella").Trim().ToLower()
        
        if ($choice -eq "0") {
            if ($selected.Count -eq 0) {
                Write-Host "Nessuna istanza selezionata." -ForegroundColor Yellow
                Start-Sleep 1
            } else {
                $continue = $false
            }
        } elseif ($choice -eq "a") {
            $selected = @(0..($installations.Count-1))
        } elseif ($choice -eq "c") {
            $selected = @()
        } elseif ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $installations.Count) {
                if ($selected -contains $idx) {
                    $selected = $selected | Where-Object { $_ -ne $idx }
                } else {
                    $selected += $idx
                }
            }
        } else {
            Write-Host "Scelta non valida." -ForegroundColor Red
            Start-Sleep 1
        }
    }
    
    $selectedInstallations = @()
    foreach ($idx in $selected) {
        $selectedInstallations += $installations[$idx]
    }
    
    return $selectedInstallations
}

function Show-ConfirmationMenuCleanup {
    param([array]$selectedInstallations, [bool]$includeAppData)
    
    Clear-Host
    Write-Host "=================================================="
    Write-Host "  RIEPILOGO RIMOZIONE"
    Write-Host "=================================================="
    Write-Host ""
    Write-Host "ISTANZE DA RIMUOVERE:" -ForegroundColor Red
    $totalSize = 0
    foreach ($inst in $selectedInstallations) {
        $size = [Math]::Round($inst.Size, 2)
        Write-Host "  - $($inst.Name) - ${size} MB"
        $totalSize += $inst.Size
    }
    Write-Host ""
    Write-Host "SPAZIO LIBERATO: $([Math]::Round($totalSize, 2)) MB" -ForegroundColor Yellow
    
    if ($includeAppData) {
        Write-Host ""
        Write-Host "Profili e dati in AppData saranno rimossi." -ForegroundColor Red
    }
    
    Write-Host ""
    
    $confirm = (Read-Host "CONFERMI LA RIMOZIONE (s/n)").Trim().ToLower()
    return ($confirm -eq "s")
}

function Get-TerminalProfiles {
    $terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    $profiles = @()
    
    if (Test-Path $terminalRoot) {
        $folders = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            $size = (Get-ChildItem -Path $folder.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
            $profiles += @{
                Name = $folder.Name
                Path = $folder.FullName
                Size = $size
            }
        }
    }
    
    return $profiles
}

function Show-AppDataRemovalMenu {
    param([array]$profiles)
    
    if ($profiles.Count -eq 0) {
        Write-Host "Nessun profilo trovato in AppData." -ForegroundColor Yellow
        return @()
    }
    
    $selected = @()
    $continue = $true
    
    while ($continue) {
        Clear-Host
        Write-Host "=================================================="
        Write-Host "  SELEZIONE PROFILI APPDATA DA RIMUOVERE"
        Write-Host "=================================================="
        Write-Host ""
        Write-Host "Questi sono i profili salvati in AppData:" -ForegroundColor Yellow
        Write-Host ""
        
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            $prof = $profiles[$i]
            $size = [Math]::Round($prof.Size, 2)
            
            if ($selected -contains $i) {
                Write-Host "[X] ($($i+1)) $($prof.Name) - ${size} MB" -ForegroundColor Green
            } else {
                Write-Host "[ ] ($($i+1)) $($prof.Name) - ${size} MB"
            }
        }
        
        Write-Host ""
        Write-Host "[0] Conferma selezione"
        Write-Host "[a] Seleziona tutto"
        Write-Host "[c] Cancella selezione"
        Write-Host "[x] Non rimuovere niente da AppData"
        Write-Host ""
        
        $choice = (Read-Host "Scelta [1-$($profiles.Count)], [0] Conferma, [a] Tutto, [c] Cancella, [x] Skip").Trim().ToLower()
        
        if ($choice -eq "0") {
            $continue = $false
        } elseif ($choice -eq "x") {
            $selected = @()
            $continue = $false
        } elseif ($choice -eq "a") {
            $selected = @(0..($profiles.Count-1))
        } elseif ($choice -eq "c") {
            $selected = @()
        } elseif ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                if ($selected -contains $idx) {
                    $selected = $selected | Where-Object { $_ -ne $idx }
                } else {
                    $selected += $idx
                }
            }
        } else {
            Write-Host "Scelta non valida." -ForegroundColor Red
            Start-Sleep 1
        }
    }
    
    $selectedProfiles = @()
    foreach ($idx in $selected) {
        $selectedProfiles += $profiles[$idx]
    }
    
    return $selectedProfiles
}

function Remove-AllMT5InstallersInteractive {
    $baseInstallPath = "C:\MetaTrader"
    
    Write-Log "=== AVVIO PULIZIA MT5 ==="
    
    Clear-Host
    Write-Host "=================================================="
    Write-Host "  ARBITEX VPS - PULIZIA INSTALLAZIONI MT5"
    Write-Host "=================================================="
    Write-Host ""
    
    # Step 1: Mostra opzioni
    Write-Host "[1] Rimuovi istanze selettive (dall'elenco)"
    Write-Host "[2] Rimuovi TUTTE le istanze"
    Write-Host "[x] Annulla"
    Write-Host ""
    
    $choice = (Read-Host "Scelta [1/2/x]").Trim().ToLower()
    
    if ($choice -eq "x") {
        Write-Log "Pulizia annullata dall'utente."
        Write-Host "Operazione annullata."
        return
    }
    
    if ($choice -ne "1" -and $choice -ne "2") {
        Write-Host "Scelta non valida." -ForegroundColor Red
        return
    }
    
    # Step 2: Ottieni lista installazioni
    $installations = Show-InstallationList $baseInstallPath
    
    if ($installations.Count -eq 0) {
        Write-Host "Nessuna istanza MT5 trovata in $baseInstallPath" -ForegroundColor Yellow
        Write-Log "Nessuna istanza trovata."
        return
    }
    
    # Step 3: Selezione istanze
    $toRemove = @()
    if ($choice -eq "1") {
        $toRemove = Show-SelectiveRemovalMenu $installations $baseInstallPath
    } elseif ($choice -eq "2") {
        $toRemove = $installations
    }
    
    if ($toRemove.Count -eq 0) {
        Write-Host "Nessuna istanza selezionata." -ForegroundColor Yellow
        return
    }
    
    # Step 4: Chiedi se rimuovere AppData
    Write-Host ""
    $removeAppData = (Read-Host "Vuoi rimuovere anche i profili e dati salvati in AppData (s/n)").Trim().ToLower()
    
    $profilesToRemove = @()
    if ($removeAppData -eq "s") {
        $profiles = Get-TerminalProfiles
        if ($profiles.Count -gt 0) {
            $profilesToRemove = Show-AppDataRemovalMenu $profiles
        }
    }
    
    # Step 5: Conferma
$confirmed = Show-ConfirmationMenuCleanup -selectedInstallations $toRemove -includeAppData ($profilesToRemove.Count -gt 0)
    if (-not $confirmed) {
        Write-Log "Rimozione annullata dall'utente."
        Write-Host "Rimozione annullata."
        return
    }
    
    # Step 6: Termina processi MT5
    Write-Host ""
    Write-Host "Terminazione processi MT5..." -ForegroundColor Cyan
    Stop-AllMT5Processes
    
    # Step 7: Rimozione
    Clear-Host
    Write-Host "=================================================="
    Write-Host "  RIMOZIONE IN CORSO..."
    Write-Host "=================================================="
    Write-Host ""
    
    $successCount = 0
    $failedCount = 0
    $failedItems = @()
    
    # Rimuovi installazioni
    foreach ($inst in $toRemove) {
        Write-Host "Rimozione: $($inst.Name)..." -NoNewline
        
        if (Remove-Safely $inst.Path) {
            Write-Host " [OK]" -ForegroundColor Green
            Write-Log "Rimossa: $($inst.Name)"
            $successCount++
        } else {
            Write-Host " [ERRORE]" -ForegroundColor Red
            Write-Log "ERRORE rimozione: $($inst.Name)"
            $failedCount++
            $failedItems += $inst.Name
        }
    }
    
    # Rimuovi profili AppData
    foreach ($profile in $profilesToRemove) {
        Write-Host "Rimozione profilo: $($profile.Name)..." -NoNewline
        
        if (Remove-Safely $profile.Path) {
            Write-Host " [OK]" -ForegroundColor Green
            Write-Log "Rimosso profilo: $($profile.Name)"
            $successCount++
        } else {
            Write-Host " [ERRORE]" -ForegroundColor Red
            Write-Log "ERRORE rimozione profilo: $($profile.Name)"
            $failedCount++
            $failedItems += "Profilo: $($profile.Name)"
        }
    }
    
    # Step 8: Riepilogo
    Clear-Host
    Write-Host "=================================================="
    Write-Host "  RIEPILOGO RIMOZIONE"
    Write-Host "=================================================="
    Write-Host ""
    Write-Host "Rimossi con successo: $successCount" -ForegroundColor Green
    
    if ($failedCount -gt 0) {
        Write-Host "Errori durante rimozione: $failedCount" -ForegroundColor Red
        Write-Host "Elementi non rimossi:"
        foreach ($failed in $failedItems) {
            Write-Host "  - $failed"
        }
        Write-Host ""
        Write-Host "NOTA: Potrebbe essere necessario riavviare per liberare i file bloccati." -ForegroundColor Yellow
    }
    
    # Verifica pulizia
    if ($removeAppData -eq "s") {
        Write-Host ""
        Write-Host "Verifica cartelle rimanenti in AppData..." -ForegroundColor Cyan
        $remainingProfiles = Get-TerminalProfiles
        if ($remainingProfiles.Count -eq 0) {
            Write-Host "AppData ripulito completamente!" -ForegroundColor Green
        } else {
            Write-Host "Profili rimanenti in AppData: $($remainingProfiles.Count)"
        }
    }
    
    Write-Host ""
    Write-Host "Pulizia completata!" -ForegroundColor Green
    Write-Log "Pulizia MT5 completata. Successi: $successCount, Errori: $failedCount"
    
    Write-Host ""
    Read-Host "Premi INVIO per tornare al menu"
}
