provider "azurerm" {
  features {}

  tenant_id       = local.tenant_id
  subscription_id = local.subscription_id
}

provider "azapi" {
  tenant_id       = local.tenant_id
  subscription_id = local.subscription_id
}
