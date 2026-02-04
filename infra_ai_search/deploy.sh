#!/bin/bash
# ============================================================================
# Contract Search Solution - Deployment Script
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track start time
START_TIME=$(date +%s)

# Function to print with timestamp
log() {
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    printf "[%02d:%02d] %b\n" "$mins" "$secs" "$1"
}

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default values from bicepparam file
PARAM_FILE="main.bicepparam"
LOCATION="centralus"
ENVIRONMENT="dev"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--params)
            PARAM_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-l <location>] [-e <environment>] [-p <param-file>]"
            echo ""
            echo "Options:"
            echo "  -l, --location        Primary location (default: centralus)"
            echo "  -e, --environment     Environment: dev, staging, prod (default: dev)"
            echo "  -p, --params          Parameter file (default: main.bicepparam)"
            echo ""
            echo "Resource group name is derived from baseName and environment in the param file."
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Extract baseName from param file to create resource group name
BASE_NAME=$(grep "param baseName" "$SCRIPT_DIR/$PARAM_FILE" | sed "s/.*= *['\"]\\([^'\"]*\\)['\"].*/\\1/")
if [ -z "$BASE_NAME" ]; then
    echo -e "${RED}Error: Could not extract baseName from $PARAM_FILE${NC}"
    exit 1
fi

# Create resource group name from baseName and environment
RESOURCE_GROUP="${BASE_NAME}-${ENVIRONMENT}-rg"

log "${BLUE}============================================${NC}"
log "${BLUE}Contract Search Solution - Deployment${NC}"
log "${BLUE}============================================${NC}"
log ""
log "Resource Group: ${GREEN}$RESOURCE_GROUP${NC}"
log "Location:       ${GREEN}$LOCATION${NC}"
log "Environment:    ${GREEN}$ENVIRONMENT${NC}"
log ""

# Check if logged in to Azure
log "${YELLOW}Checking Azure login...${NC}"
if ! az account show &> /dev/null; then
    log "${RED}Not logged in to Azure. Please run 'az login' first.${NC}"
    exit 1
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
log "Subscription: ${GREEN}$SUBSCRIPTION${NC}"
log ""

# Create resource group if it doesn't exist
log "${YELLOW}Creating resource group if needed...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
log "${GREEN}✓ Resource group ready${NC}"

# Get deploying user's Object ID for blob connection authorization
log "${YELLOW}Getting user Object ID for role assignment...${NC}"
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [ -n "$USER_OBJECT_ID" ]; then
    log "${GREEN}✓ User Object ID: $USER_OBJECT_ID${NC}"
else
    log "${YELLOW}⚠ Could not get user Object ID - you may need to manually assign blob permissions${NC}"
fi

# Deploy Bicep template
log ""
log "${YELLOW}Deploying infrastructure...${NC}"
log "This may take 20-25 minutes..."
log ""

DEPLOYMENT_NAME="contract-search-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters "$SCRIPT_DIR/$PARAM_FILE" \
    --parameters environment="$ENVIRONMENT" \
    --parameters deployingUserObjectId="$USER_OBJECT_ID" \
    --output json > /tmp/deployment-output.json

if [ $? -eq 0 ]; then
    log ""
    log "${GREEN}============================================${NC}"
    log "${GREEN}✓ Deployment completed successfully!${NC}"
    log "${GREEN}============================================${NC}"
else
    log "${RED}✗ Deployment failed${NC}"
    exit 1
fi

# Extract outputs (use tr -d '\r' to strip Windows-style carriage returns)
log ""
log "${BLUE}Deployment Outputs:${NC}"
log "--------------------------------------------"

STORAGE_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.storageAccountName.value" -o tsv | tr -d '\r')
AI_SEARCH_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.aiSearchName.value" -o tsv | tr -d '\r')
AI_SERVICES_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.aiServicesName.value" -o tsv | tr -d '\r')
LOGIC_APP_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.logicAppName.value" -o tsv | tr -d '\r')
SP_CONNECTION=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.sharePointConnectionName.value" -o tsv | tr -d '\r')
FOUNDRY_ENDPOINT=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.aiFoundryEndpoint.value" -o tsv | tr -d '\r')
PROJECT_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.outputs.projectName.value" -o tsv | tr -d '\r')

log "Storage Account:    ${GREEN}$STORAGE_NAME${NC}"
log "AI Search:          ${GREEN}$AI_SEARCH_NAME${NC}"
log "AI Services:        ${GREEN}$AI_SERVICES_NAME${NC}"
log "Logic App:          ${GREEN}$LOGIC_APP_NAME${NC}"
log "SharePoint Conn:    ${GREEN}$SP_CONNECTION${NC}"
log "Foundry Endpoint:   ${GREEN}$FOUNDRY_ENDPOINT${NC}"
log "Project Name:       ${GREEN}$PROJECT_NAME${NC}"

echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}POST-DEPLOYMENT STEPS REQUIRED${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""
echo -e "${RED}1. Authorize SharePoint Connection:${NC}"
echo "   az resource invoke-action \\"
echo "     --resource-group $RESOURCE_GROUP \\"
echo "     --resource-type Microsoft.Web/connections \\"
echo "     --name $SP_CONNECTION \\"
echo "     --action consentLink \\"
echo "     --api-version 2016-06-01"
echo ""
echo "   Or use Azure Portal:"
echo "   https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/connections/$SP_CONNECTION/edit"
echo ""
echo -e "${RED}2. Enable Logic App after authorizing connections:${NC}"
echo "   az logic workflow update \\"
echo "     --resource-group $RESOURCE_GROUP \\"
echo "     --name $LOGIC_APP_NAME \\"
echo "     --state Enabled"
echo ""
echo -e "${RED}3. Create AI Search Index (see README for details)${NC}"
echo ""
echo -e "${RED}4. Create Foundry Agent:${NC}"
echo "   - Open Azure AI Foundry: https://ai.azure.com"
echo "   - Select project: $PROJECT_NAME"
echo "   - Create Agent with AI Search tool"
echo ""
echo -e "${GREEN}See README.md for detailed post-deployment instructions.${NC}"

# ============================================================================
# Configure Azure AI Search: Data Source, Index, Skillset, and Indexer
# ============================================================================

# Disable exit-on-error for AI Search config (we handle errors explicitly)
set +e

log ""
log "${BLUE}============================================${NC}"
log "${BLUE}Configuring Azure AI Search...${NC}"
log "${BLUE}============================================${NC}"

# Get Storage Account Resource ID for managed identity connection
log "${YELLOW}Getting storage account resource ID...${NC}"

# Validate STORAGE_NAME is set
if [ -z "$STORAGE_NAME" ]; then
    log "${YELLOW}STORAGE_NAME not set, fetching from resource group...${NC}"
    STORAGE_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
fi

if [ -z "$STORAGE_NAME" ]; then
    log "${RED}✗ Could not determine storage account name${NC}"
    exit 1
fi

STORAGE_RESOURCE_ID=$(az storage account show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_NAME" \
    --query id -o tsv 2>/dev/null)

if [ -z "$STORAGE_RESOURCE_ID" ]; then
    log "${RED}✗ Could not get storage resource ID${NC}"
    exit 1
fi
log "${GREEN}✓ Got storage resource ID${NC}"

# Set variables for resource naming
SEARCH_ENDPOINT="https://${AI_SEARCH_NAME}.search.windows.net"
INDEX_NAME="${BASE_NAME}-${ENVIRONMENT}-index"
DATASOURCE_NAME="${BASE_NAME}-${ENVIRONMENT}-datasource"
SKILLSET_NAME="${BASE_NAME}-${ENVIRONMENT}-skillset"
INDEXER_NAME="${BASE_NAME}-${ENVIRONMENT}-indexer"
BLOB_CONTAINER="contracts"

# Get AI Services endpoint (for Content Understanding)
AI_SERVICES_ENDPOINT="https://${AI_SERVICES_NAME}.cognitiveservices.azure.com/"
OPENAI_ENDPOINT="https://${AI_SERVICES_NAME}.openai.azure.com"

log ""
log "Search Endpoint:    ${GREEN}$SEARCH_ENDPOINT${NC}"
log "Index Name:         ${GREEN}$INDEX_NAME${NC}"
log "Data Source:        ${GREEN}$DATASOURCE_NAME${NC}"
log "Skillset:           ${GREEN}$SKILLSET_NAME${NC}"
log "Indexer:            ${GREEN}$INDEXER_NAME${NC}"
log ""

# --- Create Data Source (using managed identity) ---
log "${YELLOW}Creating data source...${NC}"
cat > /tmp/datasource.json << EOF
{
  "name": "$DATASOURCE_NAME",
  "type": "azureblob",
  "credentials": {
    "connectionString": "ResourceId=$STORAGE_RESOURCE_ID;"
  },
  "container": {
    "name": "$BLOB_CONTAINER"
  }
}
EOF

az rest --method PUT \
    --uri "$SEARCH_ENDPOINT/datasources/$DATASOURCE_NAME?api-version=2024-07-01" \
    --headers "Content-Type=application/json" \
    --body @/tmp/datasource.json \
    --resource "https://search.azure.com" \
    -o json > /tmp/datasource-result.json 2>&1 || true

DATASOURCE_CREATED=false
if [ -f /tmp/datasource-result.json ] && ! grep -q "error" /tmp/datasource-result.json; then
    log "${GREEN}✓ Data source created${NC}"
    DATASOURCE_CREATED=true
else
    log "${RED}✗ Failed to create data source:${NC}"
    cat /tmp/datasource-result.json 2>/dev/null || echo "No response received"
fi

# --- Create Index ---
log "${YELLOW}Creating search index...${NC}"
cat > /tmp/index.json << EOF
{
  "name": "$INDEX_NAME",
  "fields": [
    {
      "name": "chunk_id",
      "type": "Edm.String",
      "key": true,
      "searchable": true,
      "filterable": true,
      "sortable": false,
      "facetable": false,
      "analyzer": "keyword"
    },
    {
      "name": "parent_id",
      "type": "Edm.String",
      "searchable": false,
      "filterable": true,
      "sortable": false,
      "facetable": false
    },
    {
      "name": "chunk",
      "type": "Edm.String",
      "searchable": true,
      "filterable": false,
      "sortable": false,
      "facetable": false
    },
    {
      "name": "title",
      "type": "Edm.String",
      "searchable": true,
      "filterable": true,
      "sortable": true,
      "facetable": false
    },
    {
      "name": "text_vector",
      "type": "Collection(Edm.Single)",
      "searchable": true,
      "filterable": false,
      "sortable": false,
      "facetable": false,
      "dimensions": 3072,
      "vectorSearchProfile": "vector-profile"
    }
  ],
  "vectorSearch": {
    "algorithms": [
      {
        "name": "hnsw-algorithm",
        "kind": "hnsw",
        "hnswParameters": {
          "metric": "cosine",
          "m": 4,
          "efConstruction": 400,
          "efSearch": 500
        }
      }
    ],
    "profiles": [
      {
        "name": "vector-profile",
        "algorithm": "hnsw-algorithm"
      }
    ]
  }
}
EOF

az rest --method PUT \
    --uri "$SEARCH_ENDPOINT/indexes/$INDEX_NAME?api-version=2024-07-01" \
    --headers "Content-Type=application/json" \
    --body @/tmp/index.json \
    --resource "https://search.azure.com" \
    -o json > /tmp/index-result.json 2>&1 || true

INDEX_CREATED=false
if [ -f /tmp/index-result.json ] && ! grep -q "error" /tmp/index-result.json; then
    log "${GREEN}✓ Index created${NC}"
    INDEX_CREATED=true
else
    log "${RED}✗ Failed to create index:${NC}"
    cat /tmp/index-result.json 2>/dev/null || echo "No response received"
fi

# --- Create Skillset ---
log "${YELLOW}Creating skillset...${NC}"
cat > /tmp/skillset.json << EOF
{
  "name": "$SKILLSET_NAME",
  "description": "Skillset to extract content using Content Understanding and generate embeddings",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Util.ContentUnderstandingSkill",
      "name": "#1",
      "description": "Extract and chunk content using Content Understanding",
      "context": "/document",
      "extractionOptions": ["images", "locationMetadata"],
      "inputs": [
        {
          "name": "file_data",
          "source": "/document/file_data"
        }
      ],
      "outputs": [
        {
          "name": "text_sections",
          "targetName": "text_sections"
        },
        {
          "name": "normalized_images",
          "targetName": "normalized_images"
        }
      ],
      "chunkingProperties": {
        "unit": "characters",
        "maximumLength": 2000,
        "overlapLength": 200
      }
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "#2",
      "description": "Generate embeddings for each text section",
      "context": "/document/text_sections/*",
      "resourceUri": "$OPENAI_ENDPOINT",
      "deploymentId": "text-embedding-3-large",
      "dimensions": 3072,
      "modelName": "text-embedding-3-large",
      "inputs": [
        {
          "name": "text",
          "source": "/document/text_sections/*/content"
        }
      ],
      "outputs": [
        {
          "name": "embedding",
          "targetName": "text_vector"
        }
      ]
    }
  ],
  "cognitiveServices": {
    "@odata.type": "#Microsoft.Azure.Search.AIServicesByIdentity",
    "description": "Keyless connection using managed identity",
    "subdomainUrl": "$AI_SERVICES_ENDPOINT"
  },
  "indexProjections": {
    "selectors": [
      {
        "targetIndexName": "$INDEX_NAME",
        "parentKeyFieldName": "parent_id",
        "sourceContext": "/document/text_sections/*",
        "mappings": [
          {
            "name": "text_vector",
            "source": "/document/text_sections/*/text_vector"
          },
          {
            "name": "chunk",
            "source": "/document/text_sections/*/content"
          },
          {
            "name": "title",
            "source": "/document/title"
          }
        ]
      }
    ],
    "parameters": {
      "projectionMode": "skipIndexingParentDocuments"
    }
  }
}
EOF

az rest --method PUT \
    --uri "$SEARCH_ENDPOINT/skillsets/$SKILLSET_NAME?api-version=2025-11-01-Preview" \
    --headers "Content-Type=application/json" \
    --body @/tmp/skillset.json \
    --resource "https://search.azure.com" \
    -o json > /tmp/skillset-result.json 2>&1 || true

SKILLSET_CREATED=false
if [ -f /tmp/skillset-result.json ] && ! grep -q "error" /tmp/skillset-result.json; then
    log "${GREEN}✓ Skillset created${NC}"
    SKILLSET_CREATED=true
else
    log "${RED}✗ Failed to create skillset:${NC}"
    cat /tmp/skillset-result.json 2>/dev/null || echo "No response received"
fi

# --- Create Indexer ---
log "${YELLOW}Creating indexer...${NC}"
cat > /tmp/indexer.json << EOF
{
  "name": "$INDEXER_NAME",
  "dataSourceName": "$DATASOURCE_NAME",
  "skillsetName": "$SKILLSET_NAME",
  "targetIndexName": "$INDEX_NAME",
  "parameters": {
    "configuration": {
      "parsingMode": "default",
      "allowSkillsetToReadFileData": true
    }
  },
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_storage_name",
      "targetFieldName": "title"
    }
  ],
  "outputFieldMappings": []
}
EOF

az rest --method PUT \
    --uri "$SEARCH_ENDPOINT/indexers/$INDEXER_NAME?api-version=2025-11-01-Preview" \
    --headers "Content-Type=application/json" \
    --body @/tmp/indexer.json \
    --resource "https://search.azure.com" \
    -o json > /tmp/indexer-result.json 2>&1 || true

INDEXER_CREATED=false
if [ -f /tmp/indexer-result.json ] && ! grep -q "error" /tmp/indexer-result.json; then
    log "${GREEN}✓ Indexer created${NC}"
    INDEXER_CREATED=true
else
    log "${RED}✗ Failed to create indexer:${NC}"
    cat /tmp/indexer-result.json 2>/dev/null || echo "No response received"
fi

# --- Run Indexer ---
log "${YELLOW}Starting indexer...${NC}"
az rest --method POST \
    --uri "$SEARCH_ENDPOINT/indexers/$INDEXER_NAME/run?api-version=2025-11-01-Preview" \
    --resource "https://search.azure.com" \
    -o none 2>/dev/null || true

log "${GREEN}✓ Indexer started${NC}"

# Clean up temp files
rm -f /tmp/datasource.json /tmp/index.json /tmp/skillset.json /tmp/indexer.json
rm -f /tmp/datasource-result.json /tmp/index-result.json /tmp/skillset-result.json /tmp/indexer-result.json

# Summary
log ""
log "${BLUE}============================================${NC}"
log "${BLUE}AI Search Configuration Summary${NC}"
log "${BLUE}============================================${NC}"
log ""
if $DATASOURCE_CREATED; then
    log "  Data Source:  ${GREEN}✓ Created${NC}"
else
    log "  Data Source:  ${RED}✗ Failed${NC}"
fi
if $INDEX_CREATED; then
    log "  Index:        ${GREEN}✓ Created${NC}"
else
    log "  Index:        ${RED}✗ Failed${NC}"
fi
if $SKILLSET_CREATED; then
    log "  Skillset:     ${GREEN}✓ Created${NC}"
else
    log "  Skillset:     ${RED}✗ Failed${NC}"
fi
if $INDEXER_CREATED; then
    log "  Indexer:      ${GREEN}✓ Created${NC}"
else
    log "  Indexer:      ${RED}✗ Failed${NC}"
fi
log ""

if $DATASOURCE_CREATED && $INDEX_CREATED && $SKILLSET_CREATED && $INDEXER_CREATED; then
    log "${GREEN}============================================${NC}"
    log "${GREEN}✓ AI Search configuration complete!${NC}"
    log "${GREEN}============================================${NC}"
    log ""
    log "Monitor indexer status at:"
    log "${BLUE}$SEARCH_ENDPOINT/indexers/$INDEXER_NAME/status?api-version=2025-11-01-Preview${NC}"
else
    log "${RED}============================================${NC}"
    log "${RED}✗ AI Search configuration incomplete${NC}"
    log "${RED}============================================${NC}"
    log ""
    log "Some resources failed to create. Check the errors above."
    exit 1
fi
