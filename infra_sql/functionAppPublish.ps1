# ============================================================================
# Contract Analysis Solution - Function App Publish Script
#
# Publishes Function App code to Azure via ARM zip deploy (management plane).
# This avoids DNS resolution issues with private endpoints — the func CLI
# connects to *.scm.azurewebsites.net which doesn't resolve outside the VNet.
#
# Prerequisites:
#   - az CLI logged in to the correct subscription
#   - deploy.ps1 has been run successfully (infrastructure exists)
#
# After this script, run logicAppDesign.ps1 to deploy the Logic App workflow.
#
# Usage:
#   .\functionAppPublish.ps1
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
# Step 2: Deploy Function App code via ARM zip deploy
# ============================================================================
Write-Host "`nStep 2: Publishing Function App code..." -ForegroundColor Yellow

# Enable Oryx build on the server so dependencies (requirements.txt) are
# installed during deployment — this replaces what `func publish --python` did.
Write-Host "  Configuring remote build settings..." -ForegroundColor Gray
az functionapp config appsettings set -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --settings `
    ENABLE_ORYX_BUILD=true `
    SCM_DO_BUILD_DURING_DEPLOYMENT=true `
    --output none

# Temporarily enable storage public access for deployment
Write-Host "  Enabling storage public access for deployment..." -ForegroundColor Gray
az storage account update -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT --public-network-access Enabled --output none

# Create deployment zip from function source code
$funcSourceDir = Join-Path $PSScriptRoot "..\azure_function_sql"
$zipPath = Join-Path $env:TEMP "func-deploy-$PID.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Write-Host "  Zipping function code from $funcSourceDir ..." -ForegroundColor Gray
Compress-Archive -Path (Join-Path $funcSourceDir "*") -DestinationPath $zipPath -Force

# Deploy via management plane (management.azure.com) — avoids SCM DNS resolution
# issues caused by privatelink.azurewebsites.net CNAME chain
Write-Host "  Deploying via ARM zip deploy (management plane)..." -ForegroundColor Gray
az functionapp deployment source config-zip `
    -g $RESOURCE_GROUP `
    -n $FUNCTION_APP_NAME `
    --src $zipPath `
    --output none

if ($LASTEXITCODE -ne 0) {
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    throw "Failed to publish Function App"
}

Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Write-Host "[OK] Function code deployed" -ForegroundColor Green

# ============================================================================
# Step 3: Re-disable storage public access
# ============================================================================
Write-Host "`nStep 3: Re-securing storage..." -ForegroundColor Yellow

az storage account update -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT --public-network-access Disabled --output none

Write-Host "[OK] Storage public access re-disabled" -ForegroundColor Green

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
