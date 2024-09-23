terraform {
  backend "azurerm" {
    resource_group_name   = "another-RG"
    storage_account_name  = "backend2234"
    container_name        = "backend"
    key = "test/terraform.tfstate"
  }
}