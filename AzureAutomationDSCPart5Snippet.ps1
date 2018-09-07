#region setup
$WorkingDir = $psISE.CurrentFile.FullPath | Split-Path
Set-Location $WorkingDir
#Add-AzureRmAccount
$AAAcct = Get-AzureRmAutomationAccount -Name DSCDemo01 -ResourceGroupName DSCDemo01
$Keys = $AAAcct | Get-AzureRmAutomationRegistrationInfo
$RG = Get-AzureRmResourceGroup -Name DSCNodes
$StorageAccountName = 'dscnodes4588'
$Location = 'westeurope'
#endregion

#region ARM PS Windows

#show cmdlets
Get-Command -Module AzureRM.Compute -Noun AzureRmVMDsc*

#show configuration
psedit $WorkingDir\AADSCLCMConfig.ps1

#create local archive
Publish-AzureRmVMDscConfiguration -ConfigurationPath $WorkingDir\AADSCLCMConfig.ps1 `
                                  -OutputArchivePath $WorkingDir\AADSCLMConfig.zip
Read-Archive -Path $WorkingDir\AADSCLMConfig.zip

#publish archive
$StorageAccount = $RG | Get-AzureRmStorageAccount -Name $StorageAccountName
$StorageAccount | Publish-AzureRmVMDscConfiguration -ConfigurationPath $WorkingDir\AADSCLCMConfig.ps1
#show publish result
$StorageAccount | Get-AzureStorageContainer
$StorageAccount | Get-AzureStorageBlob -Container windows-powershell-dsc

# onboard existing VM
$Node1 = $RG | Get-AzureRmVM -Name DSCNode1

$DSCExtensionArgs = @{
    ResourceGroupName = $RG.ResourceGroupName
    VMName = $Node1.Name
    ArchiveBlobName = 'AADSCLCMConfig.ps1.zip'
    ArchiveStorageAccountName = $StorageAccountName
    ArchiveResourceGroupName = $RG.ResourceGroupName
    ArchiveContainerName = 'windows-powershell-dsc'
    ConfigurationName = 'LCM'
    ConfigurationArgument = @{
        Endpoint = $Keys.Endpoint
        Key = $Keys.PrimaryKey
    }
    WmfVersion = 'latest'
    Version = '2.15' #https://blogs.msdn.microsoft.com/powershell/2014/11/20/release-history-for-the-azure-dsc-extension/
}

Set-AzureRmVMDscExtension @DSCExtensionArgs
#endregion

#region ARM PS Linux
#lookup node to be onboarded
$Node2 = $RG | Get-AzureRmVM -Name DSCNode2

#look for DSC for Linux extension
Get-AzureRmVMImagePublisher -Location $Location
Get-AzureRmVMImagePublisher -Location $Location | Where-Object -FilterScript {$_.PublisherName -like '*Microsoft*'}
Get-AzureRmVMExtensionImageType -PublisherName Microsoft.OSTCExtensions -Location $Location | Select-Object Type
Get-AzureRmVMExtensionImage -PublisherName Microsoft.OSTCExtensions -Location $Location -Type 'DSCForLinux'

#use DSC for Linux extension to onboard part 1
$OSTCExtensionArgs = @{
    Name = 'AADSCOnboard'
    Publisher = 'Microsoft.OSTCExtensions'
    ExtensionType = 'DSCForLinux'
    TypeHandlerVersion = '2.0'
    Location = $Location
    Settings = @{
        Mode = 'Register' #New in 2.0! Uses Register Python script from DSC For Linux package under the covers
    }
    ProtectedSettings = @{
        RegistrationUrl = $Keys.Endpoint
        RegistrationKey = $Keys.PrimaryKey
    }
    VMName = $Node2.Name
    ResourceGroupName = $RG.ResourceGroupName
}

Set-AzureRmVMExtension @OSTCExtensionArgs

#part 2 (own settings)
#Generate meta.mof
. $WorkingDir\AADSCLCMConfig.ps1
LCM -Endpoint $Keys.Endpoint -Key $Keys.PrimaryKey -OutputPath $WorkingDir
psedit $WorkingDir\localhost.meta.mof

#upload meta.mof to storage account
$StorageContainer = New-AzureStorageContainer -Context $StorageAccount.Context -Name 'aadsc-onboard' -Permission Off
$upload = Set-AzureStorageBlobContent -Container 'aadsc-onboard' -File $WorkingDir\localhost.meta.mof -Context $StorageAccount.Context
$Node3 = $RG | Get-AzureRmVM -Name DSCNode3

$OSTCExtensionArgs = @{
    Name = 'AADSCOnboard'
    Publisher = 'Microsoft.OSTCExtensions'
    ExtensionType = 'DSCForLinux'
    TypeHandlerVersion = '2.0'
    Location = $Location
    Settings = @{
        Mode = 'Pull'
        FileUri = ($StorageAccount.PrimaryEndpoints.Blob.AbsoluteUri + 'aadsc-onboard/localhost.meta.mof')
    }
    ProtectedSettings = @{
        StorageAccountKey = ($StorageAccount | Get-AzureRmStorageAccountKey).Key1
        StorageAccountName = $StorageAccountName
    }
    VMName = $Node3.Name
    ResourceGroupName = $RG.ResourceGroupName
}
Set-AzureRmVMExtension @OSTCExtensionArgs
#endregion

#region ARM Template running Windows VM
$Node4 = $RG | Get-AzureRmVM -Name DSCNode4
$TemplateURI = 'https://github.com/Azure/azure-quickstart-templates/tree/5589f0fdb03ed34c70f2dbbadb2db226c52415a1/dsc-extension-azure-automation-pullserver'
Start-Process microsoft-edge:$TemplateURI

$RGDeployArgs1 = @{
    TemplateUri = 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/5589f0fdb03ed34c70f2dbbadb2db226c52415a1/dsc-extension-azure-automation-pullserver/azuredeploy.json'
    Mode = 'Incremental'
    ResourceGroupName = $RG.ResourceGroupName
    TemplateParameterObject = @{
        vmName = $Node4.Name
        registrationKey = $Keys.PrimaryKey
        registrationUrl = $Keys.Endpoint
        nodeConfigurationName = ''
        timestamp = [datetime]::Now.ToString()
    }
}

New-AzureRmResourceGroupDeployment @RGDeployArgs1 -Force
#endregion

#region ARM Template running Linux VM
psEdit "$WorkingDir\LinuxOnboard.json"
$Node5 = $RG | Get-AzureRmVM -Name DSCNode5

$LinuxTemplateOnboard = @{
    ResourceGroupName = $RG.ResourceGroupName
    Mode = 'Incremental'
    TemplateParameterObject = @{
        registrationKey = $Keys.PrimaryKey
        registrationUrl = $Keys.Endpoint
    }
    TemplateFile = "$WorkingDir\LinuxOnboard.json"
    vmName = $Node5.Name
}

New-AzureRmResourceGroupDeployment @LinuxTemplateOnboard
#endregion