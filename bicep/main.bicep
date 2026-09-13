targetScope = 'subscription'

@allowed([
  'base'
  'certificate'
  'private'
])
param deploymentPhase string
param enableBeginner bool = false
@minLength(1)
param sshPublicKey string
param sshSourceAddressPrefix string

param customDomainName string = 'syam-gritio.com'

var location = 'japaneast'
var CommonTags = {
  ManagedBy: 'Bicep'
}

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-syam-dev'
  location: location
  tags: CommonTags
}

module resources 'resources.bicep' = {
  name: 'deploy-resources-${deploymentPhase}'
  scope: rg
  params: {
    deploymentPhase: deploymentPhase
    enableBeginner: enableBeginner
    sshSourceAddressPrefix: sshSourceAddressPrefix
    sshPublicKey: sshPublicKey
    customDomainName: customDomainName
    location: location
    commonTags: CommonTags
  }
}
