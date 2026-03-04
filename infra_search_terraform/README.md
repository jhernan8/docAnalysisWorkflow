# infra_search_terraform

Terraform for contract-search infrastructure with two execution modes.

## Architecture

This deployment provisions a two-region architecture:

- **Primary region (`location_primary`)**: AI Services, AI Search
- **Secondary region (`location_secondary`)**: Storage Account, Event Grid Topic, Logic App + API Connections

```text
SharePoint Library
	│
	▼
Logic App Trigger (SharePoint connector) ──▶ Azure Blob Storage (/contracts)
	│                                         │
	│                                         └── Event Grid Topic (storage events)
	▼
Azure AI Search ◀─────────────────────────────── Document/content pipeline input
	│
	▼
Azure AI Services (single account)
```

### Deployed Components

| Component                            | Terraform Module            | Region Source        |
| ------------------------------------ | --------------------------- | -------------------- |
| AI Services (single account)         | `modules/ai_services`       | `location_primary`   |
| AI Search Service                    | `modules/search_service`    | `location_primary`   |
| Storage Account                      | `modules/storage_account`   | `location_secondary` |
| Event Grid Topic                     | `modules/eventgrid_topic`   | `location_secondary` |
| Logic App Workflow + API Connections | `modules/logic_workflow`    | `location_secondary` |
| Private Endpoints (optional)         | `modules/private_endpoints` | `location_secondary` |

## Prerequisites

1. Azure CLI installed and authenticated (`az login`).
2. Terraform installed (compatible with `hashicorp/azurerm` provider `4.58.0` as pinned in this repo).
3. Azure permissions to create and manage:
   - Resource groups and deployments
   - Azure AI Services
   - Azure AI Search
   - Storage Accounts
   - Logic Apps and API Connections
   - Role assignments (if your tenant enforces RBAC workflows)
4. SharePoint site URL and document library ID for Logic App trigger configuration.

## Modes

- No private endpoints: `no-private-endpoints.tfvars`
- Private endpoints: `private-endpoints.tfvars`

## Configuration

Set environment-specific values in your tfvars file (for example `no-private-endpoints.tfvars`).

Required values include:

- `resource_group_name`, `subscription_id`, `tenant_id`
- `location_primary` (AI/Search region) and `location_secondary` (Storage/Logic App/Event Grid region)
- `admin_ai_name`, `search_service_name`, `storage_account_name`, `eventgrid_topic_name`
- `logic_app_name`, `blob_connection_name`, `sharepoint_connection_name`
- `sharepoint_site_url`, `sharepoint_library_id`

### Finding SharePoint Library ID

1. Open your SharePoint document library.
2. Go to **Settings** > **Library settings**.
3. In the URL, copy the GUID after `List=`.
4. Alternative API method: `/_api/web/lists?$filter=BaseTemplate eq 101`.

## Typical workflow

1. `terraform init -input=false`
2. `terraform plan -var-file="no-private-endpoints.tfvars" -no-color -input=false -lock=false`
3. `terraform apply -var-file="no-private-endpoints.tfvars" -auto-approve -no-color -input=false -lock=false`

Switch `no-private-endpoints.tfvars` to `private-endpoints.tfvars` for private endpoint deployments.

## Post-deployment

You can run the post-deploy helper to automate remaining non-Terraform steps:

- PowerShell script: `post_deploy/finish-deploy.ps1`
- Guide: `post_deploy/README.md`

Example:

`./post_deploy/finish-deploy.ps1 -ResourceGroupName "<resource-group-name>"`

1. Authorize the SharePoint API connection:
   - In Azure Portal, open the SharePoint connection resource and complete OAuth authorization.
2. Verify Logic App state:
   - Confirm the workflow is enabled in Portal.
3. Run a smoke test:
   - Upload one test document to the configured SharePoint library.
   - Wait 1-2 minutes and confirm the file is copied to the `contracts` container.

## Validation

After deployment, validate in Azure Portal:

- Logic App **Run history** shows successful trigger and actions.
- Storage account contains the uploaded file under container `contracts`.
- Azure AI Search service is provisioned and reachable.

## Troubleshooting

- Connector authorization failures:
  - Re-open the SharePoint API connection and re-authorize OAuth.
- Region constraints:
  - Keep AI Services / Search in supported regions (for this solution, `westus` is commonly required for model/project features).
- Terraform provider caveat (Logic App):
  - Some `azurerm` versions can fail or crash while creating `azurerm_logic_app_workflow` with certain `$connections` payload shapes.
  - If you hit provider panic/plugin crash, capture the first error block and provider version, then re-run with the provider-safe connection parameter structure used in this repo.
- Terraform provider/API compatibility (AI project):
  - Azure AI project creation may fail unless the parent AI Services account has `allowProjectManagement=true`.
  - The currently pinned provider path may not expose this setting on `azurerm_ai_services`; in that case create/manage the project via a compatible Bicep/ARM/Portal path.

## Cleanup

Choose one cleanup path:

- Terraform-managed teardown:
  - `terraform destroy -var-file="no-private-endpoints.tfvars" -auto-approve -no-color -input=false -lock=false`
- Resource group teardown:
  - `az group delete --name <resource-group-name> --yes --no-wait`

## Notes

- Environment-specific values (subscription, tenant, names, locations, SharePoint IDs) are set in tfvars files.
- `.terraform.lock.hcl` should be committed.
- `.terraform/`, `*.tfstate`, and lock/temp files are ignored.
