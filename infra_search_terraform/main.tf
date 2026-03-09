terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.58.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  storage_use_azuread = true
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location_primary
  tags     = local.common_tags
}

module "ai_services" {
  source                              = "./modules/ai_services"
  resource_group_name                 = azurerm_resource_group.main.name
  location                            = var.location_primary
  admin_ai_name                       = var.admin_ai_name
  admin_ai_custom_subdomain_name      = var.admin_ai_custom_subdomain_name
  cognitive_project_name              = var.cognitive_project_name
  cognitive_project_description       = var.cognitive_project_description
  cognitive_project_display_name      = var.cognitive_project_display_name
  create_cognitive_project            = var.create_cognitive_project
  sku_name                            = var.ai_sku_name
  local_authentication_enabled        = var.ai_local_authentication_enabled
  outbound_network_access_restricted  = var.ai_outbound_network_access_restricted
  public_network_access               = local.ai_public_network_access
  network_default_action              = local.ai_network_default_action
  tags                                = local.common_tags
}

module "search_service" {
  source                               = "./modules/search_service"
  resource_group_name                  = azurerm_resource_group.main.name
  location                             = var.location_primary
  search_service_name                  = var.search_service_name
  sku                                  = var.search_sku
  semantic_search_sku                  = var.search_semantic_search_sku
  local_authentication_enabled         = var.search_local_authentication_enabled
  authentication_failure_mode          = var.search_authentication_failure_mode
  customer_managed_key_enforcement     = var.search_customer_managed_key_enforcement_enabled
  hosting_mode                         = var.search_hosting_mode
  partition_count                      = var.search_partition_count
  replica_count                        = var.search_replica_count
  network_rule_bypass_option           = var.search_network_rule_bypass_option
  public_network_access_enabled        = local.search_public_network_access_enabled
  tags                                 = local.common_tags
}

module "storage_account" {
  source                            = "./modules/storage_account"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = var.location_secondary
  storage_account_name              = var.storage_account_name
  account_tier                      = var.storage_account_tier
  account_replication_type          = var.storage_account_replication_type
  account_kind                      = var.storage_account_kind
  access_tier                       = var.storage_access_tier
  min_tls_version                   = var.storage_min_tls_version
  public_network_access_enabled     = local.storage_public_network_access_enabled
  shared_access_key_enabled         = var.storage_shared_access_key_enabled
  local_user_enabled                = var.storage_local_user_enabled
  https_traffic_only_enabled        = var.storage_https_traffic_only_enabled
  allow_nested_items_to_be_public   = var.storage_allow_nested_items_to_be_public
  default_network_action            = local.storage_network_default_action
  network_bypass                    = var.storage_network_bypass
  private_link_access               = var.storage_private_link_access
  tags                              = local.common_tags
}

module "eventgrid_topic" {
  source                = "./modules/eventgrid_topic"
  resource_group_name   = azurerm_resource_group.main.name
  location              = var.location_secondary
  eventgrid_topic_name  = var.eventgrid_topic_name
  source_resource_id    = module.storage_account.storage_account_id
  topic_type            = "microsoft.storage.storageaccounts"
  tags                  = local.common_tags
}

module "logic_workflow" {
  source                          = "./modules/logic_workflow"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location_secondary
  subscription_id                 = var.subscription_id
  logic_app_name                  = var.logic_app_name
  blob_connection_name            = var.blob_connection_name
  blob_connection_display_name    = var.blob_connection_display_name
  sharepoint_connection_name      = var.sharepoint_connection_name
  sharepoint_connection_display_name = var.sharepoint_connection_display_name
  storage_account_name            = module.storage_account.storage_account_name
  sharepoint_site_url             = var.sharepoint_site_url
  sharepoint_library_id           = var.sharepoint_library_id
  tags                            = local.common_tags
}

module "private_endpoints" {
  source                      = "./modules/private_endpoints"
  enable_private_endpoints    = var.enable_private_endpoints
  create_private_dns_zones    = var.create_private_dns_zones
  private_dns_zone_ids        = var.private_dns_zone_ids
  private_endpoint_subnet_id  = var.private_endpoint_subnet_id
  private_dns_vnet_id         = var.private_dns_vnet_id
  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location_secondary
  name_prefix                 = var.private_endpoint_name_prefix
  storage_account_id          = module.storage_account.storage_account_id
  search_service_id           = module.search_service.search_service_id
  ai_services_id              = module.ai_services.admin_ai_services_id
}
