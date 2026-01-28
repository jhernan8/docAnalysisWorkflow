#!/bin/bash

# ============================================================================
# Contract Analysis Solution - Deployment Script
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Contract Analysis Solution Deployment${NC}"
echo -e "${GREEN}========================================${NC}"

# Configuration - CUSTOMIZE THESE
RESOURCE_GROUP="contract-analysis-rg"
LOCATION="eastus"  # Primary location for Function App, Storage, AI Services
SQL_LOCATION="centralus"  # SQL location (some regions have restrictions)
BASE_NAME="contracts"
ENVIRONMENT="dev"

# Content Understanding Analyzer ID - placeholder until created in Portal
ANALYZER_ID="YourAnalyzerID"

# Prompt for configuration values
echo -e "${YELLOW}Azure AD Configuration (for SQL Azure AD-only auth):${NC}"
read -p "Enter your Azure AD Object ID (run 'az ad signed-in-user show --query id -o tsv'): " AAD_OBJECT_ID
read -p "Enter your Azure AD display name (email): " AAD_DISPLAY_NAME
echo ""
echo -e "${YELLOW}SharePoint Configuration:${NC}"
read -p "Enter SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/ContractAI): " SHAREPOINT_SITE_URL
read -p "Enter SharePoint document library ID (GUID): " SHAREPOINT_LIBRARY_ID

echo -e "\n${YELLOW}Step 1: Creating resource group...${NC}"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

echo -e "${GREEN}✓ Resource group created${NC}"

echo -e "\n${YELLOW}Step 2: Deploying Bicep template...${NC}"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters baseName="$BASE_NAME" \
  --parameters location="$LOCATION" \
  --parameters sqlLocation="$SQL_LOCATION" \
  --parameters environment="$ENVIRONMENT" \
  --parameters sqlAadAdminObjectId="$AAD_OBJECT_ID" \
  --parameters sqlAadAdminDisplayName="$AAD_DISPLAY_NAME" \
  --parameters contentUnderstandingAnalyzerId="$ANALYZER_ID" \
  --parameters sharePointSiteUrl="$SHAREPOINT_SITE_URL" \
  --parameters sharePointLibraryId="$SHAREPOINT_LIBRARY_ID" \
  --output none

echo -e "${GREEN}✓ Infrastructure deployed${NC}"

# Extract outputs using Azure CLI queries (strip any carriage returns)
FUNCTION_APP_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.functionAppName.value" -o tsv | tr -d '\r')
SQL_SERVER=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.sqlServerFqdn.value" -o tsv | tr -d '\r')
SQL_DATABASE=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.sqlDatabaseName.value" -o tsv | tr -d '\r')
STORAGE_ACCOUNT=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.storageAccountName.value" -o tsv | tr -d '\r')

echo -e "\n${YELLOW}Step 3: Deploying Function App code...${NC}"
cd ../azure_function_sql
func azure functionapp publish "$FUNCTION_APP_NAME" --python
cd ../infra

echo -e "${GREEN}✓ Function code deployed${NC}"

# Extract Logic App name for final output
LOGIC_APP_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.logicAppName.value" -o tsv | tr -d '\r')
SHAREPOINT_CONNECTION=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.sharePointConnectionName.value" -o tsv | tr -d '\r')

echo -e "\n${YELLOW}Step 4: Configuring Logic App with Function key...${NC}"
FUNCTION_KEY=$(az functionapp keys list -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --query "functionKeys.default" -o tsv | tr -d '\r')

# Get Logic App details
SUBSCRIPTION_ID=$(az account show --query id -o tsv | tr -d '\r')
LOCATION=$(az logic workflow show -g "$RESOURCE_GROUP" -n "$LOGIC_APP_NAME" --query "location" -o tsv | tr -d '\r')

# Get definition and parameters separately, then construct clean JSON
DEFINITION_FILE="/tmp/logic-definition-$$.json"
PARAMS_FILE="/tmp/logic-params-$$.json"
WORKFLOW_FILE="/tmp/logic-workflow-$$.json"

az logic workflow show -g "$RESOURCE_GROUP" -n "$LOGIC_APP_NAME" --query "definition" -o json > "$DEFINITION_FILE"
az logic workflow show -g "$RESOURCE_GROUP" -n "$LOGIC_APP_NAME" --query "parameters" -o json > "$PARAMS_FILE"

# Replace placeholder with actual function key in definition (cross-platform sed)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/PLACEHOLDER_UPDATE_VIA_SCRIPT/$FUNCTION_KEY/g" "$DEFINITION_FILE"
else
    sed -i "s/PLACEHOLDER_UPDATE_VIA_SCRIPT/$FUNCTION_KEY/g" "$DEFINITION_FILE"
fi

# Construct clean workflow JSON
cat > "$WORKFLOW_FILE" << EOF
{
  "location": "$LOCATION",
  "properties": {
    "state": "Disabled",
    "definition": $(cat "$DEFINITION_FILE"),
    "parameters": $(cat "$PARAMS_FILE")
  }
}
EOF

# Update the Logic App
az rest --method PUT \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME?api-version=2019-05-01" \
    --body @"$WORKFLOW_FILE" \
    --output none

rm -f "$DEFINITION_FILE" "$PARAMS_FILE" "$WORKFLOW_FILE"
echo -e "${GREEN}✓ Logic App configured with Function key${NC}"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Resource Details:${NC}"
echo "  Function App:           $FUNCTION_APP_NAME"
echo "  Logic App:              $LOGIC_APP_NAME"
echo "  SharePoint Connection:  $SHAREPOINT_CONNECTION"
echo "  SQL Server:             $SQL_SERVER"
echo "  SQL Database:           $SQL_DATABASE"
echo "  Storage:                $STORAGE_ACCOUNT"

echo -e "\n${YELLOW}Remaining Manual Steps:${NC}"
echo ""
echo "1. Run SQL setup scripts (via Azure Portal Query Editor, SSMS, or sqlcmd):"
echo "   a. Connect to: $SQL_SERVER / $SQL_DATABASE"
echo "   b. Run create_tables.sql to create the schema"
echo "   c. Run this SQL to grant Function App access:"
echo "      CREATE USER [$FUNCTION_APP_NAME] FROM EXTERNAL PROVIDER;"
echo "      ALTER ROLE db_datareader ADD MEMBER [$FUNCTION_APP_NAME];"
echo "      ALTER ROLE db_datawriter ADD MEMBER [$FUNCTION_APP_NAME];"
echo ""
echo "2. Create the Content Understanding analyzer in Azure AI Foundry"
echo "   - Go to: AI Foundry → Content Understanding → Create Analyzer"
echo "   - Note the Analyzer ID you create"
echo "   - Update Function App setting:"
echo "     az functionapp config appsettings set -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME --settings CONTENT_UNDERSTANDING_ANALYZER_ID=<your-analyzer-id>"
echo ""
echo "3. Authorize SharePoint Connection"
echo "   - Go to: Azure Portal → Resource Group → API Connections → $SHAREPOINT_CONNECTION"
echo "   - Click 'Edit API connection' → 'Authorize' → Sign in with SharePoint account"
echo "   - Click 'Save'"
echo ""
echo "4. Enable the Logic App in Azure Portal"
echo "   - Go to: Logic Apps → $LOGIC_APP_NAME → Overview → Enable"
echo ""
echo "5. Test the solution"
echo "   - Upload a PDF contract to your SharePoint document library"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}All infrastructure is ready!${NC}"
echo -e "${GREEN}========================================${NC}"
