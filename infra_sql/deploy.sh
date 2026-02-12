#!/bin/bash

# ============================================================================
# Contract Analysis Solution - Deployment Script (v2 - Private Endpoints)
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

# Networking Configuration
VNET_NAME="cai-a1-tst-vnet-spoke01"
VNET_RESOURCE_GROUP=""          # Resource group of the existing VNet
PE_SUBNET_PREFIX=""             # e.g., "10.0.4.0/24"
FUNC_SUBNET_PREFIX=""           # e.g., "10.0.5.0/24"
LOGIC_SUBNET_PREFIX=""          # e.g., "10.0.6.0/24"
DNS_ZONE_SUBSCRIPTION_ID=""     # Subscription ID where Private DNS Zones live
DNS_ZONE_RESOURCE_GROUP=""      # Resource group containing Private DNS Zones

# Prompt for configuration values
echo -e "${YELLOW}Azure AD Configuration (for SQL Azure AD-only auth):${NC}"
read -p "Enter your Azure AD Object ID (run 'az ad signed-in-user show --query id -o tsv'): " AAD_OBJECT_ID
read -p "Enter your Azure AD display name (email): " AAD_DISPLAY_NAME
echo ""
echo -e "${YELLOW}SharePoint Configuration:${NC}"
read -p "Enter SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/ContractAI): " SHAREPOINT_SITE_URL
read -p "Enter SharePoint document library ID (GUID): " SHAREPOINT_LIBRARY_ID

echo ""
echo -e "${YELLOW}Networking Configuration:${NC}"
if [ -z "$VNET_RESOURCE_GROUP" ]; then
  read -p "Enter the VNet resource group name: " VNET_RESOURCE_GROUP
fi
if [ -z "$PE_SUBNET_PREFIX" ]; then
  read -p "Enter private endpoint subnet CIDR (e.g., 10.0.4.0/24): " PE_SUBNET_PREFIX
fi
if [ -z "$FUNC_SUBNET_PREFIX" ]; then
  read -p "Enter Function App VNet integration subnet CIDR (e.g., 10.0.5.0/24): " FUNC_SUBNET_PREFIX
fi
if [ -z "$LOGIC_SUBNET_PREFIX" ]; then
  read -p "Enter Logic App VNet integration subnet CIDR (e.g., 10.0.6.0/24): " LOGIC_SUBNET_PREFIX
fi
if [ -z "$DNS_ZONE_SUBSCRIPTION_ID" ]; then
  read -p "Enter DNS Zone subscription ID: " DNS_ZONE_SUBSCRIPTION_ID
fi
if [ -z "$DNS_ZONE_RESOURCE_GROUP" ]; then
  read -p "Enter DNS Zone resource group name: " DNS_ZONE_RESOURCE_GROUP
fi

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
  --parameters sharePointSiteUrl="$SHAREPOINT_SITE_URL" \
  --parameters sharePointLibraryId="$SHAREPOINT_LIBRARY_ID" \
  --parameters vnetName="$VNET_NAME" \
  --parameters vnetResourceGroupName="$VNET_RESOURCE_GROUP" \
  --parameters privateEndpointSubnetAddressPrefix="$PE_SUBNET_PREFIX" \
  --parameters vnetIntegrationSubnetAddressPrefix="$FUNC_SUBNET_PREFIX" \
  --parameters logicAppSubnetAddressPrefix="$LOGIC_SUBNET_PREFIX" \
  --parameters dnsZoneSubscriptionId="$DNS_ZONE_SUBSCRIPTION_ID" \
  --parameters dnsZoneResourceGroupName="$DNS_ZONE_RESOURCE_GROUP" \
  --output none

echo -e "${GREEN}✓ Infrastructure deployed${NC}"

# Extract outputs
FUNCTION_APP_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.functionAppName.value" -o tsv | tr -d '\r')
SQL_SERVER=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.sqlServerFqdn.value" -o tsv | tr -d '\r')
SQL_DATABASE=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.sqlDatabaseName.value" -o tsv | tr -d '\r')
STORAGE_ACCOUNT=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.storageAccountName.value" -o tsv | tr -d '\r')

echo -e "\n${YELLOW}Step 3: Deploying Function App code...${NC}"
echo -e "${YELLOW}  Temporarily enabling storage public access for deployment...${NC}"
az storage account update \
  -g "$RESOURCE_GROUP" \
  -n "$STORAGE_ACCOUNT" \
  --public-network-access Enabled \
  --output none

# Allow a moment for the change to propagate
sleep 10

cd ../azure_function_sql
func azure functionapp publish "$FUNCTION_APP_NAME" --python
cd ../infra_sql

echo -e "${YELLOW}  Re-disabling storage public access...${NC}"
az storage account update \
  -g "$RESOURCE_GROUP" \
  -n "$STORAGE_ACCOUNT" \
  --public-network-access Disabled \
  --output none

echo -e "${GREEN}✓ Function code deployed (storage re-secured)${NC}"

# Extract Logic App name for final output
LOGIC_APP_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.logicAppName.value" -o tsv | tr -d '\r')
SHAREPOINT_CONNECTION=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.sharePointConnectionName.value" -o tsv | tr -d '\r')

echo -e "\n${YELLOW}Step 4: Deploying Logic App Standard workflow...${NC}"

# Get Function key for the Logic App workflow to call Function App
FUNCTION_KEY=$(az functionapp keys list -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --query "functionKeys.default" -o tsv | tr -d '\r')

# Get SharePoint connection details
SUBSCRIPTION_ID=$(az account show --query id -o tsv | tr -d '\r')
SP_CONNECTION_RUNTIME_URL=$(az resource show -g "$RESOURCE_GROUP" --resource-type "Microsoft.Web/connections" -n "$SHAREPOINT_CONNECTION" --query "properties.connectionRuntimeUrl" -o tsv | tr -d '\r')
SP_CONNECTION_ID=$(az resource show -g "$RESOURCE_GROUP" --resource-type "Microsoft.Web/connections" -n "$SHAREPOINT_CONNECTION" --query id -o tsv | tr -d '\r')
MANAGED_API_ID=$(az resource show -g "$RESOURCE_GROUP" --resource-type "Microsoft.Web/connections" -n "$SHAREPOINT_CONNECTION" --query "properties.api.id" -o tsv | tr -d '\r')

# Create workflow directory structure
WORKFLOW_DIR="/tmp/logic-app-workflow-$$"
mkdir -p "$WORKFLOW_DIR/contract-trigger"

# Get app settings values
FUNC_HOSTNAME=$(az deployment group show -g "$RESOURCE_GROUP" -n main --query "properties.outputs.functionAppUrl.value" -o tsv | tr -d '\r' | sed 's|https://||')
SP_SITE_URL="$SHAREPOINT_SITE_URL"
SP_LIBRARY_ID="$SHAREPOINT_LIBRARY_ID"

# Create connections.json
cat > "$WORKFLOW_DIR/connections.json" << CONNEOF
{
  "managedApiConnections": {
    "sharepointonline": {
      "api": {
        "id": "$MANAGED_API_ID"
      },
      "connection": {
        "id": "$SP_CONNECTION_ID"
      },
      "connectionRuntimeUrl": "$SP_CONNECTION_RUNTIME_URL",
      "authentication": {
        "type": "ManagedServiceIdentity"
      }
    }
  }
}
CONNEOF

# Create workflow.json for the contract-trigger workflow
cat > "$WORKFLOW_DIR/contract-trigger/workflow.json" << WFEOF
{
  "definition": {
    "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
      "\$connections": {
        "defaultValue": {},
        "type": "Object"
      }
    },
    "triggers": {
      "When_a_file_is_created_properties_only": {
        "type": "ApiConnection",
        "inputs": {
          "host": {
            "connection": {
              "referenceName": "sharepointonline"
            }
          },
          "method": "get",
          "path": "/datasets/@{encodeURIComponent(encodeURIComponent('$SP_SITE_URL'))}/tables/@{encodeURIComponent(encodeURIComponent('$SP_LIBRARY_ID'))}/onnewfileitems"
        },
        "recurrence": {
          "frequency": "Minute",
          "interval": 1
        },
        "splitOn": "@triggerBody()?['value']"
      }
    },
    "actions": {
      "Get_file_content": {
        "type": "ApiConnection",
        "inputs": {
          "host": {
            "connection": {
              "referenceName": "sharepointonline"
            }
          },
          "method": "get",
          "path": "/datasets/@{encodeURIComponent(encodeURIComponent('$SP_SITE_URL'))}/files/@{encodeURIComponent(triggerBody()?['{Identifier}'])}/content",
          "queries": {
            "inferContentType": true
          }
        },
        "runAfter": {}
      },
      "Call_Function_App": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "https://$FUNC_HOSTNAME/api/analyze-and-store",
          "headers": {
            "x-functions-key": "$FUNCTION_KEY"
          },
          "body": {
            "filename": "@{triggerBody()?['{Name}']}",
            "content": "@{base64(body('Get_file_content'))}"
          }
        },
        "runAfter": {
          "Get_file_content": ["Succeeded"]
        },
        "runtimeConfiguration": {
          "contentTransfer": {
            "transferMode": "Chunked"
          }
        }
      }
    },
    "outputs": {}
  },
  "kind": "Stateful"
}
WFEOF

# Zip and deploy the workflow
cd "$WORKFLOW_DIR"
zip -r /tmp/logic-workflow-$$.zip . > /dev/null 2>&1

az logicapp deployment source config-zip \
  -g "$RESOURCE_GROUP" \
  -n "$LOGIC_APP_NAME" \
  --src /tmp/logic-workflow-$$.zip \
  --output none

rm -rf "$WORKFLOW_DIR" /tmp/logic-workflow-$$.zip
cd "$OLDPWD"

echo -e "${GREEN}✓ Logic App workflow deployed${NC}"

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
echo "  VNet:                   $VNET_NAME (in $VNET_RESOURCE_GROUP)"

echo -e "\n${YELLOW}Private Endpoints Created:${NC}"
echo "  - Storage (blob, file, queue, table)"
echo "  - Azure SQL Server"
echo "  - Function App (inbound)"
echo "  - Logic App Standard (inbound)"

echo -e "\n${YELLOW}Remaining Manual Steps:${NC}"
echo ""
echo "1. Run SQL setup scripts (connect via Private Endpoint or from within VNet):"
echo "   a. Connect to: $SQL_SERVER / $SQL_DATABASE"
echo "   b. Run create_tables.sql to create the schema"
echo "   c. Run this SQL to grant Function App access:"
echo "      CREATE USER [$FUNCTION_APP_NAME] FROM EXTERNAL PROVIDER;"
echo "      ALTER ROLE db_datareader ADD MEMBER [$FUNCTION_APP_NAME];"
echo "      ALTER ROLE db_datawriter ADD MEMBER [$FUNCTION_APP_NAME];"
echo ""
echo "2. Create Azure AI Foundry resource and Content Understanding analyzer"
echo "   a. Go to: Azure Portal → Create Resource → Azure AI Foundry"
echo "   b. Create in the SAME resource group: $RESOURCE_GROUP"
echo "   c. In the project, go to Content Understanding → Create Analyzer"
echo "   d. Note the Project Endpoint and Analyzer ID"
echo "   e. Update Function App settings:"
echo "      az functionapp config appsettings set -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME \\"
echo "        --settings CONTENT_UNDERSTANDING_ENDPOINT=<your-foundry-endpoint> \\"
echo "        CONTENT_UNDERSTANDING_ANALYZER_ID=<your-analyzer-id>"
echo ""
echo "3. Verify DNS Zone VNet Links"
echo "   Ensure all Private DNS Zones in subscription '$DNS_ZONE_SUBSCRIPTION_ID'"
echo "   resource group '$DNS_ZONE_RESOURCE_GROUP' have VNet links to '$VNET_NAME'"
echo "   Required zones:"
echo "     - privatelink.blob.core.windows.net"
echo "     - privatelink.file.core.windows.net"
echo "     - privatelink.queue.core.windows.net"
echo "     - privatelink.table.core.windows.net"
echo "     - privatelink.database.windows.net"
echo "     - privatelink.azurewebsites.net"
echo ""
echo "4. Authorize SharePoint Connection"
echo "   - Go to: Azure Portal → Resource Group → API Connections → $SHAREPOINT_CONNECTION"
echo "   - Click 'Edit API connection' → 'Authorize' → Sign in"
echo "   - Click 'Save'"
echo ""
echo "5. Test the solution"
echo "   - Upload a PDF contract to your SharePoint document library"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}All infrastructure is ready!${NC}"
echo -e "${GREEN}========================================${NC}"
