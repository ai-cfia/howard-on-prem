variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "minio_access_key" {
  type      = string
  sensitive = true
}

variable "minio_secret_key" {
  type      = string
  sensitive = true
}
