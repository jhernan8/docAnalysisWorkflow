variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "search_service_name" {
  type = string
}

variable "sku" {
  type = string
}

variable "semantic_search_sku" {
  type = string
}

variable "local_authentication_enabled" {
  type = bool
}

variable "authentication_failure_mode" {
  type = string
}

variable "customer_managed_key_enforcement" {
  type = bool
}

variable "hosting_mode" {
  type = string
}

variable "partition_count" {
  type = number
}

variable "replica_count" {
  type = number
}

variable "network_rule_bypass_option" {
  type = string
}

variable "public_network_access_enabled" {
  type = bool
}

variable "tags" {
  type = map(string)
}
