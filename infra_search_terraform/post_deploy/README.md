# post_deploy

Post-deployment automation for the Terraform stack in `infra_search_terraform`.

This script is intended to finish steps that are not fully covered by the current Terraform provider flow.

## What it does

`finish-deploy.ps1` can:

- Read Terraform outputs from the deployed stack
- Assign required RBAC roles (Logic App/Search/optional current user)
- Attempt Azure AI Foundry project creation (when parent account supports `allowProjectManagement=true`)
- Configure AI Search objects (data source, index, skillset, indexer) and run the indexer
- Validate that the configured Azure OpenAI embedding deployment exists before skillset/indexer execution
- Create the Azure OpenAI embedding deployment automatically when it does not exist

When an existing index is incompatible with the vector/skillset schema, the script automatically creates versioned resources (for example `contracts-index-v2`) to avoid breaking existing consumers.

## Still manual (by design)

- SharePoint OAuth authorization for the SharePoint API connection
- Enabling the Logic App after connector authorization

The script prints exact commands for these manual steps at the end.

## Usage

From `infra_search_terraform/post_deploy`:

```powershell
./finish-deploy.ps1 -ResourceGroupName "cntrct-srch-sbx-rg"
```

Optional parameters:

- `-TerraformDir` (default: `..`)
- `-ProjectName` (default: `contract-search-project`)
- `-IndexName` (default: `contracts-index`)
- `-SkillsetName` (default: `contracts-skillset`)
- `-DataSourceName` (default: `contracts-datasource`)
- `-IndexerName` (default: `contracts-indexer`)
- `-BlobContainerName` (default: `contracts`)
- `-EmbeddingDeploymentName` (default: `text-embedding-3-large`)
- `-EmbeddingModelName` (default: `text-embedding-3-large`)
- `-EmbeddingModelVersion` (default: `1`)
- `-EmbeddingDeploymentSkuName` (default: `GlobalStandard`)
- `-EmbeddingDeploymentCapacity` (default: `120`)
- `-SkillsetTemplatePath` (default: `..\index_configs\completeSKillset.json`)
- `-IndexerTemplatePath` (default: `..\index_configs\indexer.json`)
- `-VersionSuffix` (default: `v2`)
- `-SearchApiVersion` (default: `2024-07-01`)
- `-SkillsetApiVersion` (default: `2025-11-01-Preview`)
- `-DisableAutoVersionOnIncompatibleIndex` (fail instead of auto-versioning)
- `-AdminAiAccountName` (use when auto-detect is ambiguous)

Note: Skillset creation automatically falls back between `2025-11-01` and `2025-11-01-Preview` if one is unavailable in your service/region.

- `-SkipRbac`
- `-SkipFoundryProject`
- `-SkipSearchObjects`
- `-SkipEnableAllowProjectManagement` (by default the script attempts to enable it automatically before project creation)

## Notes

- Requires `az` and `terraform` on PATH.
- Requires `az login` in the target subscription.
- Script is designed to be idempotent for repeat runs where possible.
- If Foundry project creation is skipped/fails due to `allowProjectManagement`, rerun without `-SkipEnableAllowProjectManagement` (or enable it manually via ARM/Bicep) and run again.
