output "ai_services_admin_id" {
  value = module.ai_services.admin_ai_services_id
}

output "search_service_id" {
  value = module.search_service.search_service_id
}

output "storage_account_id" {
  value = module.storage_account.storage_account_id
}

output "logic_app_id" {
  value = module.logic_workflow.logic_app_id
}

output "private_endpoint_ids" {
  value = module.private_endpoints.private_endpoint_ids
}
