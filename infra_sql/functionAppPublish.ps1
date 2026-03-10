# ============================================================================
# Contract Analysis Solution - Function App Publish Script
#
# Publishes Function App code to Azure. Run this AFTER deploy.ps1 has
# completed infrastructure deployment.
#
# Prerequisites:
#   - Azure Functions Core Tools (func) installed
#     Install: winget install Microsoft.Azure.FunctionsCoreTools
#   - az CLI logged in to the correct subscription
#   - deploy.ps1 has been run successfully (infrastructure exists)
#
# After this script, run logicAppDesign.ps1 to deploy the Logic App workflow.
#
# Usage:
#   .\functionAppDeploy.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "========================================" -ForegroundColor Green
Write-Host "Function App Publish" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Load configuration from deploy.config.ps1
$configPath = Join-Path $PSScriptRoot "deploy.config.ps1"
if (-not (Test-Path $configPath)) {
    throw "Configuration file not found: $configPath"
}
Write-Host "Loading configuration from deploy.config.ps1..." -ForegroundColor Yellow
. $configPath

# Verify func CLI is available
if (-not (Get-Command func -ErrorAction SilentlyContinue)) {
    throw "Azure Functions Core Tools (func) not found. Install with: winget install Microsoft.Azure.FunctionsCoreTools"
}

# ============================================================================
# Step 1: Discover Function App and Storage Account
# ============================================================================
Write-Host "`nStep 1: Discovering resources..." -ForegroundColor Yellow

$resourcePrefix = "$BASE_NAME-$ENVIRONMENT"

# Try deployment outputs first, fall back to resource queries
$FUNCTION_APP_NAME = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.functionAppName.value" -o tsv 2>$null)
if ($FUNCTION_APP_NAME) { $FUNCTION_APP_NAME = $FUNCTION_APP_NAME.Trim() }

if (-not $FUNCTION_APP_NAME) {
    $FUNCTION_APP_NAME = "$((az functionapp list -g $RESOURCE_GROUP --query "[?starts_with(name,'$resourcePrefix-func')].name | [0]" -o tsv))".Trim()
}

$STORAGE_ACCOUNT = (az deployment group show -g $RESOURCE_GROUP -n main --query "properties.outputs.storageAccountName.value" -o tsv 2>$null)
if ($STORAGE_ACCOUNT) { $STORAGE_ACCOUNT = $STORAGE_ACCOUNT.Trim() }

if (-not $STORAGE_ACCOUNT) {
    $STORAGE_ACCOUNT = "$((az storage account list -g $RESOURCE_GROUP --query "[?starts_with(name,'$($BASE_NAME)$($ENVIRONMENT)')].name | [0]" -o tsv))".Trim()
}

if (-not $FUNCTION_APP_NAME) {
    throw "Could not find Function App in resource group '$RESOURCE_GROUP'. Run deploy.ps1 first."
}

Write-Host "  Function App: $FUNCTION_APP_NAME" -ForegroundColor Gray
Write-Host "  Storage:      $STORAGE_ACCOUNT" -ForegroundColor Gray

# ============================================================================
# Step 2: Enable public access and publish Function App code
# ============================================================================
Write-Host "`nStep 2: Publishing Function App code..." -ForegroundColor Yellow

# Temporarily enable storage public access for deployment
Write-Host "  Enabling storage public access for deployment..." -ForegroundColor Gray
az storage account update -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT --public-network-access Enabled --output none

# Temporarily enable Function App public access for deployment
Write-Host "  Enabling Function App public access for deployment..." -ForegroundColor Gray
az functionapp update -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --set publicNetworkAccess=Enabled --output none

Push-Location (Join-Path $PSScriptRoot "..\azure_function_sql")
func azure functionapp publish $FUNCTION_APP_NAME --python
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Failed to publish Function App"
}
Pop-Location
Write-Host "[OK] Function code deployed" -ForegroundColor Green

# ============================================================================
# Step 3: Re-disable public access
# ============================================================================
Write-Host "`nStep 3: Re-securing resources..." -ForegroundColor Yellow

az storage account update -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT --public-network-access Disabled --output none
az functionapp update -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --set publicNetworkAccess=Disabled --output none

Write-Host "[OK] Public access re-disabled on Storage and Function App" -ForegroundColor Green

# ============================================================================
# Done
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Function App Publish Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Step:" -ForegroundColor Yellow
Write-Host "  Run logicAppDesign.ps1 to deploy the Logic App workflow:" -ForegroundColor Cyan
Write-Host "    .\logicAppDesign.ps1" -ForegroundColor Cyan
Write-Host ""
