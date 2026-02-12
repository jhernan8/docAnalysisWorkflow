# Infrastructure as Code - Contract Analysis Solution

Bicep templates for deploying the complete Contract Analysis solution to Azure with private endpoints, VNet integration, and Logic App Standard.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   SharePoint    │────▶│   Logic App     │────▶│  Function App   │
│   Document      │     │  (SharePoint    │     │  (Python)       │
│   Library       │     │   Trigger)      │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                              ┌──────────────────────────┼──────────────────────────┐
                              │                          │                          │
                              ▼                          ▼                          │
                   ┌─────────────────┐        ┌─────────────────┐                   │
                   │  Azure AI       │        │   Azure SQL     │                   │
                   │  Foundry        │        │   Database      │                   │
                   │  (Content       │        │                 │                   │
                   │  Understanding) │        │                 │                   │
                   │  *Manual Setup* │        │                 │                   │
                   └─────────────────┘        └─────────────────┘                   │
                                                                                    │
                   ┌─────────────────┐        ┌─────────────────┐                   │
                   │  Application    │        │  Log Analytics  │◀──────────────────┘
                   │  Insights       │        │  Workspace      │
                   └─────────────────┘        └─────────────────┘
```

### Private Endpoint Topology

```
┌────────────────────────────────────────────────────────────────┐
│  Existing VNet (cai-a1-tst-vnet-spoke01)                       │
│                                                                │
│  ┌──────────────────────────┐  ┌─────────────────────────────┐ │
│  │ snet-private-endpoints   │  │ snet-func-integration       │ │
│  │                          │  │ (delegated: Web/serverFarms) │ │
│  │  PE: Storage (blob)      │  │                             │ │
│  │  PE: Storage (file)      │  │  Function App outbound ────┼─┤
│  │  PE: Storage (queue)     │  │  VNet integration           │ │
│  │  PE: Storage (table)     │  └─────────────────────────────┘ │
│  │  PE: Azure SQL Server    │                                  │
│  │  PE: Function App        │  ┌─────────────────────────────┐ │
│  │  PE: Logic App Standard  │  │ snet-logic-integration       │ │
│  └──────────────────────────┘  │ (delegated: Web/serverFarms) │ │
│                                  │                             │ │
│                                  │  Logic App outbound ──────┼─┤
│                                  │  VNet integration           │ │
│                                  └─────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
         │
         ▼
  Private DNS Zones (cross-subscription)
```

## Resources Deployed

| Resource                  | Description                                                           |
| ------------------------- | --------------------------------------------------------------------- |
| **Storage Account**       | Function App storage (managed identity)                               |
| **Logic App**             | Standard tier; triggers on SharePoint file upload, calls Function App |
| **SharePoint Connection** | API connection for SharePoint Online (requires OAuth)                 |
| **Function App**          | Python function for contract analysis (Flex Consumption plan)         |
| **App Service Plan**      | Flex Consumption for Function App, WS1 for Logic App Standard         |
| **Azure SQL Server**      | Managed SQL instance                                                  |
| **Azure SQL Database**    | Contract storage (Basic tier)                                         |
| **Log Analytics**         | Centralized logging                                                   |
| **Application Insights**  | Function App monitoring                                               |

> **Note:** (Content Understanding) must be created manually in the same resource group after deployment.

## Permissions Configured

The deployment automatically configures:

| Principal          | Target          | Role                               |
| ------------------ | --------------- | ---------------------------------- |
| Function App (MSI) | Resource Group  | Cognitive Services User            |
| Function App (MSI) | Storage Account | Storage Blob/Queue/Table/File Data |
| Logic App (MSI)    | Storage Account | Storage Blob/Queue/Table/File Data |

> **Note:** The SharePoint connection requires interactive OAuth consent after deployment.

## Prerequisites

1. **Azure CLI** installed and logged in ([Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli))
2. **Azure Functions Core Tools** for deploying function code ([Install Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local#install-the-azure-functions-core-tools))
3. **Bicep CLI** (included with Azure CLI 2.20+) ([Install Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install))
4. A **SharePoint Online** site with a document library for contracts
5. An Azure subscription with permissions to create resources

## Required Azure Permissions for Deployment

The user running `deploy.sh` needs the following Azure RBAC roles:

### Minimum Required Roles

| Scope        | Role                          | Purpose                                               |
| ------------ | ----------------------------- | ----------------------------------------------------- |
| Subscription | **Contributor**               | Create resource groups and deploy all Azure resources |
| Subscription | **User Access Administrator** | Assign RBAC roles to managed identities               |

> **Recommended:** Assign both roles at the subscription level, or use the built-in **Owner** role which includes both.

### Alternative: Scoped Permissions

If you cannot grant subscription-level access, assign these roles at the resource group level (create the RG first):

| Scope          | Role                                        | Purpose                        |
| -------------- | ------------------------------------------- | ------------------------------ |
| Resource Group | **Contributor**                             | Deploy resources within the RG |
| Resource Group | **Role Based Access Control Administrator** | Assign roles within the RG     |

### Detailed Permission Breakdown

| Operation              | Required Permission                                                    | Notes                                   |
| ---------------------- | ---------------------------------------------------------------------- | --------------------------------------- |
| Create Resource Group  | `Microsoft.Resources/subscriptions/resourceGroups/write`               | Subscription scope                      |
| Deploy Bicep Template  | `Microsoft.Resources/deployments/write`                                | Resource group scope                    |
| Create Storage Account | `Microsoft.Storage/storageAccounts/write`                              |                                         |
| Create Function App    | `Microsoft.Web/sites/write`, `Microsoft.Web/serverfarms/write`         |                                         |
| Create Logic App       | `Microsoft.Logic/workflows/write`                                      |                                         |
| Create SQL Server/DB   | `Microsoft.Sql/servers/write`, `Microsoft.Sql/servers/databases/write` |                                         |
| Create Log Analytics   | `Microsoft.OperationalInsights/workspaces/write`                       |                                         |
| Create App Insights    | `Microsoft.Insights/components/write`                                  |                                         |
| Assign RBAC Roles      | `Microsoft.Authorization/roleAssignments/write`                        | For managed identity permissions        |
| Get Function Keys      | `Microsoft.Web/sites/host/listkeys/action`                             | For Logic App to call Function          |
| Create SQL Users       | Azure AD admin on SQL Server                                           | Set via `sqlAadAdminObjectId` parameter |

### Additional Requirements

| Requirement           | Details                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------ |
| **SharePoint Access** | User must have access to authorize the SharePoint API connection (Site Member or higher)         |
| **Azure AD**          | User must be able to read their own Object ID (`az ad signed-in-user show`)                      |
| **SQL Admin**         | The deploying user should be set as the Azure AD admin for SQL to run the table creation scripts |

### Quick Permission Check

Run these commands to verify you have the required permissions:

```bash
# Check your current roles at subscription level
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --query "[].roleDefinitionName" -o tsv

# Check if you can create resource groups
az group create --name test-permissions-rg --location eastus --dry-run

# Check your Azure AD Object ID (needed for SQL admin)
az ad signed-in-user show --query id -o tsv
```

## Quick Start

### Option 1: Using the deploy script

Requires an existing VNet and Private DNS Zones (can be in a different subscription).

```bash
cd infra_sql
chmod +x deploy.sh
./deploy.sh
```

### Option 2: Manual deployment

```bash
# 1. Create resource group
az group create --name contract-analysis-rg --location eastus

# 2. Get your Azure AD Object ID
az ad signed-in-user show --query id -o tsv

# 3. Deploy infrastructure
az deployment group create \
  --resource-group contract-analysis-rg \
  --template-file main.bicep \
  --parameters baseName=contracts \
  --parameters environment=dev \
  --parameters sqlAadAdminObjectId='your-object-id' \
  --parameters sqlAadAdminDisplayName='your@email.com' \
  --parameters sharePointSiteUrl='https://contoso.sharepoint.com/sites/ContractAI' \
  --parameters sharePointLibraryId='your-library-guid' \
  --parameters vnetName='cai-a1-tst-vnet-spoke01' \
  --parameters vnetResourceGroupName='your-vnet-rg' \
  --parameters privateEndpointSubnetAddressPrefix='10.0.4.0/24' \
  --parameters vnetIntegrationSubnetAddressPrefix='10.0.5.0/24' \
  --parameters logicAppSubnetAddressPrefix='10.0.6.0/24' \
  --parameters dnsZoneSubscriptionId='your-dns-sub-id' \
  --parameters dnsZoneResourceGroupName='your-dns-rg'

# 4. Deploy function code
cd ../azure_function_sql
func azure functionapp publish <function-app-name> --python
```

## Post-Deployment Steps

### 1. Run SQL Setup Scripts

Connect to the SQL database using your preferred tool (Azure Portal Query Editor, SSMS, Azure Data Studio, or sqlcmd):

- **Server:** `<your-sql-server>.database.windows.net`
- **Database:** `contractsdb`

Then run:

```sql
-- First, run create_tables.sql to create the schema

-- Then grant the Function App access (replace with your function app name from deploy output):
CREATE USER [<function-app-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<function-app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<function-app-name>];
```

### 2. Create Content Understanding Analyzer

1. Go to Azure AI Foundry → Content Understanding
2. Create a new analyzer with your contract schema
3. Note the **Project Endpoint** (e.g., `https://<project>.services.ai.azure.com`)
4. Note the **Analyzer ID** you create
5. Update the Function App setting:
   ```bash
   az functionapp config appsettings set -g contract-analysis-rg -n <function-app-name> \
     --settings CONTENT_UNDERSTANDING_ENDPOINT=<your-foundry-endpoint> \
     CONTENT_UNDERSTANDING_ANALYZER_ID=<your-analyzer-id>
   ```

### 3. Authorize SharePoint Connection

1. Go to Azure Portal → Resource Group → API Connections
2. Click on the SharePoint connection
3. Click "Edit API connection"
4. Click "Authorize" and sign in with your SharePoint account
5. Click "Save"

### 4. Test the Solution

Upload a PDF contract to your SharePoint document library.

## What the Deploy Script Does

The `deploy.sh` script automates the full deployment:

1. ✅ Creates the resource group
2. ✅ Deploys all Azure resources via Bicep
3. ✅ Creates PE + VNet integration subnets on existing VNet
4. ✅ Deploys private endpoints (Storage blob/file/queue/table, SQL, Function App, Logic App)
5. ✅ Registers endpoints with cross-subscription Private DNS Zones
6. ✅ Disables public network access on Storage, SQL, Function App, and Logic App
7. ✅ Deploys the Function App code (temporarily enables storage public access)
8. ✅ Deploys Logic App Standard workflow definition via zip deploy
9. ✅ Configures all RBAC permissions

**Remaining manual steps after running the script:**

- Create Content Understanding analyzer and update Function App settings
- Authorize the SharePoint connection in Azure Portal
- Enable the Logic App

## Parameters

| Parameter                            | Description                           | Required | Default                 |
| ------------------------------------ | ------------------------------------- | -------- | ----------------------- |
| `baseName`                           | Base name for resources (3-15 chars)  | Yes      | -                       |
| `environment`                        | Environment name (dev/staging/prod)   | No       | dev                     |
| `location`                           | Azure region                          | No       | Resource group location |
| `sqlLocation`                        | Azure region for SQL                  | No       | centralus               |
| `sqlAadAdminObjectId`                | Azure AD admin Object ID              | Yes      | -                       |
| `sqlAadAdminDisplayName`             | Azure AD admin display name           | Yes      | -                       |
| `sharePointSiteUrl`                  | SharePoint site URL                   | Yes      | -                       |
| `sharePointLibraryId`                | SharePoint document library ID (GUID) | Yes      | -                       |
| `vnetName`                           | Name of existing VNet                 | Yes      | -                       |
| `vnetResourceGroupName`              | Resource group of the VNet            | Yes      | -                       |
| `privateEndpointSubnetAddressPrefix` | CIDR for PE subnet                    | Yes      | -                       |
| `vnetIntegrationSubnetAddressPrefix` | CIDR for Function App outbound subnet | Yes      | -                       |
| `logicAppSubnetAddressPrefix`        | CIDR for Logic App outbound subnet    | Yes      | -                       |
| `dnsZoneSubscriptionId`              | Subscription ID for Private DNS Zones | Yes      | -                       |
| `dnsZoneResourceGroupName`           | Resource group for Private DNS Zones  | Yes      | -                       |

## Finding Your SharePoint Library ID

To find the GUID of your SharePoint document library:

1. **Via Browser URL:**
   - Go to your SharePoint library settings
   - Look at the URL: `.../_layouts/15/listedit.aspx?List=%7B<GUID>%7D`
   - The GUID is between `%7B` and `%7D` (URL-encoded `{` and `}`)

2. **Via REST API:**

   ```bash
   # Lists all document libraries with their IDs
   curl "https://yourtenant.sharepoint.com/sites/YourSite/_api/web/lists?\$filter=BaseTemplate eq 101" \
     -H "Accept: application/json"
   ```

3. **Via SharePoint UI:**
   - Go to Site Contents → Click on the library → Library Settings
   - The List ID is in the URL

## Customization

### Change SKUs/Tiers

Edit the module files to change resource SKUs:

- **SQL Database**: `modules/sql.bicep` - Change `sku.name` from 'Basic' to 'Standard' etc.
- **Function App**: `modules/function-app.bicep` - Change to Premium plan for more resources

## Troubleshooting

### Function App can't connect to SQL

1. Verify the managed identity exists: `az functionapp identity show --name <func-name> --resource-group <rg>`
2. Check the SQL user was created: `SELECT name FROM sys.database_principals WHERE type = 'E'`
3. Verify the SQL private endpoint is healthy and DNS resolves correctly

### Logic App trigger not firing

1. Check the SharePoint connection is authorized
2. Verify files are in the correct SharePoint library
3. Check Logic App run history for errors
4. Ensure the Logic App workflow was deployed (`az logicapp deployment source config-zip`)

### Content Understanding errors

1. Verify the analyzer exists and is published
2. Check the endpoint and analyzer ID in Function App settings
3. Ensure the Function App has Cognitive Services User role

### Private endpoint DNS resolution issues

1. Verify all Private DNS Zones have VNet links to your spoke VNet
2. Required zones: `privatelink.blob.core.windows.net`, `privatelink.file.core.windows.net`, `privatelink.queue.core.windows.net`, `privatelink.table.core.windows.net`, `privatelink.database.windows.net`, `privatelink.azurewebsites.net`
3. Test resolution from a VM in the VNet: `nslookup <storage-account>.blob.core.windows.net`
4. The result should return a private IP (e.g., `10.x.x.x`), not a public IP

### Function App deployment fails

The deploy script temporarily enables public access on the storage account for code deployment. If it fails mid-way, re-enable public access manually:

```bash
az storage account update -g <rg> -n <storage> --public-network-access Enabled
```

After deploying, disable it again:

```bash
az storage account update -g <rg> -n <storage> --public-network-access Disabled
```

## Clean Up

To delete all resources:

```bash
az group delete --name contract-analysis-rg --yes --no-wait
```
