/*
  Possible improvements to the code for better re-use
  - Additional parameters for naming convention, IP range, etc.
  - No use of arrays which require hardcoded index references
  - Full list of location names
  - Use Elastic Premium Plan if secrets must be in Key Vault
    - Role assignments for the Key Vault
*/

// TODO: Use NAT Gateway for outbound traffic

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
// #disable-next-line secure-secrets-in-params
// param secretExpirationDateSeedDate string = '2025-05-31T00:00:00Z'

param sequence int = 1
param tags object = {}

// HACK: I don't like the way Tenable developed this
var logAnalyticsUri = replace(environment().portal, 'https://portal', 'https://${sentinelWorkspaceId}.ods.opinsights')

// var secretExpirationDate = dateTimeAdd(secretExpirationDateSeedDate, 'P1Y')
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

module networkSecurityGroupModule 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: 'networkSecurityGroupDeployment'
  params: {
    // Required parameters
    name: 'nsg-${functionName}-prod-${resourceGroup().location}-${sequenceFormatted}'
    tags: tags
  }
}

// Create the virtual network and subnets
module virtualNetworkModule 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'virtualNetworkDeployment'
  params: {
    // Required parameters
    addressPrefixes: [
      // Hardcoding in this case because this won't be peered to anything else
      '10.0.0.0/24'
    ]
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
        addressPrefix: '10.0.0.0/28'
        name: 'PrivateEndpointSubnet'
        networkSecurityGroupResourceId: networkSecurityGroupModule.outputs.resourceId
      }
      {
        addressPrefix: '10.0.0.64/26'
        delegation: 'Microsoft.App/environments'
        name: 'FunctionAppSubnet'
        networkSecurityGroupResourceId: networkSecurityGroupModule.outputs.resourceId
      }
    ]
    tags: tags
  }
}

// Link the existing private DNS zones.
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
  //'privatelink.vaultcore.azure.net'
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

// module privateDnsZonesModule 'br/public:avm/res/network/private-dns-zone:0.7.1' = [
//   for privateDnsZoneName in privateDnsZoneNames: {
//     name: 'privateDnsZoneDeployment-${privateDnsZoneName}'
//     params: {
//       // Required parameters
//       name: privateDnsZoneName
//       // Non-required parameters
//       location: 'global'
//       tags: tags

//       virtualNetworkLinks: [
//         {
//           virtualNetworkResourceId: virtualNetworkModule.outputs.resourceId
//         }
//       ]
//     }
//   }
// ]

// Create the UAMI
module userAssignedIdentityModule 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'userAssignedIdentityDeployment'
  params: {
    // Required parameters
    name: 'id-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    // Non-required parameters
    tags: tags
  }
}

// Create the Key Vault with private endpoint and secrets
// Disable due to lack of support for Key Vault references in network-restricted KVs in Flex Consumption Plan
// module vaultModule 'br/public:avm/res/key-vault/vault:0.12.1' = {
//   name: 'vaultDeployment'
//   params: {
//     // Required parameters
//     name: 'kv-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-01'
//     // Non-required parameters
//     diagnosticSettings: [
//       {
//         workspaceResourceId: appInsightsWorkspaceResourceID
//       }
//     ]
//     enablePurgeProtection: false
//     enableRbacAuthorization: true
//     publicNetworkAccess: 'Disabled'
//     networkAcls: {
//       bypass: 'AzureServices'
//       defaultAction: 'Deny'
//     }
//     privateEndpoints: [
//       {
//         privateDnsZoneGroup: {
//           privateDnsZoneGroupConfigs: [
//             {
//               privateDnsZoneResourceId: existingPrivateLinkDnsZones[3].id
//             }
//           ]
//         }
//         service: 'vault'
//         subnetResourceId: virtualNetworkModule.outputs.subnetResourceIds[0]
//       }
//     ]
//     secrets: [
//       {
//         attributes: {
//           enabled: true
//           exp: dateTimeToEpoch(secretExpirationDate)
//         }
//         contentType: 'The primary or secondary key for the Sentinel Log Analytics Workspace'
//         name: 'sentinelWorkspaceKey'
//         value: sentinelWorkspaceKey
//       }
//       {
//         attributes: {
//           enabled: true
//           exp: dateTimeToEpoch(secretExpirationDate)
//         }
//         contentType: 'Tenable API Access Key'
//         name: 'tenableAccessKey'
//         value: tenableAccessKey
//       }
//       {
//         attributes: {
//           enabled: true
//           exp: dateTimeToEpoch(secretExpirationDate)
//         }
//         contentType: 'Tenable API Secret Key'
//         name: 'tenableSecretKey' // TODO: Don't hardcode secret names
//         value: tenableSecretKey
//       }
//     ]
//     softDeleteRetentionInDays: 7
//     tags: tags

//     // TODO: Assign role to the UAMI
//     roleAssignments: [
//       {
//         principalId: userAssignedIdentityModule.outputs.principalId
//         roleDefinitionIdOrName: 'Key Vault Secrets User'
//         principalType: 'ServicePrincipal'
//       }
//     ]
//   }
// }

var appPackageContainerName = 'app-package-${toLower(functionName)}'

// Create the Storage Account with private endpoint and the file share and container
module storageAccountModule 'br/public:avm/res/storage/storage-account:0.20.0' = {
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
    ]
  }
}

// Create the App Insights
module componentModule 'br/public:avm/res/insights/component:0.6.0' = {
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
  }
}

// Create the consumption plan
module serverfarmModule 'br/public:avm/res/web/serverfarm:0.4.1' = {
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
  }
}

var functionAppSpecialTags = {
  'hidden-link: /app-insights-resource-id': componentModule.outputs.resourceId
}

// Create the Function App and assign UAMI
module functionAppModule 'br/public:avm/res/web/site:0.16.0' = {
  name: 'functionAppDeployment'
  params: {
    // Required parameters
    kind: 'functionapp,linux'
    name: 'func-${functionName}-prod-${shortLocationNames[resourceGroup().location]}-${sequenceFormatted}'
    serverFarmResourceId: serverfarmModule.outputs.resourceId

    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    vnetRouteAllEnabled: true
    vnetContentShareEnabled: true

    configs: [
      {
        applicationInsightResourceId: componentModule.outputs.resourceId
        name: 'appsettings'
        properties: {
          FUNCTIONS_EXTENSION_VERSION: '~4'
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${userAssignedIdentityModule.outputs.clientId};Authorization=AAD'
          APPLICATIONINSIGHTS_CONNECTION_STRING: componentModule.outputs.connectionString

          // Tenable app-specific settings
          WorkspaceID: sentinelWorkspaceId

          WorkspaceKey: sentinelWorkspaceKey
          TIO_SECRET_KEY: tenableSecretKey
          TIO_ACCESS_KEY: tenableAccessKey
          // WorkspaceKey: '@Microsoft.KeyVault(SecretUri=${vaultModule.outputs.uri}secrets/sentinelWorkspaceKey)' // TODO: Do not hardcode secret names
          // TIO_SECRET_KEY: '@Microsoft.KeyVault(SecretUri=${vaultModule.outputs.uri}secrets/tenableSecretKey)'
          // TIO_ACCESS_KEY: '@Microsoft.KeyVault(SecretUri=${vaultModule.outputs.uri}secrets/tenableAccessKey)'

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
    tags: tags
    virtualNetworkSubnetId: virtualNetworkModule.outputs.subnetResourceIds[1]

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
        tags: union(tags, functionAppSpecialTags)
      }
    ]
  }
}

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

output functionAppName string = functionAppModule.outputs.name
