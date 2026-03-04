variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "account_tier" {
  type = string
}

variable "account_replication_type" {
  type = string
}

variable "account_kind" {
  type = string
}

variable "access_tier" {
  type = string
}

variable "min_tls_version" {
  type = string
}

variable "public_network_access_enabled" {
  type = bool
}

variable "shared_access_key_enabled" {
  type = bool
}

variable "local_user_enabled" {
  type = bool
}

variable "https_traffic_only_enabled" {
  type = bool
}

variable "allow_nested_items_to_be_public" {
  type = bool
}

variable "default_network_action" {
  type = string
}

variable "network_bypass" {
  type = list(string)
}

variable "private_link_access" {
  type = list(object({
    endpoint_resource_id = string
    endpoint_tenant_id   = string
  }))
}

variable "tags" {
  type = map(string)
}
