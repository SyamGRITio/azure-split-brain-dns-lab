data "http" "my_public_ip" {
  url = "https://api.ipify.org"
}

locals {
  operation_user_id = "REMOVED_AZURE_OBJECT_ID"

  tenant_id           = "REMOVED_AZURE_TENANT_ID"
  subscription_id     = "REMOVED_AZURE_SUBSCRIPTION_ID"
  resource_group_name = "rg-syam-dev"
  region              = "japaneast"

  my_public_ip_cider = "${trimspace(data.http.my_public_ip.response_body)}/32"

  common_tags = {
    managedBy = "Terraform"
  }
  suffix = substr(md5(azurerm_resource_group.main.id), 0, 6)

  # 初級編で使用するストレージアカウントを作成する場合は true にする
  enable_split_brain_dns_beginner = false

  my_custom_domain = "syam-gritio.com"
}

