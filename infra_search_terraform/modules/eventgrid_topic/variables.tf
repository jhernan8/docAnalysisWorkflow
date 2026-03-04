variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "eventgrid_topic_name" {
  type = string
}

variable "source_resource_id" {
  type = string
}

variable "topic_type" {
  type = string
}

variable "tags" {
  type = map(string)
}
