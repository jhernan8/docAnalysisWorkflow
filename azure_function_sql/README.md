# Contract Analysis Azure Function (Azure SQL)

Azure Function that analyzes contracts using Azure Content Understanding and stores results in Azure SQL Database.

## Deployment

> **Recommended:** Use the infrastructure-as-code deployment in `/infra/`. It automatically provisions and configures everything.

```bash
cd infra
./deploy.sh
```

The deploy script handles:

- ✅ Creating the Function App with Flex Consumption plan
- ✅ Enabling managed identity
- ✅ Configuring all environment variables
- ✅ Granting Cognitive Services access (RBAC role)
- ✅ Granting Storage access (RBAC roles)
- ✅ Creating SQL database tables
- ✅ Creating SQL user for managed identity
- ✅ Deploying the function code

See [/infra/README.md](../infra/README.md) for full details.

---

## Endpoint

### `POST /api/analyze-and-store`

Analyzes a contract and stores results in Azure SQL.

**Request Formats:**

```http
# Option A: Binary PDF
POST /api/analyze-and-store
Content-Type: application/pdf
X-Filename: my-contract.pdf

<binary PDF content>
```

```http
# Option B: JSON with Base64
POST /api/analyze-and-store
Content-Type: application/json

{
    "filename": "my-contract.pdf",
    "content": "<base64-encoded PDF>"
}
```

**Response:**

```json
{
  "filename": "contract.pdf",
  "title": "Service Agreement",
  "parties": [{ "name": "Company A", "address": "123 Main St" }],
  "dates": { "EffectiveDate": "2025-01-01" },
  "duration": "12 months",
  "jurisdictions": ["California"],
  "clauses": [
    { "type": "Termination", "title": "Early Termination", "text": "..." }
  ],
  "database": {
    "contract_id": 1,
    "party_ids": [1, 2],
    "clause_ids": [1, 2, 3]
  }
}
```

## Manual Setup (if not using infra deployment)

<details>
<summary>Click to expand manual setup steps</summary>

### 1. Create Tables

Connect to Azure SQL (using Azure Data Studio, SSMS, or VS Code) and run `create_tables.sql`.

### 2. Create Function App on Portal

### 3. Enable Managed Identity Settings -> Identity

### 4. Grant Database Access

Connect to Azure SQL as the Azure AD admin and run:

```sql
-- Create user from managed identity
CREATE USER [<function-app-name>] FROM EXTERNAL PROVIDER;

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [<function-app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<function-app-name>];
```

### 5. Grant Cognitive Services Access

```bash
# Get managed identity principal ID
PRINCIPAL_ID=$(az functionapp identity show \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --query principalId -o tsv)

# Grant Cognitive Services User role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Cognitive Services User" \
  --scope <content-understanding-resource-id>
```

### 6. Configure App Settings

```bash
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --settings \
    CONTENT_UNDERSTANDING_ENDPOINT="https://<resource>.cognitiveservices.azure.com" \
    CONTENT_UNDERSTANDING_ANALYZER_ID="<analyzer-id>" \
    SQL_SERVER="<server-name>" \
    SQL_DATABASE="<database-name>"
```

## Deploy

```bash
func azure functionapp publish <function-app-name> --python
```

</details>

## Environment Variables

These are automatically configured by the `/infra/deploy.sh` script. Only relevant for manual setup or local development.

| Variable                            | Description                                           | Set By Infra |
| ----------------------------------- | ----------------------------------------------------- | ------------ |
| `CONTENT_UNDERSTANDING_ENDPOINT`    | Azure Content Understanding endpoint                  | ✅ Yes       |
| `CONTENT_UNDERSTANDING_ANALYZER_ID` | Analyzer ID (must create analyzer in Portal)          | ✅ Yes       |
| `CONTENT_UNDERSTANDING_API_VERSION` | API version (default: 2025-11-01)                     | ✅ Yes       |
| `SQL_SERVER`                        | Azure SQL server name (without .database.windows.net) | ✅ Yes       |
| `SQL_DATABASE`                      | Database name                                         | ✅ Yes       |

## Logic App Integration

The Logic App is automatically configured by the infra deployment. It uses a SharePoint trigger and passes the function key in headers.

Example HTTP action (for reference):

```json
{
  "method": "POST",
  "uri": "https://<function-app>.azurewebsites.net/api/analyze-and-store",
  "headers": {
    "Content-Type": "application/json",
    "x-functions-key": "<function-key>"
  },
  "body": {
    "filename": "@{triggerBody()?['{Name}']}",
    "content": "@{base64(body('Get_file_content'))}"
  }
}
```
