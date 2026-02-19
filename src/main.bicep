/*
  Possible improvements to the code for better re-use
  - Additional parameters for naming convention, IP range, etc.
  - No use of arrays which require hardcoded index references
  - Full list of location names
  - Use Elastic Premium Plan if secrets must be in Key Vault
    - Role assignments for the Key Vault
*/

param existingPrivateLinkDnsZonesResourceGroupResourceId string

param functionName string = 'TenableVM'
param sentinelWorkspaceId string
@secure()
param sentinelWorkspaceKey string
param appInsightsWorkspaceResourceID string
@secure()
param tenableAccessKey string
@secure()
param tenableSecretKey string

@allowed(['Critical', 'High', 'Medium', 'Low', 'Info'])
param lowestSeverity string = 'Info'
param complianceDataIngestion bool = false
param tenableExportScheduleInMinutes int = 1440
#disable-next-line secure-secrets-in-params
param secretExpirationDateSeedDate string = '2025-10-31T00:00:00Z'

param virtualNetworkAddressPrefix string = '10.0.0.0/24'

param virtualMachineLoginPrincipalId string
@secure()
param virtualMachineAdminPassword string
param virtualMachineEnableEncryptionAtHost bool = true

param deployAzureBastion bool = false

param enableAvmTelemetry bool = true

param sequence int = 1
param tags object = {}
param deploymentTime string = utcNow()

// HACK: I don't like the way Tenable developed this
var logAnalyticsUri = replace(environment().portal, 'https://portal', 'https://${sentinelWorkspaceId}.ods.opinsights')

// Calculate the secret expiration date as one year from the seed date
var secretExpirationDate = dateTimeAdd(secretExpirationDateSeedDate, 'P1Y')
var sequenceFormatted = format('{0:D2}', sequence)

var shortLocationNames = {
  eastus: 'eus'
  eastus2: 'eus2'
  westus: 'wus'
  westus2: 'wus2'
  westus3: 'wus3'
  centralus: 'cus'
  northcentralus: 'ncus'
  southcentralus: 'scus'
  canadacentral: 'cnc'
  // Add more locations as needed
}

// Create a NAT Gateway for outbound traffic from the app to Tenable
module natGatewayModule 'br/public:avm/res/network/nat-gateway:2.0.1' = {
  name: 'natGatewayDeployment'
  params: {
    name: 'ng-${functionName}-prod-${resourceGroup().location}-${sequenceFormatted}'
    tags: tags

    natGatewaySku: 'StandardV2'

    // Deploy non-zonal, pending zone redundancy support for NAT Gateway
    availabilityZone: -1

    // Create a public IP for the NAT Gateway and make it zone redundant even if NAT Gateway itself isn't yet
    publicIPAddresses: [
      {
        availabilityZones: [1, 2, 3]
        name: 'pip-ng-${functionName}-prod-${resourceGroup().location}-${sequenceFormatted}'
        skuTier: 'Regional'
        diagnosticSettings: [
          {
            name: 'customSetting'
            workspaceResourceId: appInsightsWorkspaceResourceID
          }
        ]
      }
    ]

    enableTelemetry: enableAvmTelemetry
  }
}

module networkSecurityGroupModule 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'networkSecurityGroupDeployment'
  params: {
    // Required parameters
    name: 'nsg-default-${functionName}-prod-${resourceGroup().location}-${sequenceFormatted}'
    tags: tags

    enableTelemetry: enableAvmTelemetry
  }
}

module networkSecurityGroupBastionModule 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'networkSecurityGroupBastionDeployment'
  params: {
    // Required parameters
    name: 'nsg-bas-${functionName}-prod-${resourceGroup().location}-${sequenceFormatted}'
    tags: tags

    // From https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg#apply
    securityRules: [
      {
        name: 'AllowBastionInbound'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 250
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommunicationInbound'
        properties: {
          priority: 300
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 150
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['22', '3389']
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommunicationOutbound'
        properties: {
          priority: 250
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          priority: 300
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]

    enableTelemetry: enableAvmTelemetry
  }
}

// Create the virtual network and subnets
module virtualNetworkModule 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'virtualNetworkDeployment'
  params: {
    // Required parameters
    addressPrefixes: [virtualNetworkAddressPrefix]
    name: 'vnet-${functionName}-prod-${resourceGroup().location}-${sequenceFormatted}'
    // Non-required parameters
    diagnosticSettings: [
      {
        name: 'customSetting'
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]
    flowTimeoutInMinutes: 20
    location: resourceGroup().location
    subnets: [
      {
        addressPrefix: cidrSubnet(virtualNetworkAddressPrefix, 28, 1)
        name: 'PrivateEndpointSubnet'
        networkSecurityGroupResourceId: networkSecurityGroupModule.outputs.resourceId
        defaultOutboundAccess: false
      }
      {
        addressPrefix: cidrSubnet(virtualNetworkAddressPrefix, 28, 2)
        name: 'ManagementSubnet'
        networkSecurityGroupResourceId: networkSecurityGroupModule.outputs.resourceId
        natGatewayResourceId: natGatewayModule.outputs.resourceId
        defaultOutboundAccess: false
      }
      {
        addressPrefix: cidrSubnet(virtualNetworkAddressPrefix, 27, 2)
        delegation: 'Microsoft.App/environments'
        name: 'FunctionAppSubnet'
        networkSecurityGroupResourceId: networkSecurityGroupModule.outputs.resourceId
        natGatewayResourceId: natGatewayModule.outputs.resourceId
        defaultOutboundAccess: false
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: cidrSubnet(virtualNetworkAddressPrefix, 26, 2)
        networkSecurityGroupResourceId: networkSecurityGroupBastionModule.outputs.resourceId
        defaultOutboundAccess: false
      }
    ]
    tags: tags

    enableTelemetry: enableAvmTelemetry
  }
}

// Link the existing private DNS zones.
// TODO: Make into a object
var privateDnsZoneNames = [
  'privatelink.azurewebsites.net'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.file.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.queue.core.windows.net'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.table.core.windows.net'
  'privatelink.vaultcore.azure.net'
]

var privateDnsZoneResourceGroupName = split(existingPrivateLinkDnsZonesResourceGroupResourceId, '/')[4]
var privateDnsZoneSubscriptionId = split(existingPrivateLinkDnsZonesResourceGroupResourceId, '/')[2]

resource privateDnsZonesResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: privateDnsZoneResourceGroupName
  scope: subscription(privateDnsZoneSubscriptionId)
}

resource existingPrivateLinkDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' existing = [
  for privateDnsZoneName in privateDnsZoneNames: {
    name: privateDnsZoneName
    scope: privateDnsZonesResourceGroup
  }
]

module privateDnsZonesVnetLinksModule 'modules/virtual-network-link/main.bicep' = [
  for privateDnsZoneName in privateDnsZoneNames: {
    name: take('dnsZoneVnetLinkDeployment-${privateDnsZoneName}', 64)
    scope: privateDnsZonesResourceGroup
    params: {
      privateDnsZoneName: privateDnsZoneName
      virtualNetworkResourceId: virtualNetworkModule.outputs.resourceId
      registrationEnabled: false
    }
  }
]

// Create the UAMI
module userAssignedIdentityModule 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.0' = {
  name: 'userAssignedIdentityDeployment'
  params: {
    // Required parameters
    name: 'id-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    // Non-required parameters
    tags: tags

    enableTelemetry: enableAvmTelemetry
  }
}

// Create the Key Vault with private endpoint and secrets
module vaultModule 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'vaultDeployment'
  params: {
    // Required parameters
    name: 'kv-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    // Non-required parameters
    diagnosticSettings: [
      {
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]
    enablePurgeProtection: false
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: existingPrivateLinkDnsZones[5].id
            }
          ]
        }
        service: 'vault'
        subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
      }
    ]
    secrets: [
      {
        attributes: {
          enabled: true
          exp: dateTimeToEpoch(secretExpirationDate)
        }
        contentType: 'The primary or secondary key for the Sentinel Log Analytics Workspace'
        name: 'sentinelWorkspaceKey'
        value: sentinelWorkspaceKey
      }
      {
        attributes: {
          enabled: true
          exp: dateTimeToEpoch(secretExpirationDate)
        }
        contentType: 'Tenable API Access Key'
        name: 'tenableAccessKey'
        value: tenableAccessKey
      }
      {
        attributes: {
          enabled: true
          exp: dateTimeToEpoch(secretExpirationDate)
        }
        contentType: 'Tenable API Secret Key'
        name: 'tenableSecretKey' // TODO: Don't hardcode secret names
        value: tenableSecretKey
      }
    ]
    softDeleteRetentionInDays: 7
    tags: tags

    // Assign a Key Vault data plane role to the UAMI
    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalType: 'ServicePrincipal'
      }
    ]

    enableTelemetry: enableAvmTelemetry
  }
}

var appPackageContainerName = 'app-package-${toLower(functionName)}'

// Create the Storage Account with private endpoint and the file share and container
module storageAccountModule 'br/public:avm/res/storage/storage-account:0.31.0' = {
  name: 'storageAccountDeployment'
  params: {
    // Required parameters
    name: toLower('st${functionName}${take(uniqueString(resourceGroup().id), 4)}${sequenceFormatted}')
    // Non-required parameters
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    blobServices: {
      containerDeleteRetentionPolicyEnabled: false
      containers: [
        {
          name: 'azure-webjobs-hosts'
          publicAccess: 'None'
        }
        {
          name: appPackageContainerName
          publicAccess: 'None'
        }
      ]
      diagnosticSettings: [
        {
          name: 'customSetting'
          workspaceResourceId: appInsightsWorkspaceResourceID
        }
      ]
    }
    diagnosticSettings: [
      {
        name: 'customSetting'
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]
    enableHierarchicalNamespace: false
    fileServices: {
      diagnosticSettings: [
        {
          name: 'customSetting'
          workspaceResourceId: appInsightsWorkspaceResourceID
        }
      ]
      shares: [
        {
          accessTier: 'Hot'
          name: toLower(functionName)
          shareQuota: 5120
        }
      ]
    }
    largeFileSharesState: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: existingPrivateLinkDnsZones[1].id
            }
          ]
        }
        service: 'blob'
        subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
        tags: tags
      }
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: existingPrivateLinkDnsZones[2].id
            }
          ]
        }
        service: 'file'
        subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
        tags: tags
      }
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: existingPrivateLinkDnsZones[3].id
            }
          ]
        }
        service: 'queue'
        subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
        tags: tags
      }
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: existingPrivateLinkDnsZones[4].id
            }
          ]
        }
        service: 'table'
        subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
        tags: tags
      }
    ]
    requireInfrastructureEncryption: true
    skuName: 'Standard_LRS'
    tags: tags

    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Storage File Data Privileged Contributor'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Storage Queue Data Contributor'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Storage Table Data Contributor'
        principalType: 'ServicePrincipal'
      }
    ]

    enableTelemetry: enableAvmTelemetry
  }
}

// Create the Application Insights resource
module componentModule 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'componentDeployment'
  params: {
    // Required parameters
    name: 'appi-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    workspaceResourceId: appInsightsWorkspaceResourceID
    // Non-required parameters
    diagnosticSettings: [
      {
        name: 'customSetting'
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]
    tags: tags

    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Monitoring Metrics Publisher'
        principalType: 'ServicePrincipal'
      }
    ]

    enableTelemetry: enableAvmTelemetry
  }
}

// Create the consumption plan
module serverfarmModule 'br/public:avm/res/web/serverfarm:0.6.0' = {
  name: 'serverfarmDeployment'
  params: {
    // Required parameters
    name: 'plan-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    // Non-required parameters
    diagnosticSettings: [
      {
        name: 'customSetting'
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]
    kind: 'linux'
    skuName: 'FC1'
    tags: tags
    zoneRedundant: false

    enableTelemetry: enableAvmTelemetry
  }
}

var functionAppSpecialTags = {
  'hidden-link: /app-insights-resource-id': componentModule.outputs.resourceId
}

// Create the Function App and assign UAMI
module functionAppModule 'br/public:avm/res/web/site:0.21.0' = {
  name: 'functionAppDeployment'
  params: {
    // Required parameters
    kind: 'functionapp,linux'
    name: 'func-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    serverFarmResourceId: serverfarmModule.outputs.resourceId

    httpsOnly: true

    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[2]
    outboundVnetRouting: {
      allTraffic: true
      contentShareTraffic: true
      applicationTraffic: true
    }

    autoGeneratedDomainNameLabelScope: 'SubscriptionReuse'

    configs: [
      {
        applicationInsightResourceId: componentModule.outputs.resourceId
        name: 'appsettings'
        properties: {
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${userAssignedIdentityModule.outputs.clientId};Authorization=AAD'
          APPLICATIONINSIGHTS_CONNECTION_STRING: componentModule.outputs.connectionString

          // Tenable app-specific settings
          WorkspaceID: sentinelWorkspaceId

          WorkspaceKey: '@Microsoft.KeyVault(SecretUri=${vaultModule.outputs.uri}secrets/sentinelWorkspaceKey)' // TODO: Do not hardcode secret names
          TIO_SECRET_KEY: '@Microsoft.KeyVault(SecretUri=${vaultModule.outputs.uri}secrets/tenableSecretKey)'
          TIO_ACCESS_KEY: '@Microsoft.KeyVault(SecretUri=${vaultModule.outputs.uri}secrets/tenableAccessKey)'

          LowestSeveritytoStore: lowestSeverity
          ComplianceDataIngestion: string(complianceDataIngestion)
          TenableExportSchedule: string(tenableExportScheduleInMinutes)
          PyTenableUAVendor: 'Microsoft'
          PyTenableUAProduct: 'Azure Sentinel' // The service name is 'Microsoft Sentinel', but Tenable uses 'Azure Sentinel'
          PyTenableUABuild: '0.0.1'
          logAnalyticsUri: logAnalyticsUri

          // Flex Consumption Plan must use OneDeploy, not ZipDeploy
          //WEBSITE_RUN_FROM_PACKAGE: 'https://aka.ms/sentinel-TenableVMAzureSentinelConnector310-functionapp'
          // https://raw.githubusercontent.com/Azure/Azure-Sentinel/refs/heads/master/Solutions/Tenable%20App/Data%20Connectors/TenableVM/TenableVMAzureSentinelConnector310.zip
        }
        storageAccountResourceId: storageAccountModule.outputs.resourceId
        storageAccountUseIdentityAuthentication: true
      }
    ]

    tags: union(tags, functionAppSpecialTags)

    keyVaultAccessIdentityResourceId: userAssignedIdentityModule.outputs.resourceId

    diagnosticSettings: [
      {
        name: 'customSetting'
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]

    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        userAssignedIdentityModule.outputs.resourceId
      ]
    }

    roleAssignments: [
      {
        // The UAMI is also assigned to the VM for deployment purposes
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'Website Contributor'
        principalType: 'ServicePrincipal'
      }
    ]

    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccountModule.outputs.primaryBlobEndpoint}${appPackageContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: userAssignedIdentityModule.outputs.resourceId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40 // 40 is the maximum for a flex consumption plan
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.11'
      }
    }

    siteConfig: {
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
    }

    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: existingPrivateLinkDnsZones[0].id
            }
          ]
        }
        service: 'sites'
        subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
        tags: tags
      }
    ]

    enableTelemetry: enableAvmTelemetry
  }
}

// Assign Storage Blob Data Contributor role to the Function App's system-assigned managed identity
module systemAssignedIdentityRoleAssignmentModule 'modules/roleAssignment-st/main.bicep' = {
  name: 'systemAssignedIdentityRoleAssignmentDeployment'
  params: {
    storageAccountName: storageAccountModule.outputs.name
    principalId: functionAppModule.outputs.?systemAssignedMIPrincipalId!
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalType: 'ServicePrincipal'
  }
}

// Create a virtual machine to perform the Function app deployment
// TODO: Enable TrustedLaunch
module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.21.0' = {
  name: 'virtualMachineDeployment'
  params: {
    // Required parameters
    availabilityZone: -1
    name: 'vm-${functionName}-${sequenceFormatted}'
    nicConfigurations: [
      {
        deleteOption: 'Delete'
        diagnosticSettings: [
          {
            name: 'customSetting'
            workspaceResourceId: appInsightsWorkspaceResourceID
          }
        ]
        ipConfigurations: [
          {
            diagnosticSettings: [
              {
                name: 'customSetting'
                workspaceResourceId: appInsightsWorkspaceResourceID
              }
            ]
            name: 'ipconfig01'
            subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[1]
          }
        ]
        name: 'vm-${functionName}-${sequenceFormatted}-nic'
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      createOption: 'FromImage'
      deleteOption: 'Delete'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
      name: 'vm-${functionName}-${sequenceFormatted}-osDisk'
    }
    osType: 'Windows'
    vmSize: 'Standard_D2as_v5'
    // Non-required parameters
    // HACK: 2026-02-17: Does not install AZ CLI :(
    // additionalUnattendContent: [
    //   {
    //     content: '<FirstLogonCommands><SynchronousCommand><CommandLine>cmd /c winget install -e -h -s winget --id Microsoft.AzureCLI</CommandLine><Description>Install Azure CLI</Description><Order>1</Order></SynchronousCommand></FirstLogonCommands>'
    //     settingName: 'FirstLogonCommands'
    //   }
    // ]
    adminPassword: virtualMachineAdminPassword
    adminUsername: 'AzureUser'
    // autoShutdownConfig: {
    //   dailyRecurrenceTime: '19:00'
    //   notificationSettings: {
    //     emailRecipient: 'test@contoso.com'
    //     notificationLocale: 'en'
    //     status: 'Enabled'
    //     timeInMinutes: 30
    //   }
    //   status: 'Enabled'
    //   timeZone: 'UTC'
    // }
    computerName: take('vm-${functionName}-${sequenceFormatted}', 15)
    enableAutomaticUpdates: true
    encryptionAtHost: virtualMachineEnableEncryptionAtHost
    extensionAadJoinConfig: {
      enabled: true
      name: 'EntraIDLoginExtension'
      settings: {
        mdmId: ''
      }
      tags: tags
    }
    extensionAntiMalwareConfig: {
      enabled: true
      name: 'AntiMalwareExtension'
      settings: {
        AntimalwareEnabled: 'true'
        RealtimeProtectionEnabled: 'true'
        ScheduledScanSettings: {
          day: '7'
          isEnabled: 'true'
          scanType: 'Quick'
          time: '120'
        }
      }
      tags: tags
    }
    // Run custom Function app deployment script
    // Flexible Consumption model doesn't support specifying the zip file as an environment variable during deployment.
    // Therefore, we need to deploy the zip file separately after the function app is created.
    extensionCustomScriptConfig: {
      name: 'FxAppDeployScript'
      protectedSettings: {}
      settings: {
        commandToExecute: 'powershell -ExecutionPolicy Bypass -File Deploy-FunctionApp.ps1 -ResourceGroupName ${resourceGroup().name} -FunctionAppName ${functionAppModule.outputs.name} -ClientId ${userAssignedIdentityModule.outputs.clientId}'
        fileUris: [
          // TODO: Update to main branch or release tag
          'https://raw.githubusercontent.com/SvenAelterman/TenableVMSentinelFunctionAppWithSecuredStorage/refs/heads/1-flex-consumption-fx-app-now-supports-retrieving-kv-secrets-over-private-endpoint/src/scripts/Deploy-FunctionApp.ps1'
        ]
      }
      forceUpdateTag: deploymentTime
      tags: tags
    }
    managedIdentities: {
      systemAssigned: true // Required for Entra ID Join
      userAssignedResourceIds: [
        // Used to deploy the function app code from the VM
        userAssignedIdentityModule.outputs.resourceId
      ]
    }
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2025-datacenter-azure-edition'
      version: 'latest'
    }
    patchMode: 'AutomaticByPlatform'
    rebootSetting: 'IfRequired'
    roleAssignments: [
      {
        principalId: virtualMachineLoginPrincipalId
        roleDefinitionIdOrName: 'Virtual Machine Administrator Login'
      }
    ]
    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}

module bastionHost 'br/public:avm/res/network/bastion-host:0.8.2' = if (deployAzureBastion) {
  name: 'bastionHostDeployment'
  params: {
    // Required parameters
    name: 'bas-${functionName}-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    virtualNetworkResourceId: virtualNetworkModule.outputs.resourceId

    // Non-required parameters
    publicIPAddressObject: {
      name: 'pip-bas-${functionName}-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
      publicIPAllocationMethod: 'Static'
      skuName: 'Standard'
      skuTier: 'Regional'
      tags: tags
    }
    availabilityZones: [1, 2, 3]
    diagnosticSettings: [
      {
        name: 'customSetting'
        workspaceResourceId: appInsightsWorkspaceResourceID
      }
    ]
    skuName: 'Basic'
    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}

output functionAppName string = functionAppModule.outputs.name
