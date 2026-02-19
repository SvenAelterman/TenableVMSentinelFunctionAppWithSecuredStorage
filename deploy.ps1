[CmdletBinding()]

[string]$ResourceGroupName = "tenablevm-test-rg-cnc-01"

$DeploymentResults = New-AzResourceGroupDeployment `
    -Name "TenableVMFxAppDeployment" `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile "./src/main.bicep" `
    -TemplateParameterFile "./src/parameters.bicepparam" `
    -Verbose

if ($DeploymentResults.ProvisioningState -eq 'Succeeded') {
    Write-Host "🔥 Deployment successful!"
}
