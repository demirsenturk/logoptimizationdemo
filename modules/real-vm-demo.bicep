// ============================================================================
// Real VM Telemetry Demo
// Deploys a Linux VM with Azure Monitor Agent and associates a DCR for Syslog/Perf
// ============================================================================

@description('Azure region')
param location string

@description('Unique suffix for resource names')
param suffix string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Admin username for demo VM')
param adminUsername string = 'lawoptadmin'

@secure()
@description('Admin password for demo VM')
param adminPassword string

var vnetName = 'vnet-lawopt-${suffix}'
var subnetName = 'snet-lawopt'
var nicName = 'nic-lawopt-${suffix}'
var vmName = 'vm-lawopt-${suffix}'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.10.1.0/24'
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

var cloudInit = '''
#cloud-config
package_update: true
runcmd:
  - [ bash, -c, "echo '*/2 * * * * root logger -p user.notice \"lawopt-real-vm heartbeat $(date +%s)\"' > /etc/cron.d/lawopt-logger" ]
  - [ chmod, '0644', '/etc/cron.d/lawopt-logger' ]
  - [ systemctl, restart, cron ]
'''

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
      customData: base64(cloudInit)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource amaExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.30'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

resource vmDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-vm-real-${suffix}'
  location: location
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
          ]
        }
      ]
      syslog: [
        {
          name: 'syslogSource'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'user'
            'daemon'
            'syslog'
            'auth'
          ]
          logLevels: [
            'Notice'
            'Warning'
            'Error'
            'Critical'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'laDestination'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Syslog'
        ]
        destinations: [
          'laDestination'
        ]
      }
    ]
  }
}

resource vmDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'assoc-vm-real-dcr'
  scope: vm
  properties: {
    dataCollectionRuleId: vmDcr.id
    description: 'Association for real VM telemetry demo'
  }
}

output vmName string = vm.name
output vmId string = vm.id
output vmDcrId string = vmDcr.id
