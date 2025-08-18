<#
.SYNOPSIS
    We Enhanced Azure Certificate Monitor

.DESCRIPTION
    Professional PowerShell script for enterprise automation.
    Optimized for performance, reliability, and error handling.

.AUTHOR
    Enterprise PowerShell Framework

.VERSION
    1.0

.NOTES
    Requires appropriate permissions and modules
#>

$WEErrorActionPreference = "Stop"
$WEVerbosePreference = if ($WEPSBoundParameters.ContainsKey('Verbose')) { " Continue" } else { " SilentlyContinue" }

[CmdletBinding()]
$ErrorActionPreference = "Stop"
param(
    [Parameter(Mandatory=$false)]
    [int]$WEExpirationWarningDays = 30,
    
    [Parameter(Mandatory=$false)]
    [switch]$WECheckKeyVaultCertificates,
    
    [Parameter(Mandatory=$false)]
    [switch]$WECheckAppGatewayCertificates
)

Import-Module (Join-Path $WEPSScriptRoot " ..\modules\AzureAutomationCommon\AzureAutomationCommon.psm1") -Force
Show-Banner -ScriptName " Azure Certificate Monitor" -Version " 1.0" -Description " Monitor SSL certificate expiration"

try {
    if (-not (Test-AzureConnection)) { throw " Azure connection validation failed" }

    $expiringCertificates = @()
    $warningDate = (Get-Date).AddDays($WEExpirationWarningDays)

    if ($WECheckKeyVaultCertificates) {
        $keyVaults = Get-AzKeyVault
        
        foreach ($vault in $keyVaults) {
            try {
                $certificates = Get-AzKeyVaultCertificate -VaultName $vault.VaultName
                
                foreach ($cert in $certificates) {
                   ;  $certDetails = Get-AzKeyVaultCertificate -VaultName $vault.VaultName -Name $cert.Name
                    
                    if ($certDetails.Expires -and $certDetails.Expires -le $warningDate) {
                        $expiringCertificates = $expiringCertificates + [PSCustomObject]@{
                            Service = " Key Vault"
                            VaultName = $vault.VaultName
                            CertificateName = $cert.Name
                            ExpirationDate = $certDetails.Expires
                            DaysUntilExpiration = [math]::Round(($certDetails.Expires - (Get-Date)).TotalDays)
                        }
                    }
                }
            } catch {
                Write-Log " ⚠️ Could not access certificates in vault: $($vault.VaultName)" -Level WARNING
            }
        }
    }

    Write-WELog " Certificate Monitoring Results:" " INFO" -ForegroundColor Cyan
    Write-WELog " Warning threshold: $WEExpirationWarningDays days" " INFO" -ForegroundColor Yellow
    Write-WELog " Certificates expiring soon: $($expiringCertificates.Count)" " INFO" -ForegroundColor Red

    if ($expiringCertificates.Count -gt 0) {
        $expiringCertificates | Sort-Object ExpirationDate | Format-Table Service, VaultName, CertificateName, ExpirationDate, DaysUntilExpiration
    } else {
        Write-WELog " ✅ No certificates expiring within $WEExpirationWarningDays days" " INFO" -ForegroundColor Green
    }

} catch {
    Write-Log " ❌ Certificate monitoring failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}



# Wesley Ellis Enterprise PowerShell Toolkit
# Enhanced automation solutions: wesellis.com
# ============================================================================