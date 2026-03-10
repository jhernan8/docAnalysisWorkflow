# ============================================================================
# Contract Analysis Solution - Logic App Workflow Deployment Script
#
# Builds and deploys the Logic App Standard workflow that triggers on new
# SharePoint files and calls the Function App for document analysis.
#
# Prerequisites:
#   - az CLI logged in to the correct subscription
#   - deploy.ps1 has been run (infrastructure exists)
#   - functionAppDeploy.ps1 has been run (Function App code published)
#   - SharePoint connection authorized in Azure Portal
#
# Usage:
#   .\logicAppDesign.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "========================================" -ForegroundColor Green
Write-Host "Logic App Workflow Deployment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Load configuration from deploy.config.ps1
$configPath = Join-Path $PSScriptRoot "deploy.config.ps1"
if (-not (Test-Path $configPath)) {
    throw "Configuration file not found: $configPath"
}
Write-Host "Loading configuration from deploy.config.ps1..." -ForegroundColor Yellow
. $configPath

# ============================================================================
# Step 1: Discover resources
# ============================================================================
Write-Host "`nStep 1: Discovering resources..." -ForegroundColor Yellow

$resourcePrefix = "$BASE_NAME-$ENVIRONMENT"

# Function App
$FUNCTION_APP_NAME = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.functionAppName.value" -o tsv 2>$null)
if ($FUNCTION_APP_NAME) { $FUNCTION_APP_NAME = $FUNCTION_APP_NAME.Trim() }
if (-not $FUNCTION_APP_NAME) {
    $FUNCTION_APP_NAME = "$((az functionapp list -g $RESOURCE_GROUP --query "[?starts_with(name,'$resourcePrefix-func')].name | [0]" -o tsv))".Trim()
}
if (-not $FUNCTION_APP_NAME) {
    throw "Could not find Function App in resource group '$RESOURCE_GROUP'. Run deploy.ps1 first."
}

# Logic App
$LOGIC_APP_NAME = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.logicAppName.value" -o tsv 2>$null)
if ($LOGIC_APP_NAME) { $LOGIC_APP_NAME = $LOGIC_APP_NAME.Trim() }
if (-not $LOGIC_APP_NAME) {
    $LOGIC_APP_NAME = "$((az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/sites' --query "[?kind=='functionapp,linux,workflowapp'].name | [0]" -o tsv))".Trim()
}
if (-not $LOGIC_APP_NAME) {
    throw "Could not find Logic App in resource group '$RESOURCE_GROUP'. Run deploy.ps1 first."
}

# SharePoint Connection
$SHAREPOINT_CONNECTION = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.sharePointConnectionName.value" -o tsv 2>$null)
if ($SHAREPOINT_CONNECTION) { $SHAREPOINT_CONNECTION = $SHAREPOINT_CONNECTION.Trim() }
if (-not $SHAREPOINT_CONNECTION) {
    $SHAREPOINT_CONNECTION = "$((az resource list -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' --query "[?starts_with(name,'$resourcePrefix')].name | [0]" -o tsv))".Trim()
}

Write-Host "  Function App:          $FUNCTION_APP_NAME" -ForegroundColor Gray
Write-Host "  Logic App:             $LOGIC_APP_NAME" -ForegroundColor Gray
Write-Host "  SharePoint Connection: $SHAREPOINT_CONNECTION" -ForegroundColor Gray

# ============================================================================
# Step 2: Retrieve Function App key
# ============================================================================
Write-Host "`nStep 2: Retrieving Function App key..." -ForegroundColor Yellow

# Try with current access first
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$FUNCTION_KEY = (az functionapp keys list -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --query "functionKeys.default" -o tsv 2>$null)
$funcKeyExitCode = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

if ($funcKeyExitCode -ne 0 -or -not $FUNCTION_KEY) {
    Write-Host "  Could not retrieve key (public access may be disabled). Temporarily enabling..." -ForegroundColor Yellow
    az functionapp update -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --set publicNetworkAccess=Enabled --output none 2>$null
    Start-Sleep -Seconds 5
    $FUNCTION_KEY = (az functionapp keys list -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --query "functionKeys.default" -o tsv 2>$null)
    az functionapp update -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --set publicNetworkAccess=Disabled --output none 2>$null
    Write-Host "  Public access re-disabled." -ForegroundColor Gray
}

if ($FUNCTION_KEY) {
    $FUNCTION_KEY = $FUNCTION_KEY.Trim()
    Write-Host "  [OK] Function key retrieved" -ForegroundColor Green
} else {
    throw "Could not retrieve Function App key. Ensure functionAppDeploy.ps1 has been run first."
}

# ============================================================================
# Step 3: Gather SharePoint connection details
# ============================================================================
Write-Host "`nStep 3: Gathering connection details..." -ForegroundColor Yellow

$SP_CONNECTION_RUNTIME_URL = "$((az resource show -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' -n $SHAREPOINT_CONNECTION --query 'properties.connectionRuntimeUrl' -o tsv))".Trim()
$SP_CONNECTION_ID = "$((az resource show -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' -n $SHAREPOINT_CONNECTION --query id -o tsv))".Trim()
$MANAGED_API_ID = "$((az resource show -g $RESOURCE_GROUP --resource-type 'Microsoft.Web/connections' -n $SHAREPOINT_CONNECTION --query 'properties.api.id' -o tsv))".Trim()

$FUNC_HOSTNAME = "$((az functionapp show -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --query 'defaultHostName' -o tsv))".Trim()

# SharePoint config from deploy.config.ps1
if ([string]::IsNullOrEmpty($SHAREPOINT_SITE_URL)) {
    $SHAREPOINT_SITE_URL = Read-Host 'Enter SharePoint site URL [e.g. https://contoso.sharepoint.com/sites/ContractAI]'
}
if ([string]::IsNullOrEmpty($SHAREPOINT_LIBRARY_ID)) {
    $SHAREPOINT_LIBRARY_ID = Read-Host "Enter SharePoint document library ID (GUID)"
}

Write-Host "  Function hostname: $FUNC_HOSTNAME" -ForegroundColor Gray
Write-Host "  SP Connection ID:  $SP_CONNECTION_ID" -ForegroundColor Gray

# ============================================================================
# Step 4: Build and deploy Logic App workflow
# ============================================================================
Write-Host "`nStep 4: Deploying Logic App workflow..." -ForegroundColor Yellow

$WORKFLOW_DIR = Join-Path $env:TEMP "logic-app-workflow-$PID"
$WORKFLOW_TRIGGER_DIR = Join-Path $WORKFLOW_DIR "contract-trigger"
New-Item -ItemType Directory -Path $WORKFLOW_TRIGGER_DIR -Force | Out-Null

# Create connections.json
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

# Create workflow.json
$spTriggerPath = '/datasets/@{encodeURIComponent(encodeURIComponent(''__SP_SITE_URL__''))}/tables/@{encodeURIComponent(encodeURIComponent(''__SP_LIBRARY_ID__''))}/onnewfileitems'
$spTriggerPath = $spTriggerPath -replace '__SP_SITE_URL__', $SHAREPOINT_SITE_URL
$spTriggerPath = $spTriggerPath -replace '__SP_LIBRARY_ID__', $SHAREPOINT_LIBRARY_ID
$spGetFilePath = '/datasets/@{encodeURIComponent(encodeURIComponent(''__SP_SITE_URL__''))}/files/@{encodeURIComponent(triggerBody()?[''{Identifier}''])}/content'
$spGetFilePath = $spGetFilePath -replace '__SP_SITE_URL__', $SHAREPOINT_SITE_URL
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

# Zip and deploy
$zipPath = Join-Path $env:TEMP "logic-workflow-$PID.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $WORKFLOW_DIR "*") -DestinationPath $zipPath -Force

az logicapp deployment source config-zip -g $RESOURCE_GROUP -n $LOGIC_APP_NAME --src $zipPath --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to deploy Logic App workflow" }

# Cleanup temp files
Remove-Item -Path $WORKFLOW_DIR -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

Write-Host "[OK] Logic App workflow deployed" -ForegroundColor Green

# ============================================================================
# Done
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Logic App Workflow Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Remaining Manual Steps:" -ForegroundColor Yellow
Write-Host "  1. Authorize SharePoint Connection (if not already done):"
Write-Host "     Portal -> Resource Group -> API Connections -> $SHAREPOINT_CONNECTION"
Write-Host "     -> Edit API connection -> Authorize -> Sign in -> Save"
Write-Host ""
Write-Host "  2. Test by uploading a PDF to your SharePoint document library"
Write-Host ""
