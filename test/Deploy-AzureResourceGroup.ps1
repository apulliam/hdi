#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName,
    [string] $DeploymentResourceGroupName = 'ARM_Deploy_Staging',
    [string] $DeploymentStorageAccountName,
    [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
    [string] $TemplateFile = 'azureDeploy.json',
    [string] $TemplateParametersFile = 'azureDeploy.parameters.json'
   
)



$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

$OptionalParameters = New-Object -TypeName Hashtable
$TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$TemplateParametersFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))
$TemplateFileName = [System.IO.Path]::GetFileName($TemplateFile)
# Convert relative paths to absolute paths if needed
$ArtifactStagingDirectory = [System.IO.Path]::GetDirectoryName($TemplateFile)


# Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
$JsonParameters = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
    $JsonParameters = $JsonParameters.parameters
}

$ArtifactsLocationSasTokenName = 'baseUrlSasToken'
$OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore

# Create a storage account name if none was provided
if ($DeploymentStorageAccountName -eq '') {
    $DeploymentStorageAccountName = 'stage' + ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 19)
}

$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $DeploymentStorageAccountName})

# Create the storage account if it doesn't already exist
if ($StorageAccount -eq $null) {
   
    New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $DeploymentResourceGroupName -Force
    $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $DeploymentStorageAccountName -Type 'Standard_LRS' -ResourceGroupName $DeploymentResourceGroupName -Location "$ResourceGroupLocation"
}

$TemplateBaseUri = $StorageAccount.Context.BlobEndPoint + $StorageContainerName


# Copy files from the local storage staging location to the storage account container
New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
foreach ($SourcePath in $ArtifactFilePaths) {
    Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
        -Container $StorageContainerName -Context $StorageAccount.Context -Force
}

# Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
    $ArtifactsLocationSasToken = (New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
    $OptionalParameters[$ArtifactsLocationSasTokenName] =  ConvertTo-SecureString -AsPlainText -Force $ArtifactsLocationSasToken
        
}

$TemplateFileUri = $TemplateBaseUri + '/' + $TemplateFileName + $ArtifactsLocationSasToken;

# Create or update the resource group using the specified template file and template parameters file
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force


New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                    -ResourceGroupName $ResourceGroupName `
                                    -TemplateUri $TemplateFileUri `
                                    -TemplateParameterFile $TemplateParametersFile `
                                    @OptionalParameters `
                                    -Force -Verbose `
                                    -ErrorVariable ErrorMessages
if ($ErrorMessages) {
    Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
}