// ============================================================================
// Real Windows VM Telemetry Demo
// Deploys a Windows VM with Azure Monitor Agent and associates a DCR for Event/Perf
// ============================================================================

@description('Azure region')
param location string

@description('Unique suffix for resource names')
param suffix string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Admin username for Windows demo VM')
param adminUsername string = 'lawoptadmin'

@secure()
@description('Admin password for Windows demo VM')
param adminPassword string

var vnetName = 'vnet-win-lawopt-${suffix}'
var subnetName = 'snet-win-lawopt'
var nicName = 'nic-win-lawopt-${suffix}'
var vmName = 'vmwin-lawopt-${suffix}'
var computerName = take(vmName, 15)

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.20.1.0/24'
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

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter'
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
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.22'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

resource vmDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-vmwin-real-${suffix}'
  location: location
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCountersWindows'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\LogicalDisk(_Total)\\% Free Space'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'windowsEventsSource'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
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
          'Microsoft-Event'
        ]
        destinations: [
          'laDestination'
        ]
      }
    ]
  }
}

resource vmDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'assoc-vmwin-real-dcr'
  scope: vm
  properties: {
    dataCollectionRuleId: vmDcr.id
    description: 'Association for real Windows VM telemetry demo'
  }
}

output vmName string = vm.name
output vmId string = vm.id
output vmDcrId string = vmDcr.id
