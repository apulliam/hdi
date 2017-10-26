$deploymentResourceGroupName = "apulliam-hdi-deployment"
$resourceGroupName="apulliam-hdi"
$resourceGroupLocation = "East US"
$deployScript = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, ".\Deploy-AzureResourceGroup.ps1"))
&$deployScript -DeploymentResourceGroupName $deploymentResourceGroupName -ResourceGroupLocation $resourceGroupLocation -ResourceGroupName $resourceGroupName  -TemplateFile "..\azureDeploy.json" -TemplateParametersFile ".\azuredeploy.parameters.json" 
