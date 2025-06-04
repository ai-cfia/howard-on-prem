variable "resource_group_name" {
  type        = string
  description = "Auzre resource group name"
  sensitive = true
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "canadacentral"
  sensitive = true
}
