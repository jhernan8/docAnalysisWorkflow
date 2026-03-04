resource "azurerm_ai_services" "admin" {
  name                               = var.admin_ai_name
  custom_subdomain_name              = var.admin_ai_custom_subdomain_name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  sku_name                           = var.sku_name
  local_authentication_enabled       = var.local_authentication_enabled
  outbound_network_access_restricted = var.outbound_network_access_restricted
  public_network_access              = var.public_network_access
  tags                               = var.tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    bypass         = "None"
    default_action = var.network_default_action
    ip_rules       = []
  }
}

resource "azurerm_cognitive_account_project" "project" {
  count                = var.create_cognitive_project ? 1 : 0
  name                 = var.cognitive_project_name
  location             = var.location
  cognitive_account_id = azurerm_ai_services.admin.id
  description          = var.cognitive_project_description
  display_name         = var.cognitive_project_display_name
  tags                 = var.tags

  identity {
    type = "SystemAssigned"
  }
}
