# Contract Analysis Azure Function (Azure SQL)

Azure Function that analyzes contracts using Azure Content Understanding and stores results in Azure SQL Database.

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

## Setup

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

### 6. Grant Cognitive Services Access

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

### 7. Configure App Settings

```bash
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --settings \
    CONTENT_UNDERSTANDING_ENDPOINT="https://<resource>.cognitiveservices.azure.com" \
    CONTENT_UNDERSTANDING_ANALYZER_ID="<analyzer-id>" \
    CONTENT_UNDERSTANDING_API_VERSION="2025-11-01" \
    SQL_SERVER="<server-name>" \
    SQL_DATABASE="<database-name>"
```

### 8. Deploy

```bash
cd azure_function_sql
func azure functionapp publish <function-app-name>
```

## Environment Variables

| Variable                            | Description                                           | Required                 |
| ----------------------------------- | ----------------------------------------------------- | ------------------------ |
| `CONTENT_UNDERSTANDING_ENDPOINT`    | Azure Content Understanding endpoint                  | Yes                      |
| `CONTENT_UNDERSTANDING_ANALYZER_ID` | Analyzer ID                                           | Yes                      |
| `CONTENT_UNDERSTANDING_API_VERSION` | API version                                           | No (default: 2025-11-01) |
| `SQL_SERVER`                        | Azure SQL server name (without .database.windows.net) | Yes                      |
| `SQL_DATABASE`                      | Database name                                         | Yes                      |

## Logic Apps Integration

```json
{
  "method": "POST",
  "uri": "https://<function-app>.azurewebsites.net/api/analyze-and-store?code=<function-key>",
  "headers": {
    "Content-Type": "application/json"
  },
  "body": {
    "filename": "@{triggerOutputs()?['headers']['x-ms-blob-name']}",
    "content": "@{base64(body('Get_blob_content'))}"
  }
}
```

## Local Development

```bash
# Install ODBC Driver (Ubuntu/Debian)
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18

# Setup
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Run locally
func start
```

**Note:** Local testing requires Azure CLI login (`az login`) for DefaultAzureCredential to work.
