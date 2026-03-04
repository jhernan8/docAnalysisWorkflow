resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = var.account_tier
  account_replication_type        = var.account_replication_type
  account_kind                    = var.account_kind
  access_tier                     = var.access_tier
  min_tls_version                 = var.min_tls_version
  public_network_access_enabled   = var.public_network_access_enabled
  shared_access_key_enabled       = var.shared_access_key_enabled
  local_user_enabled              = var.local_user_enabled
  https_traffic_only_enabled      = var.https_traffic_only_enabled
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  tags                            = var.tags

  blob_properties {
    delete_retention_policy {
      days                     = 7
      permanent_delete_enabled = false
    }
  }

  network_rules {
    bypass                     = var.network_bypass
    default_action             = var.default_network_action
    ip_rules                   = []
    virtual_network_subnet_ids = []

    dynamic "private_link_access" {
      for_each = var.private_link_access
      content {
        endpoint_resource_id = private_link_access.value.endpoint_resource_id
        endpoint_tenant_id   = private_link_access.value.endpoint_tenant_id
      }
    }
  }

  share_properties {
    retention_policy {
      days = 7
    }
  }
}
