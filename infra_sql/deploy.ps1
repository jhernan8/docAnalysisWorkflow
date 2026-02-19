# ============================================================================
# Contract Analysis Solution - Deployment Script (v2 - Private Endpoints)
# PowerShell version for Windows
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Green
Write-Host "Contract Analysis Solution Deployment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Configuration - CUSTOMIZE THESE
$RESOURCE_GROUP = "contract-analysis-rg"
$LOCATION = "eastus"        # Primary location for Function App, Storage, AI Services
$SQL_LOCATION = "centralus" # SQL location (some regions have restrictions)
$BASE_NAME = "contracts"
$ENVIRONMENT = "dev"

# Networking Configuration
$VNET_NAME = "cai-a1-tst-vnet-spoke01"
$VNET_RESOURCE_GROUP = ""          # Resource group of the existing VNet
$PE_SUBNET_PREFIX = ""             # e.g., "10.0.4.0/24"
$FUNC_SUBNET_PREFIX = ""          # e.g., "10.0.5.0/24"
$LOGIC_SUBNET_PREFIX = ""         # e.g., "10.0.6.0/24"
$DNS_ZONE_SUBSCRIPTION_ID = ""    # Subscription ID where Private DNS Zones live
$DNS_ZONE_RESOURCE_GROUP = ""     # Resource group containing Private DNS Zones

# Azure AD Configuration - FILL THESE IN to skip prompts
$AAD_OBJECT_ID = ""          # Your Azure AD Object ID (run: az ad signed-in-user show --query id -o tsv)
$AAD_DISPLAY_NAME = ""       # Your Azure AD display name / email / UPN

# SharePoint Configuration - FILL THESE IN to skip prompts
$SHAREPOINT_SITE_URL = ""    # e.g., "https://contoso.sharepoint.com/sites/ContractAI"
$SHAREPOINT_LIBRARY_ID = ""  # e.g., "0c082b7c-8834-480c-8b30-47ba73e8562c"

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
    $SHAREPOINT_SITE_URL = Read-Host "Enter SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/ContractAI)"
}
if ([string]::IsNullOrEmpty($SHAREPOINT_LIBRARY_ID)) {
    $SHAREPOINT_LIBRARY_ID = Read-Host "Enter SharePoint document library ID (GUID)"
}

Write-Host "`nNetworking Configuration:" -ForegroundColor Yellow
if ([string]::IsNullOrEmpty($VNET_RESOURCE_GROUP)) {
    $VNET_RESOURCE_GROUP = Read-Host "Enter the VNet resource group name"
}
if ([string]::IsNullOrEmpty($PE_SUBNET_PREFIX)) {
    $PE_SUBNET_PREFIX = Read-Host "Enter private endpoint subnet CIDR (e.g., 10.0.4.0/24)"
}
if ([string]::IsNullOrEmpty($FUNC_SUBNET_PREFIX)) {
    $FUNC_SUBNET_PREFIX = Read-Host "Enter Function App VNet integration subnet CIDR (e.g., 10.0.5.0/24)"
}
if ([string]::IsNullOrEmpty($LOGIC_SUBNET_PREFIX)) {
    $LOGIC_SUBNET_PREFIX = Read-Host "Enter Logic App VNet integration subnet CIDR (e.g., 10.0.6.0/24)"
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
Write-Host "`nStep 1: Creating resource group..." -ForegroundColor Yellow
$rgArgs = @(
    'group', 'create',
    '--name', $RESOURCE_GROUP,
    '--location', $LOCATION,
    '--output', 'none'
)
az @rgArgs

if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }
Write-Host "✓ Resource group created" -ForegroundColor Green

# ============================================================================
# Step 2: Deploy Bicep template
# ============================================================================
Write-Host "`nStep 2: Deploying Bicep template..." -ForegroundColor Yellow
$deployArgs = @(
    'deployment', 'group', 'create',
    '--resource-group', $RESOURCE_GROUP,
    '--name', 'main',
    '--template-file', 'main.bicep',
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

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Bicep deployment returned exit code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "  Listing deployments in resource group..." -ForegroundColor Red
    az deployment group list -g $RESOURCE_GROUP --query '[].{name:name, state:properties.provisioningState}' -o table
    throw "Failed to deploy Bicep template (exit code $LASTEXITCODE)"
}
Write-Host "✓ Infrastructure deployed" -ForegroundColor Green

# Extract outputs
Write-Host "  Extracting deployment outputs..." -ForegroundColor Yellow
$deploymentJson = az deployment group show -g $RESOURCE_GROUP -n main -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Could not find deployment 'main'. Listing all deployments:" -ForegroundColor Red
    az deployment group list -g $RESOURCE_GROUP --query '[].{name:name, state:properties.provisioningState}' -o table
    throw "Deployment 'main' not found. Check the table above for the actual deployment name/state."
}

$deployment = $deploymentJson | ConvertFrom-Json
$FUNCTION_APP_NAME = $deployment.properties.outputs.functionAppName.value
$SQL_SERVER = $deployment.properties.outputs.sqlServerFqdn.value
$SQL_DATABASE = $deployment.properties.outputs.sqlDatabaseName.value
$STORAGE_ACCOUNT = $deployment.properties.outputs.storageAccountName.value

if (-not $FUNCTION_APP_NAME) {
    throw "Deployment outputs are empty - the Bicep deployment may have failed. Check Azure Portal -> Resource Group -> Deployments."
}
Write-Host "  Function App: $FUNCTION_APP_NAME" -ForegroundColor Gray
Write-Host "  Storage:      $STORAGE_ACCOUNT" -ForegroundColor Gray

# ============================================================================
# Step 3: Deploy Function App code
# ============================================================================
Write-Host "`nStep 3: Deploying Function App code..." -ForegroundColor Yellow
Write-Host "  Temporarily enabling storage public access for deployment..." -ForegroundColor Yellow
$storageEnableArgs = @(
    'storage', 'account', 'update',
    '-g', $RESOURCE_GROUP,
    '-n', $STORAGE_ACCOUNT,
    '--public-network-access', 'Enabled',
    '--output', 'none'
)
az @storageEnableArgs

if ($LASTEXITCODE -ne 0) { throw "Failed to enable storage public access" }

# Allow a moment for the change to propagate
Start-Sleep -Seconds 10

Push-Location ..\azure_function_sql
func azure functionapp publish $FUNCTION_APP_NAME --python
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Failed to publish Function App"
}
Pop-Location

Write-Host "  Re-disabling storage public access..." -ForegroundColor Yellow
$storageDisableArgs = @(
    'storage', 'account', 'update',
    '-g', $RESOURCE_GROUP,
    '-n', $STORAGE_ACCOUNT,
    '--public-network-access', 'Disabled',
    '--output', 'none'
)
az @storageDisableArgs

if ($LASTEXITCODE -ne 0) { throw "Failed to disable storage public access" }
Write-Host "✓ Function code deployed (storage re-secured)" -ForegroundColor Green

# Extract Logic App name for final output
$LOGIC_APP_NAME = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.logicAppName.value" -o tsv).Trim()
$SHAREPOINT_CONNECTION = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.sharePointConnectionName.value" -o tsv).Trim()

# ============================================================================
# Step 4: Deploy Logic App Standard workflow
# ============================================================================
Write-Host "`nStep 4: Deploying Logic App Standard workflow..." -ForegroundColor Yellow

# Get Function key for the Logic App workflow to call Function App
$FUNCTION_KEY = (az functionapp keys list -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --query "functionKeys.default" -o tsv).Trim()

# Get SharePoint connection details
$SUBSCRIPTION_ID = (az account show --query id -o tsv).Trim()
$SP_CONNECTION_RUNTIME_URL = (az resource show -g $RESOURCE_GROUP --resource-type "Microsoft.Web/connections" -n $SHAREPOINT_CONNECTION --query "properties.connectionRuntimeUrl" -o tsv).Trim()
$SP_CONNECTION_ID = (az resource show -g $RESOURCE_GROUP --resource-type "Microsoft.Web/connections" -n $SHAREPOINT_CONNECTION --query id -o tsv).Trim()
$MANAGED_API_ID = (az resource show -g $RESOURCE_GROUP --resource-type "Microsoft.Web/connections" -n $SHAREPOINT_CONNECTION --query "properties.api.id" -o tsv).Trim()

# Create workflow directory structure
$WORKFLOW_DIR = Join-Path $env:TEMP "logic-app-workflow-$PID"
$WORKFLOW_TRIGGER_DIR = Join-Path $WORKFLOW_DIR "contract-trigger"
New-Item -ItemType Directory -Path $WORKFLOW_TRIGGER_DIR -Force | Out-Null

# Get app settings values
$FUNC_HOSTNAME = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.functionAppUrl.value" -o tsv).Trim() -replace '^https://', ''
$SP_SITE_URL = $SHAREPOINT_SITE_URL
$SP_LIBRARY_ID = $SHAREPOINT_LIBRARY_ID

# Create connections.json using PowerShell objects (avoids here-string parsing issues)
$connectionsObj = [ordered]@{
    managedApiConnections = [ordered]@{
        sharepointonline = [ordered]@{
            api = [ordered]@{ id = $MANAGED_API_ID }
            connection = [ordered]@{ id = $SP_CONNECTION_ID }
            connectionRuntimeUrl = $SP_CONNECTION_RUNTIME_URL
            authentication = [ordered]@{ type = "ManagedServiceIdentity" }
        }
    }
}
$connectionsObj | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $WORKFLOW_DIR "connections.json") -Encoding UTF8

# Create workflow.json using PowerShell objects
$spTriggerPath = '/datasets/@{encodeURIComponent(encodeURIComponent(''__SP_SITE_URL__''))}/tables/@{encodeURIComponent(encodeURIComponent(''__SP_LIBRARY_ID__''))}/onnewfileitems'
$spTriggerPath = $spTriggerPath -replace '__SP_SITE_URL__', $SP_SITE_URL
$spTriggerPath = $spTriggerPath -replace '__SP_LIBRARY_ID__', $SP_LIBRARY_ID
$spGetFilePath = '/datasets/@{encodeURIComponent(encodeURIComponent(''__SP_SITE_URL__''))}/files/@{encodeURIComponent(triggerBody()?[''{Identifier}''])}/content'
$spGetFilePath = $spGetFilePath -replace '__SP_SITE_URL__', $SP_SITE_URL
$funcUri = 'https://' + $FUNC_HOSTNAME + '/api/analyze-and-store'

$workflowObj = [ordered]@{
    definition = [ordered]@{
        '$schema' = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion = "1.0.0.0"
        parameters = [ordered]@{
            '$connections' = [ordered]@{
                defaultValue = @{}
                type = "Object"
            }
        }
        triggers = [ordered]@{
            When_a_file_is_created_properties_only = [ordered]@{
                type = "ApiConnection"
                inputs = [ordered]@{
                    host = [ordered]@{
                        connection = [ordered]@{ referenceName = "sharepointonline" }
                    }
                    method = "get"
                    path = $spTriggerPath
                }
                recurrence = [ordered]@{
                    frequency = "Minute"
                    interval = 1
                }
                splitOn = '@triggerBody()?[''value'']'
            }
        }
        actions = [ordered]@{
            Get_file_content = [ordered]@{
                type = "ApiConnection"
                inputs = [ordered]@{
                    host = [ordered]@{
                        connection = [ordered]@{ referenceName = "sharepointonline" }
                    }
                    method = "get"
                    path = $spGetFilePath
                    queries = [ordered]@{ inferContentType = $true }
                }
                runAfter = @{}
            }
            Call_Function_App = [ordered]@{
                type = "Http"
                inputs = [ordered]@{
                    method = "POST"
                    uri = $funcUri
                    headers = [ordered]@{ "x-functions-key" = $FUNCTION_KEY }
                    body = [ordered]@{
                        filename = '@{triggerBody()?[''{Name}'']}'
                        content = '@{base64(body(''Get_file_content''))}'
                    }
                }
                runAfter = [ordered]@{
                    Get_file_content = @("Succeeded")
                }
                runtimeConfiguration = [ordered]@{
                    contentTransfer = [ordered]@{ transferMode = "Chunked" }
                }
            }
        }
        outputs = @{}
    }
    kind = "Stateful"
}
$workflowObj | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $WORKFLOW_TRIGGER_DIR "workflow.json") -Encoding UTF8

# Zip and deploy the workflow
$zipPath = Join-Path $env:TEMP "logic-workflow-$PID.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $WORKFLOW_DIR "*") -DestinationPath $zipPath -Force

$logicDeployArgs = @(
    'logicapp', 'deployment', 'source', 'config-zip',
    '-g', $RESOURCE_GROUP,
    '-n', $LOGIC_APP_NAME,
    '--src', $zipPath,
    '--output', 'none'
)
az @logicDeployArgs

if ($LASTEXITCODE -ne 0) { throw "Failed to deploy Logic App workflow" }

# Cleanup temp files
Remove-Item -Path $WORKFLOW_DIR -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

Write-Host "✓ Logic App workflow deployed" -ForegroundColor Green

# ============================================================================
# Deployment Complete
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
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

Write-Host "`nRemaining Manual Steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Run SQL setup scripts (connect via Private Endpoint or from within VNet):"
Write-Host "   a. Connect to: $SQL_SERVER / $SQL_DATABASE"
Write-Host "   b. Run create_tables.sql to create the schema"
Write-Host '   c. Run this SQL to grant Function App access:'
Write-Host "      CREATE USER [`$FUNCTION_APP_NAME] FROM EXTERNAL PROVIDER;"
Write-Host "      ALTER ROLE db_datareader ADD MEMBER [`$FUNCTION_APP_NAME];"
Write-Host "      ALTER ROLE db_datawriter ADD MEMBER [`$FUNCTION_APP_NAME];"
Write-Host ""
Write-Host "2. Create Azure AI Foundry resource and Content Understanding analyzer"
Write-Host "   a. Go to: Azure Portal -> Create Resource -> Azure AI Foundry"
Write-Host "   b. Create in the SAME resource group: $RESOURCE_GROUP"
Write-Host "   c. In the project, go to Content Understanding -> Create Analyzer"
Write-Host "   d. Note the Project Endpoint and Analyzer ID"
Write-Host "   e. Update Function App settings:"
Write-Host "      az functionapp config appsettings set -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME ``"
Write-Host "        --settings CONTENT_UNDERSTANDING_ENDPOINT=<your-foundry-endpoint> ``"
Write-Host "        CONTENT_UNDERSTANDING_ANALYZER_ID=<your-analyzer-id>"
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
Write-Host "All infrastructure is ready!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
