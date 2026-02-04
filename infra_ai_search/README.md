# Contract Search Solution - Infrastructure Deployment

This Bicep deployment creates the infrastructure for a **SharePoint → AI Search → Foundry Agent** solution.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   SharePoint    │────▶│   Logic App     │────▶│  Blob Storage   │
│   (Documents)   │     │   (Trigger)     │     │  (/contracts)   │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                        ┌────────────────────────────────┘
                        ▼
              ┌─────────────────┐     ┌─────────────────┐
              │   AI Search     │◀────│  Foundry Agent  │
              │   (Indexer)     │     │  (Chat + Tools) │
              └─────────────────┘     └─────────────────┘
                        │                      │
                        └──────────┬───────────┘
                                   ▼
                         ┌─────────────────┐
                         │   AI Services   │
                         │  (GPT-4, etc.)  │
                         └─────────────────┘
```

## Deployed Resources

| Resource        | Location   | Purpose                      |
| --------------- | ---------- | ---------------------------- |
| Storage Account | Central US | Blob storage for contracts   |
| Logic App       | Central US | SharePoint → Blob automation |
| AI Search       | West US    | Vector/keyword search        |
| AI Services     | West US    | GPT-4.1, embeddings, Foundry |

### AI Search Pipeline (Automated)

The deploy script automatically configures:

- **Data Source**: Connects to the `contracts` blob container using managed identity
- **Index**: Creates a chunked document index with vector embeddings
- **Skillset**: Configures Content Understanding for document extraction
- **Indexer**: Processes documents and populates the index

Role assignments for AI Search managed identity are also configured automatically (Storage Blob Data Contributor, Cognitive Services User).

### Model Deployments (AI Services)

| Model                  | Deployment Name        | SKU            | Capacity |
| ---------------------- | ---------------------- | -------------- | -------- |
| GPT-4.1                | gpt-4-1                | GlobalStandard | 150      |
| GPT-4.1-mini           | gpt-4-1-mini           | GlobalStandard | 250      |
| text-embedding-3-large | text-embedding-3-large | GlobalStandard | 500      |
| text-embedding-3-small | text-embedding-3-small | Standard       | 120      |

## Prerequisites

1. **Azure CLI** installed and logged in
2. **Bicep CLI** (included with Azure CLI 2.20+)
3. **SharePoint site** with a document library configured
4. **Azure subscription** with access to:
   - AI Services (West US for preview features)
   - AI Search
   - Logic Apps

## Configuration

Edit `main.bicepparam` with your values:

```bicep
param baseName = 'cntrct-srch'
param environment = 'dev'

// SharePoint Configuration
param sharePointSiteUrl = 'https://your-tenant.sharepoint.com/sites/YourSite'
param sharePointLibraryId = 'your-library-guid'
```

### Finding SharePoint Library ID

1. Navigate to your SharePoint document library
2. Click **Settings** → **Library settings**
3. Look at the URL - the GUID after `List=` is your library ID
4. Or use: `/_api/web/lists?$filter=BaseTemplate eq 101`

## Deployment

```bash
# Make script executable
chmod +x deploy.sh

# Deploy to a new resource group
./deploy.sh -g my-contract-search-rg

# Deploy with custom options
./deploy.sh -g my-contract-search-rg -l centralus -e prod
```

### Command Line Options

| Option                 | Description                    | Default         |
| ---------------------- | ------------------------------ | --------------- |
| `-g, --resource-group` | Resource group name (required) | -               |
| `-l, --location`       | Primary location               | centralus       |
| `-e, --environment`    | Environment (dev/staging/prod) | dev             |
| `-p, --params`         | Parameter file                 | main.bicepparam |

## Post-Deployment Steps

### 1. Authorize SharePoint Connection

The SharePoint connection requires OAuth authorization:

**Option A: Azure Portal**

1. Navigate to your resource group
2. Click on the SharePoint connection resource (`*-sharepoint`)
3. Click **Edit API connection**
4. Click **Authorize** and sign in with your SharePoint account
5. Click **Save**

**Option B: Azure CLI**

```bash
# Get consent link
az resource invoke-action \
  --resource-group YOUR_RG \
  --resource-type Microsoft.Web/connections \
  --name YOUR_LOGIC_APP-sharepoint \
  --action consentLink \
  --api-version 2016-06-01

# Open the returned URL in a browser to authorize
```

### 2. Enable the Logic App

After authorizing connections:

```bash
az logic workflow update \
  --resource-group YOUR_RG \
  --name YOUR_LOGIC_APP_NAME \
  --state Enabled
```

### 3. Test SharePoint Integration

Upload a single contract to your SharePoint library to verify the end-to-end flow:

1. Navigate to your SharePoint document library
2. Upload one test contract (PDF or DOCX)
3. Wait 1-2 minutes for the Logic App to trigger
4. Verify the document appears in your Storage Account under the `contracts` container
5. Check Logic App run history for any errors:
   - Go to your Logic App in Azure Portal
   - Click **Run history** to see execution status

### 4. Create Foundry Agent

1. Open **Azure AI Foundry**: https://ai.azure.com
2. Select your project (created during deployment)
3. Go to **Agents** → **Create agent**
4. Configure the agent:

**Basic Settings:**

- Name: `contract-search-agent`
- Model: `gpt-4-1` (or `gpt-4-1-mini` for cost savings)

**Instructions (System Prompt):**

```
You are a contract analysis assistant. You help users search and understand contracts stored in the system.

When asked about contracts:
1. Use the search tool to find relevant contracts
2. Summarize key terms, dates, values, and parties
3. Highlight any important clauses or risks
4. Answer questions based on the contract content

Always cite the specific contract filename when providing information.
```

**Tools:**

- Enable **Azure AI Search** tool
- Configure with your search service and index

5. Save and test the agent

## Cleanup

To delete all resources:

```bash
az group delete --name YOUR_RG --yes --no-wait
```

## Troubleshooting

### Logic App not triggering

- Verify SharePoint connection is authorized (check connection status)
- Ensure Logic App is enabled (`state: Enabled`)
- Check Logic App run history for errors

### AI Search connection issues

- Verify managed identity has `Search Index Data Reader` role
- Check network access settings

### Model deployment failures

- Some models require specific regions (West US for preview)
- Check quota limits in your subscription

## Files

```
infra_foundry/
├── main.bicep              # Main deployment template
├── main.bicepparam         # Parameter file
├── deploy.sh               # Infrastructure deployment script
├── cleanup.sh              # Resource cleanup script
├── README.md               # This file
└── modules/
    ├── storage.bicep           # Storage account + containers
    ├── ai-search.bicep         # Azure AI Search
    ├── ai-services-foundry.bicep   # AI Services + model deployments
    ├── logic-app-sharepoint.bicep  # Logic App with connections
    └── role-assignment.bicep   # RBAC role assignments
```

## Search Pipeline Details

The search pipeline (configured via Azure Portal) uses the following components:

### Index Fields

| Field               | Type          | Purpose                             |
| ------------------- | ------------- | ----------------------------------- |
| `chunk_id`          | String (key)  | Unique chunk identifier             |
| `text_document_id`  | String        | Parent document ID for text chunks  |
| `image_document_id` | String        | Parent document ID for image chunks |
| `document_title`    | String        | Original document filename          |
| `content_text`      | String        | Extracted/verbalized text content   |
| `content_embedding` | Vector (3072) | text-embedding-3-large vector       |
| `content_path`      | String        | Path to extracted images            |
| `locationMetadata`  | Complex       | Page number and bounding polygons   |

### Skillset Skills

1. **ContentUnderstandingSkill** - Extracts text sections and images with chunking
2. **ChatCompletionSkill** - Verbalizes images using GPT-4.1
3. **AzureOpenAIEmbeddingSkill** - Generates embeddings for text and verbalized images
4. **ShaperSkill** - Shapes image metadata for indexing

> **Note:** The skillset uses managed identity (`AIServicesByIdentity`) for keyless connection to AI Services. Ensure all role assignments are configured before running the indexer.
