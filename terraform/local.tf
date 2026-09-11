data "http" "my_public_ip" {
  url = "https://api.ipify.org"
}

data "azurerm_client_config" "current" {}

locals {
  resource_group_name = "rg-syam-dev"
  region              = "japaneast"
  my_public_ip_cider  = "${trimspace(data.http.my_public_ip.response_body)}/32"
  ssh_public_key_path = "~/.ssh/id_rsa.pub"
  my_custom_domain    = "syam-gritio.com"
  common_tags = {
    managedBy = "Terraform"
  }
  suffix = substr(md5(azurerm_resource_group.main.id), 0, 6)

  # 初級編で使用するストレージアカウントを作成する場合は true にする
  enable_split_brain_dns_beginner = false
}

# 作成段階はコマンドから指定する（指定忘れを防ぐためデフォルトなし）
variable "deployment_phase" {
  type        = string
  description = "作成段階：base → certificate → private"

  validation {
    condition     = contains(["base", "certificate", "private"], var.deployment_phase)
    error_message = "deployment_phase は base、certificate、private のいずれかを指定してください。"
  }
}

locals {
  # 各段階で維持する構成
  deployment_settings = {
    base = {
      public_network_access = "Enabled"
      enable_certificates   = false
      enable_private_access = false
    }

    certificate = {
      public_network_access = "Enabled"
      enable_certificates   = true
      enable_private_access = false
    }

    private = {
      public_network_access = "Disabled"
      enable_certificates   = true
      enable_private_access = true
    }
  }

  # コマンドで指定された段階の設定を選ぶ
  deployment = local.deployment_settings[var.deployment_phase]
}
