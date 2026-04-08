# ============================================================================
# Logic App Standard - Clean Redeploy Script
#
# Safely deletes the Logic App, its App Service Plan, and the SharePoint
# API connection, then re-runs the Bicep deployment to recreate them
# with correct settings (WEBSITE_CONTENTOVERVNET, vnetRouteAllEnabled).
#
# WHAT THIS DELETES:
#   - Logic App Standard
#   - Its App Service Plan (WS1)
#   - SharePoint API Connection + access policies
#
# WHAT THIS DOES NOT TOUCH:
#   - Private Endpoints (contracts-dev-pe-logic stays, auto-reconnects)
#   - Private DNS Zones / VNet links
#   - Storage Account
#   - Function App
#   - SQL Database
#   - RBAC role assignments (idempotent — Bicep re-applies them)
#
# Usage:
#   .\redeploy-logicapp.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Logic App Safe Delete for Redeploy" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

# Load configuration
$configPath = Join-Path $PSScriptRoot "deploy.config.ps1"
if (-not (Test-Path $configPath)) {
    throw "Configuration file not found: $configPath"
}
Write-Host "`nLoading deploy.config.ps1..." -ForegroundColor Yellow
. $configPath

if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    throw "RESOURCE_GROUP is empty in deploy.config.ps1"
}

$resourcePrefix = "$BASE_NAME-$ENVIRONMENT"

# ============================================================================
# Step 1: Discover current resources
# ============================================================================
Write-Host "`n[Step 1] Discovering current resources..." -ForegroundColor Yellow

$LOGIC_APP_NAME = (az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/sites' --query "[?kind=='functionapp,linux,workflowapp'].name | [0]" -o tsv 2>$null)
if ($LOGIC_APP_NAME) { $LOGIC_APP_NAME = $LOGIC_APP_NAME.Trim() }

$SP_CONNECTION_NAME = (az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' --query "[?starts_with(name,'$resourcePrefix')].name | [0]" -o tsv 2>$null)
if ($SP_CONNECTION_NAME) { $SP_CONNECTION_NAME = $SP_CONNECTION_NAME.Trim() }

# Derive the ASP name
$ASP_NAME = if ($LOGIC_APP_NAME) { "$LOGIC_APP_NAME-asp" } else { "$resourcePrefix-logic-asp" }

Write-Host "  Logic App:             $(if ($LOGIC_APP_NAME) { $LOGIC_APP_NAME } else { 'NOT FOUND (nothing to delete)' })"
Write-Host "  App Service Plan:      $ASP_NAME"
Write-Host "  SharePoint Connection: $(if ($SP_CONNECTION_NAME) { $SP_CONNECTION_NAME } else { 'NOT FOUND' })"

# ============================================================================
# Step 2: Verify PE will survive
# ============================================================================
Write-Host "`n[Step 2] Checking Private Endpoint for Logic App..." -ForegroundColor Yellow

$peName = "$resourcePrefix-pe-logic"
$peCheck = az network private-endpoint show -g $RESOURCE_GROUP -n $peName -o json 2>$null
if ($LASTEXITCODE -eq 0 -and $peCheck) {
    Write-Host "  [OK] PE '$peName' exists - will auto-reconnect after redeploy" -ForegroundColor Green
} else {
    Write-Host "  [INFO] PE '$peName' not found - Bicep will create it" -ForegroundColor DarkGray
}

# ============================================================================
# Step 3: Confirm and delete
# ============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Red
Write-Host "  THIS WILL DELETE THE FOLLOWING RESOURCES:" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
if ($LOGIC_APP_NAME) {
    Write-Host "    - Logic App:             $LOGIC_APP_NAME" -ForegroundColor Red
}
Write-Host "    - App Service Plan:      $ASP_NAME" -ForegroundColor Red
if ($SP_CONNECTION_NAME) {
    Write-Host "    - SharePoint Connection: $SP_CONNECTION_NAME" -ForegroundColor Red
}
Write-Host ""
Write-Host "  NOT deleted: Private Endpoints, DNS Zones, Storage," -ForegroundColor Green
Write-Host "               Function App, SQL, RBAC, VNet/Subnets" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Type 'yes' to proceed"
if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[Step 3] Deleting resources..." -ForegroundColor Yellow

# Delete SharePoint connection first (it has access policies referencing the Logic App)
if ($SP_CONNECTION_NAME) {
    Write-Host "  Deleting SharePoint connection '$SP_CONNECTION_NAME'..." -ForegroundColor Gray
    az resource delete -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' -n $SP_CONNECTION_NAME --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] SharePoint connection deleted" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Could not delete SharePoint connection (may not exist)" -ForegroundColor Yellow
    }
}

# Delete Logic App (with retry for ARM throttling / 429)
if ($LOGIC_APP_NAME) {
    Write-Host "  Deleting Logic App '$LOGIC_APP_NAME'..." -ForegroundColor Gray
    $maxRetries = 5
    $retryDelay = 30
    $deleted = $false
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        az webapp delete -g $RESOURCE_GROUP -n $LOGIC_APP_NAME --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $deleted = $true
            break
        }
        if ($attempt -lt $maxRetries) {
            Write-Host "  [RETRY] Attempt $attempt failed (likely 429 throttle). Waiting ${retryDelay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelay
            $retryDelay = [math]::Min($retryDelay * 2, 120)
        }
    }
    if ($deleted) {
        Write-Host "  [OK] Logic App deleted" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Could not delete Logic App after $maxRetries attempts" -ForegroundColor Yellow
    }
}

# Delete App Service Plan
Write-Host "  Deleting App Service Plan '$ASP_NAME'..." -ForegroundColor Gray
az appservice plan delete -g $RESOURCE_GROUP -n $ASP_NAME --yes --output none 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] App Service Plan deleted" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Could not delete ASP (may not exist or still has apps)" -ForegroundColor Yellow
}

# Brief pause — let ARM settle
Write-Host "  Waiting 15 seconds for ARM to process deletions..." -ForegroundColor Gray
Start-Sleep -Seconds 15

# ============================================================================
# Step 4: Prompt for deployment parameters
# ============================================================================
Write-Host "`n[Step 4] Gathering deployment parameters..." -ForegroundColor Yellow

if ([string]::IsNullOrEmpty($AAD_OBJECT_ID)) {
    $AAD_OBJECT_ID = Read-Host "Enter your Azure AD Object ID (run 'az ad signed-in-user show --query id -o tsv')"
}
if ([string]::IsNullOrEmpty($AAD_DISPLAY_NAME)) {
    $AAD_DISPLAY_NAME = Read-Host "Enter your Azure AD display name (email)"
}
if ([string]::IsNullOrEmpty($SHAREPOINT_SITE_URL)) {
    $SHAREPOINT_SITE_URL = Read-Host 'Enter SharePoint site URL [e.g. https://contoso.sharepoint.com/sites/ContractAI]'
}
if ([string]::IsNullOrEmpty($SHAREPOINT_LIBRARY_ID)) {
    $SHAREPOINT_LIBRARY_ID = Read-Host "Enter SharePoint document library ID (GUID)"
}
if ([string]::IsNullOrEmpty($VNET_RESOURCE_GROUP)) {
    $VNET_RESOURCE_GROUP = Read-Host "Enter the VNet resource group name"
}
if ([string]::IsNullOrEmpty($PE_SUBNET_PREFIX)) {
    $PE_SUBNET_PREFIX = Read-Host 'Enter private endpoint subnet CIDR [e.g. 10.0.4.0/24]'
}
if ([string]::IsNullOrEmpty($FUNC_SUBNET_PREFIX)) {
    $FUNC_SUBNET_PREFIX = Read-Host 'Enter Function App VNet integration subnet CIDR [e.g. 10.0.5.0/24]'
}
if ([string]::IsNullOrEmpty($LOGIC_SUBNET_PREFIX)) {
    $LOGIC_SUBNET_PREFIX = Read-Host 'Enter Logic App VNet integration subnet CIDR [e.g. 10.0.6.0/24]'
}
if ([string]::IsNullOrEmpty($DNS_ZONE_SUBSCRIPTION_ID)) {
    $DNS_ZONE_SUBSCRIPTION_ID = Read-Host "Enter DNS Zone subscription ID"
}
if ([string]::IsNullOrEmpty($DNS_ZONE_RESOURCE_GROUP)) {
    $DNS_ZONE_RESOURCE_GROUP = Read-Host "Enter DNS Zone resource group name"
}

# ============================================================================
# Step 5: Re-deploy Bicep
# ============================================================================
Write-Host "`n[Step 5] Re-deploying Bicep template..." -ForegroundColor Yellow

$env:AZURE_BICEP_CHECK_VERSION = "false"

# Local Bicep setup (same as deployInfraRBAC.ps1)
$bicepPaths = @(
    (Join-Path $env:USERPROFILE ".azure\bin\bicep.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Bicep CLI\bicep.exe")
)
$localBicep = $bicepPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

$templateFile = Join-Path $PSScriptRoot "main.bicep"
$armTemplatePath = Join-Path $PSScriptRoot "main.json"

if ($localBicep) {
    $env:AZURE_BICEP_PATH = $localBicep
    Write-Host "  Pre-compiling main.bicep with local Bicep..." -ForegroundColor Gray
    & $localBicep build $templateFile --outfile $armTemplatePath
    if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed" }
    $templateFile = $armTemplatePath
    Write-Host "  Compiled to: $armTemplatePath" -ForegroundColor Gray
} else {
    Write-Host "  Using az CLI built-in Bicep" -ForegroundColor Gray
}

$deployArgs = @(
    'deployment', 'group', 'create',
    '--resource-group', $RESOURCE_GROUP,
    '--name', 'main',
    '--template-file', $templateFile,
    '--parameters',
    "baseName=$BASE_NAME",
    "location=$LOCATION",
    "sqlLocation=$SQL_LOCATION",
    "environment=$ENVIRONMENT",
    "sqlAadAdminObjectId=$AAD_OBJECT_ID",
    "sqlAadAdminDisplayName=$AAD_DISPLAY_NAME",
    "sharePointSiteUrl=$SHAREPOINT_SITE_URL",
    "sharePointLibraryId=$SHAREPOINT_LIBRARY_ID",
    "vnetName=$VNET_NAME",
    "vnetResourceGroupName=$VNET_RESOURCE_GROUP",
    "privateEndpointSubnetAddressPrefix=$PE_SUBNET_PREFIX",
    "vnetIntegrationSubnetAddressPrefix=$FUNC_SUBNET_PREFIX",
    "logicAppSubnetAddressPrefix=$LOGIC_SUBNET_PREFIX",
    "dnsZoneSubscriptionId=$DNS_ZONE_SUBSCRIPTION_ID",
    "dnsZoneResourceGroupName=$DNS_ZONE_RESOURCE_GROUP",
    '--output', 'none'
)

Write-Host "  Running Bicep deployment..." -ForegroundColor Gray
az @deployArgs
$deployExitCode = $LASTEXITCODE

# Clean up compiled template
if (Test-Path $armTemplatePath) { Remove-Item $armTemplatePath -Force -ErrorAction SilentlyContinue }

if ($deployExitCode -ne 0) {
    Write-Host "  [FAIL] Bicep deployment failed (exit code: $deployExitCode)" -ForegroundColor Red
    Write-Host "  Run 'az deployment group list -g $RESOURCE_GROUP' for details." -ForegroundColor Red
    throw "Bicep deployment failed"
}

Write-Host "  [OK] Bicep deployment succeeded" -ForegroundColor Green

# ============================================================================
# Step 6: Verify recreation
# ============================================================================
Write-Host "`n[Step 6] Verifying resources..." -ForegroundColor Yellow

$newLogicApp = az webapp show -g $RESOURCE_GROUP -n "$resourcePrefix-logic" -o json 2>$null
if ($LASTEXITCODE -eq 0 -and $newLogicApp) {
    $la = $newLogicApp | ConvertFrom-Json
    Write-Host "  [OK] Logic App: $($la.name) (state=$($la.state))" -ForegroundColor Green

    # Check critical app settings
    $appSettings = az webapp config appsettings list -g $RESOURCE_GROUP -n $la.name -o json 2>$null | ConvertFrom-Json
    $covn = ($appSettings | Where-Object { $_.name -eq 'WEBSITE_CONTENTOVERVNET' }).value
    if ($covn -eq '1') {
        Write-Host "  [OK] WEBSITE_CONTENTOVERVNET = 1" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] WEBSITE_CONTENTOVERVNET = $covn (expected '1')" -ForegroundColor Yellow
    }

    if ($la.vnetRouteAllEnabled) {
        Write-Host "  [OK] vnetRouteAllEnabled = true" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] vnetRouteAllEnabled = false" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [FAIL] Logic App was not recreated" -ForegroundColor Red
}

# Check PE reconnection
$peCheck2 = az network private-endpoint show -g $RESOURCE_GROUP -n $peName -o json 2>$null
if ($LASTEXITCODE -eq 0 -and $peCheck2) {
    $peObj = $peCheck2 | ConvertFrom-Json
    $connStatus = $peObj.privateLinkServiceConnections[0].privateLinkServiceConnectionState.status
    $connColor = if ($connStatus -eq 'Approved') { 'Green' } else { 'Yellow' }
    Write-Host "  [OK] PE '$peName' status: $connStatus" -ForegroundColor $connColor
} else {
    Write-Host "  [WARN] Could not verify PE status" -ForegroundColor Yellow
}

# ============================================================================
# Done — remaining manual steps
# ============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Redeploy Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "REMAINING STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. AUTHORIZE SharePoint Connection:" -ForegroundColor Cyan
Write-Host "     Portal -> API Connections -> $resourcePrefix-logic-sharepoint-connection" -ForegroundColor Gray
Write-Host "     -> Edit API Connection -> Authorize -> Sign in -> Save" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. DEPLOY WORKFLOW:" -ForegroundColor Cyan
Write-Host "     .\logicAppWorkflow.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  3. VERIFY:" -ForegroundColor Cyan
Write-Host "     .\diagnose-logicapp.ps1" -ForegroundColor White
Write-Host "     (should show 0 critical issues)" -ForegroundColor Gray
Write-Host ""
