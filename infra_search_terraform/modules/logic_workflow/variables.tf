variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "logic_app_name" {
  type = string
}

variable "blob_connection_name" {
  type = string
}

variable "blob_connection_display_name" {
  type = string
}

variable "sharepoint_connection_name" {
  type = string
}

variable "sharepoint_connection_display_name" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "sharepoint_site_url" {
  type = string
}

variable "sharepoint_library_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
