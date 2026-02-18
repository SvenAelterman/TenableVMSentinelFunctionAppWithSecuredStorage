# Tenable VM Sentinel Function App with Secured Storage

Deploys Tenable Vulnerability Management's Azure Function app for Sentinel ingest using secured Storage Account to meet common customer compliance requirements.

This repo contains Bicep code based on the ARM JSON template as of 2025-05-20.

## Security and Compliance Enhancements

- Creates a Virtual Network and Private Endpoints for the Storage Account and Function App.
  - Creates the Function app in a Flex Consumption Plan to enable virtual network integration.
  - Creates a NAT Gateway to ensure outbound connectivity even after default outbound access is retired.
- Sends data to Application Insights via Entra authentication instead of instrumentation key.
- Stores sensitive environment variables for the Function App in Key Vault to enable separation of duties and easier rotating of secrets.

## Other Enhancements

- Uses [Azure Verified Modules](https://aka.ms/AVM) where available.
- Improves resource naming based on the Cloud Adoption Framework suggested naming convention.

## Deployment: PowerShell

A PowerShell 7 script is provided that will orchestrate the complete deployment. To use it, first prepare a Bicep parameter file with the name `./src/parameters.bicepparam`. Sample contents:

```bicep
using 'main.bicep'

param appInsightsWorkspaceResourceID = '/subscriptions/...'
param sentinelWorkspaceKey = 'hmCI...'
param sentinelWorkspaceId = '552c...'
param tenableAccessKey = 'abcd...'
param tenableSecretKey = 'efgh...'

param existingPrivateLinkDnsZonesResourceGroupResourceId = '<Resource ID of the RG where private link DNS zones are created>'

param virtualNetworkAddressPrefix = '10.0.0.0/24'

param sequence = 1

param virtualMachineEnableEncryptionAtHost = true // This requires that this feature is enabled at the subscription level
param virtualMachineLoginPrincipalId = '<Entra object ID of a user or security group that will be granted Administrator login permission to the VM>'
param virtualMachineAdminPassword = '<secret value>' // As a best practice, pull this from a Key Vault
param deployAzureBastion = true

```

Then, run the `./deploy.ps` PowerShell.

```PowerShell
./deploy.ps1 [-Verbose]
```

## Future Improvements

### Add resource locks
