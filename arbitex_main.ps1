# =========================================
# ARBITEX VPS - Installation Wizard (MAIN)
# =========================================

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$msg)
    Add-Content -Path "installation_log.txt" -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -ErrorAction SilentlyContinue
    Write-Host $msg -ForegroundColor Cyan
}

trap {
    $errorMsg = "ERRORE CRITICO: $($_.Exception.Message)"
    if ($_.InvocationInfo.ScriptLineNumber) {
        $errorMsg += " (Linea $($_.InvocationInfo.ScriptLineNumber))"
    }
    Write-Log $errorMsg
    Write-Host "`n*** $errorMsg ***" -ForegroundColor Red
    Write-Host "Controlla installation_log.txt per dettagli."
    Read-Host "Premi INVIO per uscire..."
    exit 1
}

Write-Log "=== AVVIO ARBITEX VPS Installation Wizard ==="
if (-not (Test-Path "$PSScriptRoot\Programs")) {
    Write-Host "ERRORE: Cartella Programs non trovata!" -ForegroundColor Red
    Read-Host "Premi INVIO per uscire..."
    exit 1
}

$modules = @(
    "arbitex_installer.ps1",
    "arbitex_update_ea.ps1", 
    "arbitex_update_config.ps1",
    "arbitex_cleanup.ps1",
    "arbitex_selfupdate.ps1"
)

foreach ($module in $modules) {
    $modulePath = "$PSScriptRoot\$module"
    if (Test-Path $modulePath) {
        try {
            . $modulePath
            Write-Log "Modulo caricato: $module"
        } catch {
            Write-Log "ERRORE caricamento modulo $module : $($_.Exception.Message)"
        }
    } else {
        Write-Log "AVVISO: Modulo non trovato: $module"
    }
}

$programsPath     = "$PSScriptRoot\Programs"
$baseInstallPath  = "C:\MetaTrader"
$edgeConfig       = "$PSScriptRoot\standard_config_edge"
$propConfig       = "$PSScriptRoot\standard_config_prop"
$iconSourcePath   = "$PSScriptRoot\Icons"
$terminalRoot     = "$env:APPDATA\MetaQuotes\Terminal"

# URL di fallback per il pacchetto EA (es. vecchio storage Arbitex)
$urlEA            = 'https://storage.arbitexcorp.com/U0y23wTqtbby.zip'

# Versione corrente del pacchetto EA atteso da questo installer
$eaVersion = '1.0.0'

# URL opzionale su GitHub per scaricare il pacchetto EA (se valorizzato viene usato al posto di $urlEA)
# Esempio: 'https://raw.githubusercontent.com/BeaterGhalio/arbitex-installer-tools/main/releases/arbitex_ea_latest.zip'
$eaGithubUrl = ''

# URL GitHub per aggiornare l'installer stesso
$installerGithubZipUrl = 'https://github.com/BeaterGhalio/arbitex-installer-tools/archive/refs/heads/main.zip'
$installerGithubVersionUrl = 'https://raw.githubusercontent.com/BeaterGhalio/arbitex-installer-tools/main/installer_version.txt'

# Auto-aggiornamento non interattivo dell'installer (se disponibile nuova versione)
Invoke-ArbitexSelfUpdate -zipUrl $installerGithubZipUrl -versionUrl $installerGithubVersionUrl

$requiredFolders = @($programsPath, $edgeConfig, $propConfig, $iconSourcePath)
foreach ($folder in $requiredFolders) {
    if (-not (Test-Path $folder)) {
        Write-Log "AVVISO: Cartella mancante: $folder"
    }
}

$propIcons = @{
    "FTMO"         = "$iconSourcePath\FTMO.ico"
    "FundedNext"   = "$iconSourcePath\Fundednext.ico"
    "FunderPro"    = "$iconSourcePath\fplogo.ico"
    "FundingPips"  = "$iconSourcePath\fundingpips.ico"
    "The5ers"      = "$iconSourcePath\5erslogo.ico"
    "Fintokei"     = "$iconSourcePath\Fintokei.ico"
    "E8 Markets"   = "$iconSourcePath\e8markets.ico"
    "HEDGE"        = "$iconSourcePath\HEDGE.ico"
}

$propList = @("FTMO", "The5ers", "FunderPro", "FundingPips", "Fintokei", "E8 Markets", "FundedNext")
$includeEdge = $true

function Invoke-Safe {
    param([scriptblock]$Action, [string]$Description)
    try {
        Write-Log "Avvio: $Description"
        & $Action
        Write-Log "Completato: $Description"
        return $true
    } catch {
        Write-Log "ERRORE in $Description : $($_.Exception.Message)"
        Write-Host "ERRORE: $Description" -ForegroundColor Red
        return $false
    }
}

function SecretMenu {
    $choice = ""
    do {
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "  ARBITEX VPS - Installation Wizard" -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "`n======= ARBITEX VPS - MENU ADMIN ======" -ForegroundColor Magenta
        Write-Host " [1] Aggiorna Expert Advisor in tutte le installazioni MT5"
        Write-Host " [2] Aggiorna EA dentro le cartelle config standard"
        Write-Host " [3] Installazione multipla e configurazione MT5"
        Write-Host " [4] Visualizza log installazione"
        Write-Host " [5] Pulizia totale di tutte le installazioni MetaTrader 5"
        Write-Host " [x] Esci"
        $choice = (Read-Host "`nScelta [1/2/3/4/5/x]").Trim().ToLower()

        switch ($choice) {
            '1' {
                Invoke-Safe { Update-AllMT5EAs -url $urlEA } "Aggiornamento EA in tutte le installazioni MT5"
                Write-Host "`nOperazione completata. Premi INVIO per tornare al menu..." -ForegroundColor Green
                Read-Host
            }
            '2' {
                Invoke-Safe { Update-ConfigEAs -configDirEdge $edgeConfig -configDirProp $propConfig -url $urlEA } "Aggiornamento EA nelle cartelle config"
                Write-Host "`nOperazione completata. Premi INVIO per tornare al menu..." -ForegroundColor Green
                Read-Host
            }
            '3' {
                Invoke-Safe { 
                    Invoke-ArbitexInstaller -programsPath $programsPath -baseInstallPath $baseInstallPath -edgeConfig $edgeConfig -propConfig $propConfig -iconSourcePath $iconSourcePath -terminalRoot $terminalRoot -propIcons $propIcons -propList $propList -includeEdge $includeEdge
                } "Installazione multipla MT5"
                Write-Host "`nInstallazione MT5 completa. Premi INVIO per tornare al menu..." -ForegroundColor Green
                Read-Host
            }
            '4' {
                Write-Host "`n========= LOG INSTALLAZIONE ==========" -ForegroundColor Yellow
                if (Test-Path "installation_log.txt") {
                    Get-Content "installation_log.txt" -Tail 50
                } else {
                    Write-Host "Nessun log disponibile." -ForegroundColor Yellow
                }
                Write-Host "======================================" -ForegroundColor Yellow
                Write-Host "`nPremi INVIO per tornare al menu..."
                Read-Host
            }
            '5' {
                Invoke-Safe { Remove-AllMT5InstallersInteractive } "Pulizia interattiva MT5"
                Write-Host "`nPulizia completata. Premi INVIO per tornare al menu..." -ForegroundColor Green
                Read-Host
            }
            'x' {
                Write-Log "Uscita volontaria dal wizard."
                Write-Host "`nUscita dal wizard. Bye!" -ForegroundColor Green
                break
            }
            default {
                Write-Host "Scelta non valida. Riprova." -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($choice -ne 'x')
}

Write-Log "Wizard avviato da: $PSScriptRoot"
SecretMenu
Write-Log "=== FINE SESSIONE ARBITEX VPS ==="
