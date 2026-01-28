# Infrastructure as Code - Contract Analysis Solution

Bicep templates for deploying the complete Contract Analysis solution to Azure.

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
                   │  Services       │        │   Database      │                   │
                   │  (Content       │        │                 │                   │
                   │  Understanding) │        │                 │                   │
                   └─────────────────┘        └─────────────────┘                   │
                                                                                    │
                   ┌─────────────────┐        ┌─────────────────┐                   │
                   │  Application    │        │  Log Analytics  │◀──────────────────┘
                   │  Insights       │        │  Workspace      │
                   └─────────────────┘        └─────────────────┘
```

## Resources Deployed

| Resource                  | Description                                              |
| ------------------------- | -------------------------------------------------------- |
| **Storage Account**       | Function App storage (managed identity)                  |
| **Logic App**             | Triggers on SharePoint file upload, calls Function App   |
| **SharePoint Connection** | API connection for SharePoint Online (requires OAuth)    |
| **Function App**          | Python function for contract analysis (Consumption plan) |
| **App Service Plan**      | Consumption tier for Function App                        |
| **Azure AI Services**     | Content Understanding for document analysis              |
| **Azure SQL Server**      | Managed SQL instance                                     |
| **Azure SQL Database**    | Contract storage (Basic tier)                            |
| **Log Analytics**         | Centralized logging                                      |
| **Application Insights**  | Function App monitoring                                  |

## Permissions Configured

The deployment automatically configures:

| Principal          | Target          | Role                               |
| ------------------ | --------------- | ---------------------------------- |
| Function App (MSI) | AI Services     | Cognitive Services User            |
| Function App (MSI) | Storage Account | Storage Blob/Queue/Table/File Data |

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
| Create AI Services     | `Microsoft.CognitiveServices/accounts/write`                           |                                         |
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

```bash
cd infra
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
  --parameters sqlAdminPassword='YourSecurePassword123!' \
  --parameters sqlAadAdminObjectId='your-object-id' \
  --parameters sqlAadAdminDisplayName='your@email.com' \
  --parameters contentUnderstandingAnalyzerId='contract-analyzer' \
  --parameters sharePointSiteUrl='https://contoso.sharepoint.com/sites/ContractAI' \
  --parameters sharePointLibraryId='your-library-guid'

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
3. Note the Analyzer ID
4. Update the Function App setting:
   ```bash
   az functionapp config appsettings set -g contract-analysis-rg -n <function-app-name> --settings CONTENT_UNDERSTANDING_ANALYZER_ID=<your-analyzer-id>
   ```

### 3. Authorize SharePoint Connection

1. Go to Azure Portal → Resource Group → API Connections
2. Click on the SharePoint connection
3. Click "Edit API connection"
4. Click "Authorize" and sign in with your SharePoint account
5. Click "Save"

### 4. Enable Logic App

1. Go to Azure Portal → Logic Apps
2. Select your Logic App
3. Click "Enable"

### 5. Test the Solution

Upload a PDF contract to your SharePoint document library.

## What the Deploy Script Does

The `deploy.sh` script automates the deployment:

1. ✅ Creates the resource group
2. ✅ Deploys all Azure resources via Bicep
3. ✅ Deploys the Function App code
4. ✅ Configures Logic App with Function key
5. ✅ Configures all RBAC permissions

**Remaining manual steps after running the script:**

- Authorize the SharePoint connection in Azure Portal
- Create the Content Understanding analyzer in Azure Portal
- Enable the Logic App

## Parameters

| Parameter                        | Description                           | Required | Default                 |
| -------------------------------- | ------------------------------------- | -------- | ----------------------- |
| `baseName`                       | Base name for resources (3-15 chars)  | Yes      | -                       |
| `environment`                    | Environment name (dev/staging/prod)   | No       | dev                     |
| `location`                       | Azure region                          | No       | Resource group location |
| `sqlAdminUsername`               | SQL admin username                    | No       | sqladmin                |
| `sqlAdminPassword`               | SQL admin password                    | Yes      | -                       |
| `sqlAadAdminObjectId`            | Azure AD admin Object ID              | Yes      | -                       |
| `sqlAadAdminDisplayName`         | Azure AD admin display name           | Yes      | -                       |
| `contentUnderstandingAnalyzerId` | Analyzer ID                           | Yes      | -                       |
| `sharePointSiteUrl`              | SharePoint site URL                   | Yes      | -                       |
| `sharePointLibraryId`            | SharePoint document library ID (GUID) | Yes      | -                       |

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
- **AI Services**: `modules/ai-services.bicep` - Already using S0

## Troubleshooting

### Function App can't connect to SQL

1. Verify the managed identity exists: `az functionapp identity show --name <func-name> --resource-group <rg>`
2. Check the SQL user was created: `SELECT name FROM sys.database_principals WHERE type = 'E'`
3. Verify firewall allows Azure services: Check SQL Server → Networking

### Logic App trigger not firing

1. Ensure Logic App is enabled
2. Check the blob connection is authorized
3. Verify files are in the `/contracts` container
4. Check Logic App run history for errors

### Content Understanding errors

1. Verify the analyzer exists and is published
2. Check the endpoint and analyzer ID in Function App settings
3. Ensure the Function App has Cognitive Services User role

## Clean Up

To delete all resources:

```bash
az group delete --name contract-analysis-rg --yes --no-wait
```
