# ============================================================================
# Contract Analysis Solution - Infrastructure Deployment Script (Private Endpoints)
# PowerShell version for Windows
#
# This script deploys the Azure infrastructure (Step 1: Resource Group, Step 2: Bicep).
# After this script completes, run functionAppDeploy.ps1 to deploy the Function App
# code and Logic App workflow.
#
# Usage:
#   .\deploy.ps1                  # Run all steps (1-2)
#   .\deploy.ps1 -StartFromStep 2 # Skip Step 1, start from Step 2
# ============================================================================
param(
    [ValidateRange(1,2)]
    [int]$StartFromStep = 1
)

$ErrorActionPreference = "Stop"
# Prevent PowerShell from treating az CLI stderr output as terminating errors
$PSNativeCommandUseErrorActionPreference = $false
# Skip Bicep version check (avoids SSL errors on corporate networks with proxy/firewall)
$env:AZURE_BICEP_CHECK_VERSION = "false"

# Use a locally-installed Bicep CLI to avoid SSL/download issues on corporate networks.
# Checks both common install locations: az bicep install and winget/standalone installer.
$bicepPaths = @(
    (Join-Path $env:USERPROFILE ".azure\bin\bicep.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Bicep CLI\bicep.exe")
)
$localBicep = $bicepPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($localBicep) {
    $env:AZURE_BICEP_PATH = $localBicep
    Write-Host "Using local Bicep: $localBicep" -ForegroundColor Cyan
} else {
    Write-Host "Local Bicep not found - installing via az bicep install..." -ForegroundColor Yellow
    az bicep install
    $localBicep = $bicepPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($localBicep) {
        $env:AZURE_BICEP_PATH = $localBicep
        Write-Host "Bicep installed and configured: $localBicep" -ForegroundColor Cyan
    } else {
        Write-Host "WARNING: Could not locate Bicep after install. Falling back to az CLI built-in." -ForegroundColor Red
    }
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "Contract Analysis Solution Deployment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Load configuration from deploy.config.ps1
$configPath = Join-Path $PSScriptRoot "deploy.config.ps1"
if (-not (Test-Path $configPath)) {
    throw "Configuration file not found: $configPath`nCopy deploy.config.ps1.template or create deploy.config.ps1 with your settings."
}
Write-Host "Loading configuration from deploy.config.ps1..." -ForegroundColor Yellow
. $configPath

# Prompt only for values not hardcoded above
Write-Host "`nAzure AD Configuration (for SQL Azure AD-only auth):" -ForegroundColor Yellow
if ([string]::IsNullOrEmpty($AAD_OBJECT_ID)) {
    $AAD_OBJECT_ID = Read-Host "Enter your Azure AD Object ID (run 'az ad signed-in-user show --query id -o tsv')"
}
if ([string]::IsNullOrEmpty($AAD_DISPLAY_NAME)) {
    $AAD_DISPLAY_NAME = Read-Host "Enter your Azure AD display name (email)"
}

Write-Host "`nSharePoint Configuration:" -ForegroundColor Yellow
if ([string]::IsNullOrEmpty($SHAREPOINT_SITE_URL)) {
    $SHAREPOINT_SITE_URL = Read-Host 'Enter SharePoint site URL [e.g. https://contoso.sharepoint.com/sites/ContractAI]'
}
if ([string]::IsNullOrEmpty($SHAREPOINT_LIBRARY_ID)) {
    $SHAREPOINT_LIBRARY_ID = Read-Host "Enter SharePoint document library ID (GUID)"
}

Write-Host "`nNetworking Configuration:" -ForegroundColor Yellow
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
# Step 1: Create resource group
# ============================================================================
if ($StartFromStep -le 1) {
    Write-Host "`nStep 1: Creating resource group..." -ForegroundColor Yellow
    $rgArgs = @(
        'group', 'create',
        '--name', $RESOURCE_GROUP,
        '--location', $LOCATION,
        '--output', 'none'
    )
    az @rgArgs

    if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }
    Write-Host "[OK] Resource group created" -ForegroundColor Green
} else {
    Write-Host "`nStep 1: SKIPPED (resource group)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 2: Deploy Bicep template
# ============================================================================
if ($StartFromStep -le 2) {
    Write-Host "`nStep 2: Deploying Bicep template..." -ForegroundColor Yellow

    # Pre-compile Bicep to ARM JSON locally so az deployment never invokes Bicep itself
    # (avoids any network calls for Bicep version checks or downloads)
    $armTemplatePath = Join-Path $PSScriptRoot "main.json"
    if ($env:AZURE_BICEP_PATH) {
        Write-Host "  Pre-compiling main.bicep to ARM JSON using local Bicep..." -ForegroundColor Gray
        & $env:AZURE_BICEP_PATH build (Join-Path $PSScriptRoot "main.bicep") --outfile $armTemplatePath
        if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed" }
        $templateFile = $armTemplatePath
        Write-Host "  Compiled to: $armTemplatePath" -ForegroundColor Gray
    } else {
        $templateFile = 'main.bicep'
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
    Write-Host "  Running: az $($deployArgs -join ' ')" -ForegroundColor Gray
    az @deployArgs
    $deployExitCode = $LASTEXITCODE

    if ($deployExitCode -ne 0) {
        Write-Host "  Bicep deployment returned exit code: $deployExitCode" -ForegroundColor Red
        Write-Host "  Listing deployments in resource group..." -ForegroundColor Red
        az deployment group list -g $RESOURCE_GROUP --query '[].{name:name, state:properties.provisioningState}' -o table
        throw "Failed to deploy Bicep template - exit code: $deployExitCode"
    }
    Write-Host "[OK] Infrastructure deployed" -ForegroundColor Green

    # Clean up compiled ARM template
    if (Test-Path $armTemplatePath) { Remove-Item $armTemplatePath -Force -ErrorAction SilentlyContinue }
} else {
    Write-Host "`nStep 2: SKIPPED (Bicep deployment)" -ForegroundColor DarkGray
}

# Extract outputs from existing deployment (needed regardless of skip)
Write-Host "  Extracting deployment outputs..." -ForegroundColor Yellow
$deploymentJson = az deployment group show -g $RESOURCE_GROUP -n main -o json 2>&1
if ($LASTEXITCODE -eq 0) {
    $deployment = $deploymentJson | ConvertFrom-Json
    $FUNCTION_APP_NAME = $deployment.properties.outputs.functionAppName.value
    $SQL_SERVER = $deployment.properties.outputs.sqlServerFqdn.value
    $SQL_DATABASE = $deployment.properties.outputs.sqlDatabaseName.value
    $STORAGE_ACCOUNT = $deployment.properties.outputs.storageAccountName.value
    $LOGIC_APP_NAME = $deployment.properties.outputs.logicAppName.value
    $SHAREPOINT_CONNECTION = $deployment.properties.outputs.sharePointConnectionName.value
}

# If deployment outputs are empty (e.g. last deploy failed), discover resources directly
if (-not $FUNCTION_APP_NAME) {
    Write-Host "  Deployment outputs empty (prior deploy may have failed). Discovering resources directly..." -ForegroundColor Yellow
    $uniqueSuffix = (az group show -n $RESOURCE_GROUP --query "id" -o tsv | ForEach-Object {
        # Replicate Bicep's uniqueString(resourceGroup().id) — not possible exactly,
        # so we look up resources by naming convention instead.
    })

    # Query by resource type and naming pattern from config
    $resourcePrefix = "$BASE_NAME-$ENVIRONMENT"
    $FUNCTION_APP_NAME = "$((az functionapp list -g $RESOURCE_GROUP --query "[?starts_with(name,'$resourcePrefix-func')].name | [0]" -o tsv))".Trim()
    $STORAGE_ACCOUNT = "$((az storage account list -g $RESOURCE_GROUP --query "[?starts_with(name,'$($BASE_NAME)$($ENVIRONMENT)')].name | [0]" -o tsv))".Trim()
    $sqlServerName = "$((az sql server list -g $RESOURCE_GROUP --query "[?starts_with(name,'$resourcePrefix-sql')].name | [0]" -o tsv))".Trim()
    $SQL_SERVER = if ($sqlServerName) { "$sqlServerName.database.windows.net" } else { "" }
    $SQL_DATABASE = "contractsdb"
    $LOGIC_APP_NAME = "$((az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/sites' --query "[?kind=='functionapp,linux,workflowapp'].name | [0]" -o tsv))".Trim()
    $SHAREPOINT_CONNECTION = "$((az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' --query "[?starts_with(name,'$resourcePrefix')].name | [0]" -o tsv))".Trim()
}

if (-not $FUNCTION_APP_NAME) {
    throw "Could not find Function App in resource group '$RESOURCE_GROUP'. Ensure Step 2 completed at least once successfully."
}
Write-Host "  Function App: $FUNCTION_APP_NAME" -ForegroundColor Gray
Write-Host "  Storage:      $STORAGE_ACCOUNT" -ForegroundColor Gray

# NOTE: SharePoint Online connector does not support managed identity authentication.
# The connection uses OAuth and must be authorized manually in Azure Portal after deployment.
# See 'Remaining Manual Steps' -> 'Authorize SharePoint Connection' at the end of this script.

# ============================================================================
# Infrastructure Deployment Complete
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Infrastructure Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nResource Details:" -ForegroundColor Yellow
Write-Host "  Function App:           $FUNCTION_APP_NAME"
Write-Host "  Logic App:              $LOGIC_APP_NAME"
Write-Host "  SharePoint Connection:  $SHAREPOINT_CONNECTION"
Write-Host "  SQL Server:             $SQL_SERVER"
Write-Host "  SQL Database:           $SQL_DATABASE"
Write-Host "  Storage:                $STORAGE_ACCOUNT"
Write-Host "  VNet:                   $VNET_NAME (in $VNET_RESOURCE_GROUP)"

Write-Host "`nPrivate Endpoints Created:" -ForegroundColor Yellow
Write-Host '  - Storage (blob, file, queue, table)'
Write-Host '  - Azure SQL Server'
Write-Host '  - Function App (inbound)'
Write-Host '  - Logic App Standard (inbound)'

Write-Host "`nNext Steps (run in order):" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Step A: .\functionAppDeploy.ps1   (publish Function App code)" -ForegroundColor Cyan
Write-Host "  Step B: .\logicAppDesign.ps1      (deploy Logic App workflow)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Remaining Manual Steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Run SQL setup scripts (connect via Private Endpoint or from within VNet):"
Write-Host "   a. Connect to: $SQL_SERVER / $SQL_DATABASE"
Write-Host "   b. Run create_tables.sql to create the schema"
Write-Host '   c. Run this SQL to grant Function App access:'
Write-Host ('      CREATE USER [{0}] FROM EXTERNAL PROVIDER;' -f $FUNCTION_APP_NAME)
Write-Host ('      ALTER ROLE db_datareader ADD MEMBER [{0}];' -f $FUNCTION_APP_NAME)
Write-Host ('      ALTER ROLE db_datawriter ADD MEMBER [{0}];' -f $FUNCTION_APP_NAME)
Write-Host ""
Write-Host "2. Create Azure AI Foundry resource and Content Understanding analyzer"
Write-Host "   a. Go to: Azure Portal -> Create Resource -> Azure AI Foundry"
Write-Host "   b. Create in the SAME resource group: $RESOURCE_GROUP"
Write-Host "   c. In the project, go to Content Understanding -> Create Analyzer"
Write-Host "   d. Note the Project Endpoint and Analyzer ID"
Write-Host "   e. Update Function App settings:"
Write-Host ('      az functionapp config appsettings set -g {0} -n {1} `' -f $RESOURCE_GROUP, $FUNCTION_APP_NAME)
Write-Host '        --settings CONTENT_UNDERSTANDING_ENDPOINT=<your-foundry-endpoint> `'
Write-Host '        CONTENT_UNDERSTANDING_ANALYZER_ID=<your-analyzer-id>'
Write-Host ""
Write-Host "3. Verify DNS Zone VNet Links"
Write-Host "   Ensure all Private DNS Zones in subscription '$DNS_ZONE_SUBSCRIPTION_ID'"
Write-Host "   resource group '$DNS_ZONE_RESOURCE_GROUP' have VNet links to '$VNET_NAME'"
Write-Host "   Required zones:"
Write-Host "     - privatelink.blob.core.windows.net"
Write-Host "     - privatelink.file.core.windows.net"
Write-Host "     - privatelink.queue.core.windows.net"
Write-Host "     - privatelink.table.core.windows.net"
Write-Host "     - privatelink.database.windows.net"
Write-Host "     - privatelink.azurewebsites.net"
Write-Host ""
Write-Host "4. Authorize SharePoint Connection"
Write-Host "   - Go to: Azure Portal -> Resource Group -> API Connections -> $SHAREPOINT_CONNECTION"
Write-Host "   - Click 'Edit API connection' -> 'Authorize' -> Sign in"
Write-Host "   - Click 'Save'"
Write-Host ""
Write-Host "5. Test the solution"
Write-Host "   - Upload a PDF contract to your SharePoint document library"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Infrastructure is ready!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
