locals {
  blob_dns_zone_name   = "privatelink.blob.core.windows.net"
  search_dns_zone_name = "privatelink.search.windows.net"
  ai_dns_zone_name     = "privatelink.cognitiveservices.azure.com"
}

resource "azurerm_private_dns_zone" "blob" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = local.blob_dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone" "search" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = local.search_dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone" "ai" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = local.ai_dns_zone_name
  resource_group_name = var.resource_group_name
}

locals {
  blob_dns_zone_id   = var.create_private_dns_zones ? try(azurerm_private_dns_zone.blob[0].id, null) : try(var.private_dns_zone_ids["blob"], null)
  search_dns_zone_id = var.create_private_dns_zones ? try(azurerm_private_dns_zone.search[0].id, null) : try(var.private_dns_zone_ids["search"], null)
  ai_dns_zone_id     = var.create_private_dns_zones ? try(azurerm_private_dns_zone.ai[0].id, null) : try(var.private_dns_zone_ids["ai"], null)
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones && var.private_dns_vnet_id != null ? 1 : 0
  name                  = "${var.name_prefix}-blob-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = var.private_dns_vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "search" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones && var.private_dns_vnet_id != null ? 1 : 0
  name                  = "${var.name_prefix}-search-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.search[0].name
  virtual_network_id    = var.private_dns_vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ai" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones && var.private_dns_vnet_id != null ? 1 : 0
  name                  = "${var.name_prefix}-ai-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.ai[0].name
  virtual_network_id    = var.private_dns_vnet_id
}

resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${var.name_prefix}-stg-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name_prefix}-stg-blob-psc"
    private_connection_resource_id = var.storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.blob_dns_zone_id != null ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [local.blob_dns_zone_id]
    }
  }
}

resource "azurerm_private_endpoint" "search" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${var.name_prefix}-search-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name_prefix}-search-psc"
    private_connection_resource_id = var.search_service_id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.search_dns_zone_id != null ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [local.search_dns_zone_id]
    }
  }
}

resource "azurerm_private_endpoint" "ai_services" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${var.name_prefix}-ai-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name_prefix}-ai-psc"
    private_connection_resource_id = var.ai_services_id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.ai_dns_zone_id != null ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [local.ai_dns_zone_id]
    }
  }
}
