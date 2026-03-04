variable "enable_private_endpoints" {
  type = bool
}

variable "create_private_dns_zones" {
  type = bool
}

variable "private_dns_zone_ids" {
  type = map(string)
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_vnet_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "storage_account_id" {
  type = string
}

variable "search_service_id" {
  type = string
}

variable "ai_services_id" {
  type = string
}
