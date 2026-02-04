#!/bin/bash
# ============================================================================
# Contract Search Solution - Cleanup Script
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 -g <resource-group>"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${RED}Error: Resource group is required${NC}"
    echo "Usage: $0 -g <resource-group>"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will delete ALL resources in resource group: $RESOURCE_GROUP${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${YELLOW}Deleting resource group...${NC}"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo -e "${GREEN}✓ Resource group deletion initiated (running in background)${NC}"
echo "Run 'az group show -n $RESOURCE_GROUP' to check status"
