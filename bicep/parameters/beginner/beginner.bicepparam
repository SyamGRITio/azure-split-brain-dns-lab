using '../../main.bicep'

param deploymentPhase = 'private'
param enableBeginner = true
param customDomainName = 'syam-gritio.com'
param sshPublicKey = readEnvironmentVariable('SSH_KEY')
param sshSourceAddressPrefix = readEnvironmentVariable('MY_IP')
