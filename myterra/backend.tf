terraform {
  backend "azurerm" {
    resource_group_name   = "another-RG"
    storage_account_name  = "backend2234"
    container_name        = "backend"
    key = "pmRzjbF61nzYiaNYuYLQpnmcITYhK46KkK935jbdqgd+BS1SOnPG8ioa6ZQ+RLx0GJBIP7sCLZY2+AStyobD7g=="
  }
}