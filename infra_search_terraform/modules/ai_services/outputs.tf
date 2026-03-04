output "admin_ai_services_id" {
  value = azurerm_ai_services.admin.id
}

output "main_ai_services_id" {
  value = azurerm_ai_services.admin.id
}

output "cognitive_project_id" {
  value = try(azurerm_cognitive_account_project.project[0].id, null)
}
