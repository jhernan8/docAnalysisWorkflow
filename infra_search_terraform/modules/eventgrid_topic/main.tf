resource "azurerm_eventgrid_system_topic" "this" {
  name                = var.eventgrid_topic_name
  resource_group_name = var.resource_group_name
  location            = var.location
  source_resource_id  = var.source_resource_id
  topic_type          = var.topic_type
  tags                = var.tags
}
