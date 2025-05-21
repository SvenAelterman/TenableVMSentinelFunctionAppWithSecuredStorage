# Tenable VM Sentinel Function App with Secured Storage

Deploys Tenable Vulnerability Management's Azure Function app for Sentinel ingest using secured Storage Account to meet common customer compliance requirements.

This repo contains Bicep code based on the ARM JSON template as of 2025-05-20.

## Security and Compliance Enhancements

- Creates a Virtual Network and Private Endpoints for the Storage Account and Function App.
  - Creates the Function app in a Flex Consumption Plan to enable virtual network integration.
  - (pending) Creates a NAT Gateway to ensure outbound connectivity even after default outbound access is retired.
- Sends data to Application Insights via Entra authentication instead of instrumentation key.

## Other Enhancements

- Uses [Azure Verified Modules](https://aka.ms/AVM) where available.
- Improves resource naming based on the Cloud Adoption Framework suggested naming convention.

## Deployment: PowerShell

A PowerShell 7 script is provided that will orchestrate the complete deployment. To use it, first prepare a Bicep parameter file with the name `./src/parameters.bicepparam`. Sample contents:

```bicep
using 'main.bicep'

param appInsightsWorkspaceResourceID = ''
param sentinelWorkspaceKey = 'hmCI...'
param sentinelWorkspaceId = '552c...'
param tenableAccessKey = 'abcd...'
param tenableSecretKey = 'efgh...'

param existingPrivateLinkDnsZonesResourceGroupResourceId = '<Resource ID of the RG where private link DNS zones are created>'

param sequence = 1
```

Then, run the `./deploy.ps` PowerShell.

> This command should be run from a system that will have line-of-sight to the Function App's private endpoint and will be able to resolve it's DNS name to the private endpoint IP address.

```PowerShell
./deploy.ps1
```

## Future Improvements

### Key Vault for Secrets

[Flex Consumption Plan doesn't support referencing Key Vault secrets](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan#:~:text=Key%20Vault%20and%20App%20Configuration%20References) in app settings when the Key Vault is network restricted. Because the entire point behind this repo is to enable deployment of the Tenable functions in a network-restricted environment, the secret values are added directly to the app settings. If in the future, Flex Consumption Plan will support Key Vault references for Key Vaults that network restricted, the code is already present (but commented) to enable this.

Alternatively, an Elastic Premium plan could be used instead which will incur a fixed cost.

### Deployment of the Function App Code with Deployment Script
