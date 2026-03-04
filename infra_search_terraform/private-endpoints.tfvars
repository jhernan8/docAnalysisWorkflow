resource_group_name = "cntrct-srch-dev-rg"
subscription_id = "14f31c51-1ebe-4a1f-a8ce-e33cb1638019"
tenant_id       = "ab946e82-6ddf-4dfb-ae1a-4c6b7a6ff6ab"

location_primary   = "westus"
location_secondary = "centralus"

admin_ai_name                  = "admin-3458-resource"
admin_ai_custom_subdomain_name = "admin-3458-resource"
cognitive_project_name         = "admin-3458"
cognitive_project_description  = "Contract search project"
cognitive_project_display_name = "Contract Search"

search_service_name           = "cntrct-srch-dev-search-woyj6cue5no22"
storage_account_name          = "cntrctsrchdevwoyj6cue5no"
eventgrid_topic_name          = "cntrctsrchdevwoyj6cue5no-b05e562b-ad3b-4b22-b91b-4a0661ae2283"

logic_app_name                     = "cntrct-srch-dev-logic"
blob_connection_name               = "cntrct-srch-dev-logic-blob"
blob_connection_display_name       = "Azure Blob Storage Connection"
sharepoint_connection_name         = "cntrct-srch-dev-logic-sharepoint"
sharepoint_connection_display_name = "SharePoint Connection"
sharepoint_site_url                = "https://mngenvmcap560696.sharepoint.com/sites/ContractAI"
sharepoint_library_id              = "0c082b7c-8834-480c-8b30-47ba73e8562c"

enable_private_endpoints   = true
create_private_dns_zones   = true

# Required when enable_private_endpoints = true
private_endpoint_subnet_id = "/subscriptions/<subscription-id>/resourceGroups/<network-rg>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<private-endpoint-subnet>"

# Recommended when create_private_dns_zones = true
private_dns_vnet_id        = "/subscriptions/<subscription-id>/resourceGroups/<network-rg>/providers/Microsoft.Network/virtualNetworks/<vnet-name>"
