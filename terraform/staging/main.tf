terraform {
  backend "s3" {
    endpoint                = "https://minio.inspection.alpha.canada.ca"
    bucket                  = "terraform-staging-state"
    key                     = "tfstagingstate.tfstate"
    access_key              = var.minio_access_key
    secret_key              = var.minio_secret_key
    skip_metadata_api_check = true
    skip_region_validation  = true
    force_path_style        = true
  }
}

provider "azurerm" {
  features {}
}

module "az-rg" {
  source = "../modules/az-rg"

  resource_group_name = var.resource_group_name
  location            = var.location
}
