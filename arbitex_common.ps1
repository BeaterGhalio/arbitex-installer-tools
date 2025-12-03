# =========================================
# ARBITEX VPS - Common utilities
# =========================================

function Write-Log
{
    param([string]$msg)

    Add-Content -Path "installation_log.txt" -Value (
    "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    ) -ErrorAction SilentlyContinue

    Write-Host $msg -ForegroundColor Cyan
}

function Invoke-Safe
{
    param(
        [scriptblock]$Action,
        [string]$Description
    )

    try
    {
        Write-Log "Avvio: $Description"
        & $Action
        Write-Log "Completato: $Description"
        return $true
    }
    catch
    {
        Write-Log "ERRORE in $Description : $( $_.Exception.Message )"
        Write-Host "ERRORE: $Description" -ForegroundColor Red
        return $false
    }
}
