locals {
  common_tags = var.tags

  ai_public_network_access      = var.enable_private_endpoints ? "Disabled" : var.ai_public_network_access_when_disabled
  ai_network_default_action     = var.enable_private_endpoints ? "Deny" : var.ai_network_default_action_when_disabled

  search_public_network_access_enabled = var.enable_private_endpoints ? false : var.search_public_network_access_enabled_when_disabled

  storage_public_network_access_enabled = var.enable_private_endpoints ? false : var.storage_public_network_access_enabled_when_disabled
  storage_network_default_action        = var.enable_private_endpoints ? "Deny" : var.storage_network_default_action_when_disabled
}
