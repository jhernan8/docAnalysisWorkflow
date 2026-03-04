variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "admin_ai_name" {
  type = string
}

variable "admin_ai_custom_subdomain_name" {
  type = string
}

variable "cognitive_project_name" {
  type = string
}

variable "cognitive_project_description" {
  type = string
}

variable "cognitive_project_display_name" {
  type = string
}

variable "create_cognitive_project" {
  type    = bool
  default = false
}

variable "sku_name" {
  type = string
}

variable "local_authentication_enabled" {
  type = bool
}

variable "outbound_network_access_restricted" {
  type = bool
}

variable "public_network_access" {
  type = string
}

variable "network_default_action" {
  type = string
}

variable "tags" {
  type = map(string)
}
