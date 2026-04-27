# ============================================================================
# Connect existing DAB MCP Server Container App to Contract Analysis SQL
# ============================================================================
#
# Context:
#   The customer already deployed a DAB MCP Server Container App following
#   the quickstart. This script migrates it to work with the existing
#   Contract Analysis architecture:
#     - Azure AD-only SQL auth (managed identity, no passwords)
#     - Private-endpoint-only SQL Server (public access disabled)
#     - Existing VNet with private DNS zones in a separate subscription
#     - contracts / parties / clauses schema (not Products)
#
# What this script does:
#   1. Creates a new subnet for Container Apps on the existing VNet
#   2. Creates a NEW VNet-integrated Container Apps environment
#      (VNet cannot be added to an existing environment after creation)
#   3. Rebuilds the container image with the correct DAB config (3 entities)
#   4. Redeploys the Container App into the new environment with managed identity
#   5. Links the cross-subscription Private DNS zone for SQL resolution
#   6. Outputs the SQL commands to grant the managed identity access
#
# The old environment/app can be deleted after verifying the new one works.
#
# Prerequisites:
#   - Azure CLI installed (az)
#   - .NET 9+ (dotnet)
#   - DAB CLI: dotnet tool install microsoft.dataapibuilder
#   - Logged in: az login
# ============================================================================

param(
    [string]$ResourceGroup       = "contract-analysis-rg",
    [string]$Location            = "eastus",

    # Existing SQL Server deployed by infra_sql
    [string]$SqlServerName       = "",   # e.g., "contracts-dev-sql-a1b2c3d4"
    [string]$SqlDatabaseName     = "contractsdb",

    # Existing VNet (same one used by the Function App / Logic App)
    [string]$VnetName            = "cai-a1-tst-vnet-spoke01",
    [string]$VnetResourceGroup   = "",   # RG that owns the VNet

    # New subnet for Container Apps (minimum /23, must not overlap existing)
    [string]$ContainerAppSubnetPrefix = "",  # e.g., "10.0.8.0/23"
    [string]$ContainerAppSubnetName   = "snet-containerapp",

    # Private DNS zone configuration (cross-subscription)
    [string]$DnsZoneSubscriptionId   = "",
    [string]$DnsZoneResourceGroup    = "",

    # Existing Container App / ACR from the quickstart deployment
    [string]$ExistingAcrName         = "",   # ACR created during quickstart (e.g., "acrsqlmcp1234")
    [string]$ExistingContainerAppName = "",  # Current container app name (e.g., "sql-mcp-server")
    [string]$ExistingEnvName         = "",   # Current CA environment name (e.g., "sql-mcp-env")
    [string]$ExistingResourceGroup   = "",   # RG where quickstart resources live (if different)

    # New Container Apps naming (for the VNet-integrated redeployment)
    [string]$NewContainerAppEnvName  = "contracts-mcp-env-vnet",
    [string]$NewContainerAppName     = "contracts-mcp-server"
)

$ErrorActionPreference = "Stop"

# If existing RG not specified, assume same as target
if ([string]::IsNullOrWhiteSpace($ExistingResourceGroup)) {
    $ExistingResourceGroup = $ResourceGroup
}

# ============================================================================
# Validate required parameters
# ============================================================================

$requiredParams = @{
    SqlServerName              = $SqlServerName
    VnetResourceGroup          = $VnetResourceGroup
    ContainerAppSubnetPrefix   = $ContainerAppSubnetPrefix
    DnsZoneSubscriptionId      = $DnsZoneSubscriptionId
    DnsZoneResourceGroup       = $DnsZoneResourceGroup
    ExistingAcrName            = $ExistingAcrName
}

$missing = $requiredParams.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) }
if ($missing) {
    Write-Host "ERROR: The following parameters are required:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  -$($_.Key)" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Cyan
    Write-Host '  .\deploy-mcp-server.ps1 `'
    Write-Host '    -SqlServerName "contracts-dev-sql-a1b2c3d4" `'
    Write-Host '    -VnetResourceGroup "network-rg" `'
    Write-Host '    -ContainerAppSubnetPrefix "10.0.8.0/23" `'
    Write-Host '    -DnsZoneSubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `'
    Write-Host '    -DnsZoneResourceGroup "dns-zones-rg" `'
    Write-Host '    -ExistingAcrName "acrsqlmcp1234"'
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " MCP Server Migration to VNet" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SQL Server:          $SqlServerName" -ForegroundColor Gray
Write-Host "Database:            $SqlDatabaseName" -ForegroundColor Gray
Write-Host "VNet:                $VnetName" -ForegroundColor Gray
Write-Host "New CA Subnet:       $ContainerAppSubnetName ($ContainerAppSubnetPrefix)" -ForegroundColor Gray
Write-Host "Existing ACR:        $ExistingAcrName" -ForegroundColor Gray
Write-Host "New Container App:   $NewContainerAppName" -ForegroundColor Gray
Write-Host "New CA Environment:  $NewContainerAppEnvName" -ForegroundColor Gray
Write-Host ""
if (-not [string]::IsNullOrWhiteSpace($ExistingContainerAppName)) {
    Write-Host "Existing App (will be replaced): $ExistingContainerAppName" -ForegroundColor DarkYellow
}
Write-Host ""

# ============================================================================
# Step 1: Create the Container Apps subnet on the existing VNet
# ============================================================================

Write-Host "[1/8] Creating Container Apps subnet..." -ForegroundColor Yellow

$subnetExists = az network vnet subnet show `
    --resource-group $VnetResourceGroup `
    --vnet-name $VnetName `
    --name $ContainerAppSubnetName `
    --query "name" --output tsv 2>$null

if ($subnetExists) {
    Write-Host "  Subnet '$ContainerAppSubnetName' already exists, skipping." -ForegroundColor Gray
} else {
    az network vnet subnet create `
        --resource-group $VnetResourceGroup `
        --vnet-name $VnetName `
        --name $ContainerAppSubnetName `
        --address-prefixes $ContainerAppSubnetPrefix `
        --delegation "Microsoft.App/environments"
    Write-Host "  Subnet created." -ForegroundColor Green
}

$SUBNET_ID = az network vnet subnet show `
    --resource-group $VnetResourceGroup `
    --vnet-name $VnetName `
    --name $ContainerAppSubnetName `
    --query "id" --output tsv

# ============================================================================
# Step 2: Verify existing ACR
# ============================================================================

Write-Host "[2/8] Verifying existing ACR ($ExistingAcrName)..." -ForegroundColor Yellow

$acrExists = az acr show --name $ExistingAcrName --query "name" --output tsv 2>$null
if (-not $acrExists) {
    Write-Host "  ERROR: ACR '$ExistingAcrName' not found. Check the name and your subscription." -ForegroundColor Red
    exit 1
}
Write-Host "  ACR verified." -ForegroundColor Green

# ============================================================================
# Step 3: Generate DAB configuration for contract schema
# ============================================================================

Write-Host "[3/8] Generating DAB configuration (dab-config.json)..." -ForegroundColor Yellow

# Clean up any existing config
if (Test-Path "dab-config.json") { Remove-Item "dab-config.json" -Force }

# Connection string uses managed identity — no password
dab init `
    --database-type mssql `
    --connection-string "@env('MSSQL_CONNECTION_STRING')" `
    --host-mode Production `
    --config dab-config.json

# --- contracts entity ---
dab add Contracts `
    --source dbo.contracts `
    --permissions "anonymous:read" `
    --description "Contract documents with metadata including jurisdiction, dates, duration, and full markdown content"

dab update Contracts --fields.name id          --fields.description "Unique contract identifier (auto-generated)" --fields.primary-key true
dab update Contracts --fields.name filename    --fields.description "Original filename of the uploaded contract PDF"
dab update Contracts --fields.name title       --fields.description "Contract title extracted from the document"
dab update Contracts --fields.name duration    --fields.description "Contract duration or term length"
dab update Contracts --fields.name jurisdictions --fields.description "JSON array of jurisdictions the contract applies to"
dab update Contracts --fields.name dates       --fields.description "JSON object with key dates (effective, expiration, signing)"
dab update Contracts --fields.name markdown    --fields.description "Full markdown representation of the contract content"
dab update Contracts --fields.name raw_fields  --fields.description "JSON object with all raw extracted fields from document analysis"
dab update Contracts --fields.name created_at  --fields.description "UTC timestamp when the contract was ingested"

# --- parties entity ---
dab add Parties `
    --source dbo.parties `
    --permissions "anonymous:read" `
    --description "Parties involved in contracts including names, addresses, and associated clauses"

dab update Parties --fields.name id             --fields.description "Unique party identifier (auto-generated)" --fields.primary-key true
dab update Parties --fields.name contract_id    --fields.description "Foreign key to the parent contract"
dab update Parties --fields.name name           --fields.description "Full legal name of the party"
dab update Parties --fields.name address        --fields.description "Registered address of the party"
dab update Parties --fields.name reference_name --fields.description "Short reference name used within the contract (e.g. 'Buyer', 'Seller')"
dab update Parties --fields.name clause         --fields.description "Clause text where this party is defined or referenced"

# --- clauses entity ---
dab add Clauses `
    --source dbo.clauses `
    --permissions "anonymous:read" `
    --description "Individual contract clauses with type classification, title, and full text"

dab update Clauses --fields.name id            --fields.description "Unique clause identifier (auto-generated)" --fields.primary-key true
dab update Clauses --fields.name contract_id   --fields.description "Foreign key to the parent contract"
dab update Clauses --fields.name clause_type   --fields.description "Classification of clause type (e.g. Termination, Indemnity, Confidentiality, Payment)"
dab update Clauses --fields.name title         --fields.description "Title or heading of the clause"
dab update Clauses --fields.name text          --fields.description "Full text content of the clause"

Write-Host "  DAB config generated with 3 entities." -ForegroundColor Green

# ============================================================================
# Step 4: Build and push container image
# ============================================================================

Write-Host "[4/8] Rebuilding container image with contract schema config..." -ForegroundColor Yellow

# Create Dockerfile
@"
FROM mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc
COPY dab-config.json /App/dab-config.json
"@ | Out-File -FilePath Dockerfile -Encoding utf8

az acr build --registry $ExistingAcrName --image contracts-mcp-server:1 .

Write-Host "  Image built and pushed to existing ACR." -ForegroundColor Green

# ============================================================================
# Step 5: Create NEW VNet-integrated Container Apps environment
# ============================================================================
# IMPORTANT: Container Apps environments CANNOT be VNet-integrated after
# creation. Since the quickstart created the environment without VNet
# integration, we must create a new one.
# ============================================================================

Write-Host "[5/8] Creating NEW Container Apps environment (VNet-integrated)..." -ForegroundColor Yellow
Write-Host "  NOTE: The existing environment cannot be retrofitted with VNet." -ForegroundColor DarkYellow
Write-Host "  Creating new environment: $NewContainerAppEnvName" -ForegroundColor DarkYellow

az containerapp env create `
    --name $NewContainerAppEnvName `
    --resource-group $ResourceGroup `
    --location $Location `
    --infrastructure-subnet-resource-id $SUBNET_ID

Write-Host "  VNet-integrated environment created." -ForegroundColor Green

# ============================================================================
# Step 6: Deploy the Container App into the new environment
# ============================================================================

Write-Host "[6/8] Deploying Container App into VNet-integrated environment..." -ForegroundColor Yellow

$ACR_LOGIN_SERVER = az acr show --name $ExistingAcrName --query loginServer --output tsv
$ACR_USERNAME = az acr credential show --name $ExistingAcrName --query username --output tsv
$ACR_PASSWORD = az acr credential show --name $ExistingAcrName --query "passwords[0].value" --output tsv

# Connection string for Azure AD managed identity auth (no password)
$MI_CONNECTION_STRING = "Server=tcp:$SqlServerName.database.windows.net,1433;Database=$SqlDatabaseName;Authentication=Active Directory Managed Identity;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"

az containerapp create `
    --name $NewContainerAppName `
    --resource-group $ResourceGroup `
    --environment $NewContainerAppEnvName `
    --image "$ACR_LOGIN_SERVER/contracts-mcp-server:1" `
    --registry-server $ACR_LOGIN_SERVER `
    --registry-username $ACR_USERNAME `
    --registry-password $ACR_PASSWORD `
    --target-port 5000 `
    --ingress external `
    --min-replicas 1 `
    --max-replicas 3 `
    --secrets "mssql-conn=$MI_CONNECTION_STRING" `
    --env-vars "MSSQL_CONNECTION_STRING=secretref:mssql-conn" `
    --cpu 0.5 `
    --memory 1.0Gi `
    --system-assigned

Write-Host "  Container App deployed into VNet-integrated environment." -ForegroundColor Green

# ============================================================================
# Step 7: Link Private DNS Zone for SQL
# ============================================================================

Write-Host "[7/8] Linking Private DNS zone to Container Apps VNet..." -ForegroundColor Yellow

$VNET_ID = az network vnet show `
    --resource-group $VnetResourceGroup `
    --name $VnetName `
    --query "id" --output tsv

# Link the SQL private DNS zone to the VNet (so Container App can resolve the SQL private endpoint)
$DNS_LINK_NAME = "vnetlink-containerapp-sql"

$linkExists = az network private-dns link vnet show `
    --resource-group $DnsZoneResourceGroup `
    --zone-name "privatelink.database.windows.net" `
    --name $DNS_LINK_NAME `
    --subscription $DnsZoneSubscriptionId `
    --query "name" --output tsv 2>$null

if ($linkExists) {
    Write-Host "  DNS zone link already exists, skipping." -ForegroundColor Gray
} else {
    az network private-dns link vnet create `
        --resource-group $DnsZoneResourceGroup `
        --zone-name "privatelink.database.windows.net" `
        --name $DNS_LINK_NAME `
        --virtual-network $VNET_ID `
        --registration-enabled false `
        --subscription $DnsZoneSubscriptionId
    Write-Host "  DNS zone linked." -ForegroundColor Green
}

# ============================================================================
# Step 8: Output results and next steps
# ============================================================================

Write-Host "[8/8] Getting deployment details..." -ForegroundColor Yellow

$MCP_URL = az containerapp show `
    --name $NewContainerAppName `
    --resource-group $ResourceGroup `
    --query "properties.configuration.ingress.fqdn" `
    --output tsv

$MI_PRINCIPAL_ID = az containerapp show `
    --name $NewContainerAppName `
    --resource-group $ResourceGroup `
    --query "identity.principalId" `
    --output tsv

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "MCP Server URL:  https://$MCP_URL/mcp" -ForegroundColor Cyan
Write-Host "Health Check:    https://$MCP_URL/health" -ForegroundColor Cyan
Write-Host "Managed Identity Principal ID: $MI_PRINCIPAL_ID" -ForegroundColor Cyan
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " REQUIRED: Grant SQL access to the" -ForegroundColor Yellow
Write-Host " Container App managed identity" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Connect to $SqlDatabaseName as the Azure AD admin and run:" -ForegroundColor White
Write-Host ""
Write-Host "  CREATE USER [$NewContainerAppName] FROM EXTERNAL PROVIDER;" -ForegroundColor White
Write-Host "  ALTER ROLE db_datareader ADD MEMBER [$NewContainerAppName];" -ForegroundColor White
Write-Host ""
Write-Host "(Add db_datawriter too if you want write access via MCP)" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " VS Code MCP Client Configuration" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Add this to your VS Code settings.json or .vscode/mcp.json:" -ForegroundColor White
Write-Host ""
Write-Host @"
{
  "mcpServers": {
    "contracts-mcp": {
      "type": "sse",
      "url": "https://$MCP_URL/mcp"
    }
  }
}
"@ -ForegroundColor White
Write-Host ""

# Cleanup guidance for old quickstart resources
if (-not [string]::IsNullOrWhiteSpace($ExistingContainerAppName) -or -not [string]::IsNullOrWhiteSpace($ExistingEnvName)) {
    Write-Host "========================================" -ForegroundColor DarkYellow
    Write-Host " CLEANUP: Old quickstart resources" -ForegroundColor DarkYellow
    Write-Host "========================================" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "After verifying the new MCP server works (check /health and /mcp)," -ForegroundColor White
    Write-Host "delete the old non-VNet resources:" -ForegroundColor White
    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($ExistingContainerAppName)) {
        Write-Host "  az containerapp delete --name $ExistingContainerAppName --resource-group $ExistingResourceGroup --yes" -ForegroundColor Gray
    }
    if (-not [string]::IsNullOrWhiteSpace($ExistingEnvName)) {
        Write-Host "  az containerapp env delete --name $ExistingEnvName --resource-group $ExistingResourceGroup --yes" -ForegroundColor Gray
    }
    Write-Host ""
}

# Cleanup build artifacts
Remove-Item -Path "Dockerfile" -ErrorAction SilentlyContinue
Write-Host "Build artifacts cleaned up." -ForegroundColor Gray
Write-Host "Done." -ForegroundColor Green
