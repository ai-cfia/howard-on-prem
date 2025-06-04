terraform {
  backend "s3" {
    bucket                      = "terraform-staging-state"
    key                         = "tfstagingstate.tfstate"
    region                      = "main"
    skip_credentials_validation = true # Skip AWS related checks and validations
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    endpoints = {
      s3 = "https://minio.inspection.alpha.canada.ca"
    }
  }
}

provider "azurerm" {
  features {}
}
