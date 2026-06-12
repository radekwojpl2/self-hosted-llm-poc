// ---------------------------------------------------------------------------
// Ollama on an Azure Spot GPU VM
// - Spot priority (Deallocate eviction) for ~70-90% cost savings
// - No inbound SSH; access via Tailscale SSH only
// - Persistent data disk for models (survives evictions/restarts)
// - Azure-native auto-shutdown schedule
// ---------------------------------------------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Base name used to derive resource names.')
param namePrefix string = 'ollama'

@description('Admin username for the VM (login still via Tailscale SSH).')
param adminUsername string = 'azureuser'

@description('SSH public key (set on the VM; port 22 stays closed to internet).')
@secure()
param sshPublicKey string

@description('Tailscale auth key. Use a reusable, ephemeral, pre-authorized key.')
@secure()
param tailscaleAuthKey string

@description('GPU VM size (NC T4 v3 family).')
param vmSize string = 'Standard_NC4as_T4_v3'

@description('Max price you will pay per hour for the Spot VM. -1 = pay up to on-demand price.')
param spotMaxPrice string = '-1'

@description('Data disk size in GB for model storage.')
param dataDiskSizeGB int = 128

@description('Daily auto-shutdown time, 24h HHmm, in the timezone below.')
param autoShutdownTime string = '2000'

@description('Timezone for auto-shutdown (Windows timezone id).')
param autoShutdownTimeZone string = 'UTC'

var vnetName    = '${namePrefix}-vnet'
var subnetName  = '${namePrefix}-subnet'
var nsgName     = '${namePrefix}-nsg'
var pipName     = '${namePrefix}-pip'
var nicName     = '${namePrefix}-nic'
var vmName      = '${namePrefix}-vm'
var dataDiskName = '${namePrefix}-data'

// Cloud-init rendered with parameters, then base64-encoded for customData.
var cloudInit = format(loadTextContent('cloud-init.yaml'), tailscaleAuthKey, vmName)

// --- Networking -------------------------------------------------------------
// NSG with NO inbound SSH rule. Default rules deny inbound from internet;
// outbound is allowed so Tailscale can reach the coordination server.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.20.0.0/16'] }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.20.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

// Standard public IP is needed only for outbound Tailscale bootstrap.
// Cheaper than a NAT gateway for a single VM. No inbound ports are opened.
resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: pipName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
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
          subnet: { id: '${vnet.id}/subnets/${subnetName}' }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

// --- Persistent data disk for models ---------------------------------------
resource dataDisk 'Microsoft.Compute/disks@2023-10-02' = {
  name: dataDiskName
  location: location
  sku: { name: 'StandardSSD_LRS' }
  properties: {
    creationData: { createOption: 'Empty' }
    diskSizeGB: dataDiskSizeGB
  }
}

// --- Spot GPU VM ------------------------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: { maxPrice: json(spotMaxPrice) }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Attach'
          managedDisk: { id: dataDisk.id }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

// --- Azure-native auto-shutdown --------------------------------------------
resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: autoShutdownTime }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: vm.id
    notificationSettings: { status: 'Disabled' }
  }
}

output vmName string = vm.name
output publicIP string = pip.properties.ipAddress
output tailscaleHostname string = vmName
