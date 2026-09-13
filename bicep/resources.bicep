targetScope = 'resourceGroup'

param deploymentPhase string
param enableBeginner bool
param sshSourceAddressPrefix string
param sshPublicKey string
param customDomainName string
param location string
param commonTags object

// 作成段階ごとに、公開アクセスと追加リソースの有効状態を切り替える
var deploymentSettings = {
  base: {
    publicNetworkAccess: 'Enabled'
    enableCertificates: false
    enablePrivateAccess: false
  }
  certificate: {
    publicNetworkAccess: 'Enabled'
    enableCertificates: true
    enablePrivateAccess: false
  }
  private: {
    publicNetworkAccess: 'Disabled'
    enableCertificates: true
    enablePrivateAccess: true
  }
}

var deployment = deploymentSettings[deploymentPhase]

// Network (VNet+ subNet×2 + NSG)
resource vnet 'Microsoft.Network/virtualNetworks@2025-07-01' = {
  name: 'vnet-dev'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource peSnet 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  parent: vnet
  name: 'snet-pe'
  properties: {
    addressPrefix: '10.0.1.0/27'
  }
}
resource vmSnet 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  parent: vnet
  name: 'snet-vm'
  properties: {
    addressPrefix: '10.0.0.0/27'
    networkSecurityGroup: {
      id: sshNsg.id
    }
  }
}

resource sshNsg 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
  name: 'nsg-dev-ssh'
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'AllowMyIPSsh'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: sshSourceAddressPrefix
          destinationPortRange: '22'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Computing(VM + PIP + NIC + 拡張機能 + RBAC + 自動シャットダウン ) 
resource sshVm 'Microsoft.Compute/virtualMachines@2026-03-01' = {
  name: 'vm-dev-ssh'
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ts_v2'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: sshNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    osProfile: {
      computerName: 'vm-dev-ssh'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        diskSizeGB: 30
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource sshPip 'Microsoft.Network/publicIPAddresses@2025-07-01' = {
  name: 'pip-dev-ssh'
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
    ddosSettings: {
      protectionMode: 'VirtualNetworkInherited'
    }
  }
}

resource sshNic 'Microsoft.Network/networkInterfaces@2025-07-01' = {
  name: 'nic-dev-ssh'
  location: location
  tags: commonTags
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: vmSnet.id
          }
          publicIPAddress: {
            id: sshPip.id
          }
        }
      }
    ]
  }
}

resource aadSshLogin 'Microsoft.Compute/virtualMachines/extensions@2026-03-01' = {
  parent: sshVm
  name: 'AADSSHLoginForLinux'
  location: location
  tags: commonTags
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADSSHLoginForLinux'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}

var vmAdministratorLoginRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '1c0163c0-47e6-4577-8991-ea5c82e286e4'
)

resource vmAdministratorLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sshVm.id, vmAdministratorLoginRoleId, deployer().objectId)
  scope: sshVm
  properties: {
    principalId: deployer().objectId
    roleDefinitionId: vmAdministratorLoginRoleId
  }
}

resource vmShutdownSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${sshVm.name}'
  location: location
  tags: commonTags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    targetResourceId: sshVm.id
    timeZoneId: 'Tokyo Standard Time'
    dailyRecurrence: {
      time: '0200'
    }
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// Azure Private Endpointとsplit-brain DNSを実機で確認する（初級 privatelinkのCNAME）での対象リソース
// Storage Account + Private DNS Zone + Private Endpoint + 仮想ネットワークリンク
var storageAccountSuffix = take(uniqueString(resourceGroup().id), 6)

resource beginnerStorageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = if (enableBeginner) {
  name: 'stdevsplitbraindns${storageAccountSuffix}'
  location: location
  tags: commonTags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Disabled'
    dnsEndpointType: 'Standard'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource beginnerPrivateEndpoint 'Microsoft.Network/privateEndpoints@2025-07-01' = if (enableBeginner) {
  name: 'pe-st'
  location: location
  tags: commonTags
  properties: {
    customNetworkInterfaceName: 'pe-st-nic'
    subnet: {
      id: peSnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-st'
        properties: {
          privateLinkServiceId: beginnerStorageAccount!.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource beginnerPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (enableBeginner) {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: commonTags
}

resource beginnerDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-07-01' = if (enableBeginner) {
  parent: beginnerPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: beginnerPrivateDnsZone!.id
        }
      }
    ]
  }
}

resource beginnerVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (enableBeginner) {
  parent: beginnerPrivateDnsZone
  name: 'link-vnet-dev-001'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Azure Private Endpointとsplit-brain DNSを実機で確認する（中級編 カスタムドメイン）での対象リソース
// Container Apps 環境 + Container Apps + Private DNS Zone + Private Endpoint + 仮想ネットワークリンク
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: 'cae-dev'
  location: location
  tags: commonTags
  properties: {
    publicNetworkAccess: deployment.publicNetworkAccess
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: 'ca-dev-nginx'
  location: location
  tags: commonTags
  properties: {
    environmentId: containerAppEnvironment.id
    workloadProfileName: 'Consumption'

    configuration: {
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: 100
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 80
        transport: 'auto'

        customDomains: deployment.enableCertificates
          ? [
              {
                name: 'www.${customDomainName}'
                bindingType: 'Auto'
              }
              {
                name: customDomainName
                bindingType: 'Auto'
              }
            ]
          : []

        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }

    template: {
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
      containers: [
        {
          name: 'ca-dev-nginx'
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
    }
  }
}

// マネージド証明書
resource wwwManagedCertificate 'Microsoft.App/managedEnvironments/managedCertificates@2026-01-01' = if (deployment.enableCertificates) {
  parent: containerAppEnvironment
  name: 'mc-www-${replace(customDomainName, '.', '-')}'
  location: location
  tags: commonTags
  properties: {
    subjectName: 'www.${customDomainName}'
    domainControlValidation: 'CNAME'
  }
  dependsOn: [
    containerApp
  ]
}

resource apexManagedCertificate 'Microsoft.App/managedEnvironments/managedCertificates@2026-01-01' = if (deployment.enableCertificates) {
  parent: containerAppEnvironment
  name: 'mc-${replace(customDomainName, '.', '-')}'
  location: location
  tags: commonTags
  properties: {
    subjectName: customDomainName
    domainControlValidation: 'HTTP'
  }
  dependsOn: [
    containerApp
  ]
}

// Private Endpoint
resource acaPrivateEndpoint 'Microsoft.Network/privateEndpoints@2025-07-01' = if (deployment.enablePrivateAccess) {
  name: 'pe-aca'
  location: location
  tags: commonTags
  properties: {
    customNetworkInterfaceName: 'pe-aca-nic'
    subnet: {
      id: peSnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-aca'
        properties: {
          privateLinkServiceId: containerAppEnvironment.id
          groupIds: [
            'managedEnvironments'
          ]
        }
      }
    ]
  }
}

// Private Endpointによって作成されるNICを参照するための定義
resource acaPrivateEndpointNic 'Microsoft.Network/networkInterfaces@2025-07-01' existing = if (deployment.enablePrivateAccess) {
  name: 'pe-aca-nic'
}

resource acaPrivateLinkDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (deployment.enablePrivateAccess) {
  name: 'privatelink.japaneast.azurecontainerapps.io'
  location: 'global'
  tags: commonTags
}

resource acaPrivateLinkVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (deployment.enablePrivateAccess) {
  parent: acaPrivateLinkDnsZone
  name: 'link-aca'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource acaPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-07-01' = if (deployment.enablePrivateAccess) {
  parent: acaPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'aca-private-link'
        properties: {
          privateDnsZoneId: acaPrivateLinkDnsZone!.id
        }
      }
    ]
  }
}

// Apex Domain`s Private DNS Zone
resource customDomainPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (deployment.enablePrivateAccess) {
  name: customDomainName
  location: 'global'
  tags: commonTags
}

resource customDomainVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (deployment.enablePrivateAccess) {
  parent: customDomainPrivateDnsZone
  name: 'link-${customDomainName}'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// apexドメインをPrivate EndpointのIPへ向ける
resource customDomainApexRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = if (deployment.enablePrivateAccess) {
  parent: customDomainPrivateDnsZone
  name: '@'
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: acaPrivateEndpointNic!.properties.ipConfigurations[0].properties.privateIPAddress
      }
    ]
  }
  dependsOn: [
    acaPrivateEndpoint
  ]
}

// Public DNS側で隠れたwwwのCNAMEをPrivate DNS Zone側にも作成する
resource customDomainWwwRecord 'Microsoft.Network/privateDnsZones/CNAME@2024-06-01' = if (deployment.enablePrivateAccess) {
  parent: customDomainPrivateDnsZone
  name: 'www'
  properties: {
    ttl: 3600
    cnameRecord: {
      cname: containerApp.properties.configuration.ingress.fqdn
    }
  }
}
