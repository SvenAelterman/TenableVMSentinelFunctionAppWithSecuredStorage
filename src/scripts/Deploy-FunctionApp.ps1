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
[string]$FxAppSource = "https://aka.ms/sentinel-TenableVMAzureSentinelConnector310Updated-functionapp"

# Version 3.10: https://aka.ms/sentinel-TenableVMAzureSentinelConnector310-functionapp
# Version 3.11 (?): https://aka.ms/sentinel-TenableVMAzureSentinelConnector-functionapp
# Version 3.10 "updated" (latest Fx app bundle, most recent as of 2026-02-17): https://aka.ms/sentinel-TenableVMAzureSentinelConnector310Updated-functionapp
# Download the function app zip file for deployment
Invoke-WebRequest -Uri $FxAppSource -OutFile $FxAppZipFileName

# Install the AZ CLI
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I', 'AzureCLI.msi', '/quiet'
Remove-Item .\AzureCLI.msi

# Get-Command az might not return anything because "az" isn't in the path yet
#$AZCliPath = Get-Command az | Select-Object -ExpandProperty Source
# Alternative:
$AZCliPath = "$($Env:ProgramFiles)\Microsoft SDKs\Azure\CLI2\wbin\az"

& "$AZCliPath" login --identity --client-id $ClientId
& "$AZCliPath" functionapp deployment source config-zip `
    --name "$FunctionAppName" `
    --resource-group $ResourceGroupName `
    --src $FxAppZipFileName
