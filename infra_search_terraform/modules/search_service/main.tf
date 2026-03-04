resource "azurerm_search_service" "this" {
  name                                     = var.search_service_name
  location                                 = var.location
  resource_group_name                      = var.resource_group_name
  sku                                      = var.sku
  semantic_search_sku                      = var.semantic_search_sku
  local_authentication_enabled             = var.local_authentication_enabled
  authentication_failure_mode              = var.authentication_failure_mode
  customer_managed_key_enforcement_enabled = var.customer_managed_key_enforcement
  hosting_mode                             = var.hosting_mode
  partition_count                          = var.partition_count
  replica_count                            = var.replica_count
  network_rule_bypass_option               = var.network_rule_bypass_option
  public_network_access_enabled            = var.public_network_access_enabled
  allowed_ips                              = []
  tags                                     = var.tags

  identity {
    type = "SystemAssigned"
  }
}
