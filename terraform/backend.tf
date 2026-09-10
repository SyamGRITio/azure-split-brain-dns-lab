terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

## Azure上にstateを保存する場合は専用stを作成し、以下を使用する。
/*
terraform {
  backend "azurerm" {
    resource_group_name = "value"
    storage_account_name = "value"
    container_name = "value"
    key = "value"

    use_azuread_auth = true
  }
}
*/
