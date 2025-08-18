﻿# ============================================================================
# Script Name: Azure Subscription Security Auditor
# Author: Wesley Ellis
# Email: wes@wesellis.com
# Website: wesellis.com
# Date: May 23, 2025
# Description: Audits Azure subscription security settings and permissions
# ============================================================================

param (
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "SecurityAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
)

Write-Information "Starting Azure Security Audit..."

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId
    Write-Information "Auditing subscription: $SubscriptionId"
} else {
    $SubscriptionId = (Get-AzContext).Subscription.Id
    Write-Information "Auditing current subscription: $SubscriptionId"
}

$AuditResults = @{
    SubscriptionInfo = @{}
    RoleAssignments = @()
    PolicyAssignments = @()
    SecurityFindings = @()
    Recommendations = @()
}

try {
    # Get subscription information
    $Subscription = Get-AzSubscription -SubscriptionId $SubscriptionId
    $AuditResults.SubscriptionInfo = @{
        Name = $Subscription.Name
        Id = $Subscription.Id
        TenantId = $Subscription.TenantId
        State = $Subscription.State
    }
    
    Write-Information "✅ Subscription info collected"
    
    # Audit role assignments
    Write-Information "🔍 Auditing role assignments..."
    $RoleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId"
    
    foreach ($Assignment in $RoleAssignments) {
        $AuditResults.RoleAssignments += @{
            PrincipalName = $Assignment.DisplayName
            PrincipalType = $Assignment.ObjectType
            Role = $Assignment.RoleDefinitionName
            Scope = $Assignment.Scope
            PrincipalId = $Assignment.ObjectId
        }
    }
    
    # Check for privileged roles
    $PrivilegedRoles = @("Owner", "User Access Administrator", "Security Administrator")
    $PrivilegedAssignments = $RoleAssignments | Where-Object { $_.RoleDefinitionName -in $PrivilegedRoles }
    
    if ($PrivilegedAssignments.Count -gt 10) {
        $AuditResults.SecurityFindings += "⚠️ High number of privileged role assignments: $($PrivilegedAssignments.Count)"
        $AuditResults.Recommendations += "Review and minimize privileged access assignments"
    }
    
    Write-Information "✅ Role assignments audited: $($RoleAssignments.Count) found"
    
    # Audit policy assignments
    Write-Information "🔍 Auditing policy assignments..."
    $PolicyAssignments = Get-AzPolicyAssignment -Scope "/subscriptions/$SubscriptionId"
    
    foreach ($Policy in $PolicyAssignments) {
        $AuditResults.PolicyAssignments += @{
            Name = $Policy.Name
            PolicyDefinitionId = $Policy.Properties.PolicyDefinitionId
            Scope = $Policy.Properties.Scope
            EnforcementMode = $Policy.Properties.EnforcementMode
        }
    }
    
    Write-Information "✅ Policy assignments audited: $($PolicyAssignments.Count) found"
    
    # Security checks
    Write-Information "🔍 Performing security checks..."
    
    # Check for guest users with privileged access
    $GuestUsers = $RoleAssignments | Where-Object { $_.DisplayName -like "*#EXT#*" -and $_.RoleDefinitionName -in $PrivilegedRoles }
    if ($GuestUsers.Count -gt 0) {
        $AuditResults.SecurityFindings += "⚠️ Guest users with privileged access: $($GuestUsers.Count)"
        $AuditResults.Recommendations += "Review guest user access and implement time-limited assignments"
    }
    
    # Check for service principals with Owner role
    $ServicePrincipalOwners = $RoleAssignments | Where-Object { $_.ObjectType -eq "ServicePrincipal" -and $_.RoleDefinitionName -eq "Owner" }
    if ($ServicePrincipalOwners.Count -gt 0) {
        $AuditResults.SecurityFindings += "⚠️ Service principals with Owner role: $($ServicePrincipalOwners.Count)"
        $AuditResults.Recommendations += "Consider using more restrictive roles for service principals"
    }
    
    # Check for users with subscription-level Owner access
    $SubscriptionOwners = $RoleAssignments | Where-Object { $_.Scope -eq "/subscriptions/$SubscriptionId" -and $_.RoleDefinitionName -eq "Owner" }
    if ($SubscriptionOwners.Count -gt 5) {
        $AuditResults.SecurityFindings += "⚠️ Many subscription owners: $($SubscriptionOwners.Count)"
        $AuditResults.Recommendations += "Limit subscription-level Owner assignments"
    }
    
    Write-Information "✅ Security checks completed"
    
    # Generate HTML report
    $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Security Audit Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background-color: #1a1a1a; color: #ffffff; margin: 20px; }
        .header { background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%); padding: 30px; text-align: center; border-radius: 8px; margin-bottom: 20px; }
        h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .summary { background-color: #2c2c2c; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .finding { background-color: #3a2a2a; padding: 15px; margin: 10px 0; border-left: 4px solid #e74c3c; border-radius: 4px; }
        .recommendation { background-color: #2a3a2a; padding: 15px; margin: 10px 0; border-left: 4px solid #27ae60; border-radius: 4px; }
        table { width: 100%; border-collapse: collapse; background-color: #2c2c2c; border-radius: 8px; margin-bottom: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #444; }
        th { background: #34495e; font-weight: 600; }
        .footer { text-align: center; margin-top: 40px; color: #888; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Azure Security Audit Report</h1>
        <div>Subscription: $($AuditResults.SubscriptionInfo.Name)</div>
        <div>Generated by Wesley Ellis | $(Get-Date -Format "MMMM dd, yyyy 'at' HH:mm")</div>
    </div>
    
    <div class="summary">
        <h2>Executive Summary</h2>
        <p><strong>Subscription:</strong> $($AuditResults.SubscriptionInfo.Name)</p>
        <p><strong>Subscription ID:</strong> $($AuditResults.SubscriptionInfo.Id)</p>
        <p><strong>Role Assignments:</strong> $($AuditResults.RoleAssignments.Count)</p>
        <p><strong>Policy Assignments:</strong> $($AuditResults.PolicyAssignments.Count)</p>
        <p><strong>Security Findings:</strong> $($AuditResults.SecurityFindings.Count)</p>
    </div>
    
    <h2>Security Findings</h2>
"@
    
    foreach ($Finding in $AuditResults.SecurityFindings) {
        $HTML += "<div class='finding'>$Finding</div>"
    }
    
    $HTML += "<h2>Recommendations</h2>"
    
    foreach ($Recommendation in $AuditResults.Recommendations) {
        $HTML += "<div class='recommendation'>✅ $Recommendation</div>"
    }
    
    $HTML += @"
    
    <div class="footer">
        <p>Report generated by Wesley Ellis | CompuCom Systems Inc. | $(Get-Date -Format "MMMM dd, yyyy")</p>
        <p>Azure Automation Scripts | Security Audit Tool</p>
    </div>
</body>
</html>
"@
    
    # Save report
    $HTML | Out-File -FilePath $OutputPath -Encoding UTF8
    
    Write-Information "✅ Security audit completed successfully!"
    Write-Information "📊 Audit Results:"
    Write-Information "  Role Assignments: $($AuditResults.RoleAssignments.Count)"
    Write-Information "  Policy Assignments: $($AuditResults.PolicyAssignments.Count)"
    Write-Information "  Security Findings: $($AuditResults.SecurityFindings.Count)"
    Write-Information "  Report saved to: $OutputPath"
    
} catch {
    Write-Error "Security audit failed: $($_.Exception.Message)"
}
