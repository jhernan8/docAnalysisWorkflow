# Contract Analysis Azure Function

This Azure Function provides HTTP endpoints for analyzing contracts using Azure Content Understanding.

## Endpoints

### 1. `POST /api/analyze-contract`

Analyzes a contract and returns extracted data (no database storage).

### 2. `POST /api/analyze-and-store`

Analyzes a contract and stores results in PostgreSQL database.

## Request Formats

### Option A: Binary PDF Upload

```http
POST /api/analyze-contract
Content-Type: application/pdf
X-Filename: my-contract.pdf

<binary PDF content>
```

### Option B: JSON with Base64 Content

```http
POST /api/analyze-contract
Content-Type: application/json

{
    "filename": "my-contract.pdf",
    "content": "<base64-encoded PDF content>"
}
```

## Response Format

```json
{
  "filename": "contract.pdf",
  "title": "Service Agreement",
  "parties": [
    {
      "name": "Company A",
      "address": "123 Main St",
      "reference_name": "Provider"
    }
  ],
  "dates": {
    "EffectiveDate": "2025-01-01",
    "ExpirationDate": "2026-01-01"
  },
  "duration": "12 months",
  "jurisdictions": ["California", "USA"],
  "clauses": [
    {
      "type": "Termination",
      "title": "Early Termination",
      "text": "Either party may terminate..."
    }
  ],
  "database": {
    "contract_id": 1,
    "party_ids": [1, 2],
    "clause_ids": [1, 2, 3]
  }
}
```

## Logic Apps Integration

### HTTP Action Configuration

1. In Logic Apps Designer, add an **HTTP** action
2. Configure as follows:
   - **Method**: POST
   - **URI**: `https://pdf-cu-processing-2.azurewebsites.net/api/analyze-contract?code=<function-key>`
   - **Headers**:
     - `Content-Type`: `application/json`
   - **Body**:
     ```json
     {
       "filename": "@{triggerBody()?['filename']}",
       "content": "@{base64(triggerBody()?['$content'])}"
     }
     ```

To get the function key:

1. Go to Azure Portal → Function App → Functions → `analyze-contract`
2. Click **Get Function Url** and copy the `code` parameter

### Using with Blob Trigger

If your Logic App triggers on blob upload:

```json
{
  "filename": "@{triggerOutputs()?['headers']['x-ms-blob-name']}",
  "content": "@{base64(body('Get_blob_content'))}"
}
```

## Environment Variables

Configure these in your Azure Function App Settings:

| Variable                            | Description                          | Default                                                              |
| ----------------------------------- | ------------------------------------ | -------------------------------------------------------------------- |
| `CONTENT_UNDERSTANDING_ENDPOINT`    | Azure Content Understanding endpoint | `https://___-contracts-ai-proj-resource.cognitiveservices.azure.com` |
| `CONTENT_UNDERSTANDING_API_VERSION` | API version                          | `2025-11-01`                                                         |
| `CONTENT_UNDERSTANDING_ANALYZER_ID` | Analyzer ID                          | `projectAnalyzer_1768587228991_591`                                  |
| `POSTGRES_SERVER`                   | PostgreSQL server name               | `contract-db`                                                        |
| `POSTGRES_DATABASE`                 | Database name                        | `postgres`                                                           |
| `POSTGRES_USER`                     | Azure AD user/identity               | -                                                                    |

## Deployment

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- Azure Functions Core Tools v4 installed:
  ```bash
  ./install-func-tools.sh
  ```

### Create Function App (Azure Portal)

When creating the Function App in Azure Portal:

1. **Basics**:
   - Runtime stack: **Python**
   - Version: **3.10** or **3.11**
   - Operating System: **Linux**

2. **Storage** (Important for RBAC):
   - If your storage account has shared key access disabled, ensure you enable **"Use managed identity for deployment"** during creation
   - Or use a storage account with shared key access enabled

3. **Hosting**:
   - Plan type: **Consumption (Serverless)** or **Flex Consumption**

### Deploy to Azure

```bash
# Navigate to the function folder
cd azure_function

# Deploy to your Function App
func azure functionapp publish pdf-cu-processing-2
```

### Configure Managed Identity

After deployment, configure managed identity for the function to access Azure services:

1. Go to your Function App → **Identity** → Enable **System-assigned** managed identity
2. Grant the identity these roles:
   - **Cognitive Services User** on your Content Understanding resource
   - **PostgreSQL Flexible Server AAD Admin** or appropriate DB access on your PostgreSQL server

```bash
# Get the Function App's managed identity principal ID
az functionapp identity show --name pdf-cu-processing-2 --resource-group ___-contracts-rg --query principalId -o tsv

# Grant Cognitive Services User role
az role assignment create \
  --assignee <principal-id> \
  --role "Cognitive Services User" \
  --scope <content-understanding-resource-id>
```

## Local Testing

```bash
# Navigate to function folder
cd azure_function

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run locally
func start
```

Test with curl:

```bash
# Test with JSON payload
curl -X POST http://localhost:7071/api/analyze-contract \
    -H "Content-Type: application/json" \
    -d '{"filename": "test.pdf", "content": "<base64-content>"}'
```
