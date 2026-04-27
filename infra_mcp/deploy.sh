#!/bin/bash

# ============================================================================
# DAB MCP Server - Additive Deployment
# Deploys a VNet-integrated Container Apps environment + DAB MCP Server
# on top of the existing Contract Analysis infrastructure (infra_sql).
#
# Prerequisites:
#   - infra_sql already deployed (SQL Server, VNet, Private DNS Zones)
#   - Azure CLI, .NET 9+, DAB CLI (dotnet tool install microsoft.dataapibuilder)
#   - Logged in: az login
# ============================================================================

set -e

# Detect CRLF — warn early if the script has Windows line endings
if [[ "$(head -1 "$0")" == *$'\r'* ]]; then
    echo "ERROR: This script has Windows (CRLF) line endings."
    echo "Fix with:  sed -i 's/\\r\$//' $0"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check prerequisites
for CMD in az dotnet dab; do
    if ! command -v "$CMD" &> /dev/null; then
        echo -e "${RED}ERROR: '$CMD' is not installed or not in PATH.${NC}"
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================================
# Load configuration
# ============================================================================

if [ -f "$SCRIPT_DIR/deploy.config.ps1" ]; then
    echo -e "${YELLOW}Loading config from deploy.config.ps1...${NC}"
    # Parse PowerShell-style variable assignments
    eval "$(grep -E '^\$[A-Z_]+\s*=' "$SCRIPT_DIR/deploy.config.ps1" | sed 's/^\$//' | sed 's/\s*=\s*/=/' | sed 's/\r//')"
fi

# Defaults — override in deploy.config.ps1 or environment
RESOURCE_GROUP="${RESOURCE_GROUP:-contract-analysis-rg}"
LOCATION="${LOCATION:-eastus}"
SQL_SERVER_NAME="${SQL_SERVER_NAME:-}"
SQL_DATABASE="${SQL_DATABASE:-contractsdb}"
VNET_NAME="${VNET_NAME:-cai-a1-tst-vnet-spoke01}"
VNET_RESOURCE_GROUP="${VNET_RESOURCE_GROUP:-}"
CA_SUBNET_PREFIX="${CA_SUBNET_PREFIX:-}"
ACR_NAME="${ACR_NAME:-}"
DNS_ZONE_SUBSCRIPTION_ID="${DNS_ZONE_SUBSCRIPTION_ID:-}"
DNS_ZONE_RESOURCE_GROUP="${DNS_ZONE_RESOURCE_GROUP:-}"

# ============================================================================
# Validate required values
# ============================================================================

MISSING=0
for VAR_NAME in SQL_SERVER_NAME VNET_RESOURCE_GROUP CA_SUBNET_PREFIX DNS_ZONE_SUBSCRIPTION_ID DNS_ZONE_RESOURCE_GROUP; do
    eval VAL=\$$VAR_NAME
    if [ -z "$VAL" ]; then
        echo -e "${RED}ERROR: $VAR_NAME is required${NC}"
        MISSING=1
    fi
done
if [ "$MISSING" -eq 1 ]; then
    echo -e "${YELLOW}Set these in deploy.config.ps1 or as environment variables.${NC}"
    exit 1
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} DAB MCP Server - Additive Deployment${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "Resource Group:   ${RESOURCE_GROUP}"
echo -e "SQL Server:       ${SQL_SERVER_NAME}"
echo -e "Database:         ${SQL_DATABASE}"
echo -e "VNet:             ${VNET_NAME}"
echo -e "CA Subnet:        ${CA_SUBNET_PREFIX}"
echo ""

# ============================================================================
# Step 1: Create ACR if not provided
# ============================================================================

if [ -z "$ACR_NAME" ]; then
    ACR_NAME="acrcontractsmcp$(shuf -i 1000-9999 -n 1)"
    echo -e "${YELLOW}[1/4] Creating ACR ($ACR_NAME)...${NC}"
    az acr create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACR_NAME" \
        --sku Basic \
        --admin-enabled true \
        --output none
    echo -e "${GREEN}  ACR created.${NC}"
else
    echo -e "${YELLOW}[1/4] Using existing ACR ($ACR_NAME)...${NC}"
    az acr show --name "$ACR_NAME" --output none
    echo -e "${GREEN}  ACR verified.${NC}"
fi

# ============================================================================
# Step 2: Generate DAB config and build container image
# ============================================================================

echo -e "${YELLOW}[2/4] Building DAB MCP container image...${NC}"

BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

# Generate dab-config.json
pushd "$BUILD_DIR" > /dev/null

dab init \
    --database-type mssql \
    --connection-string "@env('MSSQL_CONNECTION_STRING')" \
    --host-mode Production \
    --config dab-config.json

# --- contracts ---
dab add Contracts \
    --source dbo.contracts \
    --permissions "anonymous:read" \
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

# --- parties ---
dab add Parties \
    --source dbo.parties \
    --permissions "anonymous:read" \
    --description "Parties involved in contracts including names, addresses, and associated clauses"

dab update Parties --fields.name id             --fields.description "Unique party identifier (auto-generated)" --fields.primary-key true
dab update Parties --fields.name contract_id    --fields.description "Foreign key to the parent contract"
dab update Parties --fields.name name           --fields.description "Full legal name of the party"
dab update Parties --fields.name address        --fields.description "Registered address of the party"
dab update Parties --fields.name reference_name --fields.description "Short reference name used within the contract (e.g. Buyer, Seller)"
dab update Parties --fields.name clause         --fields.description "Clause text where this party is defined or referenced"

# --- clauses ---
dab add Clauses \
    --source dbo.clauses \
    --permissions "anonymous:read" \
    --description "Individual contract clauses with type classification, title, and full text"

dab update Clauses --fields.name id            --fields.description "Unique clause identifier (auto-generated)" --fields.primary-key true
dab update Clauses --fields.name contract_id   --fields.description "Foreign key to the parent contract"
dab update Clauses --fields.name clause_type   --fields.description "Classification of clause type (e.g. Termination, Indemnity, Confidentiality, Payment)"
dab update Clauses --fields.name title         --fields.description "Title or heading of the clause"
dab update Clauses --fields.name text          --fields.description "Full text content of the clause"

# Dockerfile
cat > Dockerfile <<'EOF'
FROM mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc
COPY dab-config.json /App/dab-config.json
EOF

# Build and push
az acr build --registry "$ACR_NAME" --image contracts-mcp-server:1 .

popd > /dev/null
echo -e "${GREEN}  Image built and pushed.${NC}"

# ============================================================================
# Step 3: Deploy Bicep (subnet + Container Apps env + Container App + DNS link)
# ============================================================================

echo -e "${YELLOW}[3/4] Deploying Bicep template...${NC}"

az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters sqlServerName="$SQL_SERVER_NAME" \
    --parameters sqlDatabaseName="$SQL_DATABASE" \
    --parameters vnetName="$VNET_NAME" \
    --parameters vnetResourceGroupName="$VNET_RESOURCE_GROUP" \
    --parameters containerAppSubnetAddressPrefix="$CA_SUBNET_PREFIX" \
    --parameters acrName="$ACR_NAME" \
    --parameters dnsZoneSubscriptionId="$DNS_ZONE_SUBSCRIPTION_ID" \
    --parameters dnsZoneResourceGroupName="$DNS_ZONE_RESOURCE_GROUP" \
    --parameters location="$LOCATION" \
    --output none

echo -e "${GREEN}  Infrastructure deployed.${NC}"

# ============================================================================
# Step 4: Output results
# ============================================================================

echo -e "${YELLOW}[4/4] Retrieving deployment outputs...${NC}"

MCP_URL=$(az deployment group show -g "$RESOURCE_GROUP" -n main \
    --query "properties.outputs.mcpEndpointUrl.value" -o tsv | tr -d '\r')
HEALTH_URL=$(az deployment group show -g "$RESOURCE_GROUP" -n main \
    --query "properties.outputs.healthEndpointUrl.value" -o tsv | tr -d '\r')
CA_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n main \
    --query "properties.outputs.containerAppName.value" -o tsv | tr -d '\r')
MI_PRINCIPAL=$(az deployment group show -g "$RESOURCE_GROUP" -n main \
    --query "properties.outputs.containerAppPrincipalId.value" -o tsv | tr -d '\r')

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}MCP Server URL:    $MCP_URL${NC}"
echo -e "${CYAN}Health Check:      $HEALTH_URL${NC}"
echo -e "${CYAN}Principal ID:      $MI_PRINCIPAL${NC}"
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW} REQUIRED: Grant SQL access${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "Connect to ${SQL_DATABASE} as the Azure AD admin and run:"
echo ""
echo -e "  CREATE USER [$CA_NAME] FROM EXTERNAL PROVIDER;"
echo -e "  ALTER ROLE db_datareader ADD MEMBER [$CA_NAME];"
echo ""
echo -e "(Add db_datawriter if you want write access via MCP)"
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW} Foundry Agent — MCP Tool Connection${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${CYAN}Option A: Azure AI Foundry Portal (no code)${NC}"
echo ""
echo -e "  1. Go to https://ai.azure.com → select your project → Playground"
echo -e "  2. Create or open an agent"
echo -e "  3. In Tools, select Add → Custom → Model Context Protocol (MCP)"
echo -e "  4. Name: contracts-mcp"
echo -e "  5. Remote MCP Server endpoint: $MCP_URL"
echo -e "  6. Authentication: Unauthenticated"
echo -e "  7. Set 'Require approval' to never"
echo ""
echo -e "  Suggested agent instructions:"
echo ""
echo "  You are a contract analysis assistant. Use the contracts-mcp tool to query contract data."
echo ""
echo "  Available entities:"
echo "    - Contracts: contract documents with title, duration, jurisdictions, dates, and markdown content"
echo "    - Parties: parties involved in contracts (name, address, reference_name, clause)"
echo "    - Clauses: individual clauses with type classification (Termination, Indemnity, etc.) and full text"
echo ""
echo "  Always use the schema discovery tool first, then use query tools to retrieve data."
echo ""
echo -e "${CYAN}Option B: Python SDK${NC}"
echo ""
echo "  from azure.ai.agents.models import McpToolConnection, ToolConnectionList"
echo ""
echo "  mcp_connection = McpToolConnection("
echo "      server_label=\"contracts-mcp\","
echo "      server_url=\"$MCP_URL\","
echo "      server_type=\"sse\""
echo "  )"
echo ""
echo "  agent = client.agents.create_agent("
echo "      model=\"gpt-4o\","
echo "      name=\"contract-analyst\","
echo "      instructions=\"You are a contract analysis assistant. Use contracts-mcp to query contract data.\","
echo "      tool_resources=ToolConnectionList(mcp_tool_connections=[mcp_connection])"
echo "  )"
echo ""
echo -e "${CYAN}Option C: VS Code MCP client (.vscode/mcp.json)${NC}"
echo ""
echo "  { \"mcpServers\": { \"contracts-mcp\": { \"type\": \"sse\", \"url\": \"$MCP_URL\" } } }"
echo ""
echo -e "${GREEN}Done.${NC}"
