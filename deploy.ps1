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
    # Flexible Consumption model doesn't support specifying the zip file as an environment variable during deployment.
    # Therefore, we need to deploy the zip file separately after the function app is created.

    # Ensure we're using the same subscription for AZ CLI as for the Az PS modules
    az account set --subscription "$((Get-AzContext).Subscription.Id)"

    # Deploy the function app zip file
    az functionapp deployment source config-zip `
        --name "$($DeploymentResults.Outputs.functionAppName.Value)" `
        --resource-group $ResourceGroupName `
        --src $FxAppZipFileName

    Write-Host "🔥 Deployment successful!"
}
