[CmdletBinding()]
[CmdletBinding()]
param (
    [Parameter()]
    [string]$ResourceGroupName,
    [Parameter()]
    [string]$FunctionAppName,
    [Parameter()]
    [string]$ClientId
)

[string]$FxAppZipFileName = "tenablevm.zip"
[string]$FxAppSource = "https://aka.ms/sentinel-TenableVMAzureSentinelConnector-functionapp"

# Version 3.10: https://aka.ms/sentinel-TenableVMAzureSentinelConnector310-functionapp
# Version 3.11: https://aka.ms/sentinel-TenableVMAzureSentinelConnector-functionapp
# Download the function app zip file for deployment
Invoke-WebRequest -Uri $FxAppSource -OutFile $FxAppZipFileName
az login --identity --client-id $ClientId
az functionapp deployment source config-zip `
    --name "$FunctionAppName" `
    --resource-group $ResourceGroupName `
    --src $FxAppZipFileName
