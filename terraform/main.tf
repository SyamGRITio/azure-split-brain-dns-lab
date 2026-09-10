data "azurerm_resource_group" "main" {
  name = local.resource_group_name
}

### Network (VNet+ subNet×2 + NSG + NSG association) ###
resource "azurerm_virtual_network" "main" {
  name                           = "vnet-dev-001"
  resource_group_name            = local.resource_group_name
  location                       = local.region
  private_endpoint_vnet_policies = "Disabled"
  address_space = [
    "10.0.0.0/16"
  ]
  tags = local.common_tags
}

resource "azurerm_subnet" "pe" {
  name                                          = "snet-pe"
  resource_group_name                           = local.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.main.name
  address_prefixes                              = ["10.0.1.0/27"]
  private_link_service_network_policies_enabled = true
}

resource "azurerm_subnet" "vm" {
  name                                          = "snet-vm"
  resource_group_name                           = local.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.main.name
  address_prefixes                              = ["10.0.0.0/27"]
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.ssh.id
}

resource "azurerm_network_security_group" "ssh" {
  name                = "nsg-dev-ssh"
  location            = local.region
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
  security_rule {
    name                       = "AllowMyIPSsh"
    access                     = "Allow"
    direction                  = "Inbound"
    priority                   = 100
    source_address_prefix      = local.my_public_ip_cider
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "22"
    protocol                   = "Tcp"

  }
}

### Computing(VM + PIP + NIC + 拡張機能 + RBAC + 自動シャットダウン ) ###
resource "azurerm_linux_virtual_machine" "ssh" {
  name                            = "vm-dev-ssh"
  location                        = "japaneast"
  resource_group_name             = local.resource_group_name
  network_interface_ids           = [azurerm_network_interface.ssh.id]
  size                            = "Standard_B2ts_v2"
  computer_name                   = "vm-dev-ssh"
  admin_username                  = "azureuser"
  tags                            = local.common_tags
  disable_password_authentication = true
  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 30
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    offer     = "ubuntu-24_04-lts"
    publisher = "canonical"
    sku       = "server"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9MB0kt1OY53YmfDbsgBOotalBoXVYIzTJuH1sS/NP2o7LUqKbwPjgmIhfhhMjzHx2oyyRkRfgSsOOmdUtT6sMoED3meF4OZtXsmlx8eLGggv2477VPaummdAyhzxqSgaau3SZ6j9M+g8aRt3MWD4DCMSicZJbuD71SO+tVChQGP/om3quAE7UiX5pfI7Myo8cMKeWkPNPFDkWcqxw3Npa7qnG7SFdyc2YGRF0450joJX4CG9q8TH6k6V+bbmdOQRttnaQT1lH6fPsE0Io9NcGIzZ3x64DBRswS4z7ULDsWyeqCQk+Tu7hIkVBmkiD5+dNCDJ4Xs9fCu4sr0EfpEW17iyPH9cHL81623S35Nyk2ppcJ6sOG/54OkQ+2ox3bHMDp37N5KeN8pjiGz278xpMvVNtFN0dgcLzC5rUK6PYtEZVnXi50SwRsQpddXkXmPDx2WjXQ2gkOJL2VP5rYjpU7lw+pDmDuKh6HU4TU94e4Pfb/3yvBafs+9lNBTnWoIk= generated-by-azure"
  }

  identity {
    type = "SystemAssigned"
  }
  additional_capabilities {}
  boot_diagnostics {}

}

resource "azurerm_public_ip" "ssh" {
  name                    = "pep-dev-ssh"
  resource_group_name     = local.resource_group_name
  location                = local.region
  allocation_method       = "Static"
  ddos_protection_mode    = "VirtualNetworkInherited"
  idle_timeout_in_minutes = 4
  ip_version              = "IPv4"
  sku                     = "Standard"
  sku_tier                = "Regional"
  tags                    = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_network_interface" "ssh" {
  name                           = "nic-dev-ssh"
  resource_group_name            = local.resource_group_name
  location                       = local.region
  accelerated_networking_enabled = true
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address            = "10.0.0.4"
    primary                       = true
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv4"
    public_ip_address_id          = azurerm_public_ip.ssh.id
    subnet_id                     = azurerm_subnet.vm.id
  }
  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_virtual_machine_extension" "aad_login" {
  name                       = "AADSSHLoginForLinux"
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  virtual_machine_id         = azurerm_linux_virtual_machine.ssh.id
  auto_upgrade_minor_version = true
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  tags                       = local.common_tags

}

resource "azurerm_role_assignment" "vm_admin" {
  name                 = "0a7c3764-221b-4087-93af-0f45813ffc7f"
  scope                = azurerm_linux_virtual_machine.ssh.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = local.operation_user_id
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "ssh" {
  virtual_machine_id    = azurerm_linux_virtual_machine.ssh.id
  location              = local.region
  enabled               = true
  daily_recurrence_time = "0200"                # 毎日午前2:00（2000）を指定
  timezone              = "Tokyo Standard Time" # 日本時間（JST）ベース
  notification_settings {
    enabled = false
  }
}

### Azure Private Endpointとsplit-brain DNSを実機で確認する（初級 privatelinkのCNAME）での対象リソース
### Storage Account + Private DNS Zone + Private Endpoint + 仮想ネットワークリンク
resource "azurerm_storage_account" "split_brain_dns" {
  count                             = local.enable_split_brain_dns_beginner ? 1 : 0
  name                              = "stdevsplitbraindns${local.suffix}"
  location                          = local.region
  resource_group_name               = local.resource_group_name
  access_tier                       = "Hot"
  account_kind                      = "StorageV2"
  account_replication_type          = "LRS"
  account_tier                      = "Standard"
  dns_endpoint_type                 = "Standard"
  https_traffic_only_enabled        = true
  local_user_enabled                = true
  min_tls_version                   = "TLS1_2"
  provisioned_billing_model_version = null
  public_network_access_enabled     = false
  queue_encryption_key_type         = "Service"
  shared_access_key_enabled         = true
  table_encryption_key_type         = "Service"
  tags                              = local.common_tags
  blob_properties {
    container_delete_retention_policy {
      days = 7
    }
    delete_retention_policy {
      days = 7
    }
  }
  network_rules {
    bypass         = ["None"]
    default_action = "Deny"
  }
  share_properties {
    retention_policy {
      days = 7
    }
  }
}

resource "azurerm_private_dns_zone" "split_brain_dns" {
  count               = local.enable_split_brain_dns_beginner ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
  soa_record {
    email        = "azureprivatedns-host.microsoft.com"
    expire_time  = 2419200
    minimum_ttl  = 10
    refresh_time = 36
    retry_time   = 300
    tags         = local.common_tags
    ttl          = 3600
  }
}

resource "azurerm_private_endpoint" "split_brain_dns" {
  count                         = local.enable_split_brain_dns_beginner ? 1 : 0
  name                          = "pe-st"
  custom_network_interface_name = "pe-st-nic"
  location                      = local.region
  resource_group_name           = "SyamRG-dev"
  subnet_id                     = azurerm_subnet.pe.id
  tags                          = local.common_tags

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.split_brain_dns[0].id]
  }

  private_service_connection {
    name                           = "pe-st"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.split_brain_dns[0].id
    subresource_names              = ["blob"]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "split_brain_dns" {
  count                = local.enable_split_brain_dns_beginner ? 1 : 0
  name                 = "link-vnet-dev-001"
  private_dns_zone_id  = azurerm_private_dns_zone.split_brain_dns[0].id
  virtual_network_id   = azurerm_virtual_network.main.id
  registration_enabled = false
  tags                 = local.common_tags
}

### Azure Private Endpointとsplit-brain DNSを実機で確認する（中級編 カスタムドメイン）での対象リソース
### Container Apps 環境 + Container Apps + Private DNS Zone + Private Endpoint + 仮想ネットワークリンク

# CAE
resource "azurerm_container_app_environment" "main" {
  name                = "cae-dev"
  resource_group_name = local.resource_group_name
  location            = local.region
  workload_profile {
    maximum_count         = 0
    minimum_count         = 0
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
  public_network_access = "Disabled"
  tags                  = local.common_tags
}

# ACA
resource "azurerm_container_app" "main" {
  name                         = "ca-dev-nginx"
  resource_group_name          = local.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  max_inactive_revisions       = 100
  workload_profile_name        = "Consumption"

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 80
    transport                  = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "ca-dev-nginx"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"
    }
  }

  tags = local.common_tags
}

## Custom Domain ＆ Certificate
resource "azurerm_container_app_custom_domain" "www" {
  name                     = "www.${local.my_custom_domain}"
  certificate_binding_type = "SniEnabled"
  container_app_id         = azurerm_container_app.main.id
}

resource "azurerm_container_app_environment_managed_certificate" "www" {
  name                         = "www.${local.my_custom_domain}-cae-dev-260907093414"
  container_app_environment_id = azurerm_container_app_environment.main.id
  domain_control_validation    = "CNAME"
  subject_name                 = "www.${local.my_custom_domain}"
  tags                         = local.common_tags

  depends_on = [
    azurerm_container_app_custom_domain.www
  ]
}

resource "azurerm_container_app_custom_domain" "apex" {
  name                     = local.my_custom_domain
  certificate_binding_type = "SniEnabled"
  container_app_id         = azurerm_container_app.main.id
}

resource "azurerm_container_app_environment_managed_certificate" "apex" {
  name                         = "${local.my_custom_domain}-syamrg-d-260907105451"
  container_app_environment_id = azurerm_container_app_environment.main.id
  domain_control_validation    = "HTTP"
  subject_name                 = local.my_custom_domain
  tags                         = local.common_tags

  depends_on = [
    azurerm_container_app_custom_domain.apex
  ]
}

# Destroy時に、証明書を削除する前に紐付けを解除する (証明書の紐付け解除 → 証明書削除 → カスタムドメイン削除)
resource "azapi_resource_action" "unbind_certificates" {
  type        = "Microsoft.App/containerApps@2025-07-01"
  resource_id = azurerm_container_app.main.id
  method      = "PATCH"
  when        = "destroy"

  body = {
    location = local.region
    properties = {
      configuration = {
        ingress = {
          customDomains = [
            {
              name          = "www.${local.my_custom_domain}"
              bindingType   = "Disabled"
              certificateId = null
            },
            {
              name          = local.my_custom_domain
              bindingType   = "Disabled"
              certificateId = null
            }
          ]
        }
      }
    }
  }

  # Destroyでは依存関係が逆順になり、この処理が証明書削除より先になる
  depends_on = [
    azurerm_container_app_environment_managed_certificate.www,
    azurerm_container_app_environment_managed_certificate.apex,
  ]
}

## Private Endpoint
resource "azurerm_private_endpoint" "aca_environment" {
  name                          = "pe-aca"
  resource_group_name           = local.resource_group_name
  custom_network_interface_name = "pe-aca-nic"
  location                      = local.region
  subnet_id                     = azurerm_subnet.pe.id
  tags                          = local.common_tags
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.aca_private_link.id]
  }
  private_service_connection {
    is_manual_connection           = false
    name                           = "pe-aca"
    private_connection_resource_id = azurerm_container_app_environment.main.id
    subresource_names              = ["managedEnvironments"]
  }
}

resource "azurerm_private_dns_zone" "aca_private_link" {
  name                = "privatelink.japaneast.azurecontainerapps.io"
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
  soa_record {
    email        = "azureprivatedns-host.microsoft.com"
    expire_time  = 2419200
    minimum_ttl  = 10
    refresh_time = 3600
    retry_time   = 300
    tags         = local.common_tags
    ttl          = 3600
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca_private_link" {
  name                = "link-aca"
  private_dns_zone_id = azurerm_private_dns_zone.aca_private_link.id
  tags                = local.common_tags
  virtual_network_id  = azurerm_virtual_network.main.id
}

# Apex Domain`s Private DNS Zone
resource "azurerm_private_dns_zone" "custom_domain" {
  name                = local.my_custom_domain
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
  soa_record {
    email        = "azureprivatedns-host.microsoft.com"
    expire_time  = 2419200
    minimum_ttl  = 10
    refresh_time = 3600
    retry_time   = 300
    tags         = local.common_tags
    ttl          = 3600
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "custom_domain" {
  name                 = "link-${local.my_custom_domain}"
  private_dns_zone_id  = azurerm_private_dns_zone.custom_domain.id
  registration_enabled = false
  virtual_network_id   = azurerm_virtual_network.main.id
  tags                 = local.common_tags
}

resource "azurerm_private_dns_cname_record" "www" {
  name                = "www"
  private_dns_zone_id = azurerm_private_dns_zone.custom_domain.id
  record              = azurerm_container_app.main.ingress[0].fqdn
  tags                = local.common_tags
  ttl                 = 3600
}

resource "azurerm_private_dns_a_record" "apex" {
  name                = "@"
  private_dns_zone_id = azurerm_private_dns_zone.custom_domain.id
  records             = [azurerm_private_endpoint.aca_environment.private_service_connection[0].private_ip_address]
  tags                = local.common_tags
  ttl                 = 3600
}
