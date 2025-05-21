[string]$ResourceGroupName = "tenablevm-test-rg-cnc-01"
[string]$FxAppZipFileName = "tenablevm.zip"

# Download the function app zip file for deployment
Invoke-WebRequest -Uri "https://aka.ms/sentinel-TenableVMAzureSentinelConnector310-functionapp" -OutFile $FxAppZipFileName

$DeploymentResults = New-AzResourceGroupDeployment `
    -Name "TenableVMFxAppDeployment" `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile "./src/main.bicep" `
    -TemplateParameterFile "./src/parameters.bicepparam" `
    -Verbose

if ($DeploymentResults.ProvisioningState -eq 'Succeeded') {
    az account set --subscription "$((Get-AzContext).Subscription.Id)"

    az functionapp deployment source config-zip `
        --name "$($DeploymentResults.Outputs.functionAppName.Value)" `
        --resource-group $ResourceGroupName `
        --src $FxAppZipFileName

    Write-Host "🔥 Deployment successful!"
}
