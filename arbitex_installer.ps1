# =========================================
# ARBITEX VPS - Installer (VERSIONE COMPLETA - FIXED v11 - RETRY LOCKED FILES)
# =========================================

Add-Type -AssemblyName System.Drawing

function Get-ProgressPercent
{
    param(
        [double]$currentStep,
        [double]$totalSteps,
        [double]$offset
    )

    if (-not $totalSteps -or $totalSteps -le 0)
    {
        return 0
    }

    $rawValue = ($currentStep + $offset) * 100.0 / $totalSteps

    if ($rawValue -lt 0)
    {
        return 0
    }

    if ($rawValue -gt 100)
    {
        return 100
    }

    return [int][Math]::Round($rawValue)
}

function Get-ExistingTerminalFolder($terminalRoot, $instanceLabel) {
    if (-not (Test-Path $terminalRoot)) {
        return $null
    }

    $profiles = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue

    if ($profiles.Count -gt 0) {
        if ($profiles.Count -eq 1) {
            Write-Log "Trovato profilo esistente (unico): $($profiles[0].FullName)"
            return $profiles[0].FullName
        }

        $newest = $profiles | Sort-Object CreationTime -Descending | Select-Object -First 1
        Write-Log "Trovato profilo più recente: $($newest.FullName)"
        return $newest.FullName
    }

    return $null
}

function Get-NewTerminalFolder($foldersBefore, $terminalRoot) {
    $maxRetries = 25
    $retryCount = 0
    $newFolder = $null

    Write-Log "Ricerca cartella profilo HASH in: $terminalRoot"
    Write-Log "Max retry: $maxRetries (attesa max ~50 secondi)"

    while ($retryCount -lt $maxRetries -and -not $newFolder) {
        $foldersAfter = @()
        if (Test-Path $terminalRoot) {
            $allFoldersAfter = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue
            $foldersAfter = $allFoldersAfter |
                    Where-Object { $_.Name -match '^[0-9A-Fa-f]{32}$' } |
                    ForEach-Object { $_.FullName }

            Write-Log "Tentativo $( $retryCount + 1 ): trovate $( $allFoldersAfter.Count ) cartelle in $terminalRoot (HASH candidate: $( $foldersAfter.Count ))"
        } else {
            Write-Log "Tentativo $($retryCount + 1): $terminalRoot NON esiste ancora!"
        }

        # Considera solo nuove cartelle HASH rispetto allo stato iniziale
        $newFolders = $foldersAfter | Where-Object { $foldersBefore -notcontains $_ }

        if ($newFolders) {
            if ($newFolders -is [array]) {
                $newest = $newFolders | Get-Item | Sort-Object CreationTime -Descending | Select-Object -First 1
                $newFolder = $newest.FullName
            } else {
                $newFolder = $newFolders
            }

            Write-Log "✅ CARTELLA TROVATA al tentativo $($retryCount + 1): $newFolder"
            return $newFolder
        }

        $retryCount++
        if ($retryCount -lt $maxRetries) {
            $remainingRetries = $maxRetries - $retryCount
            Write-Host "Attesa creazione cartella AppData/Terminal... ($retryCount/$maxRetries, rimangono $remainingRetries)" -ForegroundColor Gray
            Start-Sleep -Seconds 2
        }
    }

    Write-Log "❌ CARTELLA NON TROVATA dopo $maxRetries tentativi di attesa"
    return $null
}

function Show-PropSelectionMenu {
    param([array]$propList)

    $selectedProps = @()
    $continue = $true

    while ($continue) {
        Clear-Host
        Write-Host "=================================================="
        Write-Host "  SELEZIONE PROP FIRMS"
        Write-Host "=================================================="
        Write-Host ""

        for ($i = 0; $i -lt $propList.Count; $i++) {
            $prop = $propList[$i]
            if ($selectedProps -contains $prop) {
                Write-Host "[X] ($($i+1)) $prop" -ForegroundColor Green
            } else {
                Write-Host "[ ] ($($i+1)) $prop"
            }
        }

        Write-Host ""
        Write-Host "[0] Conferma selezione e continua"
        Write-Host "[c] Cancella tutto"
        Write-Host ""

        $choice = (Read-Host "Seleziona prop [1-$($propList.Count)], [0] Conferma, [c] Cancella").Trim().ToLower()

        if ($choice -eq "0") {
            if ($selectedProps.Count -eq 0) {
                Write-Host "Devi selezionare almeno una prop!" -ForegroundColor Red
                Start-Sleep 2
            } else {
                $continue = $false
            }
        } elseif ($choice -eq "c") {
            $selectedProps = @()
        } elseif ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $propList.Count) {
                $prop = $propList[$idx]
                if ($selectedProps -contains $prop) {
                    $selectedProps = $selectedProps | Where-Object { $_ -ne $prop }
                } else {
                    $selectedProps += $prop
                }
            } else {
                Write-Host "Scelta non valida." -ForegroundColor Red
                Start-Sleep 1
            }
        } else {
            Write-Host "Scelta non valida." -ForegroundColor Red
            Start-Sleep 1
        }
    }

    return $selectedProps
}

function Show-InstanceCountMenu {
    param([array]$selectedProps, [hashtable]$existingMap)

    $instanceCounts = @{}

    Clear-Host
    Write-Host "=================================================="
    Write-Host "  NUMERO ISTANZE PER PROP"
    Write-Host "=================================================="
    Write-Host ""

    foreach ($prop in $selectedProps) {
        $existingCount = 0
        if ($existingMap.ContainsKey($prop)) {
            $existingCount = $existingMap[$prop].Count
        }

        if ($existingCount -gt 0) {
            Write-Host "ATTENZIONE: $prop gia installato con $existingCount istanza(e)" -ForegroundColor Yellow
            $confirm = (Read-Host "Vuoi aggiungere altre istanze (s/n)").Trim().ToLower()

            if ($confirm -eq "s") {
                $validInput = $false
                while (-not $validInput) {
                    $count = (Read-Host "Quante altre istanze per $prop (1-10)").Trim()
                    if ($count -match '^\d+$' -and [int]$count -ge 1 -and [int]$count -le 10) {
                        $instanceCounts[$prop] = [int]$count
                        $validInput = $true
                        Write-Host "OK - $prop : $count nuove istanze (totale $([int]$count + $existingCount))" -ForegroundColor Green
                    } else {
                        Write-Host "Inserisci un numero tra 1 e 10!" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "SKIP - $prop non modificato" -ForegroundColor Yellow
                $instanceCounts[$prop] = 0
            }
        } else {
            $validInput = $false
            while (-not $validInput) {
                $count = (Read-Host "Quante istanze per $prop (1-10)").Trim()
                if ($count -match '^\d+$' -and [int]$count -ge 1 -and [int]$count -le 10) {
                    $instanceCounts[$prop] = [int]$count
                    $validInput = $true
                    Write-Host "OK - $prop : $count istanze" -ForegroundColor Green
                } else {
                    Write-Host "Inserisci un numero tra 1 e 10!" -ForegroundColor Red
                }
            }
        }
    }

    return $instanceCounts
}

function Show-HedgeSelectionMenu {
    param([hashtable]$existingMap)

    $validInput = $false
    $includeHedge = $false

    $hedgeExists = $existingMap.ContainsKey("HEDGE")

    while (-not $validInput) {
        Clear-Host
        Write-Host "=================================================="
        Write-Host "  CONFIGURAZIONE HEDGE"
        Write-Host "=================================================="
        Write-Host ""

        if ($hedgeExists) {
            Write-Host "ATTENZIONE: HEDGE gia installato!" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "[s] Si, modifica HEDGE"
            Write-Host "[n] No, salta HEDGE"
        } else {
            Write-Host "Vuoi installare HEDGE (account Edge)?"
            Write-Host ""
            Write-Host "[s] Si, installa HEDGE"
            Write-Host "[n] No, salta HEDGE"
        }
        Write-Host ""

        $choice = (Read-Host "Scelta [s/n]").Trim().ToLower()

        if ($choice -eq "s") {
            $includeHedge = $true
            $validInput = $true
            if ($hedgeExists) {
                Write-Host "OK - Modifiche HEDGE" -ForegroundColor Green
            } else {
                Write-Host "OK - HEDGE sara installato" -ForegroundColor Green
            }
        } elseif ($choice -eq "n") {
            $includeHedge = $false
            $validInput = $true
            Write-Host "OK - HEDGE sara saltato" -ForegroundColor Green
        } else {
            Write-Host "Scelta non valida." -ForegroundColor Red
        }
        Start-Sleep 1
    }

    return $includeHedge
}

function Show-ConfirmationMenu {
    param(
        [array]$selectedProps,
        [hashtable]$instanceCounts,
        [bool]$includeHedge
    )

    Clear-Host
    Write-Host "=================================================="
    Write-Host "  RIEPILOGO CONFIGURAZIONE"
    Write-Host "=================================================="
    Write-Host ""
    Write-Host "PROP SELEZIONATE:"
    foreach ($prop in $selectedProps) {
        $count = $instanceCounts[$prop]
        if ($count -gt 0) {
            Write-Host "  - $prop : $count istanza(e)" -ForegroundColor Cyan
        } else {
            Write-Host "  - $prop : SKIP" -ForegroundColor Gray
        }
    }
    Write-Host ""
    if ($includeHedge) {
        Write-Host "HEDGE: SI (modifiche)" -ForegroundColor Cyan
    } else {
        Write-Host "HEDGE: NO" -ForegroundColor Cyan
    }
    Write-Host ""

    $totalInstances = 0
    foreach ($count in $instanceCounts.Values) {
        $totalInstances += $count
    }
    if ($includeHedge) { $totalInstances++ }

    Write-Host "TOTALE NUOVE ISTANZE: $totalInstances" -ForegroundColor Yellow
    Write-Host ""

    $confirm = (Read-Host "Confermi questa configurazione (s/n)").Trim().ToLower()
    return ($confirm -eq "s")
}

function Create-DesktopShortcut {
    param(
        [string]$instanceLabel,
        [string]$customPath,
        [string]$iconPath
    )

    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "$instanceLabel.lnk"

        $terminalExe = $null

        $terminal64 = Join-Path $customPath "terminal64.exe"
        if (Test-Path $terminal64) {
            $terminalExe = $terminal64
            Write-Log "Trovato terminal64.exe"
        } else {
            $terminal32 = Join-Path $customPath "terminal.exe"
            if (Test-Path $terminal32) {
                $terminalExe = $terminal32
                Write-Log "Trovato terminal.exe"
            }
        }

        if (-not $terminalExe) {
            Write-Log "ERRORE: Nessun terminal.exe o terminal64.exe trovato in $customPath"
            Write-Host "ERRORE - Eseguibile MT5 non trovato" -ForegroundColor Red
            return $false
        }

        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)

        $Shortcut.TargetPath = $terminalExe
        $Shortcut.WorkingDirectory = $customPath
        $Shortcut.Description = "MetaTrader 5 - $instanceLabel"

        if (Test-Path $iconPath) {
            $Shortcut.IconLocation = $iconPath
        }

        $Shortcut.Save()
        Write-Log "Shortcut desktop creato: $shortcutPath -> $terminalExe"
        Write-Host "OK - Shortcut desktop creato" -ForegroundColor Green
        return $true
    } catch {
        Write-Log "ERRORE creazione shortcut: $($_.Exception.Message)"
        Write-Host "ERRORE creazione shortcut" -ForegroundColor Red
        return $false
    }
}

function Copy-ConfigurationFiles {
    param(
        [string]$configSrc,
        [string]$profilePath,
        [string]$instanceLabel
    )

    if (-not (Test-Path $configSrc)) {
        Write-Log "AVVISO: Config source non trovato: $configSrc"
        Write-Host "AVVISO - Config non trovata" -ForegroundColor Yellow
        return $false
    }

    try {
        $configItems = Get-ChildItem -Path $configSrc -ErrorAction SilentlyContinue
        $copiedCount = 0

        foreach ($item in $configItems) {
            if ($item.Name -ieq "accounts.dat")
            {
                Write-Log "Skip copia accounts.dat da config sorgente: $( $item.FullName )"
                continue
            }
            $destPath = Join-Path $profilePath $item.Name

            try {
                if ($item.PSIsContainer) {
                    if (-not (Test-Path $destPath)) {
                        New-Item -ItemType Directory -Path $destPath -Force -ErrorAction Stop | Out-Null
                    }

                    Get-ChildItem -Path $item.FullName -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                        $relPath = $_.FullName.Substring($item.FullName.Length + 1)
                        $target = Join-Path $destPath $relPath

                        if ($_.PSIsContainer) {
                            if (-not (Test-Path $target)) {
                                New-Item -ItemType Directory -Path $target -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        } else {
                            Copy-Item -Path $_.FullName -Destination $target -Force -ErrorAction SilentlyContinue
                            $copiedCount++
                        }
                    }
                    Write-Log "Cartella copiata: $($item.Name)"
                } else {
                    Copy-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction Stop
                    $copiedCount++
                    Write-Log "File copiato: $($item.Name)"
                }
            } catch {
                Write-Log "ERRORE copia elemento $($item.Name): $($_.Exception.Message)"
            }
        }

        Write-Log "Configurazione copiata per $instanceLabel ($copiedCount file)"
        Write-Host "OK - Config copiata ($copiedCount file)" -ForegroundColor Green
        return $true
    } catch {
        Write-Log "ERRORE copia config: $($_.Exception.Message)"
        Write-Host "ERRORE copia config" -ForegroundColor Red
        return $false
    }
}

function Install-VCRedistributable {
    param([string]$programsPath)

    Write-Log "Ricerca VC Redistributables in: $programsPath"

    $vcPatterns = @(
        "vc_redist.x64.exe",
        "vc_redist.x86.exe",
        "vcredist_x64.exe",
        "vcredist_x86.exe",
        "*vcredist*x64*.exe",
        "*vcredist*x86*.exe",
        "*VC_redist*.exe",
        "*VC_redist*x64*.exe",
        "*VC_redist*x86*.exe"
    )

    $vcFiles = @()

    foreach ($pattern in $vcPatterns) {
        try {
            $found = @(Get-ChildItem -Path $programsPath -Filter $pattern -ErrorAction SilentlyContinue)
            foreach ($file in $found) {
                if ($vcFiles.FullName -notcontains $file.FullName) {
                    $vcFiles += $file
                    Write-Log "VC Redist trovato: $($file.Name)"
                }
            }
        } catch {
            Write-Log "Errore ricerca pattern $pattern : $($_.Exception.Message)"
        }
    }

    if ($vcFiles.Count -eq 0) {
        Write-Log "Nessun VC Redist trovato in $programsPath"
        Write-Host "AVVISO - Nessun VC Redist trovato" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Installazione VC Redistributables..." -ForegroundColor Cyan
    Write-Log "Trovati $($vcFiles.Count) installer VC Redist"

    foreach ($vcFile in $vcFiles) {
        $vcName = $vcFile.Name
        $vcPath = $vcFile.FullName

        Write-Host "Installo: $vcName..." -NoNewline
        Write-Log "Avvio installer VC Redist: $vcName (Path: $vcPath)"

        try {
            if (-not (Test-Path $vcPath)) {
                Write-Host " [ERRORE FILE]" -ForegroundColor Red
                Write-Log "ERRORE: File non trovato: $vcPath"
                continue
            }

            $process = Start-Process -FilePath $vcPath -ArgumentList "/quiet /norestart" -PassThru -ErrorAction Stop
            $process.WaitForExit()

            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                Write-Host " [OK]" -ForegroundColor Green
                Write-Log "VC Redist installato: $vcName (Exit code: $($process.ExitCode))"
            } else {
                Write-Host " [AVVISO]" -ForegroundColor Yellow
                Write-Log "VC Redist completato con codice: $($process.ExitCode) ($vcName)"
            }
        } catch {
            Write-Host " [ERRORE]" -ForegroundColor Red
            Write-Log "ERRORE installazione VC Redist $vcName : $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 1
    }

    Write-Host ""
}

# ✅ VERSIONE v3 CON RETRY PER FILE LOCKED - HEDGE
function Install-MT5InstanceHedge {
    param(
        [string]$instanceLabel,
        [string]$setupExe,
        [string]$customPath,
        [string]$configSrc,
        [string]$iconPath,
        [int]$currentStep,
        [int]$totalSteps,
        [string]$terminalRoot,
        [bool]$createDesktopShortcut,
        [pscustomobject]$autoLoginConfig = $null
    )

    Write-Log "INSTALL HEDGE: $instanceLabel"
    Write-Progress -Activity "Installazione $instanceLabel" -Status "Avvio installer" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -1)

    $foldersBefore = @()
    if (Test-Path $terminalRoot) {
        $foldersBefore = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    }

    try {
        Write-Host "Avvio: $instanceLabel"
        Start-Process -FilePath $setupExe -ArgumentList "/auto /path:`"$customPath`"" -Wait -ErrorAction Stop
        Write-Log "Installer $instanceLabel terminato."
    } catch {
        Write-Log "ERRORE Start-Process $instanceLabel : $($_.Exception.Message)"
        Write-Host "ERRORE avvio installer" -ForegroundColor Red
        return
    }

    Write-Progress -Activity "Installazione $instanceLabel" -Status "Attendo creazione profilo" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -0.5)
    Start-Sleep -Seconds 2

    $newFolder = Get-NewTerminalFolder $foldersBefore $terminalRoot

    Write-Log "Cartella HASH trovata: $newFolder"

    if ($newFolder) {
        Write-Progress -Activity "Configurazione $instanceLabel" -Status "Avvio MT5 per inizializzazione" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -0.3)

        <#
        Write-Log "Avvio MT5 $instanceLabel per inizializzazione..."
        Write-Host "Avvio MT5 (10 secondi)..." -ForegroundColor Cyan

        $terminalExe = $null
        $terminal64 = Join-Path $customPath "terminal64.exe"
        $terminal32 = Join-Path $customPath "terminal.exe"

        if (Test-Path $terminal64) {
            $terminalExe = $terminal64
        } elseif (Test-Path $terminal32) {
            $terminalExe = $terminal32
        }

        if ($terminalExe) {
            try {
                $mtProcess = Start-Process -FilePath $terminalExe -WorkingDirectory $customPath -PassThru -ErrorAction Stop

                Write-Log "MT5 avviato, attesa 5 secondi..."
                Start-Sleep -Seconds 5

                Write-Log "Chiusura MT5 $instanceLabel..."
                Stop-Process -Id $mtProcess.Id -Force -ErrorAction SilentlyContinue

                Write-Log "Attesa 10 secondi per chiudere tutti i processi..."
                Start-Sleep -Seconds 10

                Write-Log "MT5 $instanceLabel chiuso"
                Write-Host "OK - MT5 inizializzato e chiuso" -ForegroundColor Green
            } catch {
                Write-Log "ERRORE durante inizializzazione MT5: $($_.Exception.Message)"
                Write-Host "AVVISO - Errore inizializzazione MT5 (continuo comunque)" -ForegroundColor Yellow
            }
        }
        #>

        Write-Progress -Activity "Configurazione $instanceLabel" -Status "Ripulitura profilo HEDGE (HASH)" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -0.15)
        Write-Log "Ripulitura contenuto della cartella profilo HEDGE (HASH)..."
        Write-Log "Cartella profilo HEDGE: $newFolder"
        Write-Host "Ripulitura configurazione profilo HEDGE..." -ForegroundColor Yellow

        try {
            $profiloItems = Get-ChildItem -Path $newFolder -Force -ErrorAction SilentlyContinue
            Write-Log "Elementi da eliminare in $newFolder : $( $profiloItems.Count )"
            foreach ($item in $profiloItems)
            {
                $maxRetries = 3
                $retryCount = 0
                $deleted = $false

                while ($retryCount -lt $maxRetries -and -not $deleted)
                {
                    try
                    {
                        if ($item.PSIsContainer)
                        {
                            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        }
                        else
                        {
                            Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                        }
                        Write-Log "Eliminato da profilo HEDGE: $( $item.Name )"
                        $deleted = $true
                    }
                    catch
                    {
                        $retryCount++
                        if ($retryCount -lt $maxRetries)
                        {
                            Write-Log "AVVISO: Tentativo $retryCount fallito per $( $item.Name ), riprovo tra 2 sec..."
                            Start-Sleep -Seconds 2
                        }
                        else
                        {
                            Write-Log "AVVISO: Impossibile eliminare $( $item.Name ) dopo $maxRetries tentativi: $( $_.Exception.Message )"
                        }
                    }
                }
            }
            Write-Log "Contenuto profilo HEDGE ripulito"
            Write-Host "OK - Profilo HEDGE ripulito" -ForegroundColor Green
        } catch {
            Write-Log "ERRORE ripulitura profilo HEDGE: $( $_.Exception.Message )"
            Write-Host "ERRORE ripulitura profilo HEDGE (continuo comunque)" -ForegroundColor Red
        }

        Write-Progress -Activity "Configurazione $instanceLabel" -Status "Copia config standard_config_edge in profilo HEDGE" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset 0)
        Write-Log "Copia configurazione HEDGE da $configSrc nel profilo $newFolder"
        Write-Host "Copia configurazione standard_config_edge..." -ForegroundColor Cyan

        Copy-ConfigurationFiles -configSrc $configSrc -profilePath $newFolder -instanceLabel $instanceLabel

        if ($autoLoginConfig -and $autoLoginConfig.Login -and $autoLoginConfig.Password -and $autoLoginConfig.Server)
        {
            Set-MT5AutoLoginConfig -profilePath $newFolder -autoLoginConfig $autoLoginConfig -instanceLabel $instanceLabel
        }

        if ($createDesktopShortcut) {
            Create-DesktopShortcut -instanceLabel $instanceLabel -customPath $customPath -iconPath $iconPath
        }

        Write-Log "$instanceLabel OK"
    } else {
        Write-Log "❌ ERRORE: Cartella HASH non trovata per $instanceLabel"
        Write-Host "❌ ERRORE - Cartella HASH non trovata" -ForegroundColor Red
    }

    Start-Sleep -Seconds 1
}

# ✅ PROP VERSION v3 CON RETRY PER FILE LOCKED
function Install-MT5Instance {
    param(
        [string]$instanceLabel,
        [string]$setupExe,
        [string]$customPath,
        [string]$configSrc,
        [string]$iconPath,
        [int]$instanceNum,
        [int]$currentStep,
        [int]$totalSteps,
        [string]$terminalRoot,
        [bool]$createDesktopShortcut,
        [bool]$isReinstall = $false,
        [pscustomobject]$autoLoginConfig = $null
    )

    Write-Log "INSTALL PROP: $instanceLabel"
    Write-Progress -Activity "Installazione $instanceLabel" -Status "Avvio installer" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -1)

    $foldersBefore = @()
    if (Test-Path $terminalRoot) {
        $foldersBefore = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    }

    try {
        Write-Host "Avvio: $instanceLabel"
        Start-Process -FilePath $setupExe -ArgumentList "/auto /path:`"$customPath`"" -Wait -ErrorAction Stop
        Write-Log "Installer $instanceLabel terminato."
    } catch {
        Write-Log "ERRORE Start-Process $instanceLabel : $($_.Exception.Message)"
        Write-Host "ERRORE avvio installer" -ForegroundColor Red
        return
    }

    Write-Progress -Activity "Installazione $instanceLabel" -Status "Attendo creazione cartella" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -0.5)
    Start-Sleep -Seconds 2

    $newFolder = $null

    if ($isReinstall) {
        $newFolder = Get-ExistingTerminalFolder $terminalRoot $instanceLabel
        if ($newFolder) {
            Write-Log "Reinstallazione: Usando profilo esistente"
        }
    }

    if (-not $newFolder) {
        $newFolder = Get-NewTerminalFolder $foldersBefore $terminalRoot
    }

    if ($newFolder) {
        Write-Progress -Activity "Configurazione $instanceLabel" -Status "Avvio MT5 per inizializzazione" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -0.3)

        <#
        Write-Log "Avvio MT5 $instanceLabel per inizializzazione..."
        Write-Host "Avvio MT5 (10 secondi)..." -ForegroundColor Cyan

        $terminalExe = $null
        $terminal64 = Join-Path $customPath "terminal64.exe"
        $terminal32 = Join-Path $customPath "terminal.exe"

        if (Test-Path $terminal64) {
            $terminalExe = $terminal64
        } elseif (Test-Path $terminal32) {
            $terminalExe = $terminal32
        }

        if ($terminalExe) {
            try {
                $mtProcess = Start-Process -FilePath $terminalExe -WorkingDirectory $customPath -PassThru -ErrorAction Stop

                Write-Log "MT5 avviato, attesa 10 secondi..."
                Start-Sleep -Seconds 10

                Write-Log "Chiusura MT5 $instanceLabel..."
                Stop-Process -Id $mtProcess.Id -Force -ErrorAction SilentlyContinue

                Write-Log "Attesa 5 secondi per chiudere tutti i processi..."
                Start-Sleep -Seconds 5

                Write-Log "MT5 $instanceLabel chiuso"
                Write-Host "OK - MT5 inizializzato e chiuso" -ForegroundColor Green
            } catch {
                Write-Log "ERRORE durante inizializzazione MT5: $($_.Exception.Message)"
                Write-Host "AVVISO - Errore inizializzazione MT5 (continuo comunque)" -ForegroundColor Yellow
            }
        }
        #>

        Write-Progress -Activity "Configurazione $instanceLabel" -Status "Ripulitura profilo HASH" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset -0.15)
        Write-Log "Ripulitura contenuto della cartella profilo (HASH)..."
        Write-Log "Cartella profilo: $newFolder"
        Write-Host "Ripulitura configurazione profilo..." -ForegroundColor Yellow

        try {
            $profiloItems = Get-ChildItem -Path $newFolder -Force -ErrorAction SilentlyContinue
            Write-Log "Elementi da eliminare in $newFolder : $($profiloItems.Count)"
            foreach ($item in $profiloItems) {
                $maxRetries = 3
                $retryCount = 0
                $deleted = $false

                while ($retryCount -lt $maxRetries -and -not $deleted) {
                    try {
                        if ($item.PSIsContainer) {
                            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        } else {
                            Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                        }
                        Write-Log "Eliminato da profilo: $($item.Name)"
                        $deleted = $true
                    } catch {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Log "AVVISO: Tentativo $retryCount fallito per $($item.Name), riprovo tra 2 sec..."
                            Start-Sleep -Seconds 2
                        } else {
                            Write-Log "AVVISO: Impossibile eliminare $($item.Name) dopo $maxRetries tentativi: $($_.Exception.Message)"
                        }
                    }
                }
            }
            Write-Log "Contenuto profilo HASH ripulito"
            Write-Host "OK - Profilo ripulito" -ForegroundColor Green
        } catch {
            Write-Log "ERRORE ripulitura profilo HASH: $($_.Exception.Message)"
            Write-Host "ERRORE ripulitura (continuo comunque)" -ForegroundColor Red
        }

        Write-Progress -Activity "Configurazione $instanceLabel" -Status "Copia config personalizzata in profilo HASH" -PercentComplete (Get-ProgressPercent -currentStep $currentStep -totalSteps $totalSteps -offset 0)
        Write-Log "Copia configurazione personalizzata nel profilo HASH..."
        Write-Host "Copia configurazione personalizzata..." -ForegroundColor Cyan

        Copy-ConfigurationFiles -configSrc $configSrc -profilePath $newFolder -instanceLabel $instanceLabel

        if ($autoLoginConfig -and $autoLoginConfig.Login -and $autoLoginConfig.Password -and $autoLoginConfig.Server)
        {
            Set-MT5AutoLoginConfig -profilePath $newFolder -autoLoginConfig $autoLoginConfig -instanceLabel $instanceLabel
        }

        $terminalIconPath = Join-Path $newFolder "terminal.ico"
        if (Test-Path $iconPath) {
            try {
                Copy-Item -Path $iconPath -Destination $terminalIconPath -Force -ErrorAction Stop
                Write-Log "$instanceLabel OK"
                Write-Host "OK - $instanceLabel configurato" -ForegroundColor Green
            } catch {
                Write-Log "ERRORE copia icona: $($_.Exception.Message)"
                Write-Host "ERRORE copia icona" -ForegroundColor Red
            }
        } else {
            Write-Log "AVVISO: icona non trovata: $iconPath"
            Write-Host "AVVISO - icona non trovata" -ForegroundColor Yellow
        }

        if ($createDesktopShortcut) {
            Create-DesktopShortcut -instanceLabel $instanceLabel -customPath $customPath -iconPath $terminalIconPath
        }
    } else {
        Write-Log "❌ ERRORE: Nessuna cartella profilo HASH creata per $instanceLabel"
        Write-Host "❌ ERRORE - profilo non creato (AppData/Terminal/HASH non trovato)" -ForegroundColor Red
    }

    Start-Sleep -Seconds 1
}

function Set-MT5AutoLoginConfig
{
    param(
        [string]$profilePath,
        [pscustomobject]$autoLoginConfig,
        [string]$instanceLabel
    )

    $configDir = Join-Path $profilePath "config"
    $commonIniPath = Join-Path $configDir "common.ini"
    if (Test-Path $commonIniPath)
    {
        $iniContent = Get-Content -Path $commonIniPath -Encoding UTF8
        $newContent = @()
        $inCommon = $false
        $wroteLogin = $false
        $wroteServer = $false

        foreach ($line in $iniContent)
        {
            if ($line -match '^\[Common\]')
            {
                $inCommon = $true
                $newContent += $line
                continue
            }

            if ($line -match '^\[')
            {
                if ($inCommon)
                {
                    if (-not $wroteLogin)
                    {
                        $newContent += "Login=$( $autoLoginConfig.Login )"
                        $wroteLogin = $true
                    }
                    if (-not $wroteServer)
                    {
                        $newContent += "Server=$( $autoLoginConfig.Server )"
                        $wroteServer = $true
                    }
                }

                $inCommon = $false
                $newContent += $line
                continue
            }

            if ($inCommon)
            {
                if ($line -match '^Login=')
                {
                    $newContent += "Login=$( $autoLoginConfig.Login )"
                    $wroteLogin = $true
                    continue
                }
                elseif ($line -match '^Server=')
                {
                    $newContent += "Server=$( $autoLoginConfig.Server )"
                    $wroteServer = $true
                    continue
                }
            }

            $newContent += $line
        }

        if ($inCommon)
        {
            if (-not $wroteLogin)
            {
                $newContent += "Login=$( $autoLoginConfig.Login )"
            }
            if (-not $wroteServer)
            {
                $newContent += "Server=$( $autoLoginConfig.Server )"
            }
        }

        # Aggiunge anche una sezione separata [Login] con password in chiaro
        $newContent += "[Login]"
        $newContent += "Login=$( $autoLoginConfig.Login )"
        $newContent += "Password=$( $autoLoginConfig.Password )"
        $newContent += "Server=$( $autoLoginConfig.Server )"

        $newContent | Set-Content -Path $commonIniPath -Encoding UTF8
        Write-Log "Configurazione auto-login aggiornata per $instanceLabel (config: $commonIniPath)"
    }
}

function Remove-GenericMT5Shortcuts
{
    param([string]$baseInstallPath)

    if (-not $baseInstallPath)
    {
        return
    }

    $desktopPaths = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory")
    )

    $shortcutNames = @("MetaTrader 5.lnk", "MetaEditor 5.lnk")

    Write-Log "[ICON CLEAN POST-INSTALL] Controllo shortcut generiche MetaTrader 5/MetaEditor 5 da rimuovere. BaseInstallPath=$baseInstallPath"

    $shell = $null

    foreach ($desktop in $desktopPaths)
    {
        if (-not $desktop -or -not (Test-Path $desktop))
        {
            continue
        }

        foreach ($name in $shortcutNames)
        {
            $shortcutPath = Join-Path $desktop $name

            if (-not (Test-Path $shortcutPath))
            {
                continue
            }

            try
            {
                if (-not $shell)
                {
                    $shell = New-Object -ComObject WScript.Shell
                }

                $shortcut = $shell.CreateShortcut($shortcutPath)

                $targetDir = $null
                $logTargetPath = $shortcut.TargetPath
                $logWorkingDir = $shortcut.WorkingDirectory

                if ($shortcut.TargetPath)
                {
                    try
                    {
                        $resolvedTarget = (Resolve-Path -LiteralPath $shortcut.TargetPath -ErrorAction Stop).ProviderPath
                        $targetDir = Split-Path -Path $resolvedTarget -Parent
                    }
                    catch
                    {
                    }
                }

                if (-not $targetDir -and $shortcut.WorkingDirectory)
                {
                    try
                    {
                        $targetDir = (Resolve-Path -LiteralPath $shortcut.WorkingDirectory -ErrorAction Stop).ProviderPath
                    }
                    catch
                    {
                    }
                }

                Write-Log "[ICON CLEAN POST-INSTALL] Analizzo '$shortcutPath' | TargetPath='$logTargetPath' | WorkingDir='$logWorkingDir' | targetDir='$targetDir'"

                if ($targetDir -and ($targetDir -like (Join-Path $baseInstallPath '*')))
                {
                    Remove-Item -Path $shortcutPath -Force -ErrorAction Stop
                    Write-Log "[ICON CLEAN POST-INSTALL] Rimossa shortcut generica: $shortcutPath (puntava a $targetDir)"
                }
                else
                {
                    Write-Log "[ICON CLEAN POST-INSTALL] Shortcut lasciata intatta: $shortcutPath"
                }
            }
            catch
            {
                Write-Log "[ICON CLEAN POST-INSTALL] AVVISO: impossibile analizzare/rimuovere '$shortcutPath' : $( $_.Exception.Message )"
            }
        }
    }
}

function Invoke-ArbitexInstaller {
    param(
        [string]$programsPath,
        [string]$baseInstallPath,
        [string]$edgeConfig,
        [string]$propConfig,
        [string]$iconSourcePath,
        [string]$terminalRoot,
        [hashtable]$propIcons,
        [array]$propList,
        [bool]$includeEdge
    )

    Write-Log "Avvio wizard configurazione MT5."

    $selectedProps = Show-PropSelectionMenu $propList
    Write-Log "Prop selezionate: $($selectedProps -join ', ')"

    $existingMap = @{}
    if (Test-Path $baseInstallPath) {
        $existingFolders = Get-ChildItem -Path $baseInstallPath -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
        foreach ($folder in $existingFolders) {
            if ($folder -match '^MetaTrader 5 - ([A-Za-z0-9 ]+) (\d+)$') {
                $propFound = $Matches[1].Trim()
                $numFound = [int]$Matches[2]
                if (-not $existingMap.ContainsKey($propFound)) {
                    $existingMap[$propFound] = @()
                }
                $existingMap[$propFound] += $numFound
            } elseif ($folder -eq "MetaTrader 5 - HEDGE") {
                $existingMap["HEDGE"] = @(1)
            }
        }
    }

    $instanceCounts = Show-InstanceCountMenu $selectedProps $existingMap
    Write-Log "Istanze selezionate"

    $includeHedgeChoice = Show-HedgeSelectionMenu $existingMap
    Write-Log "Include HEDGE: $includeHedgeChoice"

    $confirmed = Show-ConfirmationMenu -selectedProps $selectedProps -instanceCounts $instanceCounts -includeHedge $includeHedgeChoice
    if (-not $confirmed) {
        Write-Log "Installazione annullata dall'utente."
        Write-Host "Installazione annullata." -ForegroundColor Yellow
        return
    }

    $createDesktopShortcuts = $false
    $shortcutChoice = (Read-Host "Vuoi creare shortcut sul desktop (s/n)").Trim().ToLower()
    if ($shortcutChoice -eq "s") {
        $createDesktopShortcuts = $true
        Write-Log "Desktop shortcuts: SI"
    } else {
        Write-Log "Desktop shortcuts: NO"
    }

    $autoLoginConfig = $null
    $autoLoginConfigPath = Join-Path $PSScriptRoot "autologin.json"
    if (Test-Path $autoLoginConfigPath)
    {
        try
        {
            Write-Log "Lettura configurazione auto-login da file JSON: $autoLoginConfigPath"
            $jsonRaw = Get-Content -Path $autoLoginConfigPath -Raw -Encoding UTF8
            $json = $jsonRaw | ConvertFrom-Json

            # Supporta piu' nomi di campo per compatibilita'
            $login = $json.Login
            if (-not $login)
            {
                $login = $json.User
            }
            if (-not $login)
            {
                $login = $json.Username
            }
            if (-not $login)
            {
                $login = $json.Utente
            }

            $server = $json.Server
            $password = $json.Password

            if ($login -and $server -and $password)
            {
                $autoLoginConfig = [PSCustomObject]@{
                    Login = $login
                    Server = $server
                    Password = $password
                }
                Write-Log "Auto-login abilitato da JSON per le nuove istanze MT5 (login=$login, server=$server)"
                Write-Log "ATTENZIONE: le credenziali sono salvate in chiaro nel file JSON e nei file di config MT5. Proteggi questo VPS!"
            }
            else
            {
                Write-Log "Auto-login NON configurato: JSON mancante di uno o piu' campi (login/server/password). File: $autoLoginConfigPath"
            }
        }
        catch
        {
            Write-Log "ERRORE lettura/parsing JSON auto-login ($autoLoginConfigPath) : $( $_.Exception.Message )"
        }
    }
    else
    {
        Write-Log "File autologin.json non trovato in $PSScriptRoot. Auto-login disabilitato."
    }

    Clear-Host
    Write-Host ""
    Write-Host "=================================================="
    Write-Host "  ARBITEX VPS - INSTALLA E CONFIGURA MT5"
    Write-Host "=================================================="
    Write-Log "Inizio installazione multipla MT5."

    foreach ($p in @($programsPath, $edgeConfig, $propConfig, $iconSourcePath, $terminalRoot)) {
        if (-not $p) {
            Write-Log "ERRORE: path nullo"
            Write-Host "ERRORE: path nullo" -ForegroundColor Red
            return
        }
        if (-not (Test-Path $p)) {
            Write-Log "ERRORE: path non trovato: $p"
            Write-Host "ERRORE: path non trovato: $p" -ForegroundColor Red
            return
        }
    }

    if (-not $baseInstallPath) {
        Write-Log "ERRORE: baseInstallPath nullo"
        Write-Host "ERRORE: baseInstallPath nullo" -ForegroundColor Red
        return
    }
    if (-not (Test-Path $baseInstallPath)) {
        try {
            New-Item -ItemType Directory -Path $baseInstallPath | Out-Null
            Write-Log "Creata directory: $baseInstallPath"
            Write-Host "Creata directory: $baseInstallPath" -ForegroundColor Green
        } catch {
            Write-Log "ERRORE creazione directory: $($_.Exception.Message)"
            Write-Host "ERRORE: impossibile creare directory" -ForegroundColor Red
            return
        }
    }

    $mt5setupExe = Join-Path $programsPath "4_mt5setup.exe"
    if (-not (Test-Path $mt5setupExe)) {
        Write-Log "ERRORE: Installer non trovato: $mt5setupExe"
        Write-Host "ERRORE: Installer non trovato" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Step 1: Verifica e installa VC Redistributables" -ForegroundColor Cyan
    Install-VCRedistributable -programsPath $programsPath
    Write-Host ""
    Write-Host "Step 2: Installazione MetaTrader 5" -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds 2

    $totalSteps = 0
    foreach ($prop in $selectedProps) {
        $totalSteps += $instanceCounts[$prop]
    }
    if ($includeHedgeChoice) { $totalSteps++ }

    $step = 1

    if ($includeHedgeChoice) {
        $hedgeExists = $existingMap.ContainsKey("HEDGE")

        if ($hedgeExists) {
            Write-Host ""
            Write-Host "HEDGE gia installato. Cosa vuoi fare?" -ForegroundColor Yellow
            Write-Host "[1] Installa HEDGE 2 (nuova istanza incrementale)"
            Write-Host "[2] Reinstalla HEDGE (sovrascrivi l'esistente)" -ForegroundColor Cyan
            Write-Host "[x] Skip HEDGE"

            $hedgeChoice = (Read-Host "Scelta [1/2/x]").Trim().ToLower()

            if ($hedgeChoice -eq "1") {
                $instanceLabel = "HEDGE 2"
                $customPath = Join-Path $baseInstallPath "MetaTrader 5 - $instanceLabel"
                $iconPath = $propIcons["HEDGE"]
                Write-Log "Installa come: $instanceLabel (HEDGE - config in AppData/Terminal)"
                Install-MT5InstanceHedge -instanceLabel $instanceLabel -setupExe $mt5setupExe -customPath $customPath `
                    -configSrc $edgeConfig -iconPath $iconPath -currentStep $step -totalSteps $totalSteps `
                    -terminalRoot $terminalRoot -createDesktopShortcut $createDesktopShortcuts -autoLoginConfig $autoLoginConfig
            } elseif ($hedgeChoice -eq "2") {
                $instanceLabel = "HEDGE"
                $customPath = Join-Path $baseInstallPath "MetaTrader 5 - $instanceLabel"
                $iconPath = $propIcons["HEDGE"]
                Write-Log "Reinstalla: $instanceLabel (HEDGE - config in AppData/Terminal)"
                Write-Host "Reinstallazione HEDGE..." -ForegroundColor Cyan
                Install-MT5InstanceHedge -instanceLabel $instanceLabel -setupExe $mt5setupExe -customPath $customPath `
                    -configSrc $edgeConfig -iconPath $iconPath -currentStep $step -totalSteps $totalSteps `
                    -terminalRoot $terminalRoot -createDesktopShortcut $createDesktopShortcuts -autoLoginConfig $autoLoginConfig
            } else {
                Write-Host "SKIP - HEDGE non modificato" -ForegroundColor Yellow
                Write-Log "Skip HEDGE"
            }
        } else {
            $instanceLabel = "HEDGE"
            $customPath = Join-Path $baseInstallPath "MetaTrader 5 - $instanceLabel"
            $iconPath = $propIcons["HEDGE"]
            Write-Log "Prima installazione HEDGE (config in AppData/Terminal)"
            Install-MT5InstanceHedge -instanceLabel $instanceLabel -setupExe $mt5setupExe -customPath $customPath `
                -configSrc $edgeConfig -iconPath $iconPath -currentStep $step -totalSteps $totalSteps `
                -terminalRoot $terminalRoot -createDesktopShortcut $createDesktopShortcuts -autoLoginConfig $autoLoginConfig
        }

        $step++
    }

    foreach ($prop in $selectedProps) {
        $numInstances = $instanceCounts[$prop]

        if ($numInstances -eq 0) {
            continue
        }

        $nextInstanceNum = 1
        if ($existingMap.ContainsKey($prop)) {
            $nextInstanceNum = ($existingMap[$prop] | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum) + 1
        }

        for ($i = 0; $i -lt $numInstances; $i++) {
            $instanceNum = $nextInstanceNum + $i
            $instanceLabel = "$prop $instanceNum"
            $customPath = Join-Path $baseInstallPath "MetaTrader 5 - $instanceLabel"
            $iconPath = $propIcons[$prop]

            Install-MT5Instance -instanceLabel $instanceLabel -setupExe $mt5setupExe -customPath $customPath `
                -configSrc $propConfig -iconPath $iconPath -instanceNum $instanceNum -currentStep $step -totalSteps $totalSteps `
                -terminalRoot $terminalRoot -createDesktopShortcut $createDesktopShortcuts -isReinstall $false -autoLoginConfig $autoLoginConfig
            $step++
        }
    }

    Write-Progress -Completed -Activity "Installazione MT5"
    Write-Host ""
    Write-Host "Installazione multipla MT5 COMPLETATA!" -ForegroundColor Green
    if ($createDesktopShortcuts) {
        Remove-GenericMT5Shortcuts -baseInstallPath $baseInstallPath
        Write-Host " Shortcut desktop generici rimossi." -ForegroundColor Green
    }
    Write-Log "Installazione multipla MT5 completata."
}
