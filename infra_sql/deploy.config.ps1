# ============================================================================
# Contract Analysis Solution - Deployment Configuration
# Fill in these values once. They will be loaded automatically by deploy.ps1.
# ============================================================================

# Configuration - CUSTOMIZE THESE
$RESOURCE_GROUP = "contract-analysis-rg"
$LOCATION = "eastus"        # Primary location for Function App, Storage, AI Services
$SQL_LOCATION = "centralus" # SQL location (some regions have restrictions)
$BASE_NAME = "contracts"
$ENVIRONMENT = "dev"

# Networking Configuration
$VNET_NAME = "cai-a1-tst-vnet-spoke01"
$VNET_RESOURCE_GROUP = ""          # Resource group of the existing VNet
$PE_SUBNET_PREFIX = ""             # e.g., "10.0.4.0/24"
$FUNC_SUBNET_PREFIX = ""          # e.g., "10.0.5.0/24"
$LOGIC_SUBNET_PREFIX = ""         # e.g., "10.0.6.0/24"
$DNS_ZONE_SUBSCRIPTION_ID = ""    # Subscription ID where Private DNS Zones live
$DNS_ZONE_RESOURCE_GROUP = ""     # Resource group containing Private DNS Zones

# Azure AD Configuration - FILL THESE IN to skip prompts
$AAD_OBJECT_ID = ""          # Your Azure AD Object ID (run: az ad signed-in-user show --query id -o tsv)
$AAD_DISPLAY_NAME = ""       # Your Azure AD display name / email / UPN

# SharePoint Configuration - FILL THESE IN to skip prompts
$SHAREPOINT_SITE_URL = ""    # e.g., "https://contoso.sharepoint.com/sites/ContractAI"
$SHAREPOINT_LIBRARY_ID = ""  # e.g., "0c082b7c-8834-480c-8b30-47ba73e8562c"
