#Requires -Version 7.0
#Requires -Modules Az.Resources

<#
.SYNOPSIS
    Start Azurev2Vm

.DESCRIPTION
    Azure automation
    Wes Ellis (wes@wesellis.com)

    1.0
    Requires appropriate permissions and modules
#>
$ErrorActionPreference = "Stop"
$VerbosePreference = if ($PSBoundParameters.ContainsKey('Verbose')) { "Continue" } else { "SilentlyContinue" }
    Starts all Azure V2 (ARM) virtual machines by resource group.
   Uses PowerShell workflow to start all VMs in parallel.  Includes a retry and wait cycle to display when VMs are started.
   Workflow sessions require Azure authentication into each session so this script uses a splatting of parameters required for Connect-AzureRmAccount that
   can be passed to each session.  Recommend using the New-AzureServicePrincipal -ErrorAction Stop script to create the required service principal and associated ApplicationId
   and certificate thumbprint required to log into Azure with the -servicePrincipal flag
   .\Start-AzureV2vm.ps1 -ResourceGroupName 'CONTOSO'  -CertificateThumbprint 'F3FB843E7D22594E16066F1A3A04CA29D5D6DA91' -ApplicationID 'd2d20159-4482-4987-9724-f367afb170e8' -TenantID '72f632bf-86f6-41af-77ab-2d7cd011db47'
   .\Start-AzureV2vm.ps1 -FirstServer 'DC-CONTOSO-01' -ResourceGroupName 'CONTOSO'  -CertificateThumbprint 'F3FB843E7D22594E16066F1A3A04CA29D5D6DA91' -ApplicationID 'd2d20159-4482-4987-9724-f367afb170e8' -TenantID '72f632bf-86f6-41af-77ab-2d7cd011db47'
.PARAMETER -ResourceGroupName [string]
  Name of resource group being copied
.PARAMETER -CertificateThumbprint [string]
  Thumbprint of the x509 certificate that is used for authentication
.PARAMETER -ApplicationId [string]
  Aplication ID of the registered Azure Active Directory Service Principal
.PARAMETER -TenantId [string]
  Tenant ID of the registered Azure Active Directory Service Principal
.PARAMETER -Environment [string]
  Name of Environment e.g. AzureUSGovernment.  Defaults to AzureCloud
.PARAMETER -FirstServer [string]
  Identifies the the first server to start. i.e. a domain controller
    Original Author:   https://github.com/JeffBow
 ------------------------------------------------------------------------
               Copyright (C) 2016 Microsoft Corporation
 You have a royalty-free right to use, modify, reproduce and distribute
 this sample script (and/or any modified version) in any way
 you find useful, provided that you agree that Microsoft has no warranty,
 obligations or liability for any sample application or script files.
 ------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateThumbprint,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationId,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,
    [Parameter(ValueFromPipeline)]`n    [string]$Environment= "AzureCloud" ,
    [Parameter(ValueFromPipeline)]`n    [string]$FirstServer
)
$loginParams = @{
"CertificateThumbprint" = $CertificateThumbprint
"ApplicationId" = $ApplicationId
"TenantId" = $TenantId
"ServicePrincipal" = $null
"EnvironmentName" = $Environment
}
$ProgressPreference = 'SilentlyContinue'
if ((Get-Module -ErrorAction Stop AzureRM).Version -lt " 5.5.0" ) {
   Write-warning "Old version of Azure PowerShell module  $((Get-Module -ErrorAction Stop AzureRM).Version.ToString()) detected.  Minimum of 5.5.0 required. Run Update-Module AzureRM"
   BREAK
}
function Start-Vm
{
    [CmdletBinding()]
param($vmName, $resourceGroupName)
    Write-Output "Starting $vmName..."
    $count=1
    do
    {
        $status = ((get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName -status).Statuses|where{$_.Code -like 'PowerState*'}).DisplayStatus
        Write-Output " $vmName current status is $status"
        if($status -ne 'VM running')
        {
            if($count -gt 1)
            {
                Write-Output "Failed to start $VMName. Retrying in 60 seconds..."
                sleep 60
            }
            $rtn = Start-AzureRMVM -Name $VMName -ResourceGroupName $ResourceGroupName -ea SilentlyContinue
            $count++
        }
    }
    while($status -ne 'VM running' -and $count -lt 5)
    if($status -eq 'VM running')
    {
        Write-Output " $VMName started."
    }
    else
    {
        Write-Output "Startup of $VMName FAILED on attempt number $count of 5."
    }
}  # end of start-vm function
Workflow Start-VMs
{ [CmdletBinding()]
param($VMs, $ResourceGroupName, $loginParams)
  foreach -parallel ($vm in $VMs)
    {
      $login = Connect-AzureRmAccount @loginParams
      $vmName = $vm.Name
      Start-Vm -VmName $vmName -ResourceGroupName $resourceGroupName
    }
} # end of worflow
try
{
    # Log into Azure
    Connect-AzureRmAccount @loginParams -ea Stop | out-null
}
catch
{
    if (! $CertificateThumbprint)
    {
        $ErrorMessage = "Certificate $CertificateThumbprint not found."
        throw $ErrorMessage
    }
    else
    {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
    BREAK
}
$vms = Get-AzureRmVM -ResourceGroupName $ResourceGroupName
 #pre action confirmation
 write-output "Starting...$($vms.Name)"
if($firstServer)
{
    Start-Vm -vmName $firstServer -ResourceGroupName $resourceGroupName
    sleep 10
}
$remainingVMs = $vms | where-object -FilterScript{$_.name -ne $firstServer}
Start-VMs -VMs $remainingVMs -ResourceGroupName $resourceGroupName -loginParams $loginParams
 #post action confirmation
 do{
    cls
    Write-Host "Waiting for VMs in $resourceGroupName to start..."
    $allStatus = @()
    foreach ($vm in $VMs)
    {
        $status = ((get-azurermvm -ResourceGroupName $resourceGroupName -Name $vm.Name -status).Statuses|where{$_.Code -like 'PowerState*'}).DisplayStatus
        " $($vm.Name) - $status"
$allStatus = $allStatus + $status
    }
    sleep 3
 }
 while($allStatus -ne 'VM Running')
cls
Write-Host "All VMs in $resourceGroupName are ready..."
foreach ($vm in $VMs)
{
$status = ((get-azurermvm -ResourceGroupName $resourceGroupName -Name $vm.Name -status).Statuses|where{$_.Code -like 'PowerState*'}).DisplayStatus
   " $($vm.Name) - $status"
}\n

