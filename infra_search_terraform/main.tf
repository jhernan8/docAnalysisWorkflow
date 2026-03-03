terraform {
  required_providers {
    azurerm = {
      source  = "azurerm"
      version = "4.58.0"
    }
  }
}
provider "azurerm" {
  features {}
}
resource "azurerm_ai_services" "res-0" {
  custom_subdomain_name              = "admin-3458-resource"
  fqdns                              = []
  local_authentication_enabled       = false
  location                           = "westus"
  name                               = "admin-3458-resource"
  outbound_network_access_restricted = false
  primary_access_key                 = "" # Masked sensitive attribute
  public_network_access              = "Enabled"
  resource_group_name                = "cntrct-srch-dev-rg"
  secondary_access_key               = "" # Masked sensitive attribute
  sku_name                           = "S0"
  tags                               = {}
  identity {
    identity_ids = []
    type         = "SystemAssigned"
  }
  network_acls {
    bypass         = ""
    default_action = "Allow"
    ip_rules       = []
  }
}
resource "azurerm_cognitive_account_project" "res-1" {
  cognitive_account_id = azurerm_ai_services.res-0.id
  description          = ""
  display_name         = ""
  location             = "westus"
  name                 = "admin-3458"
  tags                 = {}
  identity {
    identity_ids = []
    type         = "SystemAssigned"
  }
}
resource "azurerm_ai_services" "res-2" {
  custom_subdomain_name              = "cntrct-srch-dev-ai-woyj6cue5no22"
  fqdns                              = []
  local_authentication_enabled       = false
  location                           = "westus"
  name                               = "cntrct-srch-dev-ai-woyj6cue5no22"
  outbound_network_access_restricted = false
  primary_access_key                 = "" # Masked sensitive attribute
  public_network_access              = "Enabled"
  resource_group_name                = "cntrct-srch-dev-rg"
  secondary_access_key               = "" # Masked sensitive attribute
  sku_name                           = "S0"
  tags = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
  identity {
    identity_ids = []
    type         = "SystemAssigned"
  }
  network_acls {
    bypass         = ""
    default_action = "Allow"
    ip_rules       = []
  }
}
resource "azurerm_eventgrid_system_topic" "res-3" {
  location               = "centralus"
  name                   = "cntrctsrchdevwoyj6cue5no-b05e562b-ad3b-4b22-b91b-4a0661ae2283"
  resource_group_name    = "cntrct-srch-dev-rg"
  source_arm_resource_id = "/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/resourceGroups/cntrct-srch-dev-rg/providers/microsoft.storage/storageaccounts/cntrctsrchdevwoyj6cue5no"
  source_resource_id     = "/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/resourceGroups/cntrct-srch-dev-rg/providers/microsoft.storage/storageaccounts/cntrctsrchdevwoyj6cue5no"
  tags                   = {}
  topic_type             = "microsoft.storage.storageaccounts"
}
resource "azurerm_logic_app_workflow" "res-4" {
  enabled                            = true
  integration_service_environment_id = ""
  location                           = "centralus"
  logic_app_integration_account_id   = ""
  name                               = "cntrct-srch-dev-logic"
  parameters = {
    "$connections" = "{\"azureblob\":{\"connectionId\":\"/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/resourceGroups/cntrct-srch-dev-rg/providers/Microsoft.Web/connections/cntrct-srch-dev-logic-blob\",\"connectionName\":\"cntrct-srch-dev-logic-blob\",\"connectionProperties\":{\"authentication\":{\"type\":\"ManagedServiceIdentity\"}},\"id\":\"/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/providers/Microsoft.Web/locations/centralus/managedApis/azureblob\"},\"sharepointonline\":{\"connectionId\":\"/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/resourceGroups/cntrct-srch-dev-rg/providers/Microsoft.Web/connections/cntrct-srch-dev-logic-sharepoint\",\"connectionName\":\"cntrct-srch-dev-logic-sharepoint\",\"id\":\"/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/providers/Microsoft.Web/locations/centralus/managedApis/sharepointonline\"}}"
  }
  resource_group_name = "cntrct-srch-dev-rg"
  tags = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
  workflow_parameters = {
    "$connections" = "{\"defaultValue\":{},\"type\":\"Object\"}"
  }
  workflow_schema  = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
  identity {
    identity_ids = []
    type         = "SystemAssigned"
  }
}
resource "azurerm_search_service" "res-5" {
  allowed_ips                              = []
  authentication_failure_mode              = "http401WithBearerChallenge"
  customer_managed_key_enforcement_enabled = false
  hosting_mode                             = "Default"
  local_authentication_enabled             = true
  location                                 = "westus"
  name                                     = "cntrct-srch-dev-search-woyj6cue5no22"
  network_rule_bypass_option               = "None"
  partition_count                          = 1
  primary_key                              = "" # Masked sensitive attribute
  public_network_access_enabled            = true
  replica_count                            = 1
  resource_group_name                      = "cntrct-srch-dev-rg"
  secondary_key                            = "" # Masked sensitive attribute
  semantic_search_sku                      = "free"
  sku                                      = "basic"
  tags = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
  identity {
    identity_ids = []
    type         = "SystemAssigned"
  }
}
resource "azurerm_storage_account" "res-6" {
  access_tier                       = "Hot"
  account_kind                      = "StorageV2"
  account_replication_type          = "LRS"
  account_tier                      = "Standard"
  allow_nested_items_to_be_public   = false
  allowed_copy_scope                = ""
  cross_tenant_replication_enabled  = false
  default_to_oauth_authentication   = false
  dns_endpoint_type                 = "Standard"
  edge_zone                         = ""
  https_traffic_only_enabled        = true
  infrastructure_encryption_enabled = false
  is_hns_enabled                    = false
  large_file_share_enabled          = false
  local_user_enabled                = true
  location                          = "centralus"
  min_tls_version                   = "TLS1_2"
  name                              = "cntrctsrchdevwoyj6cue5no"
  nfsv3_enabled                     = false
  primary_access_key                = "" # Masked sensitive attribute
  primary_blob_connection_string    = "" # Masked sensitive attribute
  primary_connection_string         = "" # Masked sensitive attribute
  provisioned_billing_model_version = ""
  public_network_access_enabled     = false
  queue_encryption_key_type         = "Service"
  resource_group_name               = "cntrct-srch-dev-rg"
  secondary_access_key              = "" # Masked sensitive attribute
  secondary_blob_connection_string  = "" # Masked sensitive attribute
  secondary_connection_string       = "" # Masked sensitive attribute
  sftp_enabled                      = false
  shared_access_key_enabled         = false
  table_encryption_key_type         = "Service"
  tags = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
  blob_properties {
    change_feed_enabled           = false
    change_feed_retention_in_days = 0
    default_service_version       = ""
    last_access_time_enabled      = false
    versioning_enabled            = false
    delete_retention_policy {
      days                     = 7
      permanent_delete_enabled = false
    }
  }
  network_rules {
    bypass                     = ["AzureServices"]
    default_action             = "Allow"
    ip_rules                   = []
    virtual_network_subnet_ids = []
    private_link_access {
      endpoint_resource_id = "/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/providers/Microsoft.Security/datascanners/StorageDataScanner"
      endpoint_tenant_id   = "ab946e82-6ddf-4dfb-ae1a-4c6b7a6ff6ab"
    }
  }
  share_properties {
    retention_policy {
      days = 7
    }
  }
}
resource "azurerm_api_connection" "res-7" {
  display_name        = "Azure Blob Storage Connection"
  managed_api_id      = "/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/providers/Microsoft.Web/locations/centralus/managedApis/azureblob"
  name                = "cntrct-srch-dev-logic-blob"
  parameter_values    = {}
  resource_group_name = "cntrct-srch-dev-rg"
  tags = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
}
resource "azurerm_api_connection" "res-8" {
  display_name        = "SharePoint Connection"
  managed_api_id      = "/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/providers/Microsoft.Web/locations/centralus/managedApis/sharepointonline"
  name                = "cntrct-srch-dev-logic-sharepoint"
  parameter_values    = {}
  resource_group_name = "cntrct-srch-dev-rg"
  tags = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
}
resource "azurerm_logic_app_action_custom" "res-9" {
  body = jsonencode({
    inputs = {
      body = "@body('Get_file_content_from_SharePoint')"
      headers = {
        ReadFileMetadataFromServer = true
      }
      host = {
        connection = {
          name = "@parameters('$connections')['azureblob']['connectionId']"
        }
      }
      method = "post"
      path   = "/v2/datasets/@{encodeURIComponent(encodeURIComponent('cntrctsrchdevwoyj6cue5no'))}/files"
      queries = {
        folderPath                   = "/contracts"
        name                         = "@triggerBody()?['{FilenameWithExtension}']"
        queryParametersSingleEncoded = true
      }
    }
    runAfter = {
      Get_file_content_from_SharePoint = ["Succeeded"]
    }
    runtimeConfiguration = {
      contentTransfer = {
        transferMode = "Chunked"
      }
    }
    type = "ApiConnection"
  })
  logic_app_id = azurerm_logic_app_workflow.res-4.id
  name         = "Create_blob_in_contracts_container"
}
resource "azurerm_logic_app_action_custom" "res-10" {
  body = jsonencode({
    inputs = {
      host = {
        connection = {
          name = "@parameters('$connections')['sharepointonline']['connectionId']"
        }
      }
      method = "get"
      path   = "/datasets/@{encodeURIComponent(encodeURIComponent('https://mngenvmcap560696.sharepoint.com/sites/ContractAI'))}/files/@{encodeURIComponent(triggerBody()?['{Identifier}'])}/content"
      queries = {
        inferContentType = true
      }
    }
    runAfter = {}
    type     = "ApiConnection"
  })
  logic_app_id = azurerm_logic_app_workflow.res-4.id
  name         = "Get_file_content_from_SharePoint"
}
resource "azurerm_logic_app_trigger_custom" "res-11" {
  body = jsonencode({
    inputs = {
      host = {
        connection = {
          name = "@parameters('$connections')['sharepointonline']['connectionId']"
        }
      }
      method = "get"
      path   = "/datasets/@{encodeURIComponent(encodeURIComponent('https://mngenvmcap560696.sharepoint.com/sites/ContractAI'))}/tables/@{encodeURIComponent(encodeURIComponent('0c082b7c-8834-480c-8b30-47ba73e8562c'))}/onnewfileitems"
    }
    recurrence = {
      frequency = "Minute"
      interval  = 1
    }
    splitOn = "@triggerBody()?['value']"
    type    = "ApiConnection"
  })
  logic_app_id = azurerm_logic_app_workflow.res-4.id
  name         = "When_a_file_is_created_in_SharePoint"
}
