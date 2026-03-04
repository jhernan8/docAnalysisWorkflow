variable "resource_group_name" {
  description = "Resource group name for all resources."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID for provider and resource IDs."
  type        = string
}

variable "tenant_id" {
  description = "Optional Azure tenant ID for provider authentication."
  type        = string
}

variable "location_primary" {
  description = "Primary location for AI and Search resources."
  type        = string
}

variable "location_secondary" {
  description = "Secondary location for Storage, Event Grid, and Logic App."
  type        = string
}

variable "tags" {
  description = "Common tags applied to resources."
  type        = map(string)
  default = {
    deployedBy  = "bicep"
    deployedOn  = "2026-02-04"
    environment = "dev"
    solution    = "contract-search"
  }
}

variable "admin_ai_name" {
  type    = string
}

variable "admin_ai_custom_subdomain_name" {
  type    = string
}

variable "cognitive_project_name" {
  type    = string
}

variable "cognitive_project_description" {
  type    = string
}

variable "cognitive_project_display_name" {
  type    = string
}

variable "create_cognitive_project" {
  description = "Whether to create an Azure AI Foundry project under the admin AI Services account."
  type        = bool
  default     = false
}

variable "ai_sku_name" {
  type    = string
  default = "S0"
}

variable "ai_local_authentication_enabled" {
  type    = bool
  default = false
}

variable "ai_outbound_network_access_restricted" {
  type    = bool
  default = false
}

variable "ai_public_network_access_when_disabled" {
  description = "Public network access state when private endpoints are not enabled."
  type        = string
  default     = "Enabled"
}

variable "ai_network_default_action_when_disabled" {
  description = "Network ACL default action when private endpoints are not enabled."
  type        = string
  default     = "Allow"
}

variable "search_service_name" {
  type    = string
}

variable "search_sku" {
  type    = string
  default = "basic"
}

variable "search_semantic_search_sku" {
  type    = string
  default = "free"
}

variable "search_local_authentication_enabled" {
  type    = bool
  default = true
}

variable "search_authentication_failure_mode" {
  type    = string
  default = "http401WithBearerChallenge"
}

variable "search_customer_managed_key_enforcement_enabled" {
  type    = bool
  default = false
}

variable "search_hosting_mode" {
  type    = string
  default = "Default"
}

variable "search_partition_count" {
  type    = number
  default = 1
}

variable "search_replica_count" {
  type    = number
  default = 1
}

variable "search_network_rule_bypass_option" {
  type    = string
  default = "None"
}

variable "search_public_network_access_enabled_when_disabled" {
  description = "Search public network access when private endpoints are not enabled."
  type        = bool
  default     = true
}

variable "storage_account_name" {
  type    = string
}

variable "storage_account_tier" {
  type    = string
  default = "Standard"
}

variable "storage_account_replication_type" {
  type    = string
  default = "LRS"
}

variable "storage_account_kind" {
  type    = string
  default = "StorageV2"
}

variable "storage_access_tier" {
  type    = string
  default = "Hot"
}

variable "storage_min_tls_version" {
  type    = string
  default = "TLS1_2"
}

variable "storage_shared_access_key_enabled" {
  type    = bool
  default = false
}

variable "storage_local_user_enabled" {
  type    = bool
  default = true
}

variable "storage_https_traffic_only_enabled" {
  type    = bool
  default = true
}

variable "storage_allow_nested_items_to_be_public" {
  type    = bool
  default = false
}

variable "storage_public_network_access_enabled_when_disabled" {
  description = "Storage public network access when private endpoints are not enabled."
  type        = bool
  default     = false
}

variable "storage_network_default_action_when_disabled" {
  description = "Storage network rules default action when private endpoints are not enabled."
  type        = string
  default     = "Allow"
}

variable "storage_network_bypass" {
  type    = list(string)
  default = ["AzureServices"]
}

variable "storage_private_link_access" {
  description = "Existing storage network_rules.private_link_access entries to keep in sync."
  type = list(object({
    endpoint_resource_id = string
    endpoint_tenant_id   = string
  }))
  default = [
    {
      endpoint_resource_id = "/subscriptions/14f31c51-1ebe-4a1f-a8ce-e33cb1638019/providers/Microsoft.Security/datascanners/StorageDataScanner"
      endpoint_tenant_id   = "ab946e82-6ddf-4dfb-ae1a-4c6b7a6ff6ab"
    }
  ]
}

variable "eventgrid_topic_name" {
  type    = string
}

variable "logic_app_name" {
  type    = string
}

variable "blob_connection_name" {
  type    = string
}

variable "blob_connection_display_name" {
  type    = string
}

variable "sharepoint_connection_name" {
  type    = string
}

variable "sharepoint_connection_display_name" {
  type    = string
}

variable "sharepoint_site_url" {
  type    = string
}

variable "sharepoint_library_id" {
  type    = string
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for Storage (blob), Search, and AI Services."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet resource ID used by private endpoints. Required when enable_private_endpoints is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_private_endpoints || var.private_endpoint_subnet_id != null
    error_message = "private_endpoint_subnet_id must be provided when enable_private_endpoints is true."
  }
}

variable "create_private_dns_zones" {
  description = "Create private DNS zones for private endpoint resolution."
  type        = bool
  default     = true
}

variable "private_dns_vnet_id" {
  description = "Virtual network ID for linking private DNS zones. Optional but recommended when create_private_dns_zones is true."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Existing private DNS zone IDs when create_private_dns_zones is false. Keys: blob, search, ai."
  type        = map(string)
  default     = {}
}

variable "private_endpoint_name_prefix" {
  description = "Prefix for private endpoint resource names."
  type        = string
  default     = "cntrct-srch-dev"
}
