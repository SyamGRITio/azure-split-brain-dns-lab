using '../../main.bicep'

param deploymentPhase = 'private'
param enableBeginner = false
param customDomainName = 'syam-gritio.com'
param sshPublicKey = readEnvironmentVariable('SSH_KEY')
param sshSourceAddressPrefix = readEnvironmentVariable('MY_IP')
