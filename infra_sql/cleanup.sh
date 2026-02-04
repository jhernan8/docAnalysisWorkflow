#!/bin/bash

# ============================================================================
# Contract Analysis Solution - Cleanup Script
# Deletes resource group and purges soft-deleted resources
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - must match deploy.sh
RESOURCE_GROUP="contract-analysis-rg"
BASE_NAME="contracts"

echo -e "${RED}========================================${NC}"
echo -e "${RED}Contract Analysis Solution - CLEANUP${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}This will permanently delete:${NC}"
echo "  - Resource group: $RESOURCE_GROUP"
echo "  - All resources inside (Function App, SQL, Storage, etc.)"
echo "  - Purge soft-deleted AI Services resources"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

# Function to purge soft-deleted AI Services
purge_deleted_ai_services() {
    NAMES=$(az cognitiveservices account list-deleted --query "[?contains(name, '${BASE_NAME}')].name" -o tsv 2>/dev/null | tr -d '\r')
    
    if [[ -z "$NAMES" ]]; then
        echo -e "${YELLOW}No soft-deleted AI Services found.${NC}"
        return
    fi
    
    LOCATIONS=$(az cognitiveservices account list-deleted --query "[?contains(name, '${BASE_NAME}')].location" -o tsv | tr -d '\r')
    
    # Convert to arrays
    readarray -t name_array <<< "$NAMES"
    readarray -t location_array <<< "$LOCATIONS"
    
    # Iterate and purge each
    for i in "${!name_array[@]}"; do
        name="${name_array[$i]}"
        location="${location_array[$i]}"
        if [[ -n "$name" && -n "$location" ]]; then
            echo "Purging $name in $location..."
            if az cognitiveservices account purge \
                --name "$name" \
                --resource-group "$RESOURCE_GROUP" \
                --location "$location" 2>/dev/null; then
                echo -e "${GREEN}  ✓ Purged $name${NC}"
            else
                echo -e "${YELLOW}  ⚠ Could not purge $name (may already be purged)${NC}"
            fi
        fi
    done
}

# Step 1: Purge any pre-existing soft-deleted resources
echo -e "\n${YELLOW}Step 1: Purging pre-existing soft-deleted AI Services...${NC}"
purge_deleted_ai_services

# Step 2: Delete resource group
echo -e "\n${YELLOW}Step 2: Deleting resource group...${NC}"
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    az group delete --name "$RESOURCE_GROUP" --yes
    echo -e "${GREEN}✓ Resource group deleted${NC}"
else
    echo -e "${YELLOW}Resource group does not exist, skipping...${NC}"
fi

# Step 3: Purge newly soft-deleted resources (from RG deletion)
echo -e "\n${YELLOW}Step 3: Purging newly soft-deleted AI Services...${NC}"
purge_deleted_ai_services

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "You can now run ./deploy.sh for a fresh deployment."
