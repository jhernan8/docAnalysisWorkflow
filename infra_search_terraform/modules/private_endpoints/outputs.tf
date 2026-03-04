output "private_endpoint_ids" {
  value = {
    storage_blob = try(azurerm_private_endpoint.storage_blob[0].id, null)
    search       = try(azurerm_private_endpoint.search[0].id, null)
    ai_services  = try(azurerm_private_endpoint.ai_services[0].id, null)
  }
}
