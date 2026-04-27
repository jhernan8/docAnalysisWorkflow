# ============================================================================
# DAB MCP Server - Deployment Configuration
#
# INSTRUCTIONS:
#   1. Fill in the required values below (marked REQUIRED).
#      All values reference your existing infra_sql deployment.
#   2. Run deploy.sh from bash/WSL/Cloud Shell:
#        cd infra_mcp && bash deploy.sh
#   3. After deployment, grant SQL access as shown in the script output.
#
# To find values from your existing deployment:
#   az deployment group show -g contract-analysis-rg -n main --query "properties.outputs" -o json
# ============================================================================

# Resource group where the MCP Server will be deployed
# (can be the same as infra_sql or a different one — SQL Server must be in same sub)
$RESOURCE_GROUP = "contract-analysis-rg"
$LOCATION = "eastus"

# REQUIRED — Existing SQL Server name from infra_sql (short name, not FQDN)
# Find with: az deployment group show -g contract-analysis-rg -n main --query "properties.outputs.sqlServerName.value" -o tsv
$SQL_SERVER_NAME = ""          # e.g., "contracts-dev-sql-a1b2c3d4"
$SQL_DATABASE = "contractsdb"

# REQUIRED — Existing VNet (check infra_sql/main.bicepparam for vnetName / vnetResourceGroupName)
$VNET_NAME = "cai-a1-tst-vnet-spoke01"
$VNET_RESOURCE_GROUP = ""      # e.g., "network-rg"

# REQUIRED — Container Apps subnet address prefix (must NOT overlap existing subnets, minimum /23)
# Check existing subnets: az network vnet subnet list -g <VNET_RESOURCE_GROUP> --vnet-name <VNET_NAME> -o table
$CA_SUBNET_PREFIX = ""         # e.g., "10.0.8.0/23"

# OPTIONAL — ACR name. Leave empty to auto-create a new one.
$ACR_NAME = ""                 # e.g., "acrcontractsmcp1234"

# REQUIRED — Private DNS Zone location (check infra_sql/main.bicepparam for dnsZone* values)
$DNS_ZONE_SUBSCRIPTION_ID = "" # e.g., "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$DNS_ZONE_RESOURCE_GROUP = ""  # e.g., "dns-zones-rg"
