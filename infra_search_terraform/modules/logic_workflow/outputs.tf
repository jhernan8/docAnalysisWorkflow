output "logic_app_id" {
  value = azurerm_logic_app_workflow.this.id
}

output "blob_connection_id" {
  value = local.blob_connection_id
}

output "sharepoint_connection_id" {
  value = azurerm_api_connection.sharepoint.id
}
