# ============================================================================
# Logic App Standard - VNet / Storage / Trigger Diagnostic Script
#
# Read-only diagnostic — does NOT modify any resources.
# Checks the full chain: Logic App runtime → Storage connectivity →
# Private Endpoints → DNS Zone links → SharePoint connector → NSGs.
#
# Fails gracefully when permissions are insufficient — reports what's
# needed and continues checking everything it can.
#
# Prerequisites:
#   - az CLI logged in
#   - deploy.config.ps1 exists with correct values
#
# Usage:
#   .\diagnose-logicapp.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Check {
    param([string]$Label, [string]$Status, [string]$Detail = "", [string]$Severity = "INFO")
    $icon = switch ($Severity) {
        "PASS"    { "[PASS]"; }
        "FAIL"    { "[FAIL]"; }
        "WARN"    { "[WARN]"; }
        "SKIP"    { "[SKIP]"; }
        default   { "[INFO]"; }
    }
    $color = switch ($Severity) {
        "PASS"    { "Green" }
        "FAIL"    { "Red" }
        "WARN"    { "Yellow" }
        "SKIP"    { "DarkYellow" }
        default   { "Cyan" }
    }
    Write-Host "  $icon " -ForegroundColor $color -NoNewline
    Write-Host "$Label" -NoNewline
    if ($Status) { Write-Host " = " -NoNewline; Write-Host "$Status" -ForegroundColor White }
    else { Write-Host "" }
    if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

$issues = [System.Collections.ArrayList]::new()

function Add-Issue {
    param([string]$Severity, [string]$Message, [string]$Fix = "")
    $null = $script:issues.Add([pscustomobject]@{ Severity = $Severity; Message = $Message; Fix = $Fix })
}

function Write-PermissionError {
    param([string]$Operation, [string]$Permission)
    Write-Check $Operation "SKIPPED — insufficient permissions" -Severity "SKIP" `
        -Detail "Needs: $Permission"
    Add-Issue "PERMISSION" "Could not check '$Operation'" "Requires: $Permission"
}

# Runs an az CLI command, returns parsed JSON or $null on failure.
# Sets $script:lastAzOk to $true/$false.
function Invoke-AzSafe {
    param([string[]]$Arguments)
    $raw = & az @Arguments 2>$null
    $script:lastAzOk = ($LASTEXITCODE -eq 0 -and $raw)
    if ($script:lastAzOk) {
        try { return $raw | ConvertFrom-Json } catch { return $raw }
    }
    return $null
}

# ============================================================================
# Load Configuration
# ============================================================================

Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Logic App VNet/Storage Diagnostic" -ForegroundColor Magenta
Write-Host "  (read-only - no changes will be made)" -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Magenta

$configPath = Join-Path $PSScriptRoot "deploy.config.ps1"
if (-not (Test-Path $configPath)) {
    Write-Host "`n  [FAIL] Configuration file not found: $configPath" -ForegroundColor Red
    Write-Host "         Copy deploy.config.ps1.template or create it with your settings." -ForegroundColor DarkGray
    exit 1
}
Write-Host "`nLoading deploy.config.ps1..." -ForegroundColor Yellow
. $configPath

# ============================================================================
# Step 0: Verify az CLI login
# ============================================================================

$accountJson = az account show -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
    Write-Host "`n  [FAIL] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
$account = $accountJson | ConvertFrom-Json
Write-Host "  Logged in as: $($account.user.name) | Subscription: $($account.name) ($($account.id))" -ForegroundColor DarkGray

# ============================================================================
# Step 1: Discover Resources
# ============================================================================

Write-Section "1. RESOURCE DISCOVERY"

$resourcePrefix = "$BASE_NAME-$ENVIRONMENT"

# Try deployment outputs first, fall back to query
$deployment = Invoke-AzSafe @('deployment', 'group', 'show', '-g', $RESOURCE_GROUP, '-n', 'main', '-o', 'json')
$usedDeploymentOutputs = $false
if ($deployment -and $deployment.properties.outputs) {
    $LOGIC_APP_NAME      = $deployment.properties.outputs.logicAppName.value
    $FUNCTION_APP_NAME   = $deployment.properties.outputs.functionAppName.value
    $STORAGE_ACCOUNT     = $deployment.properties.outputs.storageAccountName.value
    $SP_CONNECTION_NAME  = $deployment.properties.outputs.sharePointConnectionName.value

    # Validate — outputs may be empty if deployment failed partway through
    if ($LOGIC_APP_NAME -and $STORAGE_ACCOUNT) {
        $usedDeploymentOutputs = $true
        Write-Host "  Loaded from deployment outputs" -ForegroundColor DarkGray
    } else {
        Write-Host "  Deployment 'main' found but outputs are empty (deployment may have failed)." -ForegroundColor Yellow
        Write-Host "  Deployment state: $($deployment.properties.provisioningState)" -ForegroundColor Yellow
        Write-Host "  Falling back to resource discovery..." -ForegroundColor Yellow
    }
}

if (-not $usedDeploymentOutputs) {
    if (-not $deployment) {
        Write-Host "  No deployment named 'main' found, discovering resources..." -ForegroundColor Yellow
    }

    $LOGIC_APP_NAME = (az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/sites' --query "[?kind=='functionapp,linux,workflowapp'].name | [0]" -o tsv 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-PermissionError "List resources in $RESOURCE_GROUP" "Reader on resource group '$RESOURCE_GROUP' (Microsoft.Resources/subscriptions/resourceGroups/read, Microsoft.Web/sites/read)"
    } else {
        $FUNCTION_APP_NAME  = (az functionapp list -g $RESOURCE_GROUP --query "[?starts_with(name,'$resourcePrefix-func')].name | [0]" -o tsv 2>$null)
        $STORAGE_ACCOUNT    = (az storage account list -g $RESOURCE_GROUP --query "[?starts_with(name,'$($BASE_NAME)$($ENVIRONMENT)')].name | [0]" -o tsv 2>$null)
        $SP_CONNECTION_NAME = (az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' --query "[?starts_with(name,'$resourcePrefix')].name | [0]" -o tsv 2>$null)
    }
}

# Trim all
if ($LOGIC_APP_NAME)     { $LOGIC_APP_NAME     = $LOGIC_APP_NAME.Trim() }
if ($FUNCTION_APP_NAME)  { $FUNCTION_APP_NAME  = $FUNCTION_APP_NAME.Trim() }
if ($STORAGE_ACCOUNT)    { $STORAGE_ACCOUNT    = $STORAGE_ACCOUNT.Trim() }
if ($SP_CONNECTION_NAME) { $SP_CONNECTION_NAME = $SP_CONNECTION_NAME.Trim() }

Write-Check "Resource Group"         $RESOURCE_GROUP
Write-Check "Logic App"              $(if ($LOGIC_APP_NAME) { $LOGIC_APP_NAME } else { "NOT FOUND" }) -Severity $(if ($LOGIC_APP_NAME) { "INFO" } else { "FAIL" })
Write-Check "Function App"           $(if ($FUNCTION_APP_NAME) { $FUNCTION_APP_NAME } else { "NOT FOUND" }) -Severity $(if ($FUNCTION_APP_NAME) { "INFO" } else { "WARN" })
Write-Check "Storage Account"        $(if ($STORAGE_ACCOUNT) { $STORAGE_ACCOUNT } else { "NOT FOUND" }) -Severity $(if ($STORAGE_ACCOUNT) { "INFO" } else { "FAIL" })
Write-Check "SharePoint Connection"  $(if ($SP_CONNECTION_NAME) { $SP_CONNECTION_NAME } else { "NOT FOUND" }) -Severity $(if ($SP_CONNECTION_NAME) { "INFO" } else { "WARN" })
Write-Check "VNet"                   "$VNET_NAME (in $VNET_RESOURCE_GROUP)"
Write-Check "DNS Zone Subscription"  $(if ($DNS_ZONE_SUBSCRIPTION_ID) { $DNS_ZONE_SUBSCRIPTION_ID } else { "not configured" })
Write-Check "DNS Zone Resource Group" $(if ($DNS_ZONE_RESOURCE_GROUP) { $DNS_ZONE_RESOURCE_GROUP } else { "not configured" })

# Track what we can check downstream
$hasLogicApp = [bool]$LOGIC_APP_NAME
$hasStorage  = [bool]$STORAGE_ACCOUNT

if (-not $hasLogicApp) {
    Add-Issue "CRITICAL" "Could not find Logic App in resource group '$RESOURCE_GROUP'" "Verify the infrastructure was deployed and you have Reader access"
}
if (-not $hasStorage) {
    Add-Issue "CRITICAL" "Could not find Storage Account in resource group '$RESOURCE_GROUP'" "Verify the infrastructure was deployed and you have Reader access"
}

# ============================================================================
# Step 2: Logic App Site Status & Configuration
# ============================================================================

Write-Section "2. LOGIC APP SITE STATUS"

$logicApp = $null
$vnetSubnetId = $null

if ($hasLogicApp) {
    $logicApp = Invoke-AzSafe @('webapp', 'show', '-g', $RESOURCE_GROUP, '-n', $LOGIC_APP_NAME, '-o', 'json')
    if (-not $logicApp) {
        Write-PermissionError "Read Logic App site config" "Reader on '$LOGIC_APP_NAME' (Microsoft.Web/sites/read)"
    } else {
        $siteState          = $logicApp.state
        $siteAvailability   = $logicApp.availabilityState
        $publicAccess       = $logicApp.publicNetworkAccess
        $vnetSubnetId       = $logicApp.virtualNetworkSubnetId
        $vnetRouteAll       = $logicApp.vnetRouteAllEnabled
        $httpsOnly          = $logicApp.httpsOnly
        $kind               = $logicApp.kind
        $defaultHostName    = $logicApp.defaultHostName

        # Site state
        if ($siteState -eq "Running") {
            Write-Check "Site State" $siteState -Severity "PASS"
        } else {
            Write-Check "Site State" $siteState -Severity "FAIL" -Detail "Logic App is not running — runtime cannot process triggers"
            Add-Issue "CRITICAL" "Logic App site state is '$siteState', not 'Running'" "Check App Service Plan health; restart the Logic App"
        }

        # Availability
        if ($siteAvailability -eq "Normal") {
            Write-Check "Availability State" $siteAvailability -Severity "PASS"
        } else {
            Write-Check "Availability State" $siteAvailability -Severity "FAIL" -Detail "Platform reports availability issue"
            Add-Issue "CRITICAL" "Availability state is '$siteAvailability'" "Check platform health in Azure Portal"
        }

        Write-Check "Kind" $kind
        Write-Check "Default Hostname" $defaultHostName
        Write-Check "HTTPS Only" $httpsOnly

        # Public network access
        Write-Check "Public Network Access" $publicAccess -Severity "INFO" `
            -Detail $(if ($publicAccess -eq "Disabled") { "Disabled = inbound only via Private Endpoint" } else { "Public access enabled" })

        # VNet integration
        if ($vnetSubnetId) {
            $subnetName = ($vnetSubnetId -split '/')[-1]
            $vnetNameFromId = ($vnetSubnetId -split '/')[8]
            Write-Check "VNet Integration" "ACTIVE" -Severity "PASS" -Detail "Subnet: $subnetName in VNet: $vnetNameFromId"
            Write-Check "VNet Route All Enabled" $vnetRouteAll -Severity $(if ($vnetRouteAll) { "PASS" } else { "WARN" }) `
                -Detail $(if (-not $vnetRouteAll) { "All outbound traffic should route through VNet when using private endpoints" })
            if (-not $vnetRouteAll) {
                Add-Issue "WARN" "vnetRouteAllEnabled is false" "Set to true so all outbound (including storage, connectors) routes through VNet"
            }
        } else {
            Write-Check "VNet Integration" "NOT CONFIGURED" -Severity "WARN" -Detail "No outbound VNet integration subnet attached"
            Add-Issue "WARN" "Logic App has no VNet integration" "Attach to snet-logic-integration subnet"
        }
    }
} else {
    Write-Host "  (Skipped — Logic App not found)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 3: Logic App App Settings
# ============================================================================

Write-Section "3. LOGIC APP APP SETTINGS"

$settingsMap = @{}

if ($hasLogicApp) {
    $appSettings = Invoke-AzSafe @('webapp', 'config', 'appsettings', 'list', '-g', $RESOURCE_GROUP, '-n', $LOGIC_APP_NAME, '-o', 'json')
    if (-not $appSettings) {
        Write-PermissionError "Read Logic App app settings" "Website Contributor or Reader on '$LOGIC_APP_NAME' (Microsoft.Web/sites/config/list/action)"
    } else {
        foreach ($s in $appSettings) { $settingsMap[$s.name] = $s.value }

        # Critical settings
        $storageAccountSetting    = $settingsMap['AzureWebJobsStorage__accountName']
        $contentOverVnet          = $settingsMap['WEBSITE_CONTENTOVERVNET']
        $functionsRuntime         = $settingsMap['FUNCTIONS_WORKER_RUNTIME']
        $functionsExtVersion      = $settingsMap['FUNCTIONS_EXTENSION_VERSION']
        $extensionBundleId        = $settingsMap['AzureFunctionsJobHost__extensionBundle__id']
        $extensionBundleVersion   = $settingsMap['AzureFunctionsJobHost__extensionBundle__version']
        $appKind                  = $settingsMap['APP_KIND']
        $aiConnectionString       = $settingsMap['APPLICATIONINSIGHTS_CONNECTION_STRING']
        $vnetDnsServer            = $settingsMap['WEBSITE_DNS_SERVER']
        $contentShare             = $settingsMap['WEBSITE_CONTENTSHARE']

        # AzureWebJobsStorage — identity-based vs connection string?
        $storageConnStr = $settingsMap['AzureWebJobsStorage']
        if ($storageAccountSetting) {
            Write-Check "AzureWebJobsStorage__accountName" $storageAccountSetting -Severity "PASS" `
                -Detail "Using identity-based storage (Managed Identity)"
            if ($hasStorage -and $storageAccountSetting -ne $STORAGE_ACCOUNT) {
                Write-Check "Storage Account Mismatch!" "$storageAccountSetting != $STORAGE_ACCOUNT" -Severity "FAIL"
                Add-Issue "CRITICAL" "AzureWebJobsStorage__accountName ($storageAccountSetting) doesn't match deployed storage ($STORAGE_ACCOUNT)"
            }
        } elseif ($storageConnStr) {
            Write-Check "AzureWebJobsStorage" "(connection string set)" -Severity "INFO" -Detail "Using connection string auth, not managed identity"
        } else {
            Write-Check "AzureWebJobsStorage" "MISSING" -Severity "FAIL" -Detail "No storage configuration found — runtime cannot start"
            Add-Issue "CRITICAL" "No AzureWebJobsStorage configured" "Add AzureWebJobsStorage__accountName app setting"
        }

        # WEBSITE_CONTENTOVERVNET
        if ($vnetSubnetId) {
            if ($contentOverVnet -eq "1") {
                Write-Check "WEBSITE_CONTENTOVERVNET" $contentOverVnet -Severity "PASS" `
                    -Detail "File share access routes through VNet"
            } else {
                Write-Check "WEBSITE_CONTENTOVERVNET" $(if ($contentOverVnet) { $contentOverVnet } else { "NOT SET" }) -Severity "FAIL" `
                    -Detail "MUST be '1' when using VNet integration with private storage. Without this, the runtime cannot access its file share."
                Add-Issue "CRITICAL" "WEBSITE_CONTENTOVERVNET is not set to '1'" "az webapp config appsettings set -g $RESOURCE_GROUP -n $LOGIC_APP_NAME --settings WEBSITE_CONTENTOVERVNET=1"
            }
        } else {
            Write-Check "WEBSITE_CONTENTOVERVNET" $(if ($contentOverVnet) { $contentOverVnet } else { "not set" }) -Severity "INFO" `
                -Detail "Not required without VNet integration"
        }

        # WEBSITE_DNS_SERVER
        if ($vnetSubnetId -and $vnetDnsServer) {
            Write-Check "WEBSITE_DNS_SERVER" $vnetDnsServer -Severity "INFO" -Detail "Custom DNS server configured"
        } elseif ($vnetSubnetId -and -not $vnetDnsServer) {
            Write-Check "WEBSITE_DNS_SERVER" "not set (using Azure DNS 168.63.129.16)" -Severity "INFO" `
                -Detail "Azure DNS is fine if Private DNS Zones are linked to the VNet"
        }

        Write-Check "FUNCTIONS_EXTENSION_VERSION" $functionsExtVersion
        Write-Check "FUNCTIONS_WORKER_RUNTIME" $functionsRuntime
        Write-Check "APP_KIND" $appKind -Severity $(if ($appKind -eq "workflowapp") { "PASS" } else { "FAIL" })
        Write-Check "Extension Bundle ID" $extensionBundleId -Severity $(if ($extensionBundleId -eq "Microsoft.Azure.Functions.ExtensionBundle.Workflows") { "PASS" } else { "FAIL" })
        Write-Check "Extension Bundle Version" $extensionBundleVersion
        Write-Check "App Insights" $(if ($aiConnectionString) { "Configured" } else { "NOT SET" }) -Severity $(if ($aiConnectionString) { "PASS" } else { "WARN" })
        Write-Check "WEBSITE_CONTENTSHARE" $(if ($contentShare) { $contentShare } else { "not set (auto-generated)" })
    }
} else {
    Write-Host "  (Skipped — Logic App not found)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 4: Storage Account Network Configuration
# ============================================================================

Write-Section "4. STORAGE ACCOUNT NETWORK CONFIGURATION"

$storageObj = $null
$storageId  = $null

if ($hasStorage) {
    $storageObj = Invoke-AzSafe @('storage', 'account', 'show', '-g', $RESOURCE_GROUP, '-n', $STORAGE_ACCOUNT, '-o', 'json')
    if (-not $storageObj) {
        Write-PermissionError "Read Storage Account config" "Reader on '$STORAGE_ACCOUNT' (Microsoft.Storage/storageAccounts/read)"
    } else {
        $storageId              = $storageObj.id
        $storagePublicAccess    = $storageObj.publicNetworkAccess
        $storageDefaultAction   = $storageObj.networkRuleSet.defaultAction
        $storageVnetRules       = $storageObj.networkRuleSet.virtualNetworkRules
        $storageIpRules         = $storageObj.networkRuleSet.ipRules
        $storageBypass          = $storageObj.networkRuleSet.bypass
        $storagePrimaryBlob     = $storageObj.primaryEndpoints.blob
        $storagePrimaryFile     = $storageObj.primaryEndpoints.file
        $storagePrimaryQueue    = $storageObj.primaryEndpoints.queue
        $storagePrimaryTable    = $storageObj.primaryEndpoints.table

        Write-Check "Public Network Access" $storagePublicAccess
        Write-Check "Network Default Action" $storageDefaultAction -Severity "INFO" `
            -Detail $(if ($storageDefaultAction -eq "Deny") { "Only private endpoint, VNet rules, and bypass traffic allowed" } else { "Open to all networks" })
        Write-Check "Bypass" $storageBypass -Severity "INFO" -Detail "Services that bypass network rules"

        if ($storageVnetRules -and $storageVnetRules.Count -gt 0) {
            Write-Check "VNet Rules" "$($storageVnetRules.Count) rule(s)" -Severity "INFO"
            foreach ($rule in $storageVnetRules) {
                $ruleSubnet = ($rule.virtualNetworkResourceId -split '/')[-1]
                Write-Host "        -> $ruleSubnet (state: $($rule.state))" -ForegroundColor DarkGray
            }
        } else {
            Write-Check "VNet Rules" "None" -Severity "INFO" -Detail "No service endpoint rules configured (relying on private endpoints)"
        }

        if ($storageIpRules -and $storageIpRules.Count -gt 0) {
            Write-Check "IP Rules" "$($storageIpRules.Count) rule(s)" -Severity "INFO"
            foreach ($rule in $storageIpRules) {
                Write-Host "        -> $($rule.ipAddressOrRange)" -ForegroundColor DarkGray
            }
        } else {
            Write-Check "IP Rules" "None" -Severity "INFO"
        }

        Write-Check "Blob Endpoint"  $storagePrimaryBlob
        Write-Check "File Endpoint"  $storagePrimaryFile
        Write-Check "Queue Endpoint" $storagePrimaryQueue
        Write-Check "Table Endpoint" $storagePrimaryTable
    }
} else {
    Write-Host "  (Skipped — Storage Account not found)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 5: Storage Private Endpoints
# ============================================================================

Write-Section "5. STORAGE PRIVATE ENDPOINTS"

$allPEs = $null

if ($hasStorage -and $storageId) {
    $allPEs = Invoke-AzSafe @('network', 'private-endpoint', 'list', '-g', $RESOURCE_GROUP, '-o', 'json')
    if (-not $script:lastAzOk) {
        Write-PermissionError "List Private Endpoints" "Reader on resource group '$RESOURCE_GROUP' (Microsoft.Network/privateEndpoints/read)"
        $allPEs = $null
    } else {
        if (-not $allPEs) { $allPEs = @() }
        $requiredGroups = @("blob", "file", "queue", "table")

        # Filter PEs that target this storage account
        $storagePEs = $allPEs | Where-Object {
            $_.privateLinkServiceConnections | Where-Object { $_.privateLinkServiceId -eq $storageId }
        }

        $foundGroups = @()
        foreach ($pe in $storagePEs) {
            foreach ($conn in $pe.privateLinkServiceConnections) {
                if ($conn.privateLinkServiceId -eq $storageId) {
                    foreach ($gid in $conn.groupIds) {
                        $foundGroups += $gid
                        $peStatus = $conn.privateLinkServiceConnectionState.status
                        Write-Check "PE: $($pe.name)" "group=$gid, status=$peStatus" `
                            -Severity $(if ($peStatus -eq "Approved") { "PASS" } else { "FAIL" }) `
                            -Detail "Subnet: $(($pe.subnet.id -split '/')[-1])"
                        if ($peStatus -ne "Approved") {
                            Add-Issue "CRITICAL" "Private endpoint $($pe.name) ($gid) status is '$peStatus', not 'Approved'"
                        }
                    }
                }
            }
        }

        foreach ($required in $requiredGroups) {
            if ($required -notin $foundGroups) {
                Write-Check "PE: $required" "MISSING" -Severity "FAIL" `
                    -Detail "No private endpoint found for storage $required service"
                Add-Issue "CRITICAL" "Missing private endpoint for storage '$required'" "Logic App runtime needs blob, file, queue, and table private endpoints"
            }
        }
    }
} else {
    Write-Host "  (Skipped — Storage Account details not available)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 6: Logic App & Function App Private Endpoints
# ============================================================================

Write-Section "6. APP PRIVATE ENDPOINTS"

if ($allPEs -eq $null -and $hasLogicApp) {
    # Try loading PEs if Step 5 was skipped
    $allPEs = Invoke-AzSafe @('network', 'private-endpoint', 'list', '-g', $RESOURCE_GROUP, '-o', 'json')
    if (-not $script:lastAzOk) {
        Write-PermissionError "List Private Endpoints" "Reader on resource group '$RESOURCE_GROUP' (Microsoft.Network/privateEndpoints/read)"
        $allPEs = $null
    }
}

if ($allPEs -ne $null) {
    if ($logicApp) {
        $logicAppId = $logicApp.id
        $logicPEs = $allPEs | Where-Object {
            $_.privateLinkServiceConnections | Where-Object { $_.privateLinkServiceId -eq $logicAppId }
        }
        if ($logicPEs) {
            foreach ($pe in $logicPEs) {
                $conn = $pe.privateLinkServiceConnections | Where-Object { $_.privateLinkServiceId -eq $logicAppId } | Select-Object -First 1
                Write-Check "Logic App PE: $($pe.name)" "status=$($conn.privateLinkServiceConnectionState.status)" `
                    -Severity $(if ($conn.privateLinkServiceConnectionState.status -eq "Approved") { "PASS" } else { "FAIL" })
            }
        } else {
            Write-Check "Logic App PE" "NONE FOUND" -Severity "WARN" -Detail "No private endpoint for inbound access to Logic App"
        }
    }

    if ($FUNCTION_APP_NAME) {
        $funcApp = Invoke-AzSafe @('webapp', 'show', '-g', $RESOURCE_GROUP, '-n', $FUNCTION_APP_NAME, '-o', 'json')
        if (-not $funcApp) {
            Write-PermissionError "Read Function App details" "Reader on '$FUNCTION_APP_NAME' (Microsoft.Web/sites/read)"
        } else {
            $funcPEs = $allPEs | Where-Object {
                $_.privateLinkServiceConnections | Where-Object { $_.privateLinkServiceId -eq $funcApp.id }
            }
            if ($funcPEs) {
                foreach ($pe in $funcPEs) {
                    $conn = $pe.privateLinkServiceConnections | Where-Object { $_.privateLinkServiceId -eq $funcApp.id } | Select-Object -First 1
                    Write-Check "Function App PE: $($pe.name)" "status=$($conn.privateLinkServiceConnectionState.status)" `
                        -Severity $(if ($conn.privateLinkServiceConnectionState.status -eq "Approved") { "PASS" } else { "FAIL" })
                }
            } else {
                Write-Check "Function App PE" "NONE FOUND" -Severity "WARN"
            }
        }
    }
} else {
    Write-Host "  (Skipped — could not list private endpoints)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 7: Private DNS Zone Links
# ============================================================================

Write-Section "7. PRIVATE DNS ZONE LINKS (cross-subscription)"

$dnsZones = @(
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.azurewebsites.net"
)

# We need the VNet resource ID to check links
$vnetId = ""
if ($VNET_RESOURCE_GROUP -and $VNET_NAME) {
    $vnetObj = Invoke-AzSafe @('network', 'vnet', 'show', '-g', $VNET_RESOURCE_GROUP, '-n', $VNET_NAME, '-o', 'json')
    if ($vnetObj) {
        $vnetId = $vnetObj.id
        Write-Check "VNet Resource ID" $vnetId
    } else {
        Write-PermissionError "Read VNet '$VNET_NAME' in '$VNET_RESOURCE_GROUP'" "Reader on VNet resource group '$VNET_RESOURCE_GROUP' (Microsoft.Network/virtualNetworks/read)"
    }
}

if ($DNS_ZONE_SUBSCRIPTION_ID -and $DNS_ZONE_RESOURCE_GROUP) {
    Write-Host ""
    Write-Host "  Checking DNS zones in subscription $DNS_ZONE_SUBSCRIPTION_ID / RG $DNS_ZONE_RESOURCE_GROUP" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($zone in $dnsZones) {
        # List VNet links for this zone
        $linksRaw = az network private-dns link vnet list `
            --subscription $DNS_ZONE_SUBSCRIPTION_ID `
            -g $DNS_ZONE_RESOURCE_GROUP `
            -z $zone -o json 2>$null
        $linksExitCode = $LASTEXITCODE

        if ($linksExitCode -ne 0 -or -not $linksRaw) {
            # Distinguish between "zone not found" and "no permission"
            $errOutput = az network private-dns zone show `
                --subscription $DNS_ZONE_SUBSCRIPTION_ID `
                -g $DNS_ZONE_RESOURCE_GROUP `
                -n $zone -o json 2>&1
            $zoneExitCode = $LASTEXITCODE

            if ($zoneExitCode -ne 0) {
                $errString = ($errOutput | Out-String)
                if ($errString -match "AuthorizationFailed|does not have authorization|Forbidden|authorization") {
                    Write-PermissionError "Read DNS Zone '$zone'" "Reader on subscription '$DNS_ZONE_SUBSCRIPTION_ID' (Microsoft.Network/privateDnsZones/read, Microsoft.Network/privateDnsZones/virtualNetworkLinks/read)"
                } else {
                    Write-Check "DNS Zone: $zone" "NOT FOUND" -Severity "FAIL" `
                        -Detail "Zone does not exist in $DNS_ZONE_RESOURCE_GROUP"
                    Add-Issue "CRITICAL" "Private DNS Zone '$zone' not found in $DNS_ZONE_RESOURCE_GROUP" "The DNS team must create this zone"
                }
            } else {
                Write-PermissionError "List VNet links on '$zone'" "Reader on DNS Zone (Microsoft.Network/privateDnsZones/virtualNetworkLinks/read)"
            }
            continue
        }

        $links = $linksRaw | ConvertFrom-Json
        if (-not $links -or $links.Count -eq 0) {
            Write-Check "DNS Zone: $zone" "NO VNET LINKS" -Severity "FAIL" `
                -Detail "Zone exists but has no VNet links at all"
            Add-Issue "CRITICAL" "DNS Zone '$zone' has no VNet links" "The other team must create a VNet link to $VNET_NAME"
            continue
        }

        # Check if our VNet is linked
        $ourLink = $null
        if ($vnetId) {
            $ourLink = $links | Where-Object { $_.virtualNetwork.id -eq $vnetId }
        }

        $linkNames = ($links | ForEach-Object { "$($_.name) -> $(($_.virtualNetwork.id -split '/')[-1])" }) -join "; "

        if ($ourLink) {
            $regEnabled = $ourLink.registrationEnabled
            Write-Check "DNS Zone: $zone" "LINKED to $VNET_NAME (registration=$regEnabled)" -Severity "PASS"
        } elseif (-not $vnetId) {
            Write-Check "DNS Zone: $zone" "EXISTS (could not verify VNet link — VNet lookup failed)" -Severity "WARN" `
                -Detail "Existing links: $linkNames"
        } else {
            Write-Check "DNS Zone: $zone" "NOT LINKED to $VNET_NAME" -Severity "FAIL" `
                -Detail "Existing links: $linkNames"
            Add-Issue "CRITICAL" "DNS Zone '$zone' is not linked to VNet '$VNET_NAME'" "Request the DNS team to add a VNet link for $VNET_NAME to this zone"
        }
    }
} else {
    Write-Check "DNS Zone Check" "SKIPPED" -Severity "WARN" `
        -Detail "DNS_ZONE_SUBSCRIPTION_ID or DNS_ZONE_RESOURCE_GROUP not set in deploy.config.ps1"
    Add-Issue "WARN" "Cannot check DNS zone links — config values missing" "Fill in DNS_ZONE_SUBSCRIPTION_ID and DNS_ZONE_RESOURCE_GROUP in deploy.config.ps1"
}

# ============================================================================
# Step 8: Storage RBAC for Logic App
# ============================================================================

Write-Section "8. STORAGE RBAC FOR LOGIC APP"

if ($logicApp -and $storageId) {
    $logicAppPrincipalId = $logicApp.identity.principalId
    Write-Check "Logic App Managed Identity" $(if ($logicAppPrincipalId) { $logicAppPrincipalId } else { "NOT ENABLED" })

    if ($logicAppPrincipalId) {
        $roles = Invoke-AzSafe @('role', 'assignment', 'list', '--assignee', $logicAppPrincipalId, '--scope', $storageId, '-o', 'json')
        if (-not $script:lastAzOk) {
            Write-PermissionError "List RBAC role assignments" "Reader + Microsoft.Authorization/roleAssignments/read on storage account scope"
        } else {
            if (-not $roles) { $roles = @() }

            # Required roles
            $requiredRoles = @{
                "b7e6dc6d-f1e8-4753-8033-0f276bb0955b" = "Storage Blob Data Owner"
                "974c5e8b-45b9-4653-ba55-5f855dd0fb88" = "Storage Queue Data Contributor"
                "0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3" = "Storage Table Data Contributor"
                "0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb" = "Storage File Data SMB Share Contributor"
            }

            foreach ($roleId in $requiredRoles.Keys) {
                $roleName = $requiredRoles[$roleId]
                $match = $roles | Where-Object { $_.roleDefinitionId -like "*$roleId*" -or $_.roleDefinitionName -eq $roleName }
                if ($match) {
                    Write-Check $roleName "Assigned" -Severity "PASS"
                } else {
                    Write-Check $roleName "MISSING" -Severity "FAIL" `
                        -Detail "Logic App MSI needs this role on $STORAGE_ACCOUNT"
                    Add-Issue "CRITICAL" "Logic App missing '$roleName' on storage account" "az role assignment create --assignee $logicAppPrincipalId --role '$roleId' --scope $storageId"
                }
            }
        }
    } else {
        Add-Issue "CRITICAL" "Logic App has no managed identity" "Enable System-Assigned Managed Identity"
    }
} else {
    if (-not $logicApp) {
        Write-Host "  (Skipped — Logic App details not available)" -ForegroundColor DarkGray
    } elseif (-not $storageId) {
        Write-Host "  (Skipped — Storage Account details not available)" -ForegroundColor DarkGray
    }
}

# ============================================================================
# Step 9: SharePoint API Connection Status
# ============================================================================

Write-Section "9. SHAREPOINT API CONNECTION"

if ($SP_CONNECTION_NAME) {
    $spConn = Invoke-AzSafe @('resource', 'show', '-g', $RESOURCE_GROUP, '--resource-type', 'Microsoft.Web/connections', '-n', $SP_CONNECTION_NAME, '-o', 'json')
    if (-not $spConn) {
        Write-PermissionError "Read SharePoint connection '$SP_CONNECTION_NAME'" "Reader on resource group '$RESOURCE_GROUP' (Microsoft.Web/connections/read)"
    } else {
        $connStatus     = $spConn.properties.statuses
        $connRuntimeUrl = $spConn.properties.connectionRuntimeUrl
        $connApiId      = $spConn.properties.api.id

        Write-Check "Connection Name" $SP_CONNECTION_NAME
        Write-Check "API" $connApiId
        Write-Check "Runtime URL" $(if ($connRuntimeUrl) { $connRuntimeUrl } else { "NOT SET" }) `
            -Severity $(if ($connRuntimeUrl) { "PASS" } else { "FAIL" })

        if ($connStatus) {
            foreach ($s in $connStatus) {
                Write-Check "Status" "$($s.status)" -Severity $(if ($s.status -eq "Connected") { "PASS" } else { "WARN" }) `
                    -Detail $(if ($s.error) { $s.error.message } else { "" })
            }
        }

        if (-not $connRuntimeUrl) {
            Add-Issue "CRITICAL" "SharePoint connection has no runtimeUrl" "Re-authorize: Portal -> API Connections -> $SP_CONNECTION_NAME -> Edit -> Authorize"
        }

        # Check access policy
        Write-Host ""
        Write-Host "  Checking access policies..." -ForegroundColor DarkGray
        $accessPolicies = Invoke-AzSafe @('resource', 'list', '-g', $RESOURCE_GROUP, '--resource-type', 'Microsoft.Web/connections/accessPolicies', '-o', 'json')
        if (-not $script:lastAzOk) {
            Write-PermissionError "List connection access policies" "Reader on resource group (Microsoft.Web/connections/accessPolicies/read)"
        } else {
            if (-not $accessPolicies) { $accessPolicies = @() }
            $relevantPolicies = $accessPolicies | Where-Object { $_.name -like "$SP_CONNECTION_NAME*" }
            if ($relevantPolicies) {
                Write-Check "Access Policies" "$($relevantPolicies.Count) found" -Severity "PASS"
                foreach ($ap in $relevantPolicies) {
                    Write-Host "        -> $($ap.name)" -ForegroundColor DarkGray
                }
            } else {
                Write-Check "Access Policies" "NONE for this connection" -Severity "FAIL" `
                    -Detail "Logic App MSI won't be able to invoke the connection"
                Add-Issue "CRITICAL" "No access policy linking Logic App MSI to SharePoint connection" "Re-deploy Bicep or manually create access policy"
            }
        }
    }
} else {
    Write-Check "SharePoint Connection" "NOT DISCOVERED" -Severity "WARN" `
        -Detail "Could not identify the SharePoint API connection resource"
}

# ============================================================================
# Step 10: Logic App Workflows
# ============================================================================

Write-Section "10. LOGIC APP WORKFLOWS"

if ($hasLogicApp) {
    $subscriptionId = (az account show --query id -o tsv 2>$null)
    if ($subscriptionId) { $subscriptionId = $subscriptionId.Trim() }

    $workflowsUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$LOGIC_APP_NAME/workflows?api-version=2018-11-01"
    $workflowsRaw = az rest --method GET --uri $workflowsUri -o json 2>$null
    $wfExitCode = $LASTEXITCODE

    if ($wfExitCode -ne 0 -or -not $workflowsRaw) {
        Write-PermissionError "List Logic App workflows" "Logic App Contributor or Reader on '$LOGIC_APP_NAME' (Microsoft.Web/sites/hostruntime/webhooks/workflow/read)"
    } else {
        $workflows = ($workflowsRaw | ConvertFrom-Json).value
        if ($workflows -and $workflows.Count -gt 0) {
            Write-Check "Workflows Found" "$($workflows.Count)" -Severity "PASS"
            foreach ($wf in $workflows) {
                $wfName = ($wf.name -split '/')[-1]
                $wfState = $wf.properties.state
                Write-Check "  Workflow: $wfName" "state=$wfState" `
                    -Severity $(if ($wfState -eq "Enabled") { "PASS" } else { "FAIL" })
                if ($wfState -ne "Enabled") {
                    Add-Issue "CRITICAL" "Workflow '$wfName' is '$wfState', not 'Enabled'" "Enable via Portal -> Logic App -> Workflows -> $wfName -> Enable"
                }
            }
        } else {
            Write-Check "Workflows" "NONE FOUND" -Severity "FAIL" -Detail "No workflows deployed — trigger has nothing to run"
            Add-Issue "CRITICAL" "No workflows exist on the Logic App" "Run logicAppWorkflow.ps1 to deploy the workflow"
        }
    }
} else {
    Write-Host "  (Skipped — Logic App not found)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 11: Subnet NSG & Route Table Check
# ============================================================================

Write-Section "11. SUBNET NETWORK SECURITY (NSG / Route Table)"

if ($vnetSubnetId) {
    $subnet = Invoke-AzSafe @('network', 'vnet', 'subnet', 'show', '--ids', $vnetSubnetId, '-o', 'json')
    if (-not $subnet) {
        Write-PermissionError "Read subnet '$($vnetSubnetId -split '/' | Select-Object -Last 1)'" "Reader on VNet resource group (Microsoft.Network/virtualNetworks/subnets/read)"
    } else {
        $nsgId = $subnet.networkSecurityGroup.id
        $routeTableId = $subnet.routeTable.id
        $delegations = $subnet.delegations

        Write-Check "Subnet" ($vnetSubnetId -split '/')[-1]
        Write-Check "Address Prefix" $subnet.addressPrefix

        if ($delegations) {
            foreach ($d in $delegations) {
                Write-Check "Delegation" $d.properties.serviceName -Severity "PASS"
            }
        }

        # NSG
        if ($nsgId) {
            $nsgName = ($nsgId -split '/')[-1]
            Write-Check "NSG" $nsgName -Severity "INFO"

            $nsg = Invoke-AzSafe @('network', 'nsg', 'show', '--ids', $nsgId, '-o', 'json')
            if (-not $nsg) {
                Write-PermissionError "Read NSG rules for '$nsgName'" "Reader on NSG (Microsoft.Network/networkSecurityGroups/read)"
            } else {
                $outboundRules = ($nsg.securityRules + $nsg.defaultSecurityRules) | Where-Object { $_.properties.direction -eq "Outbound" } | Sort-Object { [int]$_.properties.priority }

                Write-Host ""
                Write-Host "  Outbound rules (affects connector + storage traffic):" -ForegroundColor DarkGray
                foreach ($rule in $outboundRules) {
                    $p = $rule.properties
                    $icon = if ($p.access -eq "Allow") { "  [ALLOW]" } else { "  [DENY] " }
                    $color = if ($p.access -eq "Allow") { "Green" } else { "Red" }
                    Write-Host "    $icon " -ForegroundColor $color -NoNewline
                    Write-Host "Priority=$($p.priority) Dest=$($p.destinationAddressPrefix) Port=$($p.destinationPortRange) Proto=$($p.protocol) Name=$($rule.name)" -ForegroundColor DarkGray
                }

                # Check for blanket deny before allow-internet
                $denyAll = $outboundRules | Where-Object {
                    $_.properties.access -eq "Deny" -and
                    $_.properties.destinationAddressPrefix -in @("*", "0.0.0.0/0", "Internet") -and
                    $_.properties.destinationPortRange -in @("*", "443")
                } | Select-Object -First 1

                if ($denyAll) {
                    $denyPriority = [int]$denyAll.properties.priority
                    # Is there an allow for 443 outbound before the deny?
                    $allowHttps = $outboundRules | Where-Object {
                        $_.properties.access -eq "Allow" -and
                        [int]$_.properties.priority -lt $denyPriority -and
                        ($_.properties.destinationPortRange -in @("*", "443") -or $_.properties.destinationPortRanges -contains "443")
                    }
                    if (-not $allowHttps) {
                        Add-Issue "CRITICAL" "NSG '$nsgName' denies outbound 443 with no prior allow rule" "Logic App needs outbound HTTPS to *.azureconnectors.com, *.logic.azure.com, *.sharepoint.com, login.microsoftonline.com"
                    }
                }
            }
        } else {
            Write-Check "NSG" "None attached" -Severity "PASS" -Detail "No NSG restricting outbound traffic"
        }

        # Route Table
        if ($routeTableId) {
            $rtName = ($routeTableId -split '/')[-1]
            Write-Check "Route Table" $rtName -Severity "WARN" `
                -Detail "UDR detected — verify default route allows internet-bound traffic (SharePoint connector endpoints)"

            $rt = Invoke-AzSafe @('network', 'route-table', 'show', '--ids', $routeTableId, '-o', 'json')
            if (-not $rt) {
                Write-PermissionError "Read Route Table '$rtName'" "Reader on route table (Microsoft.Network/routeTables/read)"
            } else {
                foreach ($route in $rt.routes) {
                    $rp = $route.properties
                    Write-Host "        -> $($route.name): $($rp.addressPrefix) nextHop=$($rp.nextHopType) $($rp.nextHopIpAddress)" -ForegroundColor DarkGray
                }
                $defaultRoute = $rt.routes | Where-Object { $_.properties.addressPrefix -eq "0.0.0.0/0" }
                if ($defaultRoute -and $defaultRoute.properties.nextHopType -ne "Internet") {
                    Add-Issue "WARN" "Default route (0.0.0.0/0) goes to $($defaultRoute.properties.nextHopType) $($defaultRoute.properties.nextHopIpAddress)" "Verify the NVA/firewall allows outbound HTTPS to Azure connector endpoints"
                }
            }
        } else {
            Write-Check "Route Table" "None attached" -Severity "PASS" -Detail "Default Azure routing — internet-bound traffic goes direct"
        }
    }
} else {
    Write-Host "  (Skipped — no VNet integration configured)" -ForegroundColor DarkGray
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Magenta
Write-Host "  DIAGNOSTIC SUMMARY" -ForegroundColor Magenta
Write-Host ("=" * 70) -ForegroundColor Magenta
Write-Host ""

$criticals   = $issues | Where-Object { $_.Severity -eq "CRITICAL" }
$warnings    = $issues | Where-Object { $_.Severity -eq "WARN" }
$permissions = $issues | Where-Object { $_.Severity -eq "PERMISSION" }

if ($criticals.Count -eq 0 -and $warnings.Count -eq 0 -and $permissions.Count -eq 0) {
    Write-Host "  No issues detected. If trigger still isn't firing:" -ForegroundColor Green
    Write-Host "    - Check Logic App Log Stream (Portal -> Logic App -> Log stream) for runtime errors" -ForegroundColor Gray
    Write-Host "    - Check Application Insights for exceptions" -ForegroundColor Gray
    Write-Host "    - Upload a test file to SharePoint and wait 2+ minutes for the polling trigger" -ForegroundColor Gray
} else {
    if ($criticals.Count -gt 0) {
        Write-Host "  CRITICAL ISSUES ($($criticals.Count)):" -ForegroundColor Red
        $i = 1
        foreach ($c in $criticals) {
            Write-Host "    $i. $($c.Message)" -ForegroundColor Red
            if ($c.Fix) { Write-Host "       Fix: $($c.Fix)" -ForegroundColor Yellow }
            $i++
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
        $i = 1
        foreach ($w in $warnings) {
            Write-Host "    $i. $($w.Message)" -ForegroundColor Yellow
            if ($w.Fix) { Write-Host "       Fix: $($w.Fix)" -ForegroundColor DarkGray }
            $i++
        }
    }

    if ($permissions.Count -gt 0) {
        Write-Host ""
        Write-Host "  SKIPPED DUE TO PERMISSIONS ($($permissions.Count)):" -ForegroundColor DarkYellow
        Write-Host "  The following checks could not run. Re-run with sufficient access." -ForegroundColor DarkGray
        $i = 1
        foreach ($p in $permissions) {
            Write-Host "    $i. $($p.Message)" -ForegroundColor DarkYellow
            Write-Host "       $($p.Fix)" -ForegroundColor DarkGray
            $i++
        }
    }
}

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Magenta
