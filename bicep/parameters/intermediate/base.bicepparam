using '../../main.bicep'

param deploymentPhase = 'base'
param enableBeginner = false
param customDomainName = 'syam-gritio.com'
param sshPublicKey = readEnvironmentVariable('SSH_KEY')
param sshSourceAddressPrefix = readEnvironmentVariable('MY_IP')
